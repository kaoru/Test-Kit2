package Test::Kit;

use strict;
use warnings;

use Import::Into;
use Module::Runtime 'use_module', 'module_notional_filename';
use Sub::Delete;
use Test::Builder ();
use Test::More ();
use Scalar::Util qw(refaddr);

use parent 'Exporter';
our @EXPORT = ('include');

# my %test_kits_cache = (
#     'MyTest::Awesome' => {
#         'ok' => { source => [ 'Test::More' ], refaddr => 0x1234, },
#         'pass' => { source => [ 'Test::Simple', 'Test::More' ], refaddr => 0xbeef, },
#         'warnings_are' => { source => [ 'Test::Warn' ], refaddr => 0xbead, },
#         ...
#     },
#     ...
# )
#
my %test_kits_cache;

sub include {
    my @to_include = @_;

    my $class = __PACKAGE__;

    my $include_hashref;
    if (grep { ref($_) } @to_include) {
        $include_hashref = { @to_include };
    }
    else {
        $include_hashref = { map { $_ => {} } @to_include };
    }

    return $class->_include($include_hashref);
}

sub _include {
    my $class = shift;
    my $include_hashref = shift;

    my $target = $class->_get_package_to_import_into();

    $class->_make_target_a_test_more_like_exporter($target);

    for my $package (sort keys %$include_hashref) {
        my $fake_package = $class->_create_fake_package($package, $include_hashref->{$package}, $target);
        $fake_package->import::into($target);
    }

    $class->_update_target_provides($target);

    return;
}

sub _get_package_to_import_into {
    my $class = shift;

    # so, as far as I can tell, on Perl 5.14 and 5.16 at least, we have the
    # following callstack...
    #
    # 1. Test::Kit
    # 2. MyTest
    # 3. main
    # 4. main
    # 5. main
    #
    # ... and we want to get the package name "MyTest" out of there.
    # So let's look for the first non-Test::Kit result

    for my $i (1 .. 20) {
        my $caller_package = (caller($i))[0];
        if ($caller_package ne $class) {
            return $caller_package;
        }
    }

    die "Unable to find package to import into";
}

sub _make_target_a_test_more_like_exporter {
    my $class = shift;
    my $target = shift;

    return if $test_kits_cache{$target};

    $class->_check_target_does_not_import($target);

    {
        no strict 'refs';

        if ($Test::Builder::VERSION >= 1.3) {

            # if Perl is compiling this branch before TB 1.3 then
            # Test::More::before_import gets an 'only used once' warning because it
            # doesn't exist.
            no warnings 'once';

            *{ "${target}::before_import" } = *Test::More::before_import;

            *{ "${target}::after_import" } = sub {
                $Exporter::ExportLevel = 1;
                goto &Exporter::import;
            };

            use_module('Test::Builder::Provider')->import::into($target);
        }
        else {
            no strict 'refs';
            push @{ "${target}::ISA" }, 'Test::Builder::Module';
        }
    }

    $test_kits_cache{$target} = {};

    return;
}

sub _create_fake_package {
    my $class = shift;
    my $package = shift;
    my $package_include_hashref = shift;
    my $target = shift;

    my $fake_package = "Test::Kit::Fake::${target}::${package}";

    my $fake_package_file = module_notional_filename($fake_package);
    $INC{$fake_package_file} = 1;

    my %exclude = map { $_ => 1 } @{ $package_include_hashref->{exclude} || [] };
    my %rename = %{ $package_include_hashref->{rename} || {} };
    my @import = @{ $package_include_hashref->{import} || [] };

    use_module($package)->import::into($fake_package, @import);

    {
        no strict 'refs';
        no warnings 'redefine';

        push @{ "${fake_package}::ISA" }, 'Exporter';

        for my $from (sort keys %rename) {
            my $to = $rename{$from};

            *{ "$fake_package\::$to" } = \&{ "$fake_package\::$from" };

            delete_sub("${fake_package}::$from");
        }

        for my $exclude (sort keys %exclude) {
            delete_sub("${fake_package}::$exclude");
        }

        @{ "${fake_package}::EXPORT" } = $class->_get_exports_for($fake_package, $package, $target, \%rename);
    }

    return $fake_package;
}

sub _get_exports_for {
    my $class = shift;
    my $fake_package = shift;
    my $package = shift;
    my $target = shift;
    my $rename = shift;

    # Want to look at each item in the symbol table of
    # the fake package, and see whether it's the same
    # (according to refaddr) as the one that was in the
    # included package. If it is then it was exported
    # by the package into the fake package.
    #
    # We also store the refaddr so that we can check things which are identical
    # between included packages, and not throw a collision exception in that
    # case.
    my %type_to_sigil = ( # please don't export IO or FORMAT! ;-)
        SCALAR => '$',
        ARRAY  => '@',
        HASH   => '%',
        CODE   => '',
    );
    my %reverse_rename = reverse %{ $rename || {} };
    my @package_exports;
    {
        no strict 'refs';

        for my $glob (keys %{ "${fake_package}::" }) {

            my $fake_glob = $glob;
            my $real_glob = $reverse_rename{$glob} // $glob;

            for my $type (keys %type_to_sigil) {
                my $fake_refaddr = refaddr *{ "${fake_package}::${fake_glob}" }{$type};
                my $real_refaddr = refaddr *{ "${package}::${real_glob}" }{$type};

                if ($fake_refaddr && $real_refaddr && $fake_refaddr == $real_refaddr) {
                    my $export = sprintf("%s%s", $type_to_sigil{$type}, $fake_glob);
                    push @package_exports, $export;

                    # handle cache and collision checking
                    push @{ $test_kits_cache{$target}{$export}{source} }, $package;
                    if (my $existing_refaddr = $test_kits_cache{$target}{$export}{refaddr}) {
                        if ($existing_refaddr != $real_refaddr) {
                            die sprintf("Subroutine %s() already supplied to %s by %s",
                                $export,
                                $target,
                                $test_kits_cache{$target}{$export}{source}[0],
                            );
                        }
                    }
                    else {
                        $test_kits_cache{$target}{$export}{refaddr} = $real_refaddr;
                    }
                }
            }
        }
    }

    return @package_exports;
}

