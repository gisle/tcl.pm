/* 
 * Tcl.xs --
 *
 *	This file contains XS code for the Perl's Tcl bridge module.
 *
 * Copyright (c) 1994-1997, Malcolm Beattie
 * Copyright (c) 2003-2004, Vadim Konovalov
 * Copyright (c) 2004 ActiveState Corp., a division of Sophos PLC
 *
 * RCS: @(#) $Id$
 */

#define PERL_NO_GET_CONTEXT     /* we want efficiency */
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#ifndef DEBUG_REFCOUNTS
#define DEBUG_REFCOUNTS 0
#endif

/*
 * Until we update for 8.4 CONST-ness
 */
#define USE_NON_CONST

/*
 * Both Perl and Tcl use this macro
 */
#undef STRINGIFY

#include <tcl.h>

#define Tcl_result(interp) Tcl_GetStringResult(interp)
#define Tcl_DESTROY(interp) Tcl_DeleteInterp(interp)

typedef Tcl_Interp *Tcl;
typedef AV *Tcl__Var;

static int findexecutable_called = 0;

/*
 * Variables denoting the Tcl object types defined in the core.
 */

static Tcl_ObjType *tclBooleanTypePtr = NULL;
static Tcl_ObjType *tclByteArrayTypePtr = NULL;
static Tcl_ObjType *tclDoubleTypePtr = NULL;
static Tcl_ObjType *tclIntTypePtr = NULL;
static Tcl_ObjType *tclListTypePtr = NULL;
static Tcl_ObjType *tclStringTypePtr = NULL;
static Tcl_ObjType *tclWideIntTypePtr = NULL;

#if DEBUG_REFCOUNTS
static void
check_refcounts(Tcl_Obj *objPtr) {
    int rc = objPtr->refCount;
    if (rc != 1) {
	fprintf(stderr, "objPtr %p refcount %d\n", objPtr, rc); fflush(stderr);
    }
    if (objPtr->typePtr == tclListTypePtr) {
	int objc, i;
	Tcl_Obj **objv;

	Tcl_ListObjGetElements(NULL, objPtr, &objc, &objv);
	for (i = 0; i < objc; i++) {
	    check_refcounts(objv[i]);
	}
    }
}
#endif

static int
has_highbit(CONST char *s, int len)
{
    CONST char *e = s + len;
    while (s < e) {
	if (*s++ & 0x80)
	    return 1;
    }
    return 0;
}

static SV *
SvFromTclObj(pTHX_ Tcl_Obj *objPtr)
{
    SV *sv;
    int len;
    char *str;

    if (objPtr == NULL) {
	/*
	 * Use newSV(0) instead of &PL_sv_undef as it may be stored in an AV.
	 * It also provides symmetry with the other newSV* calls below.
	 * This SV will also be mortalized later.
	 */
	sv = newSV(0);
    }
    else if (objPtr->typePtr == tclIntTypePtr) {
	sv = newSViv(objPtr->internalRep.longValue);
    }
    else if (objPtr->typePtr == tclDoubleTypePtr) {
	sv = newSVnv(objPtr->internalRep.doubleValue);
    }
    else if (objPtr->typePtr == tclBooleanTypePtr) {
	sv = newSViv((objPtr->internalRep.longValue != 0));
    }
    else if (objPtr->typePtr == tclByteArrayTypePtr) {
	str = Tcl_GetByteArrayFromObj(objPtr, &len);
	sv = newSVpvn(str, len);
    }
#if 0
    else if (objPtr->typePtr == tclListTypePtr) {
	/*
	 * tclListTypePtr should become an AV.
	 * This code needs to reconcile with G_ context in prepare_Tcl_result
	 * and user's expectations of how data will be passed in.  The key is
	 * that a stringified-list and pure-list should be operable in the
	 * same way in Perl.
	 */
	int objc, i;
	Tcl_Obj **objv;
	AV *av = newAV();

	Tcl_ListObjGetElements(NULL, objPtr, &objc, &objv);
	for (i = 0; i < objc; i++) {
	    av_push(av, SvFromTclObj(aTHX_ objv[i]));
	}
	//sv = (SV *) av;
	sv = newRV_noinc((SV *) av);
    }
#endif
    /* tclStringTypePtr is true unicode */
    /* tclWideIntTypePtr is 64-bit int */
    else {
	str = Tcl_GetStringFromObj(objPtr, &len);
	sv = newSVpvn(str, len);
	/* should turn on, but let's check this first for efficiency */
	if (len && has_highbit(str, len)) {
	    SvUTF8_on(sv);
	}
    }
    return sv;
}

