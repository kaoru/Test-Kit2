package MyTest::PutItAllTogether;

use strict;
use warnings;

use Test::Kit2;

Test::Kit2->include({
    'Test::More' => {
        exclude => [ 'fail' ],
        rename => {
            is => 'equal',
        },
    },
});

Test::Kit2->include('Test::Warn');

Test::Kit2->include('Test::Exception');

1;
