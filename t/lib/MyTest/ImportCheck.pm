package MyTest::ImportCheck;

use strict;
use warnings;

sub import { "foo" }

use Test::Kit2;

Test::Kit2->include('Test::More');

1;
