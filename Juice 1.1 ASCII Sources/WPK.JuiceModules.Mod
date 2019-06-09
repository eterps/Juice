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

MODULE JuiceModules;	(* Oberon for Windows Module Loader; RC/MH 10.12.93 / 3.2.94 / 25.5.94 / tk 4.1.96*)

(**
 The Modules module implements the dynamic module loader of the Oberon system. It is responsible for loading and freeing modules.
*)

IMPORT Kernel:= JuiceKernel, Files := JuiceFiles, NPAPI, S := SYSTEM;

CONST
	DefMaxImport=64; DefMaxStruct=32; DefMaxReimp=32;
	ModNameLen* = 32;
	B = 32;

TYPE
	Command* = PROCEDURE;
	CommandName = ARRAY 32 OF CHAR;
	Cmd* = RECORD
		name*: CommandName;	(** Name of the command *)
		adr*: LONGINT;	(** Starting position of command code *)
	END;
	
	ExportPtr* = POINTER TO ExportDesc;
	ExportDesc* = RECORD
		fp*: LONGINT; adr*: LONGINT;
		nofExp*: INTEGER; 
		dsc*: POINTER TO ARRAY OF ExportDesc
	END;
	
	ADDRESS = LONGINT;
	
	ArrayPtr* = POINTER TO ARRAY OF LONGINT;

	TerminationHandler* = Kernel.Handler;
	Module* = POINTER TO ModDesc;
	ModuleName* = ARRAY ModNameLen OF CHAR;
	ModDesc* = RECORD
		link*: Module;
		name*: ModuleName;
		init*: BOOLEAN;
		refcnt*, sb*: LONGINT;
		dataSize*, conSize*, codeSize*, refSize*: LONGINT;
		nofEntries*, nofCmds*, nofImps*, nofTds*, nofPtrs*: LONGINT;
		entries*: POINTER TO ARRAY OF ADDRESS;
		cmds*: POINTER TO ARRAY OF Cmd;
		ptrTab*: POINTER TO ARRAY OF ADDRESS;
		tdescs*: POINTER TO ARRAY OF (* Tag *) ADDRESS;
		imports*: POINTER TO ARRAY OF (* Module *) ADDRESS;
		data*, code*: POINTER TO ARRAY OF CHAR;
		refs*: POINTER TO ARRAY OF CHAR;
		publics*, privates*: LONGINT;
		nofimp*: INTEGER; import*: ArrayPtr;
		nofstrc*: INTEGER; struct*: ArrayPtr;
		nofreimp*: INTEGER; reimp*: ArrayPtr;
		export*: ExportDesc;
		term*: TerminationHandler;
		syms*: POINTER TO ARRAY OF CHAR;
	END;

	(* asyncronous module loading *)

	(* module notification after loading *)
	NotifierProc* = PROCEDURE (M: Module; data: PTR);
	NotifierList = POINTER TO NotifierListDesc;
	NotifierListDesc = RECORD
		proc: NotifierProc;
		data: PTR;
		link: NotifierList
	END;
	
	(* list of imported requests *)
	ImportList = POINTER TO ImportDesc;
	ImportDesc = RECORD
		name: ARRAY 32 OF CHAR;
		link: ImportList
	END;
		
	(* request of modules to be loaded *)
	Request = POINTER TO RequestDesc;
	RequestDesc = RECORD
		name: ARRAY 32 OF CHAR;
		F: Files.File; R: Files.Rider;
		receiving: BOOLEAN;
		res: NPAPI.NPError;
		imports: ImportList;
		notify: NotifierList;
		link: Request;
	END;



VAR
	res*: INTEGER;	(** Error code for ThisMod and ThisCommand. res = 0 indicates succes. *)
	resMsgLen*: INTEGER; resMsg*: ARRAY 256 OF CHAR;	(** Explanation of res. *)
	modList*: Module;
	
	(** The res codes are listed in the table below.
		done = 0;
		fileNotFound = 1
		invalidObjFile = 2
		corruptedObjFile = 4
		cmdNotFound = 5
		moduleNotFound = 6
		notEnoughSpace = 7
		refCntNotZero = 8
		cyclicImport = 9
		incompImport = 16
	*)
	
	KernelRoutines: ARRAY 3 OF ADDRESS;

	requestList: Request;

