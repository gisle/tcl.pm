use warnings;
use strict;

use Test;
BEGIN { plan tests => 3, todo => [2] }

use Tcl;

my $i1 = new Tcl;
my $i2 = new Tcl;

my $cmd1 = $i1->create_tcl_sub(sub {'foo'}, undef, undef, 'same_cmd_name');
ok($i1->invoke($cmd1), 'foo');

my $cmd2 = $i2->create_tcl_sub(sub {'bar'}, undef, undef, 'same_cmd_name');
my $cmd1result;
eval {
    $cmd1result = $i1->invoke($cmd1);
    1;
} or do {
    my $err = $@ || 'unknown error';
    print "# $err";
};
ok($cmd1result, 'foo');
ok($i2->invoke($cmd2), 'bar');
