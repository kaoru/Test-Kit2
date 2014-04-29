package Test::Kit2;

use strict;
use warnings;

use namespace::clean ();
use Import::Into;
use Module::Runtime 'use_module';
use Sub::Delete;

use parent 'Exporter';
our @EXPORT = ('include');

# deep structure:
#
# my %collision_check_cache = (
#     'MyTest::Awesome' => {
#         'ok' => 'Test::More',
#         'pass' => 'Test::More',
#         'warnings_are' => 'Test::Warn',
#         ...
#     },
#     ...
# )
#
my %collision_check_cache;

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

    $class->_check_target_does_not_import($target);

    for my $package (sort keys %$include_hashref) {
        my $fake_package = $class->_create_fake_package($package, $include_hashref->{$package});
        $fake_package->import::into($target);
    }

    $class->_make_target_an_exporter($target);

    return;
}

sub _get_package_to_import_into {
    my $class = shift;

    # so, as far as I can tell, on Perl 5.14 and 5.16 at least, we have the
    # following callstack...
    #
    # 1. Test::Kit2
    # 2. MyTest
    # 3. main
    # 4. main
    # 5. main
    #
    # ... and we want to get the package name "MyTest" out of there.
    # So let's look for the first non-Test::Kit2 result

    for my $i (1 .. 20) {
        my $caller_package = (caller($i))[0];
        if ($caller_package ne $class) {
            return $caller_package;
        }
    }

    die "Unable to find package to import into";
}

sub _create_fake_package {
    my $class = shift;
    my $package = shift;
    my $package_include_hashref = shift;

    my $target = $class->_get_package_to_import_into();

    my $fake_package = "Test::Kit::Fake::$target\::$package";

    my %exclude = map { $_ => 1 } @{ $package_include_hashref->{exclude} || [] };
    my %rename = %{ $package_include_hashref->{rename} || {} };
    my @import = @{ $package_include_hashref->{import} || [] };

    use_module($package)->import::into($fake_package, @import);
    my $functions_exported_by_package = namespace::clean->get_functions($fake_package);

    my @functions_to_install = (
        (grep { !$exclude{$_} && !$rename{$_} } sort keys %$functions_exported_by_package),
        (values %rename)
    );

    my @non_functions_to_install = $class->_get_non_functions_from_package($package);

    $class->_check_collisions(
        $package,
        [
            @functions_to_install,
            @non_functions_to_install,
        ]
    );

    {
        no strict 'refs';
        no warnings 'redefine';

        push @{ "$fake_package\::ISA" }, 'Exporter';
        @{ "$fake_package\::EXPORT" } = (
            @functions_to_install,
            @non_functions_to_install
        );

        for my $from (sort keys %rename) {
            my $to = $rename{$from};

            *{ "$fake_package\::$to" } = \&{ "$fake_package\::$from" };

            delete_sub("$fake_package\::$from");
        }
    }

    return $fake_package;
}

sub _check_collisions {
    my $class = shift;
    my $package = shift;
    my $functions_to_install = shift;

    my $target = $class->_get_package_to_import_into();

    for my $function (@$functions_to_install) {
        if (exists $collision_check_cache{$target}{$function} && $collision_check_cache{$target}{$function} ne $package) {
            die sprintf("Subroutine %s() already supplied to %s by %s",
                $function,
                $target,
                $collision_check_cache{$target}{$function},
            );
        }
        else {
            $collision_check_cache{$target}{$function} = $package;
        }
    }

    return;
}

sub _check_target_does_not_import {
    my $class = shift;
    my $target = shift;

    return if $collision_check_cache{$target}; # already checked

    if ($target->can('import')) {
        die "Package $target already has an import() sub";
    }

    return;
}

sub _make_target_an_exporter {
    my $class = shift;
    my $target = shift;

    my @functions_to_install = sort keys %{ $collision_check_cache{$target} // {} };

    {
        no strict 'refs';
        push @{ "$target\::ISA" }, 'Test::Builder::Module';
        @{ "$target\::EXPORT" } = @functions_to_install;
    }

    return;
}

sub _get_non_functions_from_package {
    my $class = shift;
    my $package = shift;

    # Unfortunately we can't do the "correct" thing here, which would be to
    # walk the symbol table of the fake package to find the non-sub variables
    # exported by the included package.
    #
    # This is because the most common case we're trying to handle is the
    # '$TODO' variable from Test::More, but it's impossible to catch that in
    # the fake package symbol table because every symbol table entry has a
    # scalar no matter what. ie the following two packages are indistinguishable:
    #
    # 1.
    #     package foo;
    #     our $x = undef;
    #     our @x = qw(a b c);
    #
    # 2.
    #     package foo;
    #     our @x = qw(a b c);
    #
    # One option would be to import '$VAR' if VAR is in the symbol table and
    # has no CODE, ARRAY, or HASH entry. But that breaks down if a package is
    # trying to export both '$VAR' and '@VAR'.
    #
    # So, instead of all that I'm going to simply assume that the package is an
    # Exporter and walk its @EXPORT array for things which start with '$', '@'
    # or '%'. This at least will work for the $Test::More::TODO case.
    #

    my @non_functions;

    my @package_export;
    {
        no strict 'refs';
        @package_export = @{ "$package\::EXPORT" };
    }

    for my $e (@package_export) {
        if ($e =~ m/^[\$\@\%]/) {
            push @non_functions, $e;
        }
    }

    return @non_functions;
}

1;

__END__

=head1 NAME

Test::Kit2 - Build custom test packages with only the features you want

=head1 DESCRIPTION

Test::Kit2 allows you to create a single module in your project which gives you
access to all of the testing functions you want.

Its primary goal is to reduce boilerplate code that is currently littering the
top of all your test files.

It also allows your testing to be more consistent; for example it becomes a
trivial change to include Test::FailWarnings in all of your tests, and there is
no danger that you forget to include it in a new test.

=head1 SYNOPSIS

Somewhere in your project...

    package MyProject::Test;

    use Test::Kit2;

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

This means that Test::Kit2 was unable to determine which module include() was
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

Test::Kit2 intends to install its own import method into your module,
specifically it is going to install Test::Builder::Module's import() method.
Test::Builder::Module is an Exporter, so if you want to define your own
subroutines and export those you can push onto @EXPORT after all the calls to
include().

=head1 ISSUES

=head2 Non-subroutine Exports

For subroutine exports we are able to know exactly what subroutines are
exported by using a given module using a combination of Import::Into and
namespace::clean. Unfortunately the same trick does not work for exported SCALARs.

This is because the most common case we're trying to handle is the '$TODO'
variable from Test::More, but it's impossible to catch that in the symbol table
because every symbol table entry has a scalar no matter what. ie the following
two packages are indistinguishable:

    # One
    package foo;
    our $x = undef;
    our @x = qw(a b c);

    # Two
    package foo;
    our @x = qw(a b c);

So, instead, Test::Kit2 simply assumes that the package is an Exporter and walks
its @EXPORT array for things which start with '$', '@' or '%'.

This at least works for the $Test::More::TODO case, which is the most common.

=cut
