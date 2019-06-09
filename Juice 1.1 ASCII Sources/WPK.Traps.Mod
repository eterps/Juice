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

MODULE Traps;

(**
 Module Win32 provides the low-level interface to the Windows operating system. Some of its duties include window, font and color management. 
*)
(*
	jm 12.9.95 - Added WndProc Upcall
	ejz 6.10.95 - Improved InitInstance
*)

IMPORT Kernel:= JuiceKernel, S := SYSTEM, Modules := JuiceModules, JuiceFiles, JuiceApplets, Reals;

CONST
	DumpFileName = "Juice.Trap";

(* ------ trap ---------- *)
VAR
	x*: LONGINT;
	
TYPE
	ExceptionRecord = RECORD
		code: LONGINT;
		flags: LONGINT;
		excRec: LONGINT;
		addr: LONGINT;
	END;
	ContextRecord = RECORD
		flags: LONGINT;
		debRegs: ARRAY 6 OF LONGINT;
		floatSaveArea: ARRAY 112 OF CHAR;
		SegGs, SegFs, SegEs, SegDs: LONGINT;
		Edi, Esi, Ebx, Edx, Ecx, Eax: LONGINT;
		Ebp, Eip, SegCs, EFlags, Esp, SegSs: LONGINT;
	END;
	ExceptionInfo = POINTER TO ExceptionPointers;
	ExceptionPointers = RECORD
		exc: POINTER TO ExceptionRecord;
		cont: POINTER TO ContextRecord;
	END;

	TrapHandler = PROCEDURE (p: ExceptionInfo);

VAR
	hd: ARRAY 17 OF CHAR;

(* ---------------------- low level trap handler ------------------------- *)

PROCEDURE ReadNum (VAR pos: LONGINT; VAR i: LONGINT);
	VAR n: LONGINT; s: SHORTINT; x: CHAR;
BEGIN
	s := 0; n := 0; S.GET(pos, x); INC(pos);
	WHILE ORD(x) >= 128 DO INC(n, ASH(ORD(x) - 128, s)); INC(s, 7); S.GET(pos, x); INC(pos) END;
	i := n + ASH(ORD(x) MOD 64 - ORD(x) DIV 64 * 64, s)
END ReadNum;

PROCEDURE ReadString (VAR pos: LONGINT; VAR s: ARRAY OF CHAR);
	VAR i: LONGINT; ch: CHAR;
BEGIN i := 0;
	REPEAT
		S.GET(pos, ch); s[i] := ch; INC(i); INC(pos)
	UNTIL ch = 0X;
END ReadString;
	
PROCEDURE FindProc (pc: LONGINT; VAR mod: Modules.Module; VAR refpos, refend: LONGINT);
	CONST ProcRefTag = 0F8X; VarTag = 1X; VarParTag = 3X;
	VAR m: Modules.Module; codebase, pos, beg, offs: LONGINT; ch: CHAR;
		name: ARRAY 32 OF CHAR;
