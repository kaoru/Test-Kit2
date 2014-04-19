use strict;
use warnings;

use Test::Aggregate::Nested;

my $tests = Test::Aggregate::Nested->new({
    tests => [ sort glob('t/09-test-aggregate/tests/*.ta') ],
});

$tests->run;