/*
 * Create a Tcl_Obj from a Perl SV.
 * Return Tcl_Obj with refcount = 0.  Caller should call Tcl_IncrRefCount
 * or pass of to function that does (manage object lifetime).
 */
static Tcl_Obj *
TclObjFromSv(pTHX_ SV *sv)
{
    Tcl_Obj *objPtr = NULL;

    if (SvGMAGICAL(sv))
	mg_get(sv);
    
    if (SvROK(sv) && !SvOBJECT(SvRV(sv)) && (SvTYPE(SvRV(sv)) == SVt_PVAV)) {
	/* XXX: Should we add '&& !SvOBJECT(SvRV(sv))' above? */
	/*
	 * Recurse into ARRAYs, turning them into Tcl list Objs
	 */
	SV **svp;
	AV *av    = (AV *) SvRV(sv);
	I32 avlen = av_len(av);
	int i;

	objPtr = Tcl_NewListObj(0, (Tcl_Obj **) NULL);

	for (i = 0; i <= avlen; i++) {
	    svp = av_fetch(av, i, FALSE);
	    if (svp == NULL) {
		/* watch for sparse arrays - translate as empty element */
		/* XXX: Is this handling refcount on NewObj right? */
		Tcl_ListObjAppendElement(NULL, objPtr, Tcl_NewObj());
	    } else {
		if ((AV *) SvRV(*svp) == av) {
		    /* XXX: Is this a proper check for cyclical reference? */
		    croak("cyclical array reference found");
		    abort();
		}
		Tcl_ListObjAppendElement(NULL, objPtr,
			TclObjFromSv(aTHX_ sv_mortalcopy(*svp)));
	    }
	}
    }
    else if (SvPOK(sv)) {
	STRLEN length;
	char *str = SvPV(sv, length);
	objPtr = Tcl_NewStringObj(str, length);
    }
    else if (SvNOK(sv)) {
	objPtr = Tcl_NewDoubleObj(SvNV(sv));
    }
    else if (SvIOK(sv)) {
	objPtr = Tcl_NewIntObj(SvIV(sv));
    }
    else {
	/*
	 * Catch-all
	 * XXX: Should we recurse other REFs, or better to stringify them?
	 */
	STRLEN length;
	char *str = SvPV(sv, length);
	objPtr = Tcl_NewStringObj(str, length);
    }

    return objPtr;
}