BEGIN
	m := Modules.modList; mod := NIL; refpos := -1; codebase := S.ADR(m.code[0]);
	WHILE (m # NIL) & ((pc < codebase) OR ((codebase + LEN(m.code^)) < pc)) DO
		m := m.link;
		IF m # NIL THEN codebase := S.ADR(m.code[0]) END;
	END;
	IF m # NIL THEN
		mod := m; pc := pc - codebase;
		pos := S.ADR(m.refs[0]); refend := pos + LEN(mod.refs^);
		S.GET(pos, ch); INC(pos); beg := pos; refpos := -1;
		WHILE (pos <= refend) & (ch = ProcRefTag) DO
			refpos := beg; beg := pos;
			ReadNum(pos, offs);
			IF offs >= pc THEN RETURN END;
			ReadString(pos, name);
			S.GET(pos, ch); INC(pos);
			WHILE (ch = VarTag) OR (ch = VarParTag) DO
				S.GET(pos, ch); INC(pos); (* form *)
				ReadNum(pos, offs); ReadString(pos, name);
				S.GET(pos, ch); INC(pos);
			END
		END;
		refpos := beg;
	END
END FindProc;

PROCEDURE Trap (p: ExceptionInfo);
	VAR
		excode, pc, bp, sp, ref, refend: LONGINT;
		offs, n: LONGINT;
		trapno: LONGINT;
		name: ARRAY 32 OF CHAR;
		EBX, ESI, EDI: LONGINT;
		mod: Modules.Module;
		text: ARRAY 256 OF CHAR;
		F: JuiceFiles.File; R: JuiceFiles.Rider;
		done: BOOLEAN;
		
	PROCEDURE Append(VAR to: ARRAY OF CHAR; this: ARRAY OF CHAR);
		VAR i, j, l: LONGINT;
	BEGIN
		i := 0;
		WHILE to[i] # 0X DO
			INC(i)
		END;
		l := LEN(to)-1; j := 0;
		WHILE (i < l) & (this[j] # 0X) DO
			to[i] := this[j];
			INC(i); INC(j)
		END;
		to[i] := 0X
	END Append;

	PROCEDURE AppendCh(VAR to(** in/out *): ARRAY OF CHAR; this: CHAR);
		VAR i: LONGINT;
	BEGIN
		i := 0;
		WHILE to[i] # 0X DO
			INC(i)
		END;
		IF i < (LEN(to)-1) THEN
			to[i] := this; to[i+1] := 0X
		END
	END AppendCh;

	PROCEDURE IntToStr(i: LONGINT; VAR s: ARRAY OF CHAR);
	VAR k, j: INTEGER; x0: LONGINT; a: ARRAY 10 OF CHAR;
	BEGIN k := 0;
	 IF i < 0 THEN
	      IF i = MIN(LONGINT) THEN COPY(" -2147483648", s); RETURN
	      ELSE x0 := -i
	      END
	    ELSE x0 := i
	    END;	
	    REPEAT
	      a[k] := CHR(x0 MOD 10 + 30H); x0 := x0 DIV 10; INC(k)
	    UNTIL x0 = 0;
	    j := 0;
	    IF i < 0 THEN s[j] := "-"; INC(j); END;
	    REPEAT DEC(k); s[j] := a[k]; INC(j); UNTIL k = 0;
	    s[j] := 0X;
	END IntToStr;

	PROCEDURE RealToStr(x: LONGREAL; VAR s: ARRAY OF CHAR);
	VAR e, h, l, n: LONGINT; i, j, pos: INTEGER; z: LONGREAL; d: ARRAY 16 OF CHAR;
		
		PROCEDURE Wr(ch: CHAR);
		BEGIN
			IF ch = 0X THEN HALT(42) END;
			IF pos < LEN(s) - 1 THEN s[pos] := ch; INC(pos) END;
		END Wr;
		
	BEGIN
		pos := 0;
		e:= Reals.ExpoL(x);
		IF e = 2047 THEN
			Wr("N"); Wr("a"); Wr("N");
		ELSE
			n := 14;
			IF (x < 0) & (e # 0) THEN Wr("-"); x:= - x END;
			IF e = 0 THEN h:= 0; l:= 0 (* no denormals *)
	    ELSE e:= (e - 1023) * 301029 DIV 1000000; (* ln(2)/ln(10) = 0.301029996 *)
	      z:= Reals.Ten(e+1);
	      IF x >= z THEN x:= x/z; INC(e) ELSE x:= x * Reals.Ten(-e) END;
	      IF x >= 10 THEN x:= x * Reals.Ten(-1) + 0.5D0 / Reals.Ten(n); INC(e)
	      ELSE x:= x + 0.5D0 / Reals.Ten(n);
	        IF x >= 10 THEN x:= x * Reals.Ten(-1); INC(e) END
	      END;
	      x:= x * Reals.Ten(7); h:= ENTIER(x); x:= (x-h) * Reals.Ten(8); l:= ENTIER(x)
	    END;
			i := 15; WHILE i > 7 DO d[i]:= CHR(l MOD 10 + ORD("0")); l:= l DIV 10; DEC(i) END;
			WHILE i >= 0 DO d[i]:= CHR(h MOD 10 + ORD("0")); h:= h DIV 10; DEC(i) END;
			IF ABS(e) > 8 THEN (* scientific notation *)
				j := 15; WHILE (j > 0) & (d[j] = "0") DO DEC(j) END;
				Wr(d[0]); IF j # 0 THEN Wr(".") END; i := 1; WHILE i <= j DO Wr(d[i]); INC(i) END;
				IF e < 0 THEN Wr("D"); Wr("-"); e:= - e ELSE Wr("D"); Wr("+") END;
				Wr(CHR(e DIV 100 + ORD("0"))); e:= e MOD 100;
				Wr(CHR(e DIV 10 + ORD("0"))); Wr(CHR(e MOD 10 + ORD("0")))
			ELSE
				IF e < 0 THEN (* leading zeros *)
					j := (* !15*) 14; WHILE (j > 0) & (d[j] = "0") DO DEC(j) END;
					Wr("0"); Wr("."); INC(e);
					WHILE e < 0 DO Wr("0"); INC(e) END;
					i := 0; WHILE i <= j DO Wr(d[i]); INC(i) END;
				ELSE
					i := 0; WHILE (e >= 0) & (i < 16 ) DO Wr(d[i]); INC(i); DEC(e) END;
					IF i < 16 THEN
						Wr(".");
						WHILE i < (*16*) 15 DO Wr(d[i]); INC(i); END;
						WHILE s[pos - 1] = "0" DO DEC(pos) END;
						IF s[pos - 1] = "." THEN DEC(pos) END;
					END
				END
			END
		END;
		s[pos] := 0X;
	END RealToStr;

	PROCEDURE SetToStr(set: SET; VAR s: ARRAY OF CHAR);
		VAR k, i, j: INTEGER; notfirst: BOOLEAN; 
	BEGIN k:=1; s[0]:="{"; notfirst:=FALSE;
		i:=0; WHILE i<=MAX(SET) DO
			IF i IN set THEN
				IF notfirst THEN s[k]:=","; INC(k) ELSE notfirst:=TRUE END;
				IF i>=10 THEN s[k]:=CHR(i DIV 10+ORD("0")); INC(k) END;
				s[k]:=CHR(i MOD 10+ORD("0")); INC(k); j:=i; INC(i);
				WHILE (i<=MAX(SET)) & (i IN set) DO INC(i) END;
				IF (i-2>j) THEN s[k]:="."; s[k+1]:="."; INC(k, 2); 
					IF i>10 THEN s[k]:=CHR((i-1) DIV 10+ORD("0")); INC(k) END;
					s[k]:=CHR((i-1) MOD 10+ORD("0")); INC(k); j:=i; INC(i);
				ELSE i:=j END;
			END;
			INC(i);
		END;
		s[k]:="}"; s[k+1]:=0X;
	END SetToStr;
	
	PROCEDURE HexToStr(i: LONGINT; VAR s: ARRAY OF CHAR);
		VAR k, j, c: INTEGER; a: ARRAY 10 OF CHAR;
	BEGIN 
		k := 0; c:=0; REPEAT	a[k] := hd[i MOD 16]; i := i DIV 16; INC(k); INC(c)	UNTIL (i = 0) OR (c=8);
	    j := 0; REPEAT DEC(k); s[j] := a[k]; INC(j); UNTIL k = 0; s[j] := "H"; s[j+1]:=0X;
	END HexToStr;

	PROCEDURE Ch(ch: CHAR);
	BEGIN
		JuiceFiles.WriteChar(R, ch);
		IF ~done THEN AppendCh(text, ch) END;
	END Ch;

	PROCEDURE Str(str: ARRAY OF CHAR);
		VAR i: INTEGER;
	BEGIN 
		i := 0; WHILE str[i] # 0X DO Ch(str[i]); INC(i) END;
	END Str;

	PROCEDURE Int(i: LONGINT);
		VAR str: ARRAY 32 OF CHAR;
	BEGIN IntToStr(i, str); Str(str); 
	END Int;

	PROCEDURE Hex(i: LONGINT);
		VAR str: ARRAY 32 OF CHAR;
	BEGIN HexToStr(i, str); Str(str)
	END Hex;

	PROCEDURE Set(i: SET);
		VAR str: ARRAY 32 OF CHAR;
	BEGIN SetToStr(i, str); Str(str)
	END Set;

	PROCEDURE Real(r: LONGREAL);
		VAR str: ARRAY 32 OF CHAR;
	BEGIN RealToStr(r, str); Str(str)
	END Real;

	PROCEDURE Ln;
	BEGIN Ch(0DX); Ch(0AX);
	END Ln;

	PROCEDURE DumpVars (VAR pos: LONGINT; base: LONGINT);
		CONST VarTag = 1X; VarParTag = 3X;
		VAR ch, form: CHAR;
			sintval: SHORTINT; intval: INTEGER; lintval: LONGINT; realval: REAL; lrealval: LONGREAL;
			adr, offs: LONGINT; set: SET;
			name: ARRAY 32 OF CHAR;
	BEGIN
		S.GET(pos, ch); INC(pos);
		WHILE (ch = VarTag) OR (ch = VarParTag) DO
			S.GET(pos, form); INC(pos);
			ReadNum(pos, offs); ReadString(pos, name);
			adr := base + offs;
			IF ch = VarParTag THEN S.GET(adr, adr) END;
			Str("   "); Str(name); Str(" = ");
			CASE ORD(form) OF
				| 1H: (* Byte *)
					S.GET(adr, ch); Int(ORD(ch));
				| 2H: (* Boolean *)
					S.GET(adr, ch);
					IF ORD(ch) = 0 THEN Str("FALSE") ELSE Str("TRUE") END;
				| 3H: (* Char *)
					S.GET(adr, ch);
					IF (" " <= ch) & (ch <= "~") THEN Ch(22X); Ch(ch); Ch(22X);
					ELSE Str("CHR("); Int(ORD(ch)); Ch(")");
					END;
				| 4H: (* Shortint *)
					S.GET(adr, sintval); Int(sintval);
				| 5H: (* Integer *)
					S.GET(adr, intval); Int(intval);
				| 6H: (* Longint *)
					S.GET(adr, lintval); Int(lintval);
				| 7H: (* Real *)
					S.GET(adr, realval); (*Texts.WriteString(W, "REAL");*) Real(realval);
				| 8H: (* Longreal *)
					S.GET(adr, lrealval); (*Texts.WriteString(W, "LONGREAL");*) Real(lrealval);
				| 9H:
					S.GET(adr, set); Set(set);
				| 0DH: (* Set, Pointer*)
					S.GET(adr, lintval); Hex(lintval); 
				| 0FH: (* Array of char *)
					Ch(22X);
					S.GET(adr, ch); INC(adr);
					WHILE (" " <= ch) & (ch <= "~") DO Ch(ch); S.GET(adr, ch); INC(adr) END;
					Ch(22X);
			ELSE Str("(unknown type)");
			END;
			Ln;
			S.GET(pos, ch); INC(pos);
		END
	END DumpVars;


BEGIN
	S.GETREG(3, EBX); S.GETREG(6, ESI); S.GETREG(7, EDI);
	F := JuiceFiles.New(DumpFileName); done := FALSE;
	JuiceFiles.Set(R, F, 0);
	Str("A trap occured in Netscape:"); Ln; Ln;
	IF Kernel.TrapHandlingLevel < 2 THEN
		INC(Kernel.TrapHandlingLevel);
		IF Kernel.TrapHandlingLevel > 1 THEN
			Str("*** RECURSIVE TRAP: "); Ln;
		END;
		excode := p.exc.code MOD 10000H; pc := p.exc.addr; bp := p.cont.Ebp; sp := p.cont.Esp;
		IF pc = 0 THEN (* assume call of procedure variable with value NIL *)
			S.GET(sp, pc); (* get return address on top of stack *)
		END;
		Str("Trap ");
		IF excode = 29 THEN (* Illegal Instruction => Oberon traps *)
			trapno := p.cont.Eax;
			Int(trapno);
			CASE trapno OF
				|  0: Str("  (ASSERT failed)");
				|  1: Str("  (Heap overflow)");
				| 15: Str("  (invalid case in WITH statement)");
				| 16: Str("  (invalid case in CASE statement)");
				| 17: Str("  (function procedure without RETURN)");
				| 18: Str("  (type guard check)");
				| 19: Str("  (implicit type guard check in record assignment)");
				| 20: Str("  (integer overflow)");
				| 21: Str("  (range overflow)");
				| 22: Str("  (dimension trap)");
			ELSE
				IF trapno >= 30 THEN Str("  (programmed HALT)");
				ELSE Str("  (unknown trap)");
				END
			END;
		ELSE
			Int(excode);
			CASE excode OF
				| 5: Str(" (access violation)");
				| 8EH .. 93H: Str(" (FPU: ");
					CASE excode OF
						| 8EH: Str(" divide by zero)");
						| 91H: Str(" overflow)");
						| 93H: Str(" underflow)");
					ELSE Str(" exception "); Int(p.exc.code); Str("H)");
					END;
				| 94H: Str(" (integer division by zero)");
				| 95H: Str(" (integer overflow)");
				| 96H: Str(" (privileged instruction)");
			ELSE
			END;
		END;
		Str("    PC = "); Hex(pc);

		FindProc(pc, mod, ref, refend);
		
		IF mod # NIL THEN
			Str(" ("); Hex(pc - S.ADR(mod.code[0])); Str(") ");
		END;
		
		Ln;
		n := 0;
		WHILE (mod # NIL) & (n < 32) DO
			Str(mod.name); Str("."); 
			ReadNum(ref, offs); ReadString(ref, name);
			Str(name); Ln;
			done := TRUE;
			DumpVars(ref, bp);
			
			S.GET(bp + 4, pc);
			S.GET(bp, bp);
			INC(n);
			FindProc(pc, mod, ref, refend);
		END;
		IF Kernel.TrapHandlingLevel < 3 THEN INC(Kernel.TrapHandlingLevel);
		END;
	END;
	Kernel.TrapHandlingLevel := 0;
	Ln;
	JuiceFiles.Register(F);
	AppendCh(text, 0DX);
	Append(text, "Detailed info in file: ");
	AppendCh(text, 0DX);
	Append(text, DumpFileName);
	AppendCh(text, 0DX);
	JuiceApplets.HandleTrap(text);

	S.PUTREG(3, EBX); S.PUTREG(6, ESI); S.PUTREG(7, EDI);
END Trap;

PROCEDURE InitTrap;
VAR a: LONGINT; h: TrapHandler; 
BEGIN
	Kernel.GetAdr(0, "HandleTrap", a); h := Trap; S.PUT(a, S.VAL(LONGINT, h));
	hd := "0123456789ABCDEF";
END InitTrap;

BEGIN InitTrap;
END Traps.
