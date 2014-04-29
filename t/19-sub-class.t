use strict;
use warnings;
use lib 't/lib';

# Test that Test::Kit2 can be sub-classed

use MyTest::SubClassUser;

ok(1, "ok() exists");

done_testing();
