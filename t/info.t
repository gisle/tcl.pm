#!perl -w

use strict;
use Test qw(plan ok);

plan tests => 2;

use Tcl;
my $tcl = Tcl->new;

ok($tcl);
ok($tcl->Eval("info nameofexecutable"), $^X);