int Tcl_PerlCallWrapper(ClientData clientData, Tcl_Interp *interp,
	int objc, Tcl_Obj *CONST objv[])
{
    dTHX; /* fetch context */
    dSP;
    AV *av = (AV *) clientData;
    I32 count;
    SV *sv;
    int rc;

    /*
     * av = [$perlsub, $realclientdata, $interp, $deleteProc]
     * (where $deleteProc is optional but we don't need it here anyway)
     */

    if (AvFILL(av) != 2 && AvFILL(av) != 3)
	croak("bad clientdata argument passed to Tcl_PerlCallWrapper");

    ENTER;
    SAVETMPS;

    PUSHMARK(sp);
    EXTEND(sp, objc + 2);
    PUSHs(sv_mortalcopy(*av_fetch(av, 1, FALSE)));
    PUSHs(sv_mortalcopy(*av_fetch(av, 2, FALSE)));
    while (objc--) {
	PUSHs(sv_2mortal(SvFromTclObj(aTHX_ *objv++)));
    }
    PUTBACK;
    count = perl_call_sv(*av_fetch(av, 0, FALSE), G_EVAL|G_SCALAR);
    SPAGAIN;

    if (SvTRUE(ERRSV)) {
	Tcl_SetResult(interp, SvPV_nolen(ERRSV), TCL_VOLATILE);
	POPs; /* pop the undef off the stack */
	rc = TCL_ERROR;
    }
    else {
	if (count != 1) {
	    croak("Perl sub bound to Tcl proc returned %d args, expected 1",
		    count);
	}
	sv = POPs; /* pop the undef off the stack */

	if (SvOK(sv)) {
	    Tcl_Obj *objPtr = TclObjFromSv(aTHX_ sv);
	    /* Tcl_SetObjResult will incr refcount */
	    Tcl_SetObjResult(interp, objPtr);
	}
	rc = TCL_OK;
    }

    PUTBACK;
    /*
     * If the routine returned undef, it indicates that it has done the
     * SetResult itself and that we should return TCL_ERROR
     */

    FREETMPS;
    LEAVE;
    return rc;
}

void
Tcl_PerlCallDeleteProc(ClientData clientData)
{
    dTHX; /* fetch context */
    AV *av = (AV *) clientData;
    
    /*
     * av = [$perlsub, $realclientdata, $interp, $deleteProc]
     * (where $deleteProc is optional but we don't need it here anyway)
     */

    if (AvFILL(av) == 3) {
	dSP;

	PUSHMARK(sp);
	EXTEND(sp, 1);
	PUSHs(sv_mortalcopy(*av_fetch(av, 1, FALSE)));
	PUTBACK;
	(void) perl_call_sv(*av_fetch(av, 3, FALSE), G_SCALAR|G_DISCARD);
    }
    else if (AvFILL(av) != 2) {
	croak("bad clientdata argument passed to Tcl_PerlCallDeleteProc");
    }

    SvREFCNT_dec(av);
}

void
prepare_Tcl_result(pTHX_ Tcl interp, char *caller)
{
    dSP;
    Tcl_Obj *objPtr, **objv;
    int gimme, objc, i;

    objPtr = Tcl_GetObjResult(interp);

    gimme = GIMME_V;
    if (gimme == G_SCALAR) {
	/*
	 * This checks Tcl_Obj type.  XPUSH not needed because we
	 * are called when there is enough space on the stack.
	 */
	PUSHs(sv_2mortal(SvFromTclObj(aTHX_ objPtr)));
    }
    else if (gimme == G_ARRAY) {
	if (Tcl_ListObjGetElements(interp, objPtr, &objc, &objv)
		!= TCL_OK) {
	    croak("%s called in list context did not return a valid Tcl list",
		    caller);
	}
	if (objc) {
	    EXTEND(sp, objc);
	    for (i = 0; i < objc; i++) {
		/*
		 * This checks Tcl_Obj type
		 */
		PUSHs(sv_2mortal(SvFromTclObj(aTHX_ objv[i])));
	    }
	}
    }
    else {
	/* G_VOID context - ignore result */
    }
    PUTBACK;
    return;
}

char *
var_trace(ClientData clientData, Tcl_Interp *interp,
	char *name1, char *name2, int flags)
{
    dTHX; /* fetch context */

    if (flags & TCL_TRACE_READS) {
        warn("TCL_TRACE_READS\n");
    }
    else if (flags & TCL_TRACE_WRITES) {
        warn("TCL_TRACE_WRITES\n");
    }
    else if (flags & TCL_TRACE_ARRAY) {
        warn("TCL_TRACE_ARRAY\n");
    }
    else if (flags & TCL_TRACE_UNSETS) {
        warn("TCL_TRACE_UNSETS\n");
    }
    return 0;
}

