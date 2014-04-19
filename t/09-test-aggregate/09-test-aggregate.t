use strict;
use warnings;

use Test::Aggregate;

my $tests = Test::Aggregate->new({
    tests => [ sort glob('t/09-test-aggregate/tests/*.ta') ],
});

$tests->run;
