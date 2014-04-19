package MyTest::ListUtil;

use strict;
use warnings;

use Test::Kit2;

include 'Test::More';

include 'List::Util' => {
    'import' => [ 'min', 'max', 'shuffle' ],
};

1;