MODULE = Tcl	PACKAGE = Tcl	PREFIX = Tcl_

Tcl
Tcl_new(class = "Tcl")
	char *	class
    CODE:
    	if (!findexecutable_called) {
	    /*
	     * XXX TODO (?) place here $^X ?
	     * Ideally this would be passed the dll instance location.
	     */
	    Tcl_FindExecutable(NULL);
	    findexecutable_called = 1;
	}
	RETVAL = Tcl_CreateInterp();
	if (tclBooleanTypePtr == NULL) {
	    tclBooleanTypePtr   = Tcl_GetObjType("boolean");
	    tclByteArrayTypePtr = Tcl_GetObjType("bytearray");
	    tclDoubleTypePtr    = Tcl_GetObjType("double");
	    tclIntTypePtr       = Tcl_GetObjType("int");
	    tclListTypePtr      = Tcl_GetObjType("list");
	    tclStringTypePtr    = Tcl_GetObjType("string");
	    tclWideIntTypePtr   = Tcl_GetObjType("wideInt");
	}
    OUTPUT:
	RETVAL

char *
Tcl_result(interp)
	Tcl	interp

void
Tcl_Eval(interp, script)
	Tcl	interp
	SV *	script
	SV *	interpsv = ST(0);
	STRLEN	length = NO_INIT
	char *cscript = NO_INIT
    PPCODE: 
	(void) sv_2mortal(SvREFCNT_inc(interpsv));
	PUTBACK;
	Tcl_ResetResult(interp);
	/* sv_mortalcopy here prevents stringifying script - necessary ?? */
	cscript = SvPV(sv_mortalcopy(script), length);
	if (Tcl_EvalEx(interp, cscript, length, 0) != TCL_OK) {
	    croak(Tcl_GetStringResult(interp));
	}
	prepare_Tcl_result(aTHX_ interp, "Tcl::Eval");
	SPAGAIN;

void
Tcl_EvalFile(interp, filename)
	Tcl	interp
	char *	filename
	SV *	interpsv = ST(0);
    PPCODE:
	(void) sv_2mortal(SvREFCNT_inc(interpsv));
	PUTBACK;
	Tcl_ResetResult(interp);
	if (Tcl_EvalFile(interp, filename) != TCL_OK) {
	    croak(Tcl_GetStringResult(interp));
	}
	prepare_Tcl_result(aTHX_ interp, "Tcl::EvalFile");
	SPAGAIN;

void
Tcl_GlobalEval(interp, script)
	Tcl	interp
	SV *	script
	SV *	interpsv = ST(0);
	STRLEN	length = NO_INIT
	char *cscript = NO_INIT
    PPCODE:
	(void) sv_2mortal(SvREFCNT_inc(interpsv));
	PUTBACK;
	Tcl_ResetResult(interp);
	/* sv_mortalcopy here prevents stringifying script - necessary ?? */
	cscript = SvPV(sv_mortalcopy(script), length);
	if (Tcl_EvalEx(interp, cscript, length, TCL_EVAL_GLOBAL) != TCL_OK) {
	    croak(Tcl_GetStringResult(interp));
	}
	prepare_Tcl_result(aTHX_ interp, "Tcl::GlobalEval");
	SPAGAIN;

void
Tcl_EvalFileHandle(interp, handle)
	Tcl	interp
	PerlIO*	handle
	int	append = 0;
	SV *	interpsv = ST(0);
	SV *	sv = sv_newmortal();
	char *	s = NO_INIT
    PPCODE:
	(void) sv_2mortal(SvREFCNT_inc(interpsv));
	PUTBACK;
        while (s = sv_gets(sv, handle, append))
	{
            if (!Tcl_CommandComplete(s))
		append = 1;
	    else
	    {
		Tcl_ResetResult(interp);
		if (Tcl_Eval(interp, s) != TCL_OK)
		    croak(Tcl_GetStringResult(interp));
		append = 0;
	    }
	}
	if (append)
	    croak("unexpected end of file in Tcl::EvalFileHandle");
	prepare_Tcl_result(aTHX_ interp, "Tcl::EvalFileHandle");
	SPAGAIN;

