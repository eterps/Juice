(*
        Juice(TM), Version 1.1

        Copyright (c) 1996-1997 Regents of the University of California.
        All rights reserved.

        This software was developed as part of the Juice project by the research
        group of Prof. Dr. M. Franz at the University of California, Irvine.
        http://www.ics.uci.edu/~juice

        Redistribution and use in source and binary forms are permitted
        provided that:

        (a)     the above copyright notice and this paragraph are duplicated
                        in all such forms and provided that any documentation,
                        advertising materials, and other materials related to such
                        distribution and use acknowledge that the software was
                        developed by the University of California, Irvine.

        (b)     all interface changes and all conversions of this software to other
                        platforms agree with style and content of Juice. In case of doubt
                        juice-request@ics.uci.edu shall be asked for consent.

        The name of the University may not be used to endorse or promote products derived
        from this software without specific prior written permission.

        THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR
        IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED
        WARRANTIES OF MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.

        "Juice" is a trademark owned by the Regents of the University of California
*)

(* OBERON System 3, version 2.1.

Copyright 1996 Team of the Institute of Computer Systems of ETH Zurich, ETH Center, CH-8092 Zurich,
e-mail: oberon@inf.ethz.ch.

This module may be used under the conditions of the general Oberon System 3 license contract.
The full text can be downloaded from "ftp://ftp@ftp.inf.ethz.ch/pub/software/Oberon/System3/License.Text;A"
or requested from the above mentioned address.

Under the license terms stated it is in particular (a) prohibited to modify the interface of this module
in any way that disagrees with style or content of the system and (b) requested to provide all conversions
of the source code to another platform with the name OBERON. *)
MODULE JuiceMathL;	(* MH 30.8.93; uses C library calls *)

(** Commonly needed Math for LONGREALs.
*)

IMPORT S := SYSTEM, Kernel:= JuiceKernel;

CONST
	e* = 2.7182818284590452354D0;
	pi* = 3.14159265358979323846D0;

VAR
	sqrt0: PROCEDURE (x: LONGREAL): LONGREAL;
	exp0: PROCEDURE (x: LONGREAL): LONGREAL;
	ln0: PROCEDURE (x: LONGREAL): LONGREAL;
	sin0: PROCEDURE (x: LONGREAL): LONGREAL;
	cos0: PROCEDURE (x: LONGREAL): LONGREAL;
	arctan0: PROCEDURE (x: LONGREAL): LONGREAL;

PROCEDURE Sqrt* (x: LONGREAL): LONGREAL;
BEGIN RETURN sqrt0(x)
END Sqrt;

PROCEDURE Exp* (x: LONGREAL): LONGREAL;
BEGIN RETURN exp0(x)
END Exp;

PROCEDURE Ln* (x: LONGREAL): LONGREAL;
BEGIN RETURN ln0(x)
END Ln;

PROCEDURE Sin* (x: LONGREAL): LONGREAL;
BEGIN RETURN sin0(x)
END Sin;

PROCEDURE Cos* (x: LONGREAL): LONGREAL;
BEGIN RETURN cos0(x)
END Cos;

PROCEDURE Arctan* (x: LONGREAL): LONGREAL;
BEGIN RETURN arctan0(x)
END Arctan;


BEGIN
	Kernel.GetAdr(0, "sqrt", S.VAL(LONGINT, sqrt0));
	Kernel.GetAdr(0, "exp", S.VAL(LONGINT, exp0));
	Kernel.GetAdr(0, "ln", S.VAL(LONGINT, ln0));
	Kernel.GetAdr(0, "sin", S.VAL(LONGINT, sin0));
	Kernel.GetAdr(0, "cos", S.VAL(LONGINT, cos0));
	Kernel.GetAdr(0, "arctan", S.VAL(LONGINT, arctan0));
END JuiceMathL.
