package Tcl;
use Carp;

$Tcl::VERSION = '0.72';

=head1 NAME

Tcl - Tcl extension module for Perl

=head1 SYNOPSIS

    use Tcl;

    $interp = new Tcl;
    $interp->Eval('puts "Hello world"');

=head1 DESCRIPTION

The Tcl extension module gives access to the Tcl library with
functionality and interface similar to the C functions of Tcl.
In other words, you can

=over 8

=item create Tcl interpreters

The Tcl interpreters so created are Perl objects whose destructors
delete the interpreters cleanly when appropriate.

=item execute Tcl code in an interpreter

The code can come from strings, files or Perl filehandles.

=item bind in new Tcl procedures

The new procedures can be either C code (with addresses presumably
obtained using I<dl_open> and I<dl_find_symbol>) or Perl subroutines
(by name, reference or as anonymous subs). The (optional) deleteProc
callback in the latter case is another perl subroutine which is called
when the command is explicitly deleted by name or else when the
destructor for the interpreter object is explicitly or implicitly called.

=item Manipulate the result field of a Tcl interpreter

=item Set and get values of variables in a Tcl interpreter

=item Tie perl variables to variables in a Tcl interpreter

The variables can be either scalars or hashes.

=back

=head2 Methods in class Tcl

To create a new Tcl interpreter, use

    $i = new Tcl;

The following methods and routines can then be used on the Perl object
returned (the object argument omitted in each case).

=over 8

=item Init ()

Invoke I<Tcl_Init> on the interpeter.

=item Eval (STRING)

Evaluate script STRING in the interpreter. If the script returns
successfully (TCL_OK) then the Perl return value corresponds to
interp->result otherwise a I<die> exception is raised with the $@
variable corresponding to interp->result. In each case, I<corresponds>
means that if the method is called in scalar context then the string
interp->result is returned but if the method is called in list context
then interp->result is split as a Tcl list and returned as a Perl list.

=item GlobalEval (STRING)

Evalulate script STRING at global level. Otherwise, the same as
I<Eval>() above.

=item EvalFile (FILENAME)

Evaluate the contents of the file with name FILENAME. Otherwise, the
same as I<Eval>() above.

=item EvalFileHandle (FILEHANDLE)

Evaluate the contents of the Perl filehandle FILEHANDLE. Otherwise, the
same as I<Eval>() above. Useful when using the filehandle DATA to tack
on a Tcl script following an __END__ token.

=item call (PROC, ARG, ...)

Looks up procedure PROC in the interpreter and invokes it directly with
arguments (ARG, ...) without passing through the Tcl parser. For example,
spaces embedded in any ARG will not cause it to be split into two Tcl
arguments before being passed to PROC.

Before invoking procedure PROC special processing is performed on ARG list:

1.  All subroutine references within ARG will be substituted with Tcl name
which is responsible to invoke this subroutine. This Tcl name will be
created using CreateCommand subroutine (see below).

2.  All references to scalars will be substituted with names of Tcl variables
transformed appropriately.

These first two items allows to write and expect it to work properly such
code as:

  my $r = 'aaaa';
  button(".d", -textvariable => \$r, -command=>sub {$r++});

3.  As a special case, it is supported a mechanism to deal with Tk's special
event variables (they are mentioned as '%x', '%y' and so on throughout Tcl).
Before suborutine reference that uses such variables there must be placed a 
reference to reference to a string that enumerates all desired fields.
After this is done, access to event fields is performed via Tcl::Ev subroutine.
Example:

  $widget->bind('text', '<2>', \\'xy', sub {textPaste ($c)} );
  sub textPaste {
    my ($w,$x,$y) = (shift, Tcl::Ev('x'), Tcl::Ev('y'));
    widget($w)->insert('text', "\@$x,$y", $interp->Eval('selection get'));
  }


=item Tcl::Ev (FEILD)

Returns Tcl/Tk special event field designated by argument FIELD. FIELD must
be single character. Before invoking Tcl::Ev a subroutine that will call it
must enlist appropriate fields in argument list before appropriate code
reference in call to Tcl. See description of 'call' method for details.

=item result ()

Returns the current interp->result field. List v. scalar context is
handled as in I<Eval>() above.

=item CreateCommand (CMDNAME, CMDPROC, CLIENTDATA, DELETEPROC)

Binds a new procedure named CMDNAME into the interpreter. The
CLIENTDATA and DELETEPROC arguments are optional. There are two cases:

(1) CMDPROC is the address of a C function

