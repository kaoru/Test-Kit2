use strict;
use warnings;
use lib 't/lib';

# Basic - test that Test::Simple by itself can be Kit2'd

use MyTest::Basic;

ok(1, "ok() exists");

done_testing();