sub _check_target_does_not_import {
    my $class = shift;
    my $target = shift;

    if ($target->can('import')) {
        die "Package $target already has an import() sub";
    }

    return;
}

sub _update_target_provides {
    my $class = shift;
    my $target = shift;

    my @exports = sort keys %{ $test_kits_cache{$target} };

    {
        no strict 'refs';

        if ($Test::Builder::VERSION >= 1.3) {

            @{ "${target}::EXPORT" } = @exports;

            for my $e (@exports) {
                next if $e =~ m/^[\$\@\%]/;
                eval "package $target; provides '$e';";
                if ($@ && $@ !~ m/already provides or gives/) {
                    die sprintf("Failed to provide %s to %s: %s",
                        $e, $target, $@
                    );
                }
            }
        }
        else {
            @{ "$target\::EXPORT" } = @exports;
        }
    }
}

1;

__END__

=head1 NAME

Test::Kit - Build custom test packages with only the features you want

=head1 DESCRIPTION

Test::Kit allows you to create a single module in your project which gives you
access to all of the testing functions you want.

Its primary goal is to reduce boilerplate code that is currently littering the
top of all your test files.

It also allows your testing to be more consistent; for example it becomes a
trivial change to include Test::FailWarnings in all of your tests, and there is
no danger that you forget to include it in a new test.

=head1 VERSION

Test::Kit 2.0 is a complete rewrite of Test::Kit by a new author.

It serves much the same purpose as the original Test::Kit, but comes with a
completely new interface and some serious bugs ironed out.

The 'features' such as '+explain' and '+on_fail' have been removed. If you were
using these please contact me via rt.cpan.org.

=head1 SYNOPSIS

Somewhere in your project...

    package MyProject::Test;

    use Test::Kit;

    # Combine multiple modules' behaviour into one

    include 'Test::More';
    include 'Test::LongString';

    # Exclude or rename exported subs

    include 'Test::Warn' => {
        exclude => [ 'warning_is' ],
        renamed => {
            'warning_like' => 'test_warn_warning_like'
        },
    };

    # Pass parameters through to import() directly

    include 'List::Util' => {
        import => [ 'min', 'max', 'shuffle' ],
    };

And then in your test files...

    use strict;
    use warnings;

    use MyProject::Test tests => 4;

    ok 1, "1 is true";

    like_string(
        `cat /usr/share/dict/words`,
        qr/^ kit $/imsx,
        "kit is a word"
    );

    test_warn_warning_like {
        warn "foo";
    }
    qr/FOO/i,
    "warned foo";

    is max(qw(1 2 3 4 5)), 5, 'maximum is 5';

=head1 EXCEPTIONS

=head2 Unable to find package to import into

This means that Test::Kit was unable to determine which module include() was
called from. It probably means you're doing something weird!

If this is happening under any normal circumstances please file a bug report!

=head2 Subroutine %s() already supplied to %s by %s

This happens when there is a subroutine name collision. For example if you try
to include both Test::Simple and Test::More in your Kit it will complain that
ok() has been defined twice.

You should be able to use the exclude or rename options to solve these
collisions.

=head2 Package %s already has an import() sub

This happens when your module has an import subroutine before the first
include() call. This could be because you have defined one, or because your
module has inherited an import() subroutine through an ISA relationship.

Test::Kit intends to install its own import method into your module,
specifically it is going to install Test::Builder::Module's import() method.
Test::Builder::Module is an Exporter, so if you want to define your own
subroutines and export those you can push onto @EXPORT after all the calls to
include().

=head2 Failed to provide %s to %s: %s

This happens when working under a Test::Builder new enough to support the
provides() mechanism, when something has failed to be provided for some reason.

I don't know yet of any reason why this might happen. If it happens for you
please get in touch!

=head1 COMPATIBILITY

Test::Kit 2.1 and above should work with Test::Builder 1.3 and above (with
Test::Builder::Provider) and with older versions which still use
Test::Builder::Module.

Huge thanks to Chad Granum and Karen Etheridge for all their help with the
Test::Builder::Provider support.

=head1 SEE ALSO

A couple of other modules try to generalize this problem beyond the scope of testing:

L<ToolSet> - Load your commonly-used modules in a single import

L<Import::Base> - Import a set of modules into the calling module

Test::Kit largely differs from these in that it always makes your module behave
like Test::More.

=head1 AUTHOR

Test::Kit 2.0 was written by Alex Balhatchet, C<< <kaoru at slackwise.net> >>

Test::Kit 0.101 and before were authored by Curtis "Ovid" Poe, C<< <ovid at cpan.org> >>

=cut
