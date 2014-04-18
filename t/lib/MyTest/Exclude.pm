package MyTest::Exclude;

use strict;
use warnings;

use Test::Kit2;

Test::Kit2->include({
    'Test::More' => {
        exclude => [ 'pass', 'fail' ],    
    },
});

1;
