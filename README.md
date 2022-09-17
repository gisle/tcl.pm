# Tcl perl module for Perl5

Interface to `Tcl` and `Tcl/Tk`

# Description

The Tcl extension provides a small but complete interface into `libtcl` and
any other Tcl-based library. It lets you create Tcl interpreters as perl5
objects, execute Tcl code in those interpreters and so on. There is a `Tcl::Tk`
extension (not to be confused with "native" perl5 Perl/Tk extension)
distributed separately which provides a raw but complete interface to the
whole of libtk via this Tcl extension.

Using "tcl stubs", module could be built even without tcl-dev package
installed on system. Still, tcl (or tcl/tk) must be installed during module
build. `--nousestubs` also supported. Tcl versions 8.4, 8.5, 8.6 and above are
supported.

# Install

Build in the usual way for a perl extension:

       perl Makefile.PL
       make
       make test
       make install

This will take reasonable defaults on your system and should be ok for most
uses. In some rare cases you need to specify parameters to `Makefile.PL`, such
as pointing non-standard locations of `tcl/tk`, etc. Use `--help` option to find
out supported parameters to `Makefile.PL`:

       perl Makefile.PL --help

# License

See License, Authors sections in `Tcl.pm`, or with `perldoc Tcl` - once it
is installed - to have acknowledged on this type of information.

