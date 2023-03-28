use Tcl;

$| = 1;

print "1..18\n";

sub foo {
    my $interp = $_[1];
    my $glob = $interp->GetVar("bar", Tcl::GLOBAL_ONLY);
    my $loc = $interp->GetVar("bar");
    print "$glob $loc\n";
    $interp->Eval('puts $four', Tcl::EVAL_GLOBAL);
}

$i = Tcl->new;

$i->SetVar("foo", "ok 1");
$i->Eval('puts $foo');

$i->Eval('set foo "ok 2\n"');
print $i->GetVar("foo");

$i->CreateCommand("foo", \&foo);
$i->Eval(<<'EOT');
set bar ok
set four "ok 4"
proc baz {} {
    set bar 3
    set four "not ok 4"
    foo
}
baz
EOT

$i->Eval('set a(OK) ok; set a(five) 5');
$ok = $i->GetVar2("a", "OK");
$five = $i->GetVar2("a", "five");
print "$ok $five\n";

print defined($i->GetVar("nonesuch")) ? "not ok 6\n" : "ok 6\n";

# some Unicode tests
if ($]>=5.006) {
    $i->SetVar("univar","\x{abcd}\x{1234}");
    if ($i->GetVar("univar") ne "\x{abcd}\x{1234}") {
	print "not ";
    }
    print "ok 7 # Unicode persistence during [SG]etVar\n";
    my $r;
    tie $r, Tcl::Var, $i, "perl_r";
    $r = "\x{abcd}\x{1234}";
    if ($r ne "\x{abcd}\x{1234}") {
	print "not ";
    }
    print "ok 8 # Unicode persistence for tied variable\n";
    binmode(STDOUT, ":utf8") if $] >= 5.008;
    print "# $r\n";
}
else {
    for (7..8) {print "ok $_  # skipped: not Unicode-aware Perl\n";}
}

# array tie test
{
  my @ary = ();
  tie @ary, "Tcl::AList", $i, "t_list";
  $i->Eval('set t_list [ list a "b c" "d e f" ]');
  print "not " unless(@ary == 3);
  print "ok 9 list has correct length\n";
  print "not " unless($ary[0] eq 'a' && $ary[1] eq 'b c' && $ary[2] eq 'd e f');
  print "ok 10 list has correct content\n";
  my $x = shift(@ary);
  print "not " unless($x eq 'a');
  print "ok 11 shift return the first element\n";
  $x = $i->Eval('concat "$t_list" ""');
  print "not " unless($x eq '{b c} {d e f}');
  print "ok 12 shift action is visible in Tcl\n";
  $x = pop(@ary);
  print "not " unless($x eq 'd e f');
  print "ok 13 pop returns the correct value\n";
  $x = $i->Eval('concat "$t_list" ""');
  print "not " unless($x eq '{b c}');
  print "ok 14 pop action is visible in Tcl\n";
  unshift(@ary, 'aaa');
  $x = $i->Eval('concat "$t_list" ""');
  print "not " unless($x eq 'aaa {b c}');
  print "ok 15 unshift action is visible in Tcl\n";
  push(@ary, 'xxx');
  $x = $i->Eval('concat "$t_list" ""');
  print "not " unless($x eq 'aaa {b c} xxx');
  print "ok 16 push action is visible in Tcl\n";
  $x = delete($ary[1]);
  #print "# ary is '@ary' x is $x\n";
  print "not " unless($x eq 'b c');
  print "ok 17 delete returned correct value\n";
  $x = $i->Eval('concat "$t_list" ""');
  print "not " unless($x eq 'aaa xxx');
  print "ok 18 delete action is visible in Tcl\n";
}

