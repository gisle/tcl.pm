# before running this script make sure you have 'tclsh' in your path, 
# and this 'tcl' distribution is required one.
# FreeBSD users may want to modify name of tcl interpreter (this is
# $tclsh variable below) as long as 'tclsh' does not work in their case

my $tclsh = 'tclsh';
my $tclconfig;
my $buildspec;
my $libpath;
my $incpath;

while (1) {
    # Handle any --options
    last unless @ARGV[0] =~ /^--/;
    my $opt = shift @ARGV;
    my $val = shift @ARGV;
    if ($opt eq "--tclsh") {
	$tclsh = $val;
    }
    elsif ($opt eq "--tclconfig") {
	$tclconfig = $val;
    }
    elsif ($opt eq "--buildspec") {
	$buildspec = 1;
    }
    else {
	die "unknown option '$opt', must be --tclsh, --tclconfig or --buildspec\n";
    }
}


if ($tclconfig) {
    die "Tcl config file '$tclconfig' not found\n" unless (-f $tclconfig);
    # Retrieve all info based on tclConfig.sh
    my $libspecvar = "TCL_BUILD_LIB_SPEC" if $buildspec;
    ($libpath, $incpath) = process_tclconfig($tclconfig, $libspecvar);
} else {
    open(TCLSH, "$tclsh tclcfg.tcl |") or die "error starting tclsh: $!\n";
    my $tclcfg = join '', <TCLSH>;
    close(TCLSH);
    print $tclcfg;
    my %tclcfg = $tclcfg =~ /^([^=]+)=(.*?)\n/gm;

    if (0 && -f $tclcfg{'tclConfig.sh'}) {
	# Retrieve all info based on tclConfig.sh
	# Don't do this unless the user passes --tclconfig
	($libpath, $incpath) = process_tclconfig($tclcfg{'tclConfig.sh'});
    } else {
	my $tclver = $tclcfg{tcl_version};
	if ($tclcfg{tcl_library} =~ /^(.*)[\\\/]lib[\\\/]/) {
	    $libpath = "-L$1/lib";
	    $incpath = "-I$1/include";
	}

	if ($^O eq 'MSWin32') {
	    $tclver=~s/\.//;
	}
	elsif ($^O eq 'freebsd') {
	    $tclver=~s/\.//;
	    $tclsh=~/([\d.]+)$/ and $incpath .= " -I/usr/local/include/tcl$1";
	}
	else {
	    $tclver = '';
	}
	$libpath .= " -ltcl$tclver";
    }
}
print "LIBS = $libpath\n";
print "INC  = $incpath\n";

use ExtUtils::MakeMaker;
#print <<"#EOS";
WriteMakefile(
    NAME => "Tcl",
    VERSION_FROM => 'Tcl.pm',
    LIBS => ["$libpath"],
    INC => "$incpath",
);

#EOS

sub process_tclconfig {
    # Process a tclConfig.sh file for build info
    my $tclconfig = shift;
    my $libspecvar = shift || "TCL_LIB_SPEC";
    my $incspecvar = shift || "TCL_INCLUDE_SPEC";

    open(TCLSH, $tclconfig)
	or die "error opening file '$tclconfig': $!\n";
    print "Using config data in $tclconfig\n";
    my $tclcfg = join '', <TCLSH>;
    close(TCLSH);
    my %tclcfg = $tclcfg =~ /^(\w+)=['"]?(.*?)["']?\n/gm;

    # Handle sh subs like ${TCL_DBGX}
    $tclcfg{$libspecvar} =~ s/\$\{(\w+)\}/$tclcfg{$1}/g;
    # Handle any cygdrive-style paths
    $tclcfg{$libspecvar} =~ s,/cygdrive/(\w)/,$1:/,ig;
    return $tclcfg{$libspecvar}, $tclcfg{$incspecvar};
}