#if 1

void
Tcl_icall(interp, sv, ...)
	Tcl		interp
	SV *		sv
    PPCODE:
	{
	    /*
	     * This icall invokes the command directly, avoiding
	     * command tracing and the ::unknown mechanism.
	     */
#define NUM_OBJS 16
	    Tcl_Obj     *baseobjv[NUM_OBJS];
	    Tcl_Obj    **objv = baseobjv;
	    char        *cmdName;
	    int          objc, i, result;
	    STRLEN       length;
	    Tcl_CmdInfo	 cmdinfo;

	    objv = baseobjv;
	    objc = items-1;
	    if (objc > NUM_OBJS) {
		New(666, objv, objc, Tcl_Obj *);
	    }

	    SP += items;
	    PUTBACK;

	    /* Verify first arg is a Tcl command */
	    cmdName = SvPV(sv, length);
	    if (!Tcl_GetCommandInfo(interp, cmdName, &cmdinfo)) {
		croak("Tcl procedure '%s' not found", cmdName);
	    }

	    if (cmdinfo.objProc && cmdinfo.isNativeObjectProc) {
		/*
		 * We might want to check that this isn't
		 * TclInvokeStringCommand, which just means we waste time
		 * making Tcl_Obj's.
		 *
		 * Emulate TclInvokeObjectCommand (from Tcl), namely create the
		 * object argument array "objv" before calling right procedure
		 */
		objv[0] = Tcl_NewStringObj(cmdName, length);
		Tcl_IncrRefCount(objv[0]);
		for (i = 1; i < objc; i++) {
		    /*
		     * Use efficient Sv to Tcl_Obj conversion.
		     * This returns Tcl_Obj with refcount 1.
		     * This can cause recursive calls if we have tied vars.
		     */
		    objv[i] = TclObjFromSv(aTHX_ sv_mortalcopy(ST(i+1)));
		    Tcl_IncrRefCount(objv[i]);
		}
		SP -= items;
		PUTBACK;

		/*
		 * Result interp result and invoke the command's object-based
		 * Tcl_ObjCmdProc.
		 */
#if DEBUG_REFCOUNTS
		for (i = 1; i < objc; i++) { check_refcounts(objv[i]); }
#endif
		Tcl_ResetResult(interp);
		result = (*cmdinfo.objProc)(cmdinfo.objClientData, interp,
			objc, objv);

		/*
		 * Decrement ref count for first arg, others decr'd below
		 */
		Tcl_DecrRefCount(objv[0]);
	    }
	    else {
		/* 
		 * we have cmdinfo.objProc==0
		 * prepare string arguments into argv (1st is already done)
		 * and call found procedure
		 */
		char  *baseargv[NUM_OBJS];
		char **argv = baseargv;

		if (objc > NUM_OBJS) {
		    New(666, argv, objc, char *);
		}

		argv[0] = cmdName;
		for (i = 1; i < objc; i++) {
		    /*
		     * We need the inefficient round-trip through Tcl_Obj to
		     * ensure that we are listify-ing correctly.
		     * This can cause recursive calls if we have tied vars.
		     */
		    objv[i] = TclObjFromSv(aTHX_ sv_mortalcopy(ST(i+1)));
		    Tcl_IncrRefCount(objv[i]);
		    argv[i] = Tcl_GetString(objv[i]);
		}
		SP -= items;
		PUTBACK;

		/*
		 * Result interp result and invoke the command's string-based
		 * procedure.
		 */
#if DEBUG_REFCOUNTS
		for (i = 1; i < objc; i++) { check_refcounts(objv[i]); }
#endif
		Tcl_ResetResult(interp);
		result = (*cmdinfo.proc)(cmdinfo.clientData, interp,
			objc, argv);

		if (argv != baseargv) {
		    Safefree(argv);
		}
	    }

	    /*
	     * Decrement the ref counts for the argument objects created above
	     */
	    for (i = 1;  i < objc;  i++) {
		Tcl_DecrRefCount(objv[i]);
	    }

	    if (result != TCL_OK) {
		croak(Tcl_GetStringResult(interp));
	    }
	    prepare_Tcl_result(aTHX_ interp, "Tcl::call");

	    if (objv != baseobjv) {
		Safefree(objv);
	    }
	    SPAGAIN;
#undef NUM_OBJS
	}

