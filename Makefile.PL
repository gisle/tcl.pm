# before running this script make sure you have 'tclsh' in your path, 
# and this 'tcl' distribution is required one.
# FreeBSD users may want to modify name of tcl interpreter (this is
# $tclsh variable below) as long as 'tclsh' does not work in their case

my $tclsh = 'tclsh';

open TCLSH, "$tclsh tclcfg.tcl |";
my $tclcfg = join '', <TCLSH>;
print $tclcfg;
my %tclcfg = $tclcfg =~ /^(\w+)=(.*?)\n/gm;
my $tclver = $tclcfg{tcl_version};
my $libpref = '';

if ($tclcfg{tcl_library} =~ /^(.*)[\\\/]lib[\\\/]/) {
    $tclcfg{libpath} = "-L$1/lib";
    $tclcfg{incpath} = "-I$1/include";
}

if ($^O eq 'MSWin32') {
    $tclver=~s/\.//;
}
elsif ($^O eq 'freebsd') {
    $tclver=~s/\.//;
    $tclsh=~/([\d.]+)$/ and $tclcfg{incpath} .= " -I/usr/local/include/tcl$1";
}
else {
    $tclver = '';
}

use ExtUtils::MakeMaker;
#print <<"#EOS";
WriteMakefile(
    NAME => "Tcl",
    VERSION_FROM => 'Tcl.pm',
    LIBS => ["$tclcfg{libpath} -l${libpref}tcl$tclver"],
    INC => "$tclcfg{incpath}",
);

#EOS
