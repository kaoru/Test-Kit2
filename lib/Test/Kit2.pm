package Test::Kit2;

use strict;
use warnings;

use namespace::clean ();
use Import::Into;
use Module::Runtime 'use_module';

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

sub include {
    my $class = shift;
    my $to_include = shift;

    if (ref($to_include) eq 'HASH') {
        $class->_complex_include($to_include);
    }
    else {
        $class->_simple_include($to_include);
    }

    return;

}

sub _simple_include {
    my $class = shift;
    my $class_to_include = shift;

    my $class_to_import_into = $class->_get_class_to_import_into();
    use_module($class_to_include)->import::into($class_to_import_into);

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

1;
