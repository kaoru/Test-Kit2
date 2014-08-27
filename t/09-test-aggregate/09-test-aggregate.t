use strict;
use warnings;

use Test::Aggregate;

if ($Test::Builder::VERSION >= 1.3) {
    plan skip_all => "Test::Aggregate does not work on Test::Builder $Test::Builder::VERSION";
}

my $tests = Test::Aggregate->new({
    tests => [ sort glob('t/09-test-aggregate/tests/*.ta') ],
});

$tests->run;