CONST
	done = 0;
	fileNotFound = 1;
	invalidObjFile = 2;
	corruptedObjFile = 4;
	cmdNotFound = 5;
	moduleNotFound = 6;
	notEnoughSpace = 7;
	refCntNotZero = 8;
	cyclicImport = 9;


VAR
	mod: LONGINT;
	LocalAlloc: PROCEDURE (type, size: LONGINT): LONGINT;
	LocalFree: PROCEDURE (h: LONGINT): LONGINT;
	LocalLock: PROCEDURE (h: LONGINT): LONGINT;
	LocalUnlock: PROCEDURE (h: LONGINT);
	LocalReAlloc: PROCEDURE (h: LONGINT; size, type: LONGINT): LONGINT;
	LocalHandle: PROCEDURE (adr: LONGINT): LONGINT;
	LocalSize: PROCEDURE (h: LONGINT): LONGINT;
	extended*: RECORD
		Load*: PROCEDURE(VAR R: Files.Rider; M: Module);
		Unlink*: PROCEDURE(mod: Module; all: BOOLEAN)
	END;
	nofBlocks: INTEGER; blocks: ARRAY 1024 OF LONGINT;

(* Error Messages *)

PROCEDURE Str(s: ARRAY OF CHAR);
	VAR i: INTEGER;
BEGIN	i:=0; REPEAT resMsg[resMsgLen]:=s[i]; INC(i); INC(resMsgLen) UNTIL s[i-1]=0X; DEC(resMsgLen);
END Str;

PROCEDURE Clear;
BEGIN	resMsg[0]:=0X; resMsgLen:=0; res := done
END Clear;


PROCEDURE ErrMsg(n: INTEGER; name: ARRAY OF CHAR);
BEGIN IF res # 0 THEN RETURN END;
	res := n;
	IF res # 0 THEN
		Str(name);
		IF (res = fileNotFound) OR (res = moduleNotFound) THEN Str(" not found")
		ELSIF res = invalidObjFile THEN Str(" not an obj-file")
		ELSIF res = corruptedObjFile THEN Str(" corrupted obj file")
		ELSIF res = notEnoughSpace THEN Str(" not enough space")
		ELSIF res = refCntNotZero THEN Str(" reference count not zero")
		ELSIF res = cyclicImport THEN Str(" cyclic import")
		ELSIF res = cmdNotFound THEN Str(" not found")  (* assumes importing = procedure name *)
		ELSE Str(" unknown error code")
		END
	END
END ErrMsg;

PROCEDURE Find (VAR modname: ARRAY OF CHAR; VAR m: Module);
BEGIN
	m := modList;
	WHILE m # NIL DO
		IF m.name = modname THEN RETURN END;
		m := m.link;
	END;
END Find;

(* ---- auxiliaries ---- *)

PROCEDURE ReadString(VAR R: Files.Rider; VAR string: ARRAY OF CHAR);
	VAR i: INTEGER; ch: CHAR;
BEGIN i := 0;
	LOOP Files.ReadChar(R, ch);
		IF ch = 0X THEN string[i] := 0X; RETURN
		ELSIF ch > 7FX THEN string[i] := CHR(ORD(ch)-80H); string[i+1] := 0X; RETURN
		ELSE string[i] := ch; INC(i) END
	END
END ReadString;

(* ---- code/data allocation ----- *)

PROCEDURE AllocBlock(VAR adr: LONGINT; size: LONGINT);
	CONST LMEMFIXED = 0000H; LMEMZEROINIT = 0040H;
	VAR h: LONGINT; i: INTEGER;
