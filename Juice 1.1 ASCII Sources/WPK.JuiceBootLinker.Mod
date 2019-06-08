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

MODULE JuiceBootLinker;	(* Oberon for Windows bootlinker (MH) / based on MIPS bootlinker (RC) *)

IMPORT Texts, Oberon, Files, S := SYSTEM;

CONST
	Version = "EB/MH/RC 15.2.96";
	KernelName = "JuiceKernel";
	ModulesName = "Modules";
	AppModulesName = "JuiceModules";

	(* BootLinker runs on Oberon for Windows: *)
	ArrPtrAdj = 0;
	
	(* BootLinker runs on Ceres : 
	ArrPtrAdj = 8;
	*)

	BootHeapSize = 1024*1000;
	NofPtrFix = 20000;

VAR
	W: Texts.Writer;
	heapAdr, dlsymAdr, kernelBody: LONGINT;
	modTag, expTag: LONGINT;
	heap: S.PTR;
	ptrFix: ARRAY NofPtrFix OF LONGINT;
	ptrFixx: LONGINT;

(* ------------ Allocator (Kernel) declarations: ------------ *)

TYPE
	Name = ARRAY 32 OF CHAR;
	ADDRESS = LONGINT;
	Cmd = RECORD name: Name; adr: ADDRESS END;

	Tag = POINTER TO TypeDesc;
	
	ExportPtr = POINTER TO ExportDesc;
	ExportDesc = RECORD
		fp: LONGINT; adr: LONGINT;
		nofExp: INTEGER; 
		dsc: POINTER TO ARRAY OF ExportDesc
	END;
	
	Module = POINTER TO ModuleDesc;
	ModuleDesc = RECORD
		next: Module;
		name: Name;
		init: BOOLEAN;
		refcnt, sb: LONGINT;
		dataSize, conSize, codeSize, refSize: LONGINT;
		nofEntries, nofCmds, nofImps, nofTds, nofPtrs: LONGINT;
		entries: POINTER TO ARRAY OF ADDRESS;
		cmds: POINTER TO ARRAY OF Cmd;
		ptrTab: POINTER TO ARRAY OF ADDRESS;
		tdescs: POINTER TO ARRAY OF (* Tag *) ADDRESS;
		imports: POINTER TO ARRAY OF (* Module *) ADDRESS;
		data, code: POINTER TO ARRAY OF CHAR;
		refs: POINTER TO ARRAY OF CHAR;
		publics, privates: LONGINT;
		nofstrc: INTEGER; struct: LONGINT;	(* ArrPtr *)
		nofimp: INTEGER; import: LONGINT;	(* ArrPtr *)
		nofreimp: INTEGER; reimp: LONGINT;	(* ArrPtr *)
		export: ExportDesc;
		term: PROCEDURE;
		syms: POINTER TO ARRAY OF CHAR;
	END;

VAR
	modules: LONGINT;

TYPE
	TypeDesc = RECORD
		size: LONGINT;
		ptroff: LONGINT
	END;

	FreeBlockPtr = POINTER TO FreeBlock;
	FreeBlock = RECORD
		(* off-4 *) tag: Tag;
		(* off0 *) size: LONGINT;	(* field size aligned to 8-byte boundary, size MOD B = B-4 *)
		(* off4 *) next: ADDRESS
	END;

	InitPtr = POINTER TO RECORD tag: Tag; z0, z1, z2, z3, z4, z5, z6, z7: LONGINT END;

CONST
	B = 32;	(* must be a mutiple of 32 *)
	N = 9;
	nil = 0;
	mark = {0}; array = {1};
	
VAR
	exp: ExportPtr;
	A: ARRAY N+1 OF (*FreeBlockPtr*) ADDRESS;

(* ------------ Loader (Modules) declarations: ------------ *)

TYPE
	Command = PROCEDURE;

VAR
	res: INTEGER;
	KernelRoutines: ARRAY 3 OF RECORD name: Name; adr: ADDRESS END;
	lastMod: LONGINT;
	
CONST
	ModSize = SIZE(ModuleDesc);	(* on target machine!! *)
	done = 0;
	cmdNotFound = 1;
	invalidObjFile = 2;
	keyMismatch = 3;
	corruptedObjFile = 4;	(* not used *)
	fileNotFound = 5;
	moduleNotFound = 6;
	notEnoughSpace = 7;
	refCntNotZero = 8;
	cyclicImport = 9;

	ExtTabWordSize = 16;
	Tag0WordOffset = -2;
	Mth0WordOffset = Tag0WordOffset - ExtTabWordSize;

TYPE
	LinkTab = ARRAY 256 OF RECORD
		mod, entry: CHAR;
		link: LONGINT;
	END;

	DataLinkTab = ARRAY 128 OF RECORD
		mod: CHAR;
		entry: INTEGER;
		nofFixups: INTEGER;
		offset: POINTER TO ARRAY OF LONGINT;
	END;
	
CONST
	(* export/use section *)
	EUEnd = 0; EURecord = 1; EUobjScope = 0; EUrecScope = 1;  EUerrScope = -1;
	EUProcFlag = 80000000H; EUTypFlag = 0C0000000H;

(* ------------------- General procedures -------------------- *)

PROCEDURE Str (s: ARRAY OF CHAR);
BEGIN Texts.WriteString(W, s); Texts.Append(Oberon.Log, W.buf)
END Str;

PROCEDURE Int (i: LONGINT);
BEGIN Texts.WriteInt(W, i, 0); Texts.Append(Oberon.Log, W.buf);
END Int;

PROCEDURE Hex (x: LONGINT);
BEGIN Texts.WriteHex(W, x); Texts.Write(W, "H"); Texts.Append(Oberon.Log, W.buf);
END Hex;

PROCEDURE Ln;
BEGIN Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
END Ln;

PROCEDURE Error (str1, str2: ARRAY OF CHAR);
BEGIN
	Texts.WriteString(W, "Error: "); Texts.WriteString(W, str1); Texts.WriteString(W, str2); Texts.WriteLn(W);
	Texts.Append(Oberon.Log, W.buf)
END Error;

PROCEDURE ASSERT (b: BOOLEAN; err: ARRAY OF CHAR);
BEGIN
	IF ~b THEN Error("", err); HALT(100) END;
END ASSERT;

PROCEDURE ReadUnsigned (VAR R: Files.Rider; VAR u: LONGINT);
	(* read unsigned, 16 bit, little endian value *)
	VAR lowByte, highByte: CHAR;
BEGIN
	Files.Read(R, lowByte); Files.Read(R, highByte);
	u := 256*LONG(ORD(highByte)) + ORD(lowByte)
