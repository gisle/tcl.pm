use strict;
use warnings;

use Tcl;

$| = 1;

print "1..2\n";

my $i = new Tcl;

tie my $perlscalar, 'Tcl::Var', $i, "tclscalar";
tie my %perlhash, 'Tcl::Var', $i, "tclhash";

$i->Eval('set tclscalar ok; set tclhash(key) 1');
printf "%s %s\n", $perlscalar, $perlhash{"key"};
$perlscalar = "newvalue";
$perlhash{"newkey"} = 2;
$i->Eval(<<'EOT');
if {($tclscalar == "newvalue") && ($tclhash(newkey) == 2)} {
    puts "ok 2"
} else {
    puts "not ok 2"
}
EOT