BEGIN
	IF size > 0 THEN h := LocalAlloc(LMEMFIXED, size) ELSE h := LocalAlloc(LMEMFIXED + LMEMZEROINIT, -size) END;
	IF h # 0 THEN adr := LocalLock(h) ELSE adr := 0 END;
	i := 0;
	WHILE (i < nofBlocks) & (blocks[i] # 0) DO INC(i) END;
	blocks[i] := adr;
	IF i >= nofBlocks THEN INC(nofBlocks) END;
END AllocBlock;

PROCEDURE AdjustBlock(adr, newSize: LONGINT);
	VAR h, h1: LONGINT;
BEGIN
	IF (adr # 0) & (newSize # 0) THEN
		h := LocalHandle(adr);
		IF h # 0 THEN h1 := LocalReAlloc(h, newSize, 0) END
	END
END AdjustBlock;

PROCEDURE DisposeAll;
	VAR h, h1: LONGINT; i: INTEGER;
BEGIN
	i := 0; WHILE i < nofBlocks DO
		IF blocks[i] # 0 THEN 
			h := LocalHandle(blocks[i]);
			IF h # 0 THEN LocalUnlock(h); h1 := LocalFree(h) END
		END;
		INC(i)
	END
END DisposeAll;

(*
PROCEDURE GetBlockSize(adr: LONGINT): LONGINT;
	VAR h: LONGINT;
BEGIN
	IF adr # 0 THEN
		h := LocalHandle(adr);
		IF h # 0 THEN RETURN LocalSize(h) END
	END;
	RETURN 0;
END GetBlockSize;
*)
PROCEDURE AllocCodeBlock*(VAR p: LONGINT; blocksize: LONGINT);
	VAR size, adr: LONGINT; 
BEGIN
	size := S.VAL(LONGINT, S.VAL(SET, blocksize + 4 + 12 + (28 + B-1))-S.VAL(SET, B-1))+B;
	AllocBlock(adr, -size);
	INC(adr, (-adr) MOD B);
	ASSERT(adr MOD B=0);
	S.PUT(adr, adr+4);
	S.PUT(adr+4, size-4);
	S.PUT(adr+24, adr+4);
	p := adr + 28;
	S.PUT(p+12, blocksize)
END AllocCodeBlock;

PROCEDURE ShrinkCodeBlock* (p, blocksize: LONGINT);
	VAR size: LONGINT;
BEGIN
	size := S.VAL(LONGINT, S.VAL(SET, blocksize + 4 + 12 + (28 + B-1))-S.VAL(SET, B-1));
	AdjustBlock(p-28, size);
	S.PUT(p+12, blocksize)
END ShrinkCodeBlock;


(*---- module loading ---- *)

PROCEDURE ^ ThisMod* (name: ARRAY OF CHAR): Module;

PROCEDURE Load (name: ARRAY OF CHAR; VAR f: Files.File): Module;
	VAR R: Files.Rider; i: INTEGER; fname: ARRAY 64 OF CHAR; tag: CHAR; m: Module;
BEGIN 
	COPY(name, fname); i := 0;
	WHILE fname[i] # 0X DO INC(i) END;
	fname[i] := "."; fname[i+1] := "O"; fname[i+2] := "b"; fname[i+3] := "j"; fname[i+4] := 0X;
	IF f = NIL THEN f := Files.Old(fname);
		IF f = NIL THEN
			ErrMsg(fileNotFound, name);
			RETURN NIL;
		END;
	END;
	Files.Set(R, f, 0); 
	Files.ReadChar(R, tag);
	IF tag = 0BBX THEN
		IF Kernel.LargestAvailable() < SIZE(ModDesc) THEN
			ErrMsg(notEnoughSpace, name); RETURN NIL
		END;
		NEW(m); NEW(m.import, DefMaxImport); NEW(m.struct, DefMaxStruct); 
		NEW(m.reimp, DefMaxReimp); m.nofImps := -1;
		COPY(name, m.name);
		Files.ReadChar(R, tag);
		IF tag = 055X THEN 
		ELSIF (tag = 088X) & (extended.Load # NIL) THEN extended.Load(R, m)
		ELSE ErrMsg(invalidObjFile, name);
		END
	ELSE ErrMsg(invalidObjFile, name);
	END;
	RETURN m;
END Load;

(** Returns a handle to an already loaded module, or loads a module and all its imported modules. *)
PROCEDURE ThisMod* (name: ARRAY OF CHAR): Module;
	VAR mod: Module; r: Request; F: Files.File;
BEGIN Find(name, mod); Clear;
	IF mod = NIL THEN
		r := requestList;
		WHILE (r # NIL) & ((name # r.name) OR (r.imports # NIL) OR r.receiving OR (r.res # 0)) DO r := r.link END;
		IF r = NIL THEN F := NIL
		ELSE F := r.F;
		END;
		RETURN Load(name, F); 
	ELSE RETURN mod
	END
END ThisMod;

	PROCEDURE ^ RequestMod (name, from: ARRAY OF CHAR; proc: NotifierProc; data: PTR);

	PROCEDURE Write(VAR buf: NPAPI.NPBuffer; len: LONGINT; data: PTR);
		VAR k: LONGINT;
	BEGIN
		WITH data: Request DO
			FOR k:= 0 TO len-1 DO Files.WriteChar(data.R, buf[k]); END
		END
	END Write;

	(* a module must only be loaded after all imported requests are handled *)
	PROCEDURE AddImport(mod, imp: ARRAY OF CHAR);
		VAR r: Request; i: ImportList;
	BEGIN
		r := requestList;
		WHILE (r # NIL) & (r.name # mod) DO r := r.link END;
		IF r # NIL THEN
			i := r.imports;
			WHILE (i # NIL) & (i.name # imp) DO i := i.link END;
			IF i = NIL THEN 
				NEW(i); COPY(imp, i.name);
				i.link := r.imports; r.imports := i
			END
		END
	END AddImport;

	PROCEDURE RemoveImport(imp: ARRAY OF CHAR; reason: NPAPI.NPError);
		VAR r, prevr: Request; i, previ: ImportList; n: NotifierList; m: Module;
	BEGIN
		r := requestList; 
		WHILE r # NIL DO
			IF r.name = imp THEN r.receiving := FALSE; 
				IF reason # 0 THEN r.res := reason END
			END;
			i := r.imports; previ := NIL;
			WHILE i # NIL DO
				IF i.name = imp THEN
					IF previ = NIL THEN r.imports := i.link ELSE previ.link := i.link END;
					IF reason # 0 THEN r.res := reason END;
				END;
				previ := i; i := i.link
			END;
			r := r.link
		END;
		r := requestList; prevr := NIL;
		WHILE r # NIL DO
			IF ~(r.receiving) & (r.imports = NIL) THEN (* no modules outstanding *)
			m := ThisMod(r.name);
			IF m = NIL THEN Files.Close(r.F) END;
			
			IF prevr = NIL THEN requestList := r.link ELSE prevr.link := r.link END;
			
			n := r.notify;
			WHILE n # NIL DO n.proc(m, n.data); n := n.link END;
			END;
			prevr := r; r := r.link
		END
	END RemoveImport;

	PROCEDURE Destroy(reason: NPAPI.NPError; data: PTR);
		VAR ch0, ch1: CHAR; size: LONGINT; name: ARRAY 32 OF CHAR; R, R1: Files.Rider;
	BEGIN
		WITH data: Request DO
			IF reason = 0 THEN
				Files.Set(R, data.F, 0);				
				Files.ReadChar(R, ch0); Files.ReadChar(R, ch1);
				
				IF (ch0 = 0BBX) & (ch1 = 088X) THEN 
					Files.ReadNum(R, size); R1:=R; Files.Set(R1, data.F, Files.Pos(R1)+size);  
					ReadString(R, name);
					WHILE name#"" DO 
						RequestMod(name, data.name, NIL, NIL);
						ReadString(R, name);
					END;
					Files.ReadNum(R1, size); Files.ReadNum(R1, size); Files.ReadNum(R1, size); 
					ReadString(R1, name);
					WHILE name#"" DO 
						RequestMod(name, data.name, NIL, NIL); 
						ReadString(R1, name);
					END
				ELSE (* not an object file *)
					reason := 1
				END
			END;
			
			RemoveImport(data.name, reason);
		END
	END Destroy;

	PROCEDURE RequestMod (name, from: ARRAY OF CHAR; proc: NotifierProc; data: PTR);
		VAR fname: ARRAY 64 OF CHAR; mod: Module; i: INTEGER; r: Request; n: NotifierList;
	BEGIN
		mod := ThisMod(name);
		IF mod = NIL THEN
			COPY(name, fname); i:=0;
			WHILE fname[i]#0X DO INC(i) END;
			fname[i]:="."; fname[i+1]:="O"; fname[i+2]:="b"; fname[i+3]:="j"; fname[i+4]:=0X;

			r := requestList;
			WHILE (r # NIL) & (r.name # name) DO r := r.link END;
			IF r = NIL THEN
				NEW(r); COPY(name, r.name); r.F := Files.New(""); Files.Set(r.R, r.F, 0);
				r.link := requestList; requestList := r; r.receiving := TRUE;
				NPAPI.GetLocalFile(fname, Write, Destroy, r)
			END;
			IF from # "" THEN AddImport(from, name) END;
			IF proc # NIL THEN 
				NEW(n); n.link := r.notify; r.notify := n;
				n.proc := proc; n.data := data;
			END;
		ELSE 
			IF proc # NIL THEN proc(mod, data) END
		END;
	END RequestMod;

	PROCEDURE LoadMod* (name: ARRAY OF CHAR; proc: NotifierProc; data: PTR);
	BEGIN
		RequestMod(name, "", proc, data)
	END LoadMod;


(** Returns a procedure variable representing an exported command in a module. Calling this procedure, executes the command. *)
PROCEDURE ThisCommand* (mod: Module; name: ARRAY OF CHAR): Command;
	VAR i: LONGINT;
BEGIN
	i := mod.nofCmds;
	WHILE i > 0 DO DEC(i);
		IF mod.cmds[i].name = name THEN
			Clear;
			RETURN S.VAL(Command, mod.cmds[i].adr)
		END
	END;
	ErrMsg(cmdNotFound, name); RETURN NIL
END ThisCommand;

PROCEDURE Delete (m: Module);
	VAR m1: Module;
BEGIN
	m1 := modList;
	IF m = m1 THEN modList := m.link;
	ELSE
		WHILE m1.link # m DO m1 := m1.link END;
		m1.link := m.link;
	END
END Delete;

(** Free a module from memory. Only modules with no clients can be freed. The all flag requests that all imported modules should be freed too (i.e. a recursive call to Free). *)
PROCEDURE Free* (name: ARRAY OF CHAR; all: BOOLEAN);
	VAR m, m1: Module; i: LONGINT; h: TerminationHandler;
BEGIN Clear;
	Find(name, m);
	IF m = NIL THEN ErrMsg(moduleNotFound, name)
	ELSIF m.refcnt # 0 THEN ErrMsg(refCntNotZero, m.name)
	ELSE
		IF m.term # NIL THEN h := m.term; m.term := NIL; h END;
		i := m.nofImps;
		IF i > 0 THEN
			WHILE i > 0 DO DEC(i); m1 := S.VAL(Module, m.imports[i]); DEC(m1.refcnt) END;
			IF all THEN i := m.nofImps;
				WHILE i > 0 DO DEC(i); m1 := S.VAL(Module, m.imports[i]); Free(m1.name, TRUE) END;
				Clear;
			END
		ELSIF (i < 0) & (extended.Unlink # NIL) THEN extended.Unlink(m, all)
		END;
		Delete(m)
	END
END Free;

PROCEDURE MarkModules;
	VAR m: Module; ptradr, i, p: LONGINT; ptr: Kernel.BlockPtr;
BEGIN
	m := modList;	(* ModuleDesc and ModuleBlock are marked via Kernel.modules *)
	WHILE m # NIL DO
		i := m.nofPtrs; ptradr := S.ADR(m.ptrTab^);
		WHILE i > 0 DO
			S.GET(ptradr, p); S.GET(p, ptr);
			IF ptr # NIL THEN Kernel.Mark(ptr) END;
			DEC(i); INC(ptradr, 4);
		END;
		i := m.nofTds; ptradr := S.ADR(m.tdescs^);
		WHILE i > 0 DO
			S.GET(ptradr, ptr);
			IF ptr # NIL THEN Kernel.Mark(ptr) END; (* tk *)
			DEC(i); INC(ptradr, 4);
		END;
		IF m.privates # 0 THEN Kernel.Mark(S.VAL(Kernel.BlockPtr, m.privates)) END;
		IF m.publics # 0 THEN Kernel.Mark(S.VAL(Kernel.BlockPtr, m.publics)) END;
		IF m.import # NIL THEN Kernel.Mark(S.VAL(Kernel.BlockPtr, m.import)) END;
		IF m.struct # NIL THEN Kernel.Mark(S.VAL(Kernel.BlockPtr, m.struct)) END;
		IF m.reimp # NIL THEN Kernel.Mark(S.VAL(Kernel.BlockPtr, m.reimp)) END;
		m := m^.link;
	END;
END MarkModules;

PROCEDURE FinalizeModules;
	VAR m: Module; h: TerminationHandler;
BEGIN
	m := modList;
	WHILE m # NIL DO
		IF m.term # NIL THEN h := m.term; m.term := NIL; h END;
		m := m.link;
	END
END FinalizeModules;

PROCEDURE GetCodeSize(VAR code, data: LONGINT);
	VAR m: Module;
BEGIN
	code := 0; data := 0;
	m := modList;
	WHILE m # NIL DO
		code := code + LEN(m.code^);
		IF m.data # NIL THEN data := data + LEN(m.data^) END;
		m := m.link
	END
END GetCodeSize;

PROCEDURE Init;
	VAR 
		newRec: PROCEDURE(tag: Kernel.Tag; VAR p: ADDRESS);
		newSys: PROCEDURE(size: LONGINT; VAR p: ADDRESS);
		newArr: PROCEDURE(nofdim, nofelem: LONGINT; eltag: Kernel.Tag; VAR p: ADDRESS);
		m: Module;
BEGIN
	mod := Kernel.LoadLibrary("Kernel32");
	Kernel.GetAdr(mod, "LocalAlloc", S.VAL(LONGINT, LocalAlloc));
	Kernel.GetAdr(mod, "LocalFree", S.VAL(LONGINT, LocalFree));
	Kernel.GetAdr(mod, "LocalLock", S.VAL(LONGINT, LocalLock));
	Kernel.GetAdr(mod, "LocalUnlock", S.VAL(LONGINT, LocalUnlock));
	Kernel.GetAdr(mod, "LocalReAlloc", S.VAL(LONGINT, LocalReAlloc));
	Kernel.GetAdr(mod, "LocalHandle", S.VAL(LONGINT, LocalHandle));
	Kernel.GetAdr(mod, "LocalSize", S.VAL(LONGINT, LocalSize));
	newRec := Kernel.NewRec; 
	newSys := Kernel.NewSys;
	newArr := Kernel.NewArr;
	KernelRoutines[0] := S.VAL(ADDRESS, newRec);
	KernelRoutines[1] := S.VAL(ADDRESS, newSys);
	KernelRoutines[2] := S.VAL(ADDRESS, newArr);
	(* init loop only if Modules is last module in boot file: *)
	modList := S.VAL(Module, Kernel.modules);
	Kernel.getCodeSize := GetCodeSize;
	Kernel.InstallQ(Kernel.mkQ, MarkModules);
	Kernel.InstallQ(Kernel.quitQ, FinalizeModules);
	Kernel.InstallQ(Kernel.quitQ, DisposeAll);
	m := ThisMod("Interchange");
END Init;

BEGIN
	Init;
END JuiceModules.

(** Remarks:

1. Oberon uses reference counting to determine how many clients of a module are loaded. A module can only be freed when the reference count is 0.

2. The res codes are not the same numerically on all Oberon platforms. It is advisable to use the resMsg as a correct indication of the error condition.

3. Module and command names are single words consisting of A to Z, a to z, and 0 to 9. Names must not start with a digit.

4. Care should be taken freeing modules. Oberon cannot detect if a client has a procedure variable still "pointing" at code in a freed module. Calling such a procedure can be unpredictable at times, although the system generates a trap most of the time.
*)
