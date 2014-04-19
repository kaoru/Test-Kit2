package MyTest::Rename;

use strict;
use warnings;

use Test::Kit2;

include 'Test::More' => {
    rename => {
        ok => 'is_true',
        is => 'equal',
        pass => 'ok', # evil!
    },
};

1;