#else

void
Tcl_icall(interp, sv, ...)
	Tcl		interp
	SV *		sv
    PPCODE:
	{
	    /*
	     * This icall passes the args to Tcl to invoke.  It will do
	     * command tracing and call ::unknown mechanism for unrecognized
	     * commands.
	     */
#define NUM_OBJS 16
	    Tcl_Obj  *baseobjv[NUM_OBJS];
	    Tcl_Obj **objv = baseobjv;
	    int       objc, i, result;

	    objc = items-1;
	    if (objc > NUM_OBJS) {
		New(666, objv, objc, Tcl_Obj *);
	    }

	    SP += items;
	    PUTBACK;
	    for (i = 0; i < objc;  i++) {
		/*
		 * Use efficient Sv to Tcl_Obj conversion.
		 * This returns Tcl_Obj with refcount 1.
		 * This can cause recursive calls if we have tied vars.
		 */
		objv[i] = TclObjFromSv(aTHX_ sv_mortalcopy(ST(i+1)));
		Tcl_IncrRefCount(objv[i]);
	    }
	    SP -= items;
	    PUTBACK;

	    /*
	     * Reset current result and invoke using Tcl_EvalObjv.
	     * This will trigger command traces and handle async signals.
	     */
#if DEBUG_REFCOUNTS
	    for (i = 1;  i < objc;  i++) { check_refcounts(objv[i]); }
#endif
	    Tcl_ResetResult(interp);
	    result = Tcl_EvalObjv(interp, objc, objv, 0);

	    /*
	     * Decrement the ref counts for the argument objects created above
	     */
	    for (i = 0;  i < objc;  i++) {
		Tcl_DecrRefCount(objv[i]);
	    }

	    if (result != TCL_OK) {
		croak(Tcl_GetStringResult(interp));
	    }
	    prepare_Tcl_result(aTHX_ interp, "Tcl::call");

	    if (objv != baseobjv) {
		Safefree(objv);
	    }
	    SPAGAIN;
#undef NUM_OBJS
	}

#endif

void
Tcl_DESTROY(interp)
	Tcl	interp

void
Tcl_Init(interp)
	Tcl	interp
    CODE:
	if (Tcl_Init(interp) != TCL_OK) {
	    croak(Tcl_GetStringResult(interp));
	}

void
Tcl_CreateCommand(interp,cmdName,cmdProc,clientData=&PL_sv_undef,deleteProc=Nullsv)
	Tcl	interp
	char *	cmdName
	SV *	cmdProc
	SV *	clientData
	SV *	deleteProc
    CODE:
	if (SvIOK(cmdProc))
	    Tcl_CreateCommand(interp, cmdName, (Tcl_CmdProc *) SvIV(cmdProc),
			      (ClientData) SvIV(clientData), NULL);
	else {
	    AV *av = (AV *) SvREFCNT_inc((SV *) newAV());
	    av_store(av, 0, newSVsv(cmdProc));
	    av_store(av, 1, newSVsv(clientData));
	    av_store(av, 2, newSVsv(ST(0)));
	    if (deleteProc) {
		av_store(av, 3, newSVsv(deleteProc));
	    }
	    Tcl_CreateObjCommand(interp, cmdName, Tcl_PerlCallWrapper,
		    (ClientData) av, Tcl_PerlCallDeleteProc);
	}
	ST(0) = &PL_sv_yes;
	XSRETURN(1);

