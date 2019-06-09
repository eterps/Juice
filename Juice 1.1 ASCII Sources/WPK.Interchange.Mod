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

MODULE Interchange;	(*mf 11.11.94 / od Jan 95 / tk  *)

	IMPORT
		SYS := SYSTEM, Kernel:= JuiceKernel, Modules:=JuiceModules, Files:=JuiceFiles,
		PLT := OPLT, PLO := OPLO, PLL := OPLL, PLC := OPLC, PLV := OPLV;

	CONST
		Var = 1; Par = 2; VarPar = 3; Con = 4; LProc = 6; XProc = 7; TypDynArr = 8;
		TypArray = 9; TypPointer = 10; TypRecord = 11; TypProcTyp = 12;
		
		Local=FALSE; Global=TRUE;
			
		inxchk = 0; ovflchk = 1; ranchk = 2; typchk = 3; ptrinit = 5;
		
	VAR
		verbose : BOOLEAN;
		verboseHook*: PROCEDURE (M: Modules.Module);
		options: SET;

	PROCEDURE Str(s: ARRAY OF CHAR);
		VAR i: INTEGER;
	BEGIN	i:=0; REPEAT Modules.resMsg[Modules.resMsgLen]:=s[i]; INC(i); INC(Modules.resMsgLen) UNTIL s[i-1]=0X; DEC(Modules.resMsgLen);
	END Str;

	PROCEDURE err(n: INTEGER; VAR name: ARRAY OF CHAR);
	BEGIN Modules.res := n; 
		IF n > 0 THEN
			IF n < 20 THEN Str("Call error: "); Str(name) END;
			IF n = 1 THEN Str(" not found")
			ELSIF n = 2 THEN Str(" not a valid object file")
			ELSIF n = 8 THEN Str(" no symbols")
			END
		END
	END err;

	PROCEDURE^ Import(VAR R: Files.Rider; M: Modules.Module);

	PROCEDURE BuildSym(VAR R: Files.Rider; M: Modules.Module);
		VAR nofEntries, adr, nofRecs, s: LONGINT;
			mod: Modules.Module; obj: PLT.Object;
	BEGIN	Import(R, M);
		IF Modules.res = 0 THEN	M.nofstrc := 1; obj := NIL;
			mod := Modules.modList; WHILE mod # NIL DO mod.nofreimp := 0; mod := mod.link END;
			PLT.ReadScope(R, M, 0, obj, Global); M.publics := SYS.VAL(LONGINT, obj);			
			nofEntries := 1; adr := 0; nofRecs := 0;
			WHILE obj # NIL DO
				CASE obj.mode OF
					| Var: PLL.TypSize(obj.typ); s := obj.typ.size; PLL.AlignVar(adr, s); PLL.AllocVar(adr, obj.linkadr, s); 
						obj.linkadr := obj.linkadr + M.sb;
					| XProc: obj.linkadr := M.entries[nofEntries];
							INC(nofEntries); IF nofEntries > 127 THEN HALT(33) END;
							obj.adr := 0; PLL.ParamAdr(obj);
					| TypRecord: PLL.TypSize(obj.typ); obj.typ.tdadr := M.tdescs[nofRecs]; INC(nofRecs); obj.linkadr := -1;
					| TypDynArr, TypArray, TypPointer, TypProcTyp: PLL.TypSize(obj.typ); obj.linkadr := -1;
					| Con:
				ELSE
				END;
				obj:=obj.nxtobj
			END;
		END;
	END BuildSym;

	(*append object list to module descriptor*)
	PROCEDURE Decorate*(M: Modules.Module);
	VAR ch0, ch1: CHAR; i: INTEGER; symSize: LONGINT;
		R: Files.Rider; fname: Modules.ModuleName; F: Files.File; k: LONGINT;
	BEGIN
		IF M.publics = 0 THEN
			IF M.syms # NIL THEN
				F := Files.New(""); Files.Set(R, F, 0);
				Files.WriteChar(R, 0BBX); Files.WriteChar(R, 088X); Files.WriteNum(R, LEN(M.syms^));
				FOR k:= 0 TO LEN(M.syms^)-1 DO Files.WriteChar(R, M.syms^[k]); END;
			ELSE
				i := 0; ch0 := M.name[0];
				WHILE ch0 # 0X DO fname[i] := ch0; INC(i); ch0 := M.name[i] END;
				fname[i] := "."; fname[i+1] := "O"; fname[i+2] := "b"; fname[i+3] := "j"; fname[i+4] := 0X;
				F := Files.Old(fname)
			END;
			IF F # NIL THEN Files.Set(R, F, 0);
				Files.ReadChar(R, ch0);
				IF ch0 = 0BBX THEN Files.ReadChar(R, ch1); 
					Files.ReadNum(R, symSize); BuildSym(R, M)
				ELSE err(2, M.name) END;
				Files.Close(Files.Base(R))
			ELSE err(8, M.name) END
		END
	END Decorate;

	PROCEDURE Import(VAR R: Files.Rider; M: Modules.Module);
		VAR name: Modules.ModuleName; im: Modules.Module;  
	BEGIN
		PLT.ReadString(R, name);
		WHILE (name # "") & (Modules.res = 0) DO
			im := Modules.ThisMod(name);
			IF Modules.res = 0 THEN	Decorate(im);
				IF Modules.res = 0 THEN
					M.import[M.nofimp] := SYS.VAL(LONGINT, im);
					INC(M.nofimp); IF M.nofimp>=LEN(M.import^) THEN PLT.DoubleArr(M.import) END;
					INC(im.refcnt); PLT.ReadString(R, name)
				END
			END
		END;
	END Import;

	PROCEDURE Unlink(mod: Modules.Module; all: BOOLEAN);
		VAR i: INTEGER; imp: Modules.Module;
	BEGIN	i := mod.nofimp;
		WHILE i > 0 DO	DEC(i); imp:=SYS.VAL(Modules.Module, mod.import[i]); DEC(imp.refcnt) END;
		IF all THEN i := mod.nofimp;
			WHILE i > 0 DO DEC(i); imp:=SYS.VAL(Modules.Module, mod.import[i]); Modules.Free(imp.name, TRUE) END;
			Modules.res := 0;
		END;
	END Unlink;

	PROCEDURE* Load(VAR R: Files.Rider; M: Modules.Module);
		VAR nofcmds, nofptrs: INTEGER; above, below, c, i, sfSize: LONGINT;
		body: PROCEDURE; R1: Files.Rider; m1: Modules.Module; globals, obj: PLT.Object;
			
		PROCEDURE LSW (x: LONGINT): LONGINT;
		BEGIN (* least significant word (unsigned) *)
			RETURN SYS.VAL(LONGINT, SYS.VAL(SET, x) * SYS.VAL(SET, 0FFFFH))
		END LSW;
	
	BEGIN
		Kernel.DisableGC(); Files.ReadNum(R, sfSize); R1 := R;
		Files.Set(R1, Files.Base(R1), Files.Pos(R1) + sfSize); Import(R, M); 
		IF Modules.res = 0 THEN
			M.nofstrc := 1; globals := NIL; Files.ReadNum(R1, sfSize); Files.ReadNum(R1, below); Files.ReadNum(R1, above); 									
			Import(R1, M);															
			m1 := Modules.modList; WHILE m1 # NIL DO m1.nofreimp := 0; m1 := m1.link END;
			PLT.ReadScope(R, M, 0, globals, Global); R := R1;
			IF Modules.res = 0 THEN PLT.theMod:=M; PLL.Open; PLO.Open;
				M.publics:=SYS.VAL(LONGINT, globals); PLT.ReadScope(R, M, 0, globals, Local);
				M.privates:=SYS.VAL(LONGINT, globals);	
				PLC.Init({0, 3, 5});
				PLL.Traverse(SYS.VAL(PLT.Object, M.publics)); PLL.Traverse(globals);
				PLL.AllocGlobalVar(SYS.VAL(PLT.Object, M.publics), globals);	(* Calculates global Var Size : PLL.dsize *)
				M.sb := PLO.sb;
				PLL.AllocLinkTable(M.nofimp+1);
				
				PLV.Load(R, M, globals, below, above);
				IF Modules.res = 0 THEN
					(* code *)
					M.codeSize:=PLO.pc;
					SYS.PUT(SYS.ADR(M.code), PLO.code);
					Modules.ShrinkCodeBlock(SYS.VAL(LONGINT, M.code), M.codeSize);
	
					(* Const *)
					M.conSize:=0;	(* SHORT(PLO.csize); *)
					SYS.PUT(SYS.ADR(M.data), PLO.data); M.dataSize:=PLO.dsize;
					Modules.ShrinkCodeBlock(SYS.VAL(LONGINT, M.data), M.dataSize);
	
					(* Imports *)
					M.nofImps := M.nofimp; 
					i := M.nofImps; 
					IF i # 0 THEN NEW(M.imports, i) END;
					WHILE i > 0 DO
						DEC(i);
						M.imports[i] := M.import[i];
					END;
										
					(* Entries *)
					M.nofEntries := PLL.nofEntries;
					IF PLL.nofEntries > 0 THEN
						NEW(M.entries, PLL.nofEntries);
						i := 0; c := SYS.ADR(M.code[0]);
						WHILE i < PLL.nofEntries DO M.entries[i] := c + LSW(PLL.entry[i]); INC(i) END
					END;
					
					(* collect commands and pointers *)
					nofptrs := 0;
					obj := SYS.VAL(PLT.Object, M.privates);
					WHILE obj # NIL DO
						IF (obj.mode = XProc) & (obj.par = NIL) & (obj.typ = PLT.notyp) THEN INC(nofcmds)
						ELSIF obj.mode = Var THEN 
							PLL.FindPtrs(obj.typ, obj.linkadr, nofptrs)
						END;
						obj := obj.nxtobj
					END;
									
					(* Commands *)
					M.nofCmds := nofcmds; c := SYS.ADR(M.code[0]);
					IF nofcmds > 0 THEN
						NEW(M.cmds, nofcmds);
						i := 0; obj := SYS.VAL(PLT.Object, M.privates);
						WHILE obj # NIL DO
							IF (obj.mode = XProc) & (obj.par = NIL) & (obj.typ = PLT.notyp) THEN
								COPY(obj.name, M.cmds[i].name);
								M.cmds[i].adr := c + LSW(PLL.entry[obj.adr MOD 10000H]);
								INC(i)
							END;
							obj := obj.nxtobj
						END
					END;
	
					(* Pointers *)
					M.nofPtrs := nofptrs;
					IF nofptrs > 0 THEN
						NEW(M.ptrTab, nofptrs);
						i := 0; WHILE i < nofptrs DO M.ptrTab[i] := PLL.ptrTab[i]; INC(i) END
					END;

					(* Type Descriptors *)
					M.nofTds := PLL.nofrecs;
					IF M.nofTds > 0 THEN
						NEW(M.tdescs, PLL.nofrecs);
						i := 0; WHILE i < PLL.nofrecs DO M.tdescs[i] := PLL.recTab[i].tdadr; INC(i) END;
					END;
					
					(* References *)
					M.refSize := PLL.refSize;
					IF PLL.refSize > 0 THEN
						NEW(M.refs, PLL.refSize);
						i := 0; WHILE i < PLL.refSize DO M.refs[i] := PLL.refs[i]; INC(i) END;
					END;
	
					M.link := Modules.modList; Modules.modList := M;
	
					IF verbose & (verboseHook#NIL) THEN verboseHook(M) END;
					M.init := TRUE; PLL.Close; M.privates := 0;
					SYS.PUT(SYS.ADR(body), M.entries[0]);
					Kernel.EnableGC(); IF Kernel.stackBottom # 0 THEN Kernel.GC END;
					body();
					Modules.res := 0;
				ELSE Unlink(M, FALSE); Files.Close(Files.Base(R)); M := NIL END
			ELSE Unlink(M, FALSE); Files.Close(Files.Base(R)); M:=NIL END
		ELSE Unlink(M, FALSE); Files.Close(Files.Base(R)); M:=NIL END
	END Load;

	PROCEDURE Start*;
	BEGIN	Modules.extended.Load := Load
	END Start;

	PROCEDURE Stop*;
	BEGIN	Modules.extended.Load := NIL
	END Stop;

	PROCEDURE Verbose*;
	BEGIN verbose := TRUE
	END Verbose;

	PROCEDURE ChecksOn*;
	BEGIN	options := {inxchk, ovflchk, ranchk, typchk, ptrinit}
	END ChecksOn;

	PROCEDURE ChecksOff*;
	BEGIN	options := {}
	END ChecksOff;

BEGIN
	options := {inxchk, ovflchk, ranchk, typchk, ptrinit};
	Modules.extended.Load:=Load; Modules.extended.Unlink:=Unlink
END Interchange.
