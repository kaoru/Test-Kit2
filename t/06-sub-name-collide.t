use strict;
use warnings;
use lib 't/lib';

use Test::More;

# Sub Name Collide - test that Test::Kit2 dies on sub name collisions

eval "use MyTest::SubNameCollide;";
like(
    $@,
    qr/\Qsubroutine ok() already supplied by Test::More\E/,
    'sub name collission throws an exception'
);

eval "use MyTest::SubNameCollideFixed; ok(1, 'ok() from Test::More'); test_simple_ok(1, 'test_simple_ok() from Test::Simple');";
like(
    $@,
    qr//,
    'sub name collission can be fixed by use of the rename feature'
);

done_testing();