(presumably obtained using I<dl_open> and I<dl_find_symbol>. In this case
CLIENTDATA and DELETEPROC are taken to be raw data of the ClientData and
deleteProc field presumably obtained in a similar way.

(2) CMDPROC is a Perl subroutine

(either a sub name, a sub reference or an anonymous sub). In this case
CLIENTDATA can be any perl scalar (e.g. a ref to some other data) and
DELETEPROC must be a perl sub too. When CMDNAME is invoked in the Tcl
interpeter, the arguments passed to the Perl sub CMDPROC are

    (CLIENTDATA, INTERP, LIST)

where INTERP is a Perl object for the Tcl interpreter which called out
and LIST is a Perl list of the arguments CMDNAME was called with.
As usual in Tcl, the first element of the list is CMDNAME itself.
When CMDNAME is deleted from the interpreter (either explicitly with
I<DeleteCommand> or because the destructor for the interpeter object
is called), it is passed the single argument CLIENTDATA.

=item DeleteCommand (CMDNAME)

Deletes command CMDNAME from the interpreter. If the command was created
with a DELETEPROC (see I<CreateCommand> above), then it is invoked at
this point. When a Tcl interpreter object is destroyed either explicitly
or implicitly, an implicit I<DeleteCommand> happens on all its currently
registered commands.

=item SetResult (STRING)

Sets interp->result to STRING.

=item AppendResult (LIST)

Appends each element of LIST to interp->result.

=item AppendElement (STRING)

Appends STRING to interp->result as an extra Tcl list element.

=item ResetResult ()

Resets interp->result.

=item SplitList (STRING)

Splits STRING as a Tcl list. Returns a Perl list or the empty list if
there was an error (i.e. STRING was not a properly formed Tcl list).
In the latter case, the error message is left in interp->result.

=item SetVar (VARNAME, VALUE, FLAGS)

The FLAGS field is optional. Sets Tcl variable VARNAME in the
interpreter to VALUE. The FLAGS argument is the usual Tcl one and
can be a bitwise OR of the constants $Tcl::GLOBAL_ONLY,
$Tcl::LEAVE_ERR_MSG, $Tcl::APPEND_VALUE, $Tcl::LIST_ELEMENT.

=item SetVar2 (VARNAME1, VARNAME2, VALUE, FLAGS)

Sets the element VARNAME1(VARNAME2) of a Tcl array to VALUE. The optional
argument FLAGS behaves as in I<SetVar> above.

=item GetVar (VARNAME, FLAGS)

Returns the value of Tcl variable VARNAME. The optional argument FLAGS
behaves as in I<SetVar> above.

=item GetVar2 (VARNAME1, VARNAME2, FLAGS)

Returns the value of the element VARNAME1(VARNAME2) of a Tcl array.
The optional argument FLAGS behaves as in I<SetVar> above.

=item UnsetVar (VARNAME, FLAGS)

Unsets Tcl variable VARNAME. The optional argument FLAGS
behaves as in I<SetVar> above.

=item UnsetVar2 (VARNAME1, VARNAME2, FLAGS)

Unsets the element VARNAME1(VARNAME2) of a Tcl array.
The optional argument FLAGS behaves as in I<SetVar> above.

=back

=head2 Linking Perl and Tcl variables

You can I<tie> a Perl variable (scalar or hash) into class Tcl::Var
so that changes to a Tcl variable automatically "change" the value
of the Perl variable. In fact, as usual with Perl tied variables,
its current value is just fetched from the Tcl variable when needed
and setting the Perl variable triggers the setting of the Tcl variable.

To tie a Perl scalar I<$scalar> to the Tcl variable I<tclscalar> in
interpreter I<$interp> with optional flags I<$flags> (see I<SetVar>
above), use

	tie $scalar, Tcl::Var, $interp, "tclscalar", $flags;

Omit the I<$flags> argument if not wanted.

To tie a Perl hash I<%hash> to the Tcl array variable I<array> in
interpreter I<$interp> with optional flags I<$flags>
(see I<SetVar> above), use

	tie %hash, Tcl::Var, $interp, "array", $flags;

Omit the I<$flags> argument if not wanted. Any alteration to Perl
variable I<$hash{"key"}> affects the Tcl variable I<array(key)>
and I<vice versa>.

=head1 AUTHORS

Malcolm Beattie, mbeattie@sable.ox.ac.uk, 23 Oct 1994.
Vadim Konovalov, vkonovalov@peterstar.ru, 19 May 2003.

=head1 COPYRIGHT

This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

See http://www.perl.com/perl/misc/Artistic.html

=cut

use strict;
use DynaLoader;
unless (defined $Tcl::Tk::VERSION) {
  package Tcl::Tk; # define empty package
}
use vars qw(@ISA);
@ISA = qw(DynaLoader Tcl::Tk);

sub OK ()	{ 0 }
sub ERROR ()	{ 1 }
sub RETURN ()	{ 2 }
sub BREAK ()	{ 3 }
sub CONTINUE ()	{ 4 }

sub GLOBAL_ONLY ()	{ 1 }
sub APPEND_VALUE ()	{ 2 }
sub LIST_ELEMENT ()	{ 4 }
sub TRACE_READS ()	{ 0x10 }
sub TRACE_WRITES ()	{ 0x20 }
sub TRACE_UNSETS ()	{ 0x40 }
sub TRACE_DESTROYED ()	{ 0x80 }
sub INTERP_DESTROYED ()	{ 0x100 }
sub LEAVE_ERR_MSG ()	{ 0x200 }

sub LINK_INT ()		{ 1 }
sub LINK_DOUBLE ()	{ 2 }
sub LINK_BOOLEAN ()	{ 3 }
sub LINK_STRING ()	{ 4 }
sub LINK_READ_ONLY ()	{ 0x80 }

bootstrap Tcl;

#TODO make better wording here
# %anon_refs keeps track of anonymous subroutines that were created with
# "CreateComand" method during process of transformation of arguments for "call"
# and other stuff such as scalar refs and so on.
# (TODO -- find out how to check for refcounting and proper releasing of resources)
my %anon_refs;

# subroutine "call" checks for its parameters, adopts them and calls "icall"
# method which implemented in Tcl.xs file and does essential work
sub call {
  if (0) {
    local $"=',';
    print STDERR "{{@_}}\n";
  };
  # look for CODE and ARRAY refs and substitute them with working code fragments
  my $interp = shift;
  my @args = @_; # this could be optimized
  for (my $argcnt=0; $argcnt<=$#args; $argcnt++) {
    my $arg = $args[$argcnt];
    if (ref($arg) eq 'CODE') {
      $args[$argcnt] = $interp->create_tcl_sub($arg);
    }
    elsif (ref($arg) eq 'Tcl::Tk::Widget' || ref($arg) eq 'Tcl::Tk::Widget::MainWindow') {
      $args[$argcnt] = $$arg; # this trick will help manipulate widgets
    }
    elsif (ref($arg) eq 'SCALAR') {
      my $nm = "$arg"; # stringify scalar ref ...
      $nm =~ s/\W/_/g;
      unless (exists $anon_refs{$nm}) {
        $anon_refs{$nm}++;
	my $s = $$arg;
	tie $$arg, 'Tcl::Var', $interp, $nm;
	$$arg = $s;
      }
      $args[$argcnt] = $nm; # ... and substitute its name
    }
    if (ref($arg) eq 'REF' and ref($$arg) eq 'SCALAR') {
      # this is a very special case: if we see construct like \\"xy" then
      # we must prepare TCL-events variables such as TCL variables %x, %y
      # and so on, and next must be code reference for subroutine that will
      # use those variables.
      # TODO - implement better way, using OO and blessing into special package
      if (ref($args[$argcnt+1]) ne 'CODE') {
	warn "CODE reference expected after description of event fields";
	next;
      }
      $args[$argcnt] = $interp->create_tcl_sub($args[$argcnt+1],$$$arg);
      splice @args, $argcnt+1, 1;
    }
    elsif ((ref($arg) eq 'ARRAY') and (ref($arg->[0]) eq 'CODE')) {
      $args[$argcnt] = $interp->create_tcl_sub(sub {$arg->[0]->(@$arg[1..$#$arg])});
      die "Implement this! (array ref that means subroutine and its parameters)";
    }
  }
  my (@res,$res);
  eval {
    @res = $interp->icall(@args);
  };
  if ($@) {
    confess "Tcl error $@ while invoking call\n \"@args\"";
  }
  return @res if wantarray;
  return $res[0];
}

# create_tcl_sub will create TCL sub that will invoke perl anonymous sub
# if $events variable is specified then special processing will be
# performed to provide needed '%' variables
# if $tclname is specified then procedure will have namely that name, otherwise
# it will have machine-readable name
# returns tcl script suitable for using in tcl events
my %Ev_helper;
sub create_tcl_sub {
  my ($interp,$sub,$events,$tclname) = @_;
  unless ($tclname) {
    $tclname = "$sub"; # stringify subroutine ...
    $tclname =~ s/\W/_/g;
  }
  unless (exists $anon_refs{$tclname}) {
    $anon_refs{$tclname}++;
    $interp->CreateCommand($tclname, $sub);
  }
  if ($events) {
    $tclname = (join '', map {"set _ptcl_ev$_ %$_;"} split '', $events) . "$tclname";
    $tclname =~ s/_ptcl_ev(?:#|%)/"_ptcl_ev".($1 eq '#'?'_sharp':'_perc')/eg;
    for (split '', $events) {
      $Ev_helper{$_} = $interp;
    }
  }
  $tclname;
}
sub Ev {
  my $s = shift;
  if (length($s)>1) {
    warn "Event variable must have length 1";
    return;
  }
  if ($s eq '%') {$s = '_perc'}
  elsif ($s eq '#') {$s = '_sharp'}
  return $Ev_helper{$s}->GetVar("_ptcl_ev$s");
}
sub ev_sub {
  my ($interp,$events,$sub) = @_;
  return $interp->create_tcl_sub($sub,$events);
}


package Tcl::Var;

sub TIESCALAR {
    my $class = shift;
    my @objdata = @_;
    Carp::croak 'Usage: tie $s, Tcl::Var, $interp, $varname [, $flags]'
	unless @_ == 2 || @_ == 3;
    bless \@objdata, $class;
}

sub TIEHASH {
    my $class = shift;
    my @objdata = @_;
    Carp::croak 'Usage: tie %hash, Tcl::Var, $interp, $varname [, $flags]'
	unless @_ == 2 || @_ == 3;
    bless \@objdata, $class;
}

sub UNTIE {
    my $ref = shift;
    print STDERR "UNTIE:$ref(@_)\n"; # Why this never called?
}
sub DESTROY {
    my $ref = shift;
    delete $anon_refs{$ref->[1]};
}

1;
__END__