void
Tcl_SetResult(interp, sv)
	Tcl	interp
	SV *	sv
    CODE:
	{
	    Tcl_Obj *objPtr = TclObjFromSv(aTHX_ sv);
	    /* Tcl_SetObjResult will incr refcount */
	    Tcl_SetObjResult(interp, objPtr);
	    ST(0) = ST(1);
	    XSRETURN(1);
	}

void
Tcl_AppendElement(interp, str)
	Tcl	interp
	char *	str

void
Tcl_ResetResult(interp)
	Tcl	interp

void
Tcl_FindExecutable(argv)
	char *	argv
    CODE:
    	Tcl_FindExecutable(argv);
	findexecutable_called = 1;


char *
Tcl_AppendResult(interp, ...)
	Tcl	interp
	int	i = NO_INIT
    CODE:
	for (i = 1; i <= items; i++)
	    Tcl_AppendResult(interp, SvPV_nolen(ST(i)), NULL);
	RETVAL = Tcl_GetStringResult(interp);
    OUTPUT:
	RETVAL

int
Tcl_DeleteCommand(interp, cmdName)
	Tcl	interp
	char *	cmdName
    CODE:
	RETVAL = Tcl_DeleteCommand(interp, cmdName) == 0;
    OUTPUT:
	RETVAL

void
Tcl_SplitList(interp, str)
	Tcl		interp
	char *		str
	int		argc = NO_INIT
	char **		argv = NO_INIT
	char **		tofree = NO_INIT
    PPCODE:
	if (Tcl_SplitList(interp, str, &argc, &argv) == TCL_OK)
	{
	    tofree = argv;
	    EXTEND(sp, argc);
	    while (argc--)
		PUSHs(sv_2mortal(newSVpv(*argv++, 0)));
	    ckfree((char *) tofree);
	}

char *
Tcl_SetVar(interp, varname, value, flags = 0)
	Tcl	interp
	char *	varname
	char *	value
	int	flags

char *
Tcl_SetVar2(interp, varname1, varname2, value, flags = 0)
	Tcl	interp
	char *	varname1
	char *	varname2
	char *	value
	int	flags

SV *
Tcl_GetVar(interp, varname, flags = 0)
	Tcl	interp
	char *	varname
	int	flags
    CODE:
	RETVAL = SvFromTclObj(aTHX_ Tcl_GetVar2Ex(interp, varname, NULL, flags));
    OUTPUT:
	RETVAL

SV *
Tcl_GetVar2(interp, varname1, varname2, flags = 0)
	Tcl	interp
	char *	varname1
	char *	varname2
	int	flags
    CODE:
	RETVAL = SvFromTclObj(aTHX_ Tcl_GetVar2Ex(interp, varname1, varname2, flags));
    OUTPUT:
	RETVAL

int
Tcl_UnsetVar(interp, varname, flags = 0)
	Tcl	interp
	char *	varname
	int	flags
    CODE:
	RETVAL = Tcl_UnsetVar2(interp, varname, NULL, flags) == TCL_OK;
    OUTPUT:
	RETVAL

int
Tcl_UnsetVar2(interp, varname1, varname2, flags = 0)
	Tcl	interp
	char *	varname1
	char *	varname2
	int	flags
    CODE:
	RETVAL = Tcl_UnsetVar2(interp, varname1, varname2, flags) == TCL_OK;
    OUTPUT:
	RETVAL

