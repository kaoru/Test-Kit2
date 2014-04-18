package MyTest::SubNameCollideFixed;

use strict;
use warnings;

use Test::Kit2;

Test::Kit2->include('Test::More');

Test::Kit2->include({
    'Test::Simple' => {
        'rename' => { 'ok' => 'test_simple_ok' },
    },
});

1;