END ReadUnsigned;

(* ------------------- Allocator procedures ------------------- *)

PROCEDURE NewBlock (size: LONGINT): InitPtr;	(* size MOD B = 0 *)
	VAR i, rest: LONGINT; adr, AN: ADDRESS; ptr: InitPtr; restptr: FreeBlockPtr;
BEGIN
	(*IF size < 0 (* NEW(p, MAX(LONGINT)) *) THEN HALT1 END;*)
	i := size DIV B;
	IF i > N THEN i := N END;
	adr := S.ADR(A[0]) + 4*i;
	AN := S.ADR(A[N]);	(* constant register *)
	LOOP
		S.GET(adr, ptr);
		IF adr = AN THEN
			LOOP
				IF ptr = NIL THEN res := notEnoughSpace;
					Texts.WriteString(W, "Pseudo-heap too small");
					Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf); RETURN NIL
				END;
				IF ptr^.z0 + 4 >= size THEN EXIT END;
				adr := S.ADR(ptr^.z1); S.GET(adr, ptr)
			END;
			EXIT
		END;
		IF ptr # NIL THEN EXIT END;
		INC(adr, 4)
	END;
	(* ptr # NIL *)
	S.PUT(adr, ptr^.z1);
	rest := ptr^.z0 + 4 - size;
	restptr := S.VAL(FreeBlockPtr, S.VAL(ADDRESS, ptr) + size);
	IF rest > 0 THEN	(* >= B >= 16 *)
		i := rest DIV B;
		IF i > N THEN i := N END;
		restptr^.tag := S.VAL(Tag, S.ADR(restptr^.size));
		restptr^.size := rest - 4;
		restptr^.next := A[i]; A[i] := S.VAL(ADDRESS, restptr)
	END;
	RETURN ptr
END NewBlock;
	
PROCEDURE NewRec (tag: Tag; size: LONGINT): ADDRESS;	(* implementation of NEW(ptr) *)
	VAR ptr, init: InitPtr;
BEGIN (* tag^.size = rectyp^.size *)
	size := S.VAL(LONGINT, S.VAL(SET, size + (4 (*tag*) + B-1))-S.VAL(SET, B-1));
	ptr := NewBlock(size);
	init := S.VAL(InitPtr, S.VAL(ADDRESS, ptr) + size - 32);
	init^.z0 := 0; init^.z1 := 0; init^.z2 := 0; init^.z3 := 0; init^.z4 := 0; init^.z5 := 0; init^.z6 := 0;
	WHILE init # ptr DO
		DEC(S.VAL(ADDRESS, init), 32);
		init^.z0 := 0; init^.z1 := 0; init^.z2 := 0; init^.z3 := 0; init^.z4 := 0; init^.z5 := 0; init^.z6 := 0; init^.z7 := 0
	END;
	ptr^.tag := tag;
	RETURN S.VAL(ADDRESS, ptr) + 4
END NewRec;

PROCEDURE NewSys (size: LONGINT): ADDRESS;	(* implementation of S.NEW(ptr, size) *)
	VAR ptr, init: InitPtr;
BEGIN
	size := S.VAL(LONGINT, S.VAL(SET, size + (28 + B-1))-S.VAL(SET, B-1));
	ptr := NewBlock(size);
	init := S.VAL(InitPtr, S.VAL(ADDRESS, ptr) + size - 32);
	WHILE init # ptr DO
		init^.tag := NIL; init^.z0 := 0; init^.z1 := 0; init^.z2 := 0; init^.z3 := 0; init^.z4 := 0; init^.z5 := 0; init^.z6 := 0;
		DEC(S.VAL(ADDRESS, init), 32);
	END;
	ptr^.tag := S.VAL(Tag, S.ADR(ptr^.z0));
	ptr^.z0 := size - 4;
	ptr^.z1 := -4;
	init^.z2 := 0; init^.z3 := 0; init^.z4 := 0;
	ptr^.z5 := S.ADR(ptr^.z0);
	init^.z6 := 0;
	RETURN S.VAL(ADDRESS, ptr) + 28
END NewSys;

PROCEDURE NewArr(nofdim, nofelem: LONGINT; eltag: Tag): ADDRESS;
	(* implementation of NEW(ptr, dim0, dim1, ...) *)
	VAR size, firstElem, elSize, arrSize, vectSize: LONGINT; ptr, init: InitPtr;
BEGIN
	(* eb, 4.12.95
	IF eltag = NIL THEN (* ARRAY OF POINTER *) eltag := S.VAL(Tag, ptrElemTag) END;
	*)
	elSize := eltag^.size;
	arrSize := nofelem*elSize;
	vectSize := 8*(nofdim DIV 2) + 4;	(* -> ADR(firstElem) MOD 8 = 0 *)
	IF eltag^.ptroff = -4 THEN (* no pointers in element type *) RETURN NewSys(arrSize + vectSize + 12) END;
	size := S.VAL(LONGINT, S.VAL(SET, arrSize + vectSize + (16 + B-1))-S.VAL(SET, B-1));
	ptr := NewBlock(size);
	init := S.VAL(InitPtr, S.VAL(ADDRESS, ptr) + size - 32);
	WHILE init # ptr DO
		init^.tag := NIL; init^.z0 := 0; init^.z1 := 0; init^.z2 := 0; init^.z3 := 0; init^.z4 := 0; init^.z5 := 0; init^.z6 := 0;
		DEC(S.VAL(ADDRESS, init), 32);
	END;
	ptr^.tag := S.VAL(Tag, S.VAL(SET, eltag) + array);
	firstElem := S.ADR(ptr^.z3) + vectSize;
	ptr^.z0 := firstElem + arrSize - elSize;
	(* ptr^.z1 is reserved for mark phase *)
	ptr^.z2 := firstElem;
	ptr^.z3 := 0; ptr^.z4 := 0; ptr^.z5 := 0; ptr^.z6 := 0;
	RETURN S.VAL(ADDRESS, ptr) + 4
END NewArr;

(* ------------------- Loader procedures ------------------- *)

PROCEDURE LSW (x: LONGINT): LONGINT;
BEGIN (* least significant word (unsigned) *)
	RETURN S.VAL(LONGINT, S.VAL(SET, x) * S.VAL(SET, 0FFFFH))
END LSW;

PROCEDURE MSW (x: LONGINT): LONGINT;
BEGIN (* most significant word (unsigned) *)
	RETURN S.LSH(x, -16); RETURN x
END MSW;

PROCEDURE InitKernel (m: Module);
	CONST ProcRefTag = 0F8X; VarTag = 1X; VarParTag = 3X;
	VAR i, pos, refend, adr: LONGINT; ch: CHAR; name: Name; 

	PROCEDURE ReadNum (VAR pos: LONGINT; VAR i: LONGINT);
		VAR n: LONGINT; shift: SHORTINT; x: CHAR;
	BEGIN
		shift := 0; n := 0; S.GET(pos, x); INC(pos);
		WHILE ORD(x) >= 128 DO
			INC(n, ASH(ORD(x) MOD 128, shift));
			INC(shift, 7); S.GET(pos, x); INC(pos);
		END;
		i := n + ASH(ORD(x) MOD 64 - ORD(x) DIV 64*64, shift)
	END ReadNum;

	PROCEDURE ReadName (VAR pos: LONGINT; VAR n: ARRAY OF CHAR);
		VAR i: INTEGER; ch: CHAR;
	BEGIN i := 0;
		REPEAT S.GET(pos, ch); INC(pos); n[i] := ch; INC(i) UNTIL ch = 0X
	END ReadName;
	
BEGIN
	INC(m.refcnt);	(* Kernel never unloaded *)
	(* link to Windows and entry point: *)
	dlsymAdr := m.sb - 4;
	kernelBody := S.ADR(m.code[0]);
	(* find entries for KernelRoutines *)
	pos := S.ADR(m.refs[0]); refend := pos + LEN(m.refs^); i := 0;
	S.GET(pos, ch); INC(pos);
	WHILE (pos <= refend) & (ch = ProcRefTag) & (i < 3) DO
		ReadNum(pos, adr); ReadName(pos, name);
		IF name = KernelRoutines[i].name THEN
			KernelRoutines[i].adr := S.ADR(m.code[adr]);
			INC(i)
		END;
		S.GET(pos, ch); INC(pos);
		WHILE (ch = VarTag) OR (ch = VarParTag) DO
			S.GET(pos, ch); INC(pos); (* form *)
			ReadNum(pos, adr); ReadName(pos, name);
			S.GET(pos, ch); INC(pos);
		END;
	END;
	IF i # 3 THEN Str("Error: Only "); Int(i); Str(" of 3 Kernel routines found"); Ln; HALT(99) END;
END InitKernel;

PROCEDURE InitModules(m: Module);
	VAR i: LONGINT; mm: Module;
		td: POINTER TO RECORD filler: ARRAY 4 OF LONGINT; name: Name END;

	PROCEDURE PatchExport(VAR scope: ExportDesc; tag: LONGINT);
	VAR i, t: LONGINT;
	BEGIN
		S.GET(S.VAL(LONGINT, scope.dsc)-4, t);
		IF t # tag THEN
			S.PUT(S.VAL(LONGINT, scope.dsc)-4, tag);
			i := 0;
			WHILE i < scope.nofExp DO
				IF scope.dsc[i].nofExp > 0 THEN PatchExport(scope.dsc[i], tag) END;
				INC(i)
			END
		END
	END PatchExport;

BEGIN
	(* find ModuleDesc tag *)
	i := LEN(m.tdescs^);
	REPEAT
		DEC(i);
		modTag := S.VAL(LONGINT, m.tdescs[i]);
		S.GET(modTag - 4, td);
	UNTIL td.name = "ModDesc";
	(* patch all ModuleDesc tags *)
	mm := S.VAL(Module, modules);
	WHILE mm # NIL DO
		S.PUT(S.VAL(LONGINT, mm) - 4, modTag);
		mm := mm.next
	END;
	(* find ExportDesc tag *)
	i := LEN(m.tdescs^);
	REPEAT
		DEC(i);
		expTag := S.VAL(LONGINT, m.tdescs[i]);
		S.GET(S.VAL(LONGINT, expTag) - 4, td);
	UNTIL td.name = "ExportDesc";
	(* patch all ExportDesc tags *)
	mm := S.VAL(Module, modules);
	WHILE mm # NIL DO
		PatchExport(mm.export, S.VAL(LONGINT, S.VAL(SET, expTag)+array));
		mm := mm.next
	END
END InitModules;

PROCEDURE RecordFix (adr: LONGINT);
BEGIN
	IF ptrFixx # -1 THEN
		IF ptrFixx < NofPtrFix THEN ptrFix[ptrFixx] := adr; INC(ptrFixx)
		ELSE Error("", "Too many ptr fixes"); ptrFixx := -1; res := notEnoughSpace;
		END
	END
END RecordFix;

(* ---- auxiliaries ---- *)

PROCEDURE And(x, y: LONGINT): LONGINT;
BEGIN RETURN S.VAL(LONGINT, S.VAL(SET, x) * S.VAL(SET, y));
END And;

(* ---- files auxiliaries ---- *)

PROCEDURE FilesRString*(VAR R: Files.Rider; VAR string: ARRAY OF CHAR);
	VAR i: INTEGER; ch: CHAR;
BEGIN i := 0;
	LOOP Files.Read(R, ch);
		IF ch = 0X THEN string[i] := 0X; RETURN
		ELSIF ch > 7FX THEN string[i] := CHR(ORD(ch)-80H); string[i+1] := 0X; RETURN
		ELSE string[i] := ch; INC(i) END
	END
END FilesRString;

(* load obj file *)

PROCEDURE ^Load (name: ARRAY OF CHAR; VAR m: Module);

PROCEDURE LoadModule (VAR R: Files.Rider; VAR m: Module);
	TYPE
		TDesc = POINTER TO RECORD word: ARRAY 32000 OF LONGINT END;
		ArrPtr = POINTER TO RECORD a, b, c, len, data: LONGINT END;
	VAR
		i: LONGINT; j, tmp, nofDataLinks, nofLinks: INTEGER; symSize, e, k, t: LONGINT;
		m1, imp: Module; mname: Name; ch: CHAR; body: Command;
		linkTab: LinkTab; dataLinks: DataLinkTab;
		types: ARRAY 128 OF RECORD initialized: BOOLEAN; tdesc: TDesc; entry, root, nofMeth, nofInhMeth, baseMod: INTEGER; baseEntry: LONGINT END;
		arrPtr: ArrPtr;

	PROCEDURE FixupCall(code, link, fixval: LONGINT);
	VAR instr, nextlink, jmp: LONGINT;
	BEGIN
		REPEAT
			S.GET(code + link, instr);
			nextlink := MSW(instr);
			S.GET(code + link - 1, jmp);
			IF LSW(jmp) MOD 100H = 0E8H THEN
				S.PUT(code + link, fixval - (code + link + 4)) (* + 4: to next instruction *)
			ELSE
				S.PUT(code + link, fixval); RecordFix(code + link)
			END;
			link := nextlink
		UNTIL link = 0FFFFH
	END FixupCall;
	
	PROCEDURE FixupVar(code, link, fixval: LONGINT);
	VAR nofFixups: INTEGER; i, val: LONGINT;
	BEGIN
		nofFixups := dataLinks[link].nofFixups;
		i := 0;
		WHILE i < nofFixups DO
			S.GET(code + dataLinks[link].offset[i], val);
			S.PUT(code + dataLinks[link].offset[i], val + fixval);
			RecordFix(code + dataLinks[link].offset[i]);
			INC(i)
		END
	END FixupVar;
	
	PROCEDURE Fixup (m: Module; VAR link: LinkTab);
		VAR i, j, val, offs, disp: LONGINT;
			modNo, entryNo, nofFixups: INTEGER;
			codebase: ADDRESS;
			from: Module;
	BEGIN
		codebase := S.ADR(m.code[0]);
	
		(* global variables *)
		modNo := ORD(dataLinks[0].mod); nofFixups := dataLinks[0].nofFixups;
		IF modNo = 0 THEN
			i := 0;
			WHILE i < nofFixups DO
				S.GET(codebase + dataLinks[0].offset[i], val);
				S.PUT(codebase + dataLinks[0].offset[i], val + m.sb);
				RecordFix(codebase + dataLinks[0].offset[i]);
				INC(i)
			END
		END;
	
		(* Kernel.NewRec, Kernel.NewSys, Kernel.NewArr, local Procedure assignments, case table and imported procedures *)
		i := 0;
		WHILE i < nofLinks DO
			IF ORD(link[i].mod) = 0 THEN
				(* Kernel.NewRec, Kernel.NewSys, Kernel.NewArr, local Procedure assignments, case table *)
				CASE ORD(link[i].entry) OF
					255:	(* case table fixup in constant area *)
						offs := link[i].link;
						WHILE offs # 0FFFFH DO
							S.GET(m.sb + offs, val); S.PUT(m.sb + offs, codebase + LSW(val));
							RecordFix(m.sb + offs);
							offs := MSW(val);
						END;
				|   254:	(* local procedure assignment *)
						offs := link[i].link;
						WHILE offs # 0FFFFH DO
							S.GET(codebase + offs, val); S.PUT(codebase + offs, m.entries[LSW(val)]);
							RecordFix(codebase + offs);
							offs := MSW(val);
						END;
				|   253:	(* Kernel.NewRec *)
						offs := link[i].link;
						WHILE offs # 0FFFFH DO
							ASSERT(KernelRoutines[0].adr # 0, "NewRec not found");
							S.GET(codebase + offs, val); S.PUT(codebase + offs, KernelRoutines[0].adr - (codebase + offs + 4));
							offs := MSW(val);
						END;
				|   252:	(* Kernel.NewSys *)
						offs := link[i].link;
						WHILE offs # 0FFFFH DO
							ASSERT(KernelRoutines[1].adr # 0, "NewSys not found");
							S.GET(codebase + offs, val); S.PUT(codebase + offs, KernelRoutines[1].adr - (codebase + offs + 4));
							offs := MSW(val);
						END;
				|   251:	(* Kernel.NewArr *)
						offs := link[i].link;
						WHILE offs # 0FFFFH DO
							ASSERT(KernelRoutines[2].adr # 0, "NewArr not found");
							S.GET(codebase + offs, val); S.PUT(codebase + offs, KernelRoutines[2].adr - (codebase + offs + 4));
							offs := MSW(val);
						END;
				ELSE 
					Error("Fixup error  0 module 0", ""); HALT(101);
				END;
			ELSE	(* imported procedure from module from *)
				Error("Fixup error  1 module 0", ""); HALT(100);
			END;
			INC(i);
		END;
	END Fixup;
	
	PROCEDURE LoadExpBlock(VAR R: Files.Rider; M: Module);
		TYPE ArrPtr = POINTER TO RECORD a, b, c, len, data: LONGINT END;
		VAR struct: ARRAY 1024 OF ExportPtr; nofStr: INTEGER;
	
		PROCEDURE LoadScope(VAR scope: ExportDesc; level: INTEGER; adr: LONGINT);
			VAR no, no2: INTEGER; fp, off: LONGINT; dsc: ExportDesc;
		BEGIN
			Files.ReadBytes(R, scope.nofExp, 2); no := 0; no2 := 0;
			
			S.PUT(S.ADR(scope.dsc), NewArr(1, scope.nofExp, S.VAL(Tag, expTag)));
			S.PUT(S.VAL(LONGINT, scope.dsc)+12, scope.nofExp);
			RecordFix(S.VAL(LONGINT, scope.dsc)-4);
			RecordFix(S.VAL(LONGINT, scope.dsc));
			RecordFix(S.VAL(LONGINT, scope.dsc)+8);
			RecordFix(S.ADR(scope.dsc));
	
			scope.dsc[0].adr := adr;
			IF level = EUrecScope THEN INC(nofStr); struct[nofStr] := S.VAL(ExportPtr, S.ADR(scope)) END;
			Files.ReadNum(R, fp);
			WHILE fp#EUEnd DO
				IF fp=EURecord THEN Files.ReadNum(R, off);
					IF off < 0 THEN
						scope.dsc[no2].nofExp := struct[-off].nofExp; scope.dsc[no2].dsc := struct[-off].dsc; 	(* old type *)
						RecordFix(S.ADR(scope.dsc[no2].dsc))
					ELSE LoadScope(scope.dsc[no2], EUrecScope, off)
					END
				ELSE 
					IF level = EUobjScope THEN Files.ReadNum(R, scope.dsc[no].adr) END;
					scope.dsc[no].fp := fp; no2 := no; INC(no)
				END;
				Files.ReadNum(R, fp)
			END
		END LoadScope;
	
	BEGIN nofStr := 0; LoadScope(M.export, EUobjScope, 0)
	END LoadExpBlock;
	
	PROCEDURE CheckUseBlock(VAR R: Files.Rider; M: Module);
		VAR mod: Module; name: Name; 
	
		PROCEDURE Err;
		BEGIN	
			IF res = 0 THEN Str(M.name); Str(" imports incompatible version of "); Str(mod.name); Str(": "); res := 16
			ELSE Str("   ") END
		END Err;
	
		PROCEDURE CheckScope(scope: ExportDesc; level: INTEGER);
			VAR fp, link, i, tdadr: LONGINT; tadr: ExportPtr; tmpErr: BOOLEAN;
		BEGIN tmpErr := (level = EUerrScope);
			i := 0;
			Files.ReadNum(R, fp);
			WHILE fp # EUEnd DO
				IF fp = EURecord THEN Files.ReadNum(R, link);
					IF tmpErr THEN CheckScope(scope.dsc[i], EUerrScope)
					ELSE
						IF link # 0 THEN tadr := S.VAL(ExportPtr, S.ADR(scope.dsc[i].dsc[0]));
							S.GET(mod.sb+tadr.adr, tdadr); S.PUT(M.sb-link, tdadr);	(* tdadr at tadr[0] *)
							RecordFix(M.sb-link)
						END;
						CheckScope(scope.dsc[i], EUrecScope)
					END
				ELSE FilesRString(R, name);
					IF level >= EUobjScope THEN tmpErr := FALSE;
						IF level = EUobjScope THEN Files.ReadNum(R, link) END;
						i := 0; WHILE (i < scope.nofExp) & (scope.dsc[i].fp # fp) DO INC(i) END;
						IF i >= scope.nofExp THEN Err; tmpErr := TRUE; Ln; Str("    ");
							IF name = "@" THEN Str("RECORD ") 
							ELSE Str(name)
							END;
							Str(" incompatible")
						ELSIF (level = EUobjScope) & (link # 0) THEN 
							IF And(link, EUProcFlag) = 0 THEN
								FixupVar(S.ADR(M.code[0]), link, mod.sb+scope.dsc[i].adr)
							ELSE
								FixupCall(S.ADR(M.code[0]), link-EUProcFlag, scope.dsc[i].adr+S.ADR(mod.code[0]))
							END
						END
					END
				END;
				Files.ReadNum(R, fp)
			END
		END CheckScope;
	
	BEGIN FilesRString(R, name);
		WHILE (name # "") & (res = 0) DO
			Load(name, mod);
			IF res = 0 THEN CheckScope(mod.export, EUobjScope) END;
			FilesRString(R, name)
		END
	END CheckUseBlock;
	
	PROCEDURE Expect (tag: CHAR; tagName: ARRAY OF CHAR);
		VAR ch: CHAR;
	BEGIN Files.Read(R, ch);
		IF ch # tag THEN res := invalidObjFile;
			Ln; Str(m.name); Str(" is corrupted (bad "); Str(tagName); Str(").");
		END;
	END Expect;
	
	PROCEDURE FindTDescAdr(M: Module; fp: LONGINT; VAR adr: LONGINT);
	VAR i: INTEGER;
	BEGIN
		i := 0;
		WHILE ( i < M.export.nofExp) & (M.export.dsc[i].fp # fp) DO INC(i) END;
		IF i < M.export.nofExp THEN adr := M.export.dsc[i].dsc[0].adr
		ELSE
			adr := 0;
			Str(M.name); Str(" not compatible to "); Str(m.name); Ln;
			Str("TDesc in Module not found"); Ln
		END
	END FindTDescAdr;
	
	PROCEDURE ReadTypes; 
		VAR i, j, k, tdsize, recordSize: LONGINT;
			tdEntry, nofMethods, nofNewMeths, mthNo, nofPointers, root, entryNo: INTEGER;
			td: TDesc; name: Name; ch: CHAR;
	BEGIN
		i := 0;
		WHILE i < LEN(m.tdescs^) DO
			types[i].initialized := FALSE;
			Files.ReadLInt(R, recordSize);
			Files.ReadInt(R, tdEntry); types[i].entry := tdEntry;
			Files.ReadInt(R, types[i].baseMod);
			Files.ReadLInt(R, types[i].baseEntry);
			Files.ReadInt(R, nofMethods);
			types[i].nofMeth := nofMethods; Files.ReadInt(R, types[i].nofInhMeth);
			Files.ReadInt(R, nofNewMeths); Files.ReadInt(R, nofPointers);
			Files.ReadString(R, name);
			root := 13 (* fields tdsize..mdesc *) + nofMethods + ExtTabWordSize + 1 (* tag *);
			INC(root, (-root+2) MOD 4);	(* ADR(td.word[root]) MOD 16 = 8 ! *)
			types[i].root := root;
			tdsize := (root + 1 (* recsize *) + nofPointers + 1 (* sentinel *) )*4;
			(* IF LargestAvailable() < tdsize THEN res := notEnoughSpace; RETURN END; *)
			(* S.NEW(td, tdsize - 24 (* overhead of SysBlk header *) ); *)
			td := S.VAL(TDesc, NewSys(tdsize - 24 (* overhead of SysBlk header *) ));
			IF td = NIL THEN RETURN END;
			DEC(S.VAL(ADDRESS, td), 24);
			types[i].tdesc := td; RecordFix(S.ADR(td.word[0]) - 4);
			td.word[0] := tdsize;
			td.word[1] := -4; (* sentinel *)
			td.word[2] := S.ADR(td.word[root]) (* self *); RecordFix(S.ADR(td.word[2]));
			td.word[3] := 0; (* extlev *)
			k := S.ADR(td.word[4]); j := 0;
			REPEAT ch := name[j]; S.PUT(k, ch); INC(j); INC(k) UNTIL ch = 0X;
			td.word[12] := S.ADR(m^); (* mdesc *) RecordFix(S.ADR(td.word[12]));
			j := 0;
			WHILE j < nofNewMeths DO
				Files.ReadInt(R, mthNo); Files.ReadInt(R, entryNo);
				td.word[root + Mth0WordOffset - mthNo] := m.entries[entryNo];
				RecordFix(S.ADR(td.word[root + Mth0WordOffset - mthNo]));
				INC(j)
			END;
			td.word[root - 1] := S.ADR(td.word[0]); (* tag of subobj *) RecordFix(S.ADR(td.word[root - 1]));
			td.word[root] := recordSize;
			S.PUT(m.sb + tdEntry, S.ADR(td.word[root])); RecordFix(m.sb + tdEntry);
			m.tdescs[i] := S.ADR(td.word[root]); RecordFix(S.ADR(m.tdescs[i]));
			j := 0;
			WHILE j < nofPointers DO Files.ReadLInt(R, td.word[root+1+j]); INC(j) END;
			td.word[root+1+nofPointers] := -(nofPointers+1)*4; (* sentinel *)
			INC(i)
		END
	END ReadTypes;

	PROCEDURE InitType(i: LONGINT);
		VAR t, k, baseType, tag, entry: LONGINT; root, baseModNo, n: INTEGER; td: TDesc; baseMod: Module;
	BEGIN
		IF ~types[i].initialized THEN
			td := types[i].tdesc; baseModNo := types[i].baseMod;
			k := 0; root := types[i].root;
			IF baseModNo # -1 THEN
				IF baseModNo = 0 THEN (* base type in this module, initialize first! *)
					t := 0;
					WHILE (t < LEN(m^.tdescs^)) & (types[t].entry # types[i].baseEntry) DO INC(t) END;
					InitType(t);
				END;
				(* copy base type tags *)
				IF baseModNo > 0 THEN
					baseMod := S.VAL(Module, m.imports[baseModNo-1]);
					FindTDescAdr(baseMod, types[i].baseEntry, types[i].baseEntry)
				ELSE (* baseModNo = 0 *)
					baseMod := m
				END;
				S.GET(baseMod.sb + types[i].baseEntry, baseType);
				S.GET(baseType + Tag0WordOffset*4, tag);
				WHILE tag # 0 DO
					td.word[root + Tag0WordOffset - k] := tag; RecordFix(S.ADR(td.word[root + Tag0WordOffset - k]));
					INC(k);
					S.GET(baseType + (Tag0WordOffset - k)*4, tag);
				END;
				(* copy non-overwritten base methods *)
				n := types[i].nofInhMeth;
				WHILE n > 0 DO DEC(n);
					entry := td.word[root + Mth0WordOffset - n];
					IF entry = 0 THEN
						S.GET(baseType + (Mth0WordOffset - n)*4, td.word[root + Mth0WordOffset - n]);
						RecordFix(S.ADR(td.word[root + Mth0WordOffset - n]))
					END;
				END;
			END;
			td.word[3] := k; (* extlev *)
			td.word[root + Tag0WordOffset - k] := S.ADR(td.word[root]); (* own type tag *)
			RecordFix(S.ADR(td.word[root + Tag0WordOffset - k]));
			types[i].initialized := TRUE;
		END
	END InitType;

	PROCEDURE InitTypes;
		VAR i: LONGINT;
	BEGIN i := 0;
		WHILE i < LEN(m.tdescs^) DO InitType(i); INC(i) END
	END InitTypes;

	PROCEDURE BuildModuleBlock (m: Module);
		VAR t, size, gvarSize: LONGINT;
			arrPtr: ArrPtr;
	BEGIN
		size := 16 * ((m.nofEntries*4 + 35) DIV 16
			+ (m.nofCmds*SIZE(Cmd) + 35) DIV 16 + (m.nofPtrs*4 + 35) DIV 16
			+ (m.nofTds*4 + 35) DIV 16 + ((m.nofImps+1)*4 + 35) DIV 16
			+ (m.dataSize + (-m.dataSize) MOD 8 + m.conSize + 35) DIV 16
			+ (m.codeSize + 35) DIV 16 + (m.refSize + 35) DIV 16);
		arrPtr := S.VAL(ArrPtr, NewSys(size)); RecordFix(S.ADR(arrPtr^) - 28);
		IF arrPtr = NIL THEN HALT(101) END;

		S.GET(S.VAL(ADDRESS, arrPtr) - 4, t);
		
		S.PUT(S.VAL(ADDRESS, arrPtr) - 4, t); RecordFix(S.VAL(ADDRESS, arrPtr) - 4);
		S.PUT(S.ADR(m.entries), S.VAL(ADDRESS, arrPtr) + ArrPtrAdj); RecordFix(S.ADR(m.entries));
		arrPtr.len := m.nofEntries;
		INC(S.VAL(ADDRESS, arrPtr), ((m.nofEntries*4 + 35) DIV 16)*16);

		S.PUT(S.VAL(ADDRESS, arrPtr) - 4, t); RecordFix(S.VAL(ADDRESS, arrPtr) - 4);
		S.PUT(S.ADR(m.cmds), S.VAL(ADDRESS, arrPtr) + ArrPtrAdj); RecordFix(S.ADR(m.cmds));
		arrPtr.len := m.nofCmds;
		INC(S.VAL(ADDRESS, arrPtr), ((m.nofCmds*SIZE(Cmd) + 35) DIV 16)*16);

		S.PUT(S.VAL(ADDRESS, arrPtr) - 4, t); RecordFix(S.VAL(ADDRESS, arrPtr) - 4);
		S.PUT(S.ADR(m.ptrTab), S.VAL(ADDRESS, arrPtr) + ArrPtrAdj); RecordFix(S.ADR(m.ptrTab));
		arrPtr.len := m.nofPtrs;
		INC(S.VAL(ADDRESS, arrPtr), ((m.nofPtrs*4 + 35) DIV 16)*16);

		S.PUT(S.VAL(ADDRESS, arrPtr) - 4, t); RecordFix(S.VAL(ADDRESS, arrPtr) - 4);
		S.PUT(S.ADR(m.tdescs), S.VAL(ADDRESS, arrPtr) + ArrPtrAdj); RecordFix(S.ADR(m.tdescs));
		arrPtr.len := m.nofTds;
		INC(S.VAL(ADDRESS, arrPtr), ((m.nofTds*4 + 35) DIV 16)*16);

		S.PUT(S.VAL(ADDRESS, arrPtr) - 4, t); RecordFix(S.VAL(ADDRESS, arrPtr) - 4);
		S.PUT(S.ADR(m.imports), S.VAL(ADDRESS, arrPtr) + ArrPtrAdj); RecordFix(S.ADR(m.imports));
		arrPtr.len := m.nofImps+1;
		INC(S.VAL(ADDRESS, arrPtr), (((m.nofImps+1)*4 + 35) DIV 16)*16);

		S.PUT(S.VAL(ADDRESS, arrPtr) - 4, t); RecordFix(S.VAL(ADDRESS, arrPtr) - 4);
		S.PUT(S.ADR(m.data), S.VAL(ADDRESS, arrPtr) + ArrPtrAdj); RecordFix(S.ADR(m.data));
		gvarSize := m.dataSize + (-m.dataSize) MOD 8;
		m.sb := S.ADR(arrPtr.data) + gvarSize; RecordFix(S.ADR(m.sb));
		arrPtr.len := (gvarSize + m.conSize + 3);
		INC(S.VAL(ADDRESS, arrPtr), ((gvarSize + m.conSize + 35) DIV 16)*16);

		S.PUT(S.VAL(ADDRESS, arrPtr) - 4, t); RecordFix(S.VAL(ADDRESS, arrPtr) - 4);
		S.PUT(S.ADR(m.code), S.VAL(ADDRESS, arrPtr) + ArrPtrAdj); RecordFix(S.ADR(m.code));
		arrPtr.len := m.codeSize;
		INC(S.VAL(ADDRESS, arrPtr), ((m.codeSize + 35) DIV 16)*16);

		S.PUT(S.VAL(ADDRESS, arrPtr) - 4, t); RecordFix(S.VAL(ADDRESS, arrPtr) - 4);
		S.PUT(S.ADR(m.refs), S.VAL(ADDRESS, arrPtr) + ArrPtrAdj); RecordFix(S.ADR(m.refs));
		arrPtr.len := m.refSize;
	END BuildModuleBlock;

BEGIN (* LoadModule *)
	res := done;
	m := S.VAL(Module, NewRec(S.VAL(Tag, modTag), ModSize)); RecordFix(S.ADR(m^) - 4);
	IF m = NIL THEN RETURN END;
	imp := S.VAL(Module, lastMod);
	IF imp # NIL THEN imp.next := m; RecordFix(S.ADR(imp.next)) END;
	lastMod := S.VAL(LONGINT, m);
	IF modules = 0 THEN modules := lastMod END;
	m.init := FALSE; m.refcnt := 0; m.next := NIL;

	(* Skip sym file *)
	Files.ReadNum(R, symSize); 
	IF TRUE THEN
		arrPtr := S.VAL(ArrPtr, NewSys(symSize + 35)); 
		RecordFix(S.ADR(arrPtr^)-28); RecordFix(S.VAL(ADDRESS, arrPtr)-4);
		S.PUT(S.ADR(m.syms), S.VAL(ADDRESS, arrPtr) + ArrPtrAdj); RecordFix(S.ADR(m.syms));
		arrPtr.len := symSize;
		i := 0; WHILE i < symSize DO
			Files.Read(R, m.syms[i]);
			INC(i)
		END 
	ELSE Files.Set(R, Files.Base(R), Files.Pos(R)+symSize)
	END;

	(* HeaderBlk *)
	Files.ReadLInt(R, m.refSize);
	Files.ReadInt(R, tmp); m.nofEntries := tmp;
	Files.ReadInt(R, tmp); m.nofCmds := tmp;
	Files.ReadInt(R, tmp); m.nofPtrs := tmp;
	Files.ReadInt(R, tmp); m.nofTds := tmp;
	Files.ReadInt(R, tmp); m.nofImps := tmp;
	Files.ReadInt(R, nofDataLinks);
	Files.ReadInt(R, nofLinks);
	Files.ReadLInt(R, m.dataSize);
	Files.ReadInt(R, tmp); m.conSize := tmp;
	ReadUnsigned(R, m.codeSize);
	Files.ReadString(R, m.name);

	BuildModuleBlock(m);

	(* EntryBlk *)
	Expect(082X, "EntryTag"); i := 0; t := S.ADR(m.code[0]);
	WHILE i < m.nofEntries DO
		ReadUnsigned(R, e); m.entries[i] := t + e;
		RecordFix(S.ADR(m.entries[i])); 
		INC(i)
	END;

	(* CmdBlk *)
	Expect(083X, "CommandTag"); i := 0;
	WHILE i < m.nofCmds DO
		Files.ReadString(R, m.cmds[i].name); ReadUnsigned(R, e);
		m.cmds[i].adr := t + e; RecordFix(S.ADR(m.cmds[i].adr));
		INC(i)
	END;

	(* PtrBlk *)
	Expect(084X, "PointerTag"); i := 0; t := m.sb;
	WHILE i < m.nofPtrs DO
		Files.ReadLInt(R, k); m.ptrTab[i] := t + k; RecordFix(S.ADR(m.ptrTab[i]));
		INC(i)
	END;

	(* Import Block *)
	Expect(085X, "ImportTag"); i := 0;
	WHILE (i < m.nofImps) & (res = done) DO
		FilesRString(R, mname); Load(mname, imp);
		IF res = done THEN
			INC(imp.refcnt);
			m.imports[i] := S.VAL(LONGINT, imp);
			RecordFix(S.ADR(m.imports[i]));
			INC(i)
		END
	END;

	(* Data Link Block *)
	Expect(08DX, "DataLinkTag"); i := 0;
	WHILE i < nofDataLinks DO
		Files.Read(R, dataLinks[i].mod);
		Files.ReadInt(R, dataLinks[i].entry);
		Files.ReadInt(R, dataLinks[i].nofFixups);
		IF dataLinks[i].nofFixups > 0 THEN
			NEW(dataLinks[i].offset, dataLinks[i].nofFixups);
			j := 0;
			WHILE j < dataLinks[i].nofFixups DO
				ReadUnsigned(R, dataLinks[i].offset[j]);
				INC(j)
			END
		ELSE dataLinks[i].offset := NIL
		END;
		INC(i)
	END;

	(* Link Block *)
	Expect(086X, "LinkTag"); i := 0;
	WHILE i < nofLinks DO
		Files.Read(R, linkTab[i].mod); Files.Read(R, linkTab[i].entry); 
		ReadUnsigned(R, linkTab[i].link);
		INC(i)
	END;

	(* Const Block *)
	Expect(087X, "DataTag"); i := 0; t := m.sb;
	WHILE i < m.conSize DO Files.Read(R, ch); S.PUT(t, ch); INC(t); INC(i) END;

	(* Export Block *)
	Expect(088X, "Export Tag");
	LoadExpBlock(R, m);

	(* Code Block *)
	Expect(089X, "CodeTag"); i := 0; t := S.ADR(m.code[0]);
	WHILE i < m.codeSize DO Files.Read(R, ch); S.PUT(t, ch); INC(t); INC(i) END;

	(* Use Block *)
	Expect(08AX, "Use Tag");
	CheckUseBlock(R, m);

	(* TypeBlk *)
	Expect(08BX, "TypeTag"); ReadTypes;
	IF res # done THEN RETURN END;

	(* Reference Block *)
	Expect(08CX, "ReferenceTag"); i := 0; t := S.ADR(m.refs[0]);
	WHILE i < m.refSize DO Files.Read(R, ch); S.PUT(t, ch); INC(t); INC(i) END;

	IF res = done THEN
		Str("   "); Str(m.name); Ln;
		Fixup(m, linkTab);
		InitTypes;
		IF m.name =  KernelName THEN InitKernel(m) 
		ELSIF (m.name = ModulesName) OR (m.name = AppModulesName) THEN InitModules(m)
		END;
		m.init := TRUE
	END
END LoadModule;

PROCEDURE Load (name: ARRAY OF CHAR; VAR m: Module);
	VAR f: Files.File; R: Files.Rider; i: INTEGER; fname: ARRAY 64 OF CHAR; tag: CHAR;
BEGIN
	m := S.VAL(Module, modules); res := done;
	WHILE (m # NIL) & (name # m.name) DO m := m.next END;
	IF m = NIL THEN
		COPY(name, fname); i := 0;
		WHILE fname[i] # 0X DO INC(i) END;
		fname[i] := "."; fname[i+1] := "O"; fname[i+2] := "b"; fname[i+3] := "j"; fname[i+4] := 0X;
		f := Files.Old(fname);
		IF f = NIL THEN
			Error(fname, " not found"); res := fileNotFound; RETURN
		END;
		Files.Set(R, f, 0); Files.Read(R, tag);
		IF tag = 0BBX THEN
			Files.Read(R, tag);
			IF tag = 055X THEN LoadModule(R, m)
			ELSE Error(fname, ": wrong object file version");
			END;
		ELSE Error(fname, " is not an object file"); res := invalidObjFile;
		END
	ELSIF ~m.init THEN
		Error("", "cyclic import not allowed"); res := cyclicImport;
	END
END Load;

PROCEDURE Init;
	VAR a: ADDRESS; i, size: LONGINT; rest: FreeBlockPtr;
BEGIN
	KernelRoutines[0].name := "NewRec"; KernelRoutines[0].adr := 0;
	KernelRoutines[1].name := "NewSys"; KernelRoutines[1].adr := 0;
	KernelRoutines[2].name := "NewArr"; KernelRoutines[2].adr := 0;
	modules := 0;
	lastMod := 0;
	modTag := 0;
	ptrFixx := 0;
	i := 0;
	WHILE i < N DO A[i] := nil; INC(i) END;
	heapAdr := S.VAL(LONGINT, heap);
	heapAdr := heapAdr + (-heapAdr) MOD B;
	a := heapAdr + B - 4;
	size := S.VAL(LONGINT, heap) + BootHeapSize - a;
	DEC(size, size MOD B);
	rest := S.VAL(FreeBlockPtr, a);
	rest^.tag := S.VAL(Tag, S.ADR(rest^.size));
	rest^.size := size - 4;
	rest^.next := nil;
	A[N] := a
END Init;

PROCEDURE Out (VAR bootName: ARRAY OF CHAR);
	TYPE ArrPtr = POINTER TO RECORD a, b, c, len: LONGINT END;
	VAR f: Files.File; R: Files.Rider; end, from, to, relocSize, i: LONGINT;
		m: Module; p: ArrPtr;
BEGIN
	IF modTag = 0 THEN res := moduleNotFound;
		Error("Kernel not loaded", ""); RETURN
	END;

	(* cut heap *)
	end := S.VAL(LONGINT, NewBlock(B*N));
	IF res # done THEN RETURN END;

	m := S.VAL(Module, modules);
	WHILE m # NIL DO
		IF ArrPtrAdj # 0 THEN
			DEC(S.VAL(ADDRESS, m.entries), ArrPtrAdj);
			DEC(S.VAL(ADDRESS, m.cmds), ArrPtrAdj);
			DEC(S.VAL(ADDRESS, m.ptrTab), ArrPtrAdj);
			DEC(S.VAL(ADDRESS, m.tdescs), ArrPtrAdj);
			DEC(S.VAL(ADDRESS, m.imports), ArrPtrAdj);
			DEC(S.VAL(ADDRESS, m.data), ArrPtrAdj);
			DEC(S.VAL(ADDRESS, m.code), ArrPtrAdj);
			DEC(S.VAL(ADDRESS, m.refs), ArrPtrAdj)
		END;
		m := m.next
	END;

	(* output heap *)
	(* BootLinker runs on Ceres:
	f := Files.New(bootName);
	*)
	(* BootLinker runs on Windows: *)
	f := Files.New(bootName);
	
	Files.Set(R, f, 0);
	Files.WriteLInt(R, heapAdr); Files.WriteLInt(R, end - heapAdr);
	from := heapAdr + B - 4;
	Files.WriteLInt(R, from); Files.WriteLInt(R, end - from);
	WHILE from < end DO S.GET(from, i); Files.WriteLInt(R, i); INC(from, 4) END;
	Files.WriteLInt(R, kernelBody); Files.WriteLInt(R, 0);

	(* output relocate information *)
	relocSize := Files.Pos(R);
	Files.WriteNum(R, ptrFixx); i := 0;
	WHILE i < ptrFixx DO Files.WriteNum(R, ptrFix[i] - heapAdr);
		INC(i);
	END;
	Files.WriteLInt(R, dlsymAdr - heapAdr);
	relocSize := Files.Pos(R) - relocSize;
	Files.Register(f);
	Str("heap: "); Int(end - heapAdr);
	Str("  reloc: "); Int(relocSize);
	Str("  file: "); Int(Files.Length(f))
END Out;

PROCEDURE GetArgs (VAR S: Texts.Scanner);
	VAR text: Texts.Text; beg, end, time: LONGINT;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
	IF (S.line # 0) OR (S.class # Texts.Name) & (S.class # Texts.Int) THEN
		Oberon.GetSelection(text, beg, end, time);
		IF time>=0 THEN Texts.OpenScanner(S, text, beg); Texts.Scan(S) END
	END
END GetArgs;

PROCEDURE Link*;
	VAR bootName: Name; Sc: Texts.Scanner; VAR m: Module;
BEGIN
	GetArgs(Sc);
	IF Sc.class = Texts.Name THEN COPY(Sc.s, bootName); Texts.Scan(Sc) ELSE RETURN END;
	IF (Sc.class = Texts.Char) & (Sc.c = ":") THEN Texts.Scan(Sc) ELSE RETURN END;
	IF (Sc.class = Texts.Char) & (Sc.c = "=") THEN Texts.Scan(Sc) ELSE RETURN END;
	IF Sc.class = Texts.Name THEN Init;
		Str("linking "); Str(bootName); Ln;
		res := done;
		REPEAT Load(Sc.s, m); Texts.Scan(Sc) UNTIL (Sc.class # Texts.Name) OR (res # done);
		IF res = done THEN Out(bootName) END;
		Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
	END
END Link;

BEGIN
	NEW(exp); S.GET(S.VAL(LONGINT, exp)-4, expTag);
	Texts.OpenWriter(W); S.NEW(heap, BootHeapSize);
	Str("Oberon for Windows boot linker ("); Str(Version); Str(") "); Ln
END JuiceBootLinker.



BootLinker.Link  bootFileName := modName0 modName1 ... ~

	All module names must be listed and topologically sorted.

Boot File Format:

	heapAdr4
	heapSize4
	{adr4 len4 {byte1}}		(* len4 times byte1 *)
	entryAdr4 0X 0X 0X 0X
	nofPtr {adr}				(* nofPtr times adr *)
	dlsymAdr


	All numbers in the relocate information part are in compact format and relative to
	heapAdr.
