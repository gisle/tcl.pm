# this perl script prepares already built module to have moveable Tcl/Tk,
# so that after installation only given Tcl/Tk will be used

# parameters - 
#  - directory with Tcl/Tk installation (either "live" installation, or manually prepared)

my $idir = shift;
die "directory '$idir' must exist" unless -d $idir;

my $type = 2;

system(qw/cp -R/, $idir, "blib/lib/");

(my $tclpath) = $idir=~/[\\\/]([^\\\/]+)$/g;
my $tcldll = $^O eq 'MSWin32'? '\bin\tcl84.dll' : "lib/libtsl.so";  # ? TBD

if ($type == 2) {
  open my $fhout, ">blib/lib/Tcl.cfg";
  print $fhout <<"EOS";
\$Tcl::config::tcl_path = \$Tcl::config::tcl_pm_path.'$tclpath';
# preload dll, so bootstrap will find it
DynaLoader::dl_load_file(\$Tcl::config::tcl_path.'$tcldll',0);
EOS
}
else {
   die "type $type is done differently";
}
