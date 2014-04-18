package Test::Kit2;

use strict;
use warnings;
use namespace::clean ();
use Import::Into;
use Module::Runtime 'use_module';
use Storable; # we need to do evil evil things to rename!
use Sub::Delete; # seriously, just don't look here!

=head1 NAME

Test::Kit2 - Build custom test packages with only the features you want

=head1 SYNOPSIS

In a module somewhere in your project...

    package MyProject::Test;

    use Test::Kit2;

    Test::Kit2->include('Test::More');
    Test::Kit2->include('Test::LongString');

    Test::Kit2->include({
        'Test::Warn' => {
            exclude => [ 'warning_is' ],
            renamed => {
                'warning_like' => 'test_warn_warning_like'
            },
        }
    });

=cut

# deep strucutre:
#
# my %collission_check_cache = (
#     'MyTest::Awesome' => {
#         'ok' => 'Test::More',
#         'pass' => 'Test::More',
#         'warnings_are' => 'Test::Warn',
#         ...
#     },
#     ...
# )
#
my %collission_check_cache;

sub include {
    my $class = shift;
    my $to_include = shift;

    if (!ref($to_include)) {
        $to_include = { $to_include => {} };
    }

    return $class->_include($to_include);
}

sub _include {
    my $class = shift;
    my $include_hashref = shift;

    my $target = $class->_get_class_to_import_into();

    for my $pkg (sort keys %$include_hashref) {
        my $fake_pkg = $class->_create_fake_package($pkg, $include_hashref->{$pkg});
        $fake_pkg->import::into($target);
    }

    return;
}

sub _get_class_to_import_into {
    my $class = shift;

    # so, as far as I can tell, on Perl 5.14 and 5.16 at least, we have the
    # following callstack...
    #
    # 1. Test::Kit2::_simple_include
    # 2. Test::Kit2::include
    # 3. (eval)
    # 4. MyModule::BEGIN
    # 5. (eval)
    #
    # ... and we want to get the package name "MyModule" out of there.
    # So, let's look for the first occurrence of BEGIN or something!

    my @begins = grep { m/::BEGIN$/ }
                 map  { (caller($_))[3] }
                 1 .. 20;

    if ($begins[0] && $begins[0] =~ m/^ (.+) ::BEGIN $/msx) {
        return $1;
    }

    die "Unable to find class to import into";
}

sub _create_fake_package {
    my $class = shift;
    my $pkg = shift;
    my $pkg_include_hashref = shift;

    my $fake_pkg = "Test::Kit::Fake::$pkg";

    my %exclude = map { $_ => 1 } @{ $pkg_include_hashref->{exclude} || [] };
    my %rename = %{ $pkg_include_hashref->{rename} || {} };

    use_module($pkg)->import::into($fake_pkg);
    my $functions_exported_by_pkg = namespace::clean->get_functions($fake_pkg);

    my @functions_to_install = (
        (grep { !$exclude{$_} && !$rename{$_} } keys %$functions_exported_by_pkg),
        (values %rename)
    );
    $class->_check_collissions($pkg, \@functions_to_install);

    {
        no strict 'refs';
        no warnings 'redefine';

        push @{ "$fake_pkg\::ISA" }, 'Exporter';
        @{ "$fake_pkg\::EXPORT" } = @functions_to_install;

        for my $from (sort keys %rename) {
            my $to = $rename{$from};

            local $Storable::Deparse = 1;
            local $Storable::Eval = 1;

            *{ "$fake_pkg\::$to" } = Storable::dclone(\&{ "$fake_pkg\::$from" });

            delete_sub("$fake_pkg\::$from");
        }
    }

    return $fake_pkg;
}

sub _check_collissions {
    my $class = shift;
    my $pkg = shift;
    my $functions_to_install = shift;

    my $target = $class->_get_class_to_import_into();

    for my $function (@$functions_to_install) {
        if (exists $collission_check_cache{$target}{$function} && $collission_check_cache{$target}{$function} ne $pkg) {
            die sprintf("subroutine %s() already supplied by %s into %s",
                $function,
                $collission_check_cache{$target}{$function},
                $target
            );
        }
        else {
            $collission_check_cache{$target}{$function} = $pkg;
        }
    }

    return;
}

1;