void
Tcl_perl_attach(interp, name)
	Tcl	interp
	char *	name
    PPCODE:
	PUTBACK;
	/* create Tcl array */
	Tcl_SetVar2(interp, name, NULL, "", 0);
	/* start trace on it */
	if (Tcl_TraceVar2(interp, name, 0,
	    TCL_TRACE_READS | TCL_TRACE_WRITES | TCL_TRACE_UNSETS |
	    TCL_TRACE_ARRAY,
	    &var_trace,
	    NULL /* clientData*/
	    ) != TCL_OK) {
	    croak(Tcl_GetStringResult(interp));
	}
	if (Tcl_TraceVar(interp, name,
	    TCL_TRACE_READS | TCL_TRACE_WRITES | TCL_TRACE_UNSETS,
	    &var_trace,
	    NULL /* clientData*/
	    ) != TCL_OK) {
	    croak(Tcl_GetStringResult(interp));
	}
        SPAGAIN;
       
void
Tcl_perl_detach(interp, name)
	Tcl	interp
	char *	name
    PPCODE:
	PUTBACK;
	/* stop trace */
        Tcl_UntraceVar2(interp, name, 0,
	    TCL_TRACE_READS|TCL_TRACE_WRITES|TCL_TRACE_UNSETS,
	    &var_trace,
	    NULL /* clientData*/
	    );
        SPAGAIN;

MODULE = Tcl		PACKAGE = Tcl::Var

SV *
FETCH(av, key = NULL)
	Tcl::Var	av
	char *		key
	SV *		sv = NO_INIT
	Tcl		interp = NO_INIT
	char *		varname1 = NO_INIT
	int		flags = 0;
    CODE:
	/*
	 * This handles both hash and scalar fetches. The blessed object
	 * passed in is [$interp, $varname, $flags] ($flags optional).
	 */
	if (AvFILL(av) != 1 && AvFILL(av) != 2) {
	    croak("bad object passed to Tcl::Var::FETCH");
	}
	sv = *av_fetch(av, 0, FALSE);
	if (sv_isa(sv, "Tcl")) {
	    IV tmp = SvIV((SV *) SvRV(sv));
	    interp = (Tcl) tmp;
	}
	else {
	    croak("bad object passed to Tcl::Var::FETCH");
	}
	if (AvFILL(av) == 2) {
	    flags = (int) SvIV(*av_fetch(av, 2, FALSE));
	}
	varname1 = SvPV_nolen(*av_fetch(av, 1, FALSE));
	RETVAL = SvFromTclObj(aTHX_ Tcl_GetVar2Ex(interp, varname1, key, flags));
    OUTPUT:
	RETVAL

void
STORE(av, sv1, sv2 = NULL)
	Tcl::Var	av
	SV *		sv1
	SV *		sv2
	SV *		sv = NO_INIT
	Tcl		interp = NO_INIT
	char *		varname1 = NO_INIT
	Tcl_Obj *	objPtr = NO_INIT
	int		flags = 0;
    CODE:
	/*
	 * This handles both hash and scalar stores. The blessed object
	 * passed in is [$interp, $varname, $flags] ($flags optional).
	 */
	if (AvFILL(av) != 1 && AvFILL(av) != 2)
	    croak("bad object passed to Tcl::Var::STORE");
	sv = *av_fetch(av, 0, FALSE);
	if (sv_isa(sv, "Tcl")) {
	    IV tmp = SvIV((SV *) SvRV(sv));
	    interp = (Tcl) tmp;
	}
	else
	    croak("bad object passed to Tcl::Var::STORE");
	if (AvFILL(av) == 2) {
	    flags = (int) SvIV(*av_fetch(av, 2, FALSE));
	}
	varname1 = SvPV_nolen(*av_fetch(av, 1, FALSE));
	/*
	 * HASH:   sv1 == key,   sv2 == value
	 * SCALAR: sv1 == value, sv2 NULL
	 * Tcl_SetVar2Ex will incr refcount
	 */
	if (sv2) {
	    objPtr = TclObjFromSv(aTHX_ sv2);
	    Tcl_SetVar2Ex(interp, varname1, SvPV_nolen(sv1), objPtr, flags);
	}
	else {
	    objPtr = TclObjFromSv(aTHX_ sv1);
	    Tcl_SetVar2Ex(interp, varname1, NULL, objPtr, flags);
	}

