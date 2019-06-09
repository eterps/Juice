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

MODULE JuiceKernel;	(* RC 23.7.92 / MH 3.2.1994 / 5.5.94 / tk 4.1.96 *)

(**
 Module Kernel is responsible for memory allocation, garbage collection, object finalization, module termination, interfacing to the underlying operating system, and clock functions. Using features exported from module Kernel may result in an unportable module, as not all Oberon Kernels are the same. This module is of little importance to most Oberon programmers.
*)

(* WARNING: do not use NEW nor SYSTEM.NEW in this module !! use NewRec, NewArr or NewSys instead *)
(* Finalization due to J. Templ *)
(* in blue: changes for non-contiguous heap allocation, jm *)

(*
	tk 21.8.95 - Fixed GC during type descriptor allocation.
*)

IMPORT S := SYSTEM;

CONST
	MarkBit* = 0;

TYPE
	Name = ARRAY 32 OF CHAR;
	Tag* = POINTER TO TypeDesc;
	ADDRESS = LONGINT;

	Handler* = PROCEDURE;

	Queue* = POINTER TO QElem;
	QElem = RECORD 
		link: Queue;
		handle: Handler
	END;
	
VAR
	(* the first variable is initialized by the boot loader in Windows *)
	(* AAgetadr must be first alphabetically listed variable *)
	AAgetadr-: PROCEDURE (adr: ADDRESS; symbol: ADDRESS; handle: LONGINT);
	modules*: LONGINT;	(** Anchor of all modules loaded in system *)
	heapAdr-, heapSize-: LONGINT;	(** Starting address and size of the Oberon heap *)
	GCenabled*: LONGINT;
	stackBottom*: LONGINT;	(** Stack pointer is reset to this value during a trap *)
													(* pointer to dynamic link of Oberon.Loop *)
	EventLoop*: PROCEDURE ;	(** Control returns here after a trap *)

	exit: PROCEDURE (code: LONGINT);
	loadLibrary: PROCEDURE (name: LONGINT): LONGINT;
	freeLibrary: PROCEDURE(lib: LONGINT);
	GetLocalTime: PROCEDURE (systime: LONGINT);
	SetLocalTime: PROCEDURE (systime: LONGINT);
	
	mod: LONGINT;
	initialised: BOOLEAN;
	
TYPE
	TypeDesc = RECORD
		size: LONGINT;
		ptroff: LONGINT
	END;

	FreeBlockPtr = POINTER TO FreeBlock;
	FreeBlock = RECORD
		(* off-4 *) tag: Tag;
		(* off0 *) size: LONGINT;	(* field size aligned to 8-byte boundary, size MOD B = B-4 *)
		(* off4 *) next: ADDRESS;
	END;

	BlockPtr* = POINTER TO Block;
	Block = RECORD
		lastElemToMark, currElem, firstElem: BlockPtr;
	END;

	Blockm4Ptr = POINTER TO Blockm4;
	Blockm4 = RECORD
		tag: Tag;
		lastElemToMark, currElem, firstElem: LONGINT;
	END;

	InitPtr = POINTER TO RECORD tag: Tag; z0, z1, z2, z3, z4, z5, z6, z7: LONGINT END;

	Cmd = RECORD name: Name; adr: LONGINT END;
	Module = POINTER TO RECORD 
		link: Module; 
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
		data, code: POINTER TO ARRAY OF CHAR
	END;

	PtrElemDesc = RECORD a: S.PTR END;	(* has same type descriptor as element of ARRAY OF POINTER *)

	Finalizer* = PROCEDURE (obj: PTR);
	FinObj = POINTER TO FinObjNode;
	FinObjNode = RECORD
		next: FinObj;
		obj: LONGINT;
		marked: BOOLEAN;
		fin: Finalizer;
	END;

CONST
	B = 32;	(* must be a mutiple of 32 *)
	N = 9;
	nil = 0;
	SubObjBit = 3;
	mark = {MarkBit}; array = {1}; subobj = {SubObjBit};
	
VAR
	TrapHandlingLevel*: LONGINT;
	firstBlock-, endBlock-: (*FreeBlockPtr*) ADDRESS;	(* free blocks must be collected !! *)
	A: ARRAY N+1 OF (*FreeBlockPtr*) ADDRESS;
	PointerTD, queueTD: LONGINT;
	firstTry: BOOLEAN;
	candidates: ARRAY 1024 OF LONGINT;
	nofcand: INTEGER;
	FinObjs: FinObj;
	getCodeSize*: PROCEDURE (VAR code, data: LONGINT);
	mkQ*, quitQ*: Queue;

CONST
	Debug = TRUE;
	MEMCOMMIT = 1000H; PAGEEXECUTEREADWRITE = 40H; MEMDECOMMIT = 4000H;
	SuperBlockSize = 256 * 1024;
	ReserveBlockSize = 128*1024;	(* 128k *)

TYPE
	SuperBlockPtr = POINTER TO SuperBlock;
	SuperBlock = RECORD
		next: ADDRESS;
		size: LONGINT;
		firstblock: ADDRESS;
		endblock: ADDRESS;
	END;
	
VAR
	VirtualAlloc: PROCEDURE (lpvAddress, cbSize, fdwAllocationType, fdwProtect: LONGINT): LONGINT;	
	VirtualFree: PROCEDURE (lpvAddress, cbSize, fdwFreeType: LONGINT): LONGINT;
	OutputDebugString: PROCEDURE (s: LONGINT);

	superblocks*: ADDRESS;	(* list of all super blocks *)
	oberonsuperblock*: SuperBlock;	(* the Oberon super block *)
	supermin*, supermax*, reserve*: ADDRESS;	(* boundaries between which all pointers should lie *)
	
	nofBlocks: INTEGER; blocks: ARRAY 1024 OF RECORD adr, size: LONGINT END;

PROCEDURE AllocBlock(size: LONGINT): LONGINT;
	VAR adr: LONGINT; i: INTEGER;
BEGIN
	adr := VirtualAlloc(0, size, MEMCOMMIT, PAGEEXECUTEREADWRITE);
	i := 0;
	WHILE (i < nofBlocks) & (blocks[i].adr # 0) DO INC(i) END;
	blocks[i].adr := adr; blocks[i].size := size;
	IF i >= nofBlocks THEN INC(nofBlocks) END;
	RETURN adr
END AllocBlock;

PROCEDURE DeAllocBlock(adr, size: LONGINT): LONGINT;
	VAR i: INTEGER;
BEGIN
	i := 0; WHILE (i < nofBlocks) & (blocks[i].adr # adr) DO INC(i) END;
	IF i < nofBlocks THEN blocks[i].adr := 0 END;
	RETURN VirtualFree(adr, size, MEMDECOMMIT);
END DeAllocBlock;

PROCEDURE DisposeAll;
	VAR i: INTEGER; res: LONGINT;
BEGIN
	i := 0; WHILE i < nofBlocks DO
		IF blocks[i].adr # 0 THEN res := VirtualFree(blocks[i].adr, blocks[i].size, MEMDECOMMIT) END;
		INC(i)
	END
END DisposeAll;

PROCEDURE IntToStr*(i: LONGINT; VAR s: ARRAY OF CHAR);
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

PROCEDURE Str*(s: ARRAY OF CHAR);
BEGIN
	IF OutputDebugString # NIL THEN
		OutputDebugString(S.ADR(s))
	END
END Str;

PROCEDURE Ln*;
VAR s: ARRAY 4 OF CHAR;
BEGIN
	IF OutputDebugString # NIL THEN
		s[0] := 0DX; s[1] := 0AX; s[2] := 0X;
		OutputDebugString(S.ADR(s))
	END
END Ln;

PROCEDURE Int*(x: LONGINT);
VAR s: ARRAY 32 OF CHAR;
BEGIN
	IF OutputDebugString # NIL THEN
		IntToStr(x, s); OutputDebugString(S.ADR(s))
	END
END Int;

(* --- handler queues --- *)

PROCEDURE ^ NewRec* (tag: Tag; VAR p: ADDRESS);
(** Init a new handler queue *)
PROCEDURE InitQ*(VAR q: Queue);
	VAR l: LONGINT;
BEGIN	NewRec(S.VAL(Tag, queueTD), l); q:=S.VAL(Queue, l); q.link:=q
END InitQ;

(** Install a queue-handler *)
PROCEDURE InstallQ*(q: Queue; p: Handler);
	VAR el: Queue; l: LONGINT;
BEGIN	NewRec(S.VAL(Tag, queueTD), l); el:=S.VAL(Queue, l); el.handle:=p; el.link:=q.link; q.link:=el
END InstallQ;

(** Call all handlers installed in a queue *)
PROCEDURE HandleQ*(q: Queue);
	VAR el: Queue;
BEGIN	el:=q.link;	WHILE	el#q	DO	el.handle; el:=el.link	END
END HandleQ;

(** Register an object for finalization. *)
PROCEDURE RegisterObject* (obj: PTR; fin: Finalizer);
	VAR n: FinObj;
	PROCEDURE new (VAR o: S.PTR);
	BEGIN NewRec(S.VAL(Tag, o), S.VAL(LONGINT, o));
	END new;
BEGIN
	new(n); n.next := FinObjs; n.obj := S.VAL(LONGINT, obj); n.marked := FALSE; n.fin := fin;
	FinObjs := n;
END RegisterObject;

(** Returns the size in bytes of the largest free available memory block. Allocating objects with a size greater than this size will cause the memory allocation to fail. *) 
PROCEDURE LargestAvailable*(): LONGINT;
	VAR i, max: LONGINT; ptr: FreeBlockPtr;
BEGIN
	RETURN MAX(LONGINT);
	i := N; max := 0;
	WHILE (i >= 0) & (max = 0) DO
		ptr := S.VAL(FreeBlockPtr, A[i]);
		WHILE ptr # NIL DO
			IF ptr^.size > max THEN max := ptr^.size END;
			ptr := S.VAL(FreeBlockPtr, ptr^.next)
		END;
		DEC(i)
	END;
	RETURN max
END LargestAvailable;

	(* ------------------------- garbage collector ----------------------- *)

PROCEDURE Mark* (block: BlockPtr);
	TYPE Tag = POINTER TO RECORD (*size,*) ptroff: LONGINT  END;
		(* size skipped, because accessed via tag = actual tag + 4 *)
	VAR father, field, currElem: BlockPtr; offset: LONGINT; tag, downtag, marked: Tag; arraybit: SET;
BEGIN
	S.GET(S.VAL(ADDRESS, block)-4, tag);
	IF ~(SubObjBit IN S.VAL(SET, block)) THEN	(* not a subobject *)
		marked := S.VAL(Tag, S.VAL(SET, tag) + mark);
		IF tag # marked THEN
			S.PUT(S.VAL(ADDRESS, block)-4, marked);
			S.GET(S.VAL(ADDRESS, S.VAL(SET, tag) - array)-4, marked);
			(* unnecessary to mask mark bit *)
			S.GET(S.VAL(ADDRESS, marked)-4, arraybit);
			INCL(arraybit, MarkBit);
			S.PUT(S.VAL(ADDRESS, marked)-4, arraybit);
			arraybit := S.VAL(SET, tag) * array;
			IF arraybit # {} THEN currElem := block^.firstElem;
				tag := S.VAL(Tag, S.VAL(SET, tag) - arraybit)
			ELSE currElem := block
			END;
			father := NIL;
			LOOP
				INC(S.VAL(ADDRESS, tag), 4);
				offset := tag^.ptroff;
				IF offset < 0 THEN
					INC(S.VAL(ADDRESS, tag), offset);
					IF (arraybit # {}) & (currElem # block^.lastElemToMark) THEN
						INC(S.VAL(ADDRESS, currElem), tag^.ptroff)
					ELSE (* up *)
						S.PUT(S.VAL(ADDRESS, block)-4, S.VAL(SET, tag) + arraybit + mark);
						IF father = NIL THEN EXIT END;
						S.GET(S.VAL(ADDRESS, father)-4, tag);
						arraybit := S.VAL(SET, tag) * array;
						tag := S.VAL(Tag, S.VAL(SET, tag) - (array + mark));
						IF arraybit # {} THEN currElem := father^.currElem
						ELSE currElem := father
						END;
						offset (*field address*) := S.VAL(ADDRESS, currElem) + tag^.ptroff;
						S.GET(offset, field);
						S.PUT(offset, block);
						block := father;
						father := field
					END
				ELSE
					offset (*field address*) := S.VAL(ADDRESS, currElem) + offset;
					S.GET(offset, field);
					IF field # NIL THEN
						S.GET(S.VAL(ADDRESS, field)-4, downtag);
						IF subobj * S.VAL(SET, field) = {} THEN	(* not a subobject *)
							marked := S.VAL(Tag, S.VAL(SET, downtag) + mark);
							IF downtag # marked THEN (* down *)
								S.PUT(S.VAL(ADDRESS, field)-4, marked);
								S.PUT(S.VAL(ADDRESS, block)-4, S.VAL(SET, tag) + arraybit + mark);
								IF arraybit # {} THEN block^.currElem:= currElem END;
								S.GET(S.VAL(ADDRESS, S.VAL(SET, downtag) - array)-4, marked);
								(* unnecessary to mask mark bit *)
								S.GET(S.VAL(ADDRESS, marked)-4, arraybit);
								INCL(arraybit, MarkBit);
								S.PUT(S.VAL(ADDRESS, marked)-4, arraybit);
								arraybit := S.VAL(SET, downtag) * array;
								IF arraybit # {} THEN currElem := field^.firstElem ELSE currElem := field END;
								S.PUT(offset, father);
								father := block;
								block := field;
								tag := S.VAL(Tag, S.VAL(SET, downtag) - arraybit)
							END
						ELSE	(* do not mark subobject *)
							S.GET(S.VAL(ADDRESS, S.VAL(SET, downtag) - array)-4, marked);
							EXCL(S.VAL(SET, marked), MarkBit);
							S.GET(S.VAL(ADDRESS, marked)-4, downtag);
							INCL(S.VAL(SET, downtag), MarkBit);
							S.PUT(S.VAL(ADDRESS, marked)-4, downtag)
						END
					END
				END
			END
		END
	ELSE (* do not mark subobject, subobjects are not traced *)
		S.GET(S.VAL(ADDRESS, S.VAL(SET, tag) - array)-4, tag);
		EXCL(S.VAL(SET, tag), MarkBit);
		S.GET(S.VAL(ADDRESS, tag)-4, arraybit);
		INCL(arraybit, MarkBit);
		S.PUT(S.VAL(ADDRESS, tag)-4, arraybit)
	END
END Mark;

PROCEDURE CheckFinObjs;
	VAR n: FinObj; tag: LONGINT;
BEGIN n := FinObjs;
	WHILE n # NIL DO
		S.GET(n.obj - 4, tag);
		IF MarkBit IN S.VAL(SET, tag) THEN n.marked := TRUE
		ELSE n.marked := FALSE;
			(* mark all objects accessible from n.obj to prevent them from being collected *)
			Mark(S.VAL(BlockPtr, n.obj));
		END;
		n := n.next;
	END
END CheckFinObjs;

PROCEDURE Sweep;
	VAR p, end: Blockm4Ptr; lastp: FreeBlockPtr; tag, notmarked, tdesc: Tag; size, lastsize, i: LONGINT;
		lastA: ARRAY N+1 OF ADDRESS;
		thisSuper, lastSuper, nextSuper: SuperBlockPtr; res: LONGINT;
BEGIN
	i := 0;
	WHILE i <= N DO A[i] := nil; lastA[i] := S.ADR(A[i]); INC(i) END;
	
	lastSuper := NIL;
	thisSuper := S.VAL(SuperBlockPtr, superblocks);
	WHILE thisSuper # NIL DO
		p := S.VAL(Blockm4Ptr, thisSuper^.firstblock);
		end := S.VAL(Blockm4Ptr, thisSuper^.endblock);
		Str("  Sweeping SuperBlock at "); Int(S.VAL(LONGINT, p));
		IF S.VAL(LONGINT, thisSuper) = S.ADR(oberonsuperblock) THEN Str(" (oberon)") END;
		Ln;
		nextSuper := S.VAL(SuperBlockPtr, thisSuper^.next);

		lastsize := 0;
		WHILE p # end DO
			tag := p^.tag;
			notmarked := S.VAL(Tag, S.VAL(SET, tag) - mark);
			tdesc := S.VAL(Tag, S.VAL(SET, notmarked) - array);
			IF notmarked # tdesc THEN (* array block *) size := p^.lastElemToMark + tdesc^.size - S.VAL(ADDRESS, p);
			ELSE size := tdesc^.size + 4;
			END;
			size := S.VAL(LONGINT, S.VAL(SET, size + B-1)-S.VAL(SET, B-1));
			IF tag = notmarked THEN (* collect *)
				IF lastsize = 0 THEN lastp := S.VAL(FreeBlockPtr, p) END;
				INC(lastsize, size)
			ELSE
				p^.tag := notmarked;
				IF lastsize > 0 THEN
					lastp^.size := lastsize - 4;
					lastp^.tag := S.VAL(Tag, S.ADR(lastp^.size));
					i := lastsize DIV B;
					IF i > N THEN i := N END;
					lastp^.next := nil;
					S.PUT(lastA[i], lastp);
					lastA[i] := S.ADR(lastp^.next);
					lastsize := 0
				END
			END;
			INC(S.VAL(ADDRESS, p), size)
		END;
	
		(* last collected block: *)
		IF (lastsize = thisSuper.endblock - thisSuper.firstblock) & (S.VAL(LONGINT, thisSuper) # S.ADR(oberonsuperblock)) THEN
			(* whole block is free, unlink it*)
			IF lastSuper = NIL THEN superblocks := S.VAL(LONGINT, nextSuper);
				supermin := S.VAL(LONGINT, nextSuper)
			ELSE lastSuper.next := thisSuper.next
			END;
			
			(* adjust  max pointer *)
			IF nextSuper = NIL THEN	(* hanged out the last block *)
				ASSERT(lastSuper # NIL);
				supermax := lastSuper^.endblock
			END;
			Str("  Deallocate SuperBlock at "); Int(S.VAL(LONGINT, thisSuper^.firstblock));
			
			res := DeAllocBlock(S.VAL(LONGINT, thisSuper), thisSuper.size);
			IF res # 1 THEN Str("  could not deallocate SuperBlock") END;
			Ln;
		ELSIF lastsize > 0 THEN (* last collected block: *) lastSuper := thisSuper;
			lastp^.size := lastsize - 4;
			lastp^.tag := S.VAL(Tag, S.ADR(lastp^.size));
			i := lastsize DIV B;
			IF i > N THEN i := N END;
			lastp^.next := nil;
			S.PUT(lastA[i], lastp);
			lastA[i] := S.ADR(lastp^.next)
		ELSE lastSuper := thisSuper	(* tk *)
		END;
		thisSuper := nextSuper;
	END
END Sweep;

PROCEDURE CheckCandidates;	(* nofcand > 0 *)
	VAR i, j, h, p: LONGINT; block, lastBlock, nextBlock: Blockm4Ptr; tag, notmarked, tdesc: Tag;
	thisSuper: SuperBlockPtr; 
BEGIN
	(* first sort them in increasing order using shellsort *)
	h := 1; REPEAT h := h*3 + 1 UNTIL h > nofcand;
	REPEAT h := h DIV 3; i := h;
		WHILE i < nofcand DO p := candidates[i]; j := i;
			WHILE (j >= h) & (candidates[j-h] > p) DO
				candidates[j] := candidates[j-h]; j := j-h;
			END;
			candidates[j] := p; INC(i)
		END
	UNTIL h = 1;
	
	(* sweep phase *)
	i := 0; p := candidates[i];

	thisSuper := S.VAL(SuperBlockPtr, superblocks);
	LOOP

		IF thisSuper = NIL THEN EXIT END;
		block := S.VAL(Blockm4Ptr, thisSuper^.firstblock);
		lastBlock := S.VAL(Blockm4Ptr, thisSuper^.endblock);
		Str("  candidate sweep SuperBlock at "); Int(S.VAL(LONGINT, block));
		IF S.VAL(LONGINT, thisSuper) = S.ADR(oberonsuperblock) THEN Str(" (oberon)") END;
		Ln;

		(* next block calc *)
		tag := block^.tag;
		notmarked := S.VAL(Tag, S.VAL(SET, tag) - mark);
		tdesc := S.VAL(Tag, S.VAL(SET, notmarked) - array);
		IF notmarked # tdesc THEN (* array block *) h := block^.lastElemToMark + tdesc^.size - S.VAL(ADDRESS, block)
		ELSE h := tdesc^.size + 4
		END;
		nextBlock := S.VAL(Blockm4Ptr, S.VAL(ADDRESS, block) + S.VAL(LONGINT, S.VAL(SET, h + B-1)-S.VAL(SET, B-1)));
		(* end of next block calc *)		
		
		LOOP
			IF p <= S.VAL(ADDRESS, block) + 4 THEN
				IF p = S.VAL(ADDRESS, block) + 4 THEN 
					S.GET(p-4, h);
					IF h # p THEN Mark(S.VAL(BlockPtr, p)) END
				END;
				INC(i);
				IF i = nofcand THEN EXIT END;
				p := candidates[i]
			ELSIF p <= S.VAL(ADDRESS, block) + 28 THEN (* system block *)
				IF p = S.VAL(ADDRESS, block) + 28 THEN Mark(S.VAL(BlockPtr, S.VAL(ADDRESS, block)+4)) END;
				INC(i);
				IF i = nofcand THEN EXIT END;
				p := candidates[i]
			ELSE
				block := nextBlock;
				IF block = lastBlock THEN EXIT END;
				
				(* next block calc *)

				tag := block^.tag;
				notmarked := S.VAL(Tag, S.VAL(SET, tag) - mark);
				tdesc := S.VAL(Tag, S.VAL(SET, notmarked) - array);
				IF notmarked # tdesc THEN (* array block *) h := block^.lastElemToMark + tdesc^.size - S.VAL(ADDRESS, block)
				ELSE h := tdesc^.size + 4
				END;
				nextBlock := S.VAL(Blockm4Ptr, S.VAL(ADDRESS, block) + S.VAL(LONGINT, S.VAL(SET, h + B-1)-S.VAL(SET, B-1)));
				(* end of next block calc *)
			END
		END;
		IF i = nofcand THEN EXIT END;
		thisSuper := S.VAL(SuperBlockPtr, thisSuper.next);
	END;
	nofcand := 0
END CheckCandidates;

PROCEDURE - Less(x, y: LONGINT): BOOLEAN
	8BH, 0FCH, (* mov edi, esp *)
	8BH,  5FH,  0H, 	(* mov ebx, 0[edi] *)
	8BH, 57H, 04H,	(* mov edx, 4[edi] *)
	3BH, 0DAH,		(* cmp ebx, edx *)
	0FH, 92H, 0C0H;  (* setb al *)

PROCEDURE Candidate (p: LONGINT);
	VAR tag: LONGINT; thisSuper: SuperBlockPtr;
BEGIN
	IF ((p MOD B = 0) OR (p MOD 16 = 8)) & Less(supermin, p) & Less(p, supermax) THEN
		thisSuper := S.VAL(SuperBlockPtr, superblocks);
		LOOP
			IF thisSuper = NIL THEN EXIT
			ELSIF Less(p, thisSuper.endblock) & Less(thisSuper.firstblock, p) THEN
				S.GET(p-4, tag);
				IF tag MOD 8 IN {0, 2} (* array or record, not yet marked *) THEN
					candidates[nofcand] := p; INC(nofcand);
					IF nofcand = LEN(candidates) THEN CheckCandidates END
				END;
				EXIT
			END;
			thisSuper := S.VAL(SuperBlockPtr, thisSuper.next)
		END
	END
(*
	IF ((p MOD B = 0) OR (p MOD 16 = 8)) & (p > supermin) & (p < supermax) THEN
		S.GET(p-4, tag);
		IF tag MOD 8 IN {0, 2} (* array or record, not yet marked *) THEN
			candidates[nofcand] := p; INC(nofcand);
			IF nofcand = LEN(candidates) THEN CheckCandidates END
		END
	END
*)
END Candidate;

PROCEDURE FinalizeObjs;
	VAR n, prev: FinObj;
BEGIN
	n := FinObjs;
	WHILE n # NIL DO
		IF ~n.marked THEN
			IF n = FinObjs THEN FinObjs := FinObjs.next ELSE prev.next := n.next END;
			n.fin(S.VAL(S.PTR, n.obj))
		ELSE prev := n
		END;
		n := n.next;
	END
END FinalizeObjs;

PROCEDURE ^ NewSys* (size: LONGINT; VAR p: ADDRESS);

(** Immediately activate the garbage collector. This procedure may be called at any time during execution. *)
PROCEDURE GC*;
	VAR p, sp: LONGINT; 
BEGIN
	IF (GCenabled = 1) & (stackBottom # 0) THEN
		HandleQ(mkQ);
		
		(* check stack *)
		S.GETREG(4, sp); nofcand := 0;
		WHILE sp < stackBottom DO
			S.GET(sp, p); Candidate(p);
			INC(sp, 4)
		END;
		IF nofcand > 0 THEN CheckCandidates END;
		CheckFinObjs;
		Sweep;
		(*
		IF (reserve = NIL) & firstTry THEN
			IF LargestAvailable() >= ReserveSize THEN NewSys(ReserveSize, p); reserve := S.VAL(BlockPtr, p) END
		END;
		*)
		FinalizeObjs;
		IF reserve = 0 THEN 
			reserve := AllocBlock(ReserveBlockSize + 16 + B);
			Str("alloc reserve");
		END
	END
END GC;

	(* ---------------------------------------------------------------- *)

PROCEDURE FinalizeAll;
	VAR n: FinObj;
BEGIN n := FinObjs;
	WHILE n # NIL DO n.fin(S.VAL(S.PTR, n.obj)); n := n.next END;
END FinalizeAll;

(** Terminate Oberon with a fatal error. Termination handlers will be called. *)
PROCEDURE Exit* (err: LONGINT);
BEGIN
	IF err = 0 THEN FinalizeAll;
		HandleQ(quitQ)
	END;
	DisposeAll;
	(* exit(err); *)
END Exit;

	(* -------------------------- memory allocation ----------------------- *)

PROCEDURE - HALT1
	0B8H, 01H, 0H, 0H, 0H,	(* mov eax,1 *)
	08DH, 0C9H;	(* lea ecx, ecx; generate illegal instruction *)

PROCEDURE AllocSuperBlock(VAR adr: ADDRESS; size: LONGINT);
VAR block, p, p0: SuperBlockPtr; rest: FreeBlockPtr; s, alloc, res: LONGINT;
BEGIN
	Str("AllocSuperBlock"); Ln;
	IF size <= SuperBlockSize THEN alloc := SuperBlockSize
	ELSE alloc := size + (-size MOD B)
	END;
	INC(alloc, 16 + B);
	
	adr := AllocBlock(alloc);
	IF adr = 0 THEN
		IF reserve # 0 THEN Str("free reserve"); 
			res := DeAllocBlock(reserve, ReserveBlockSize + 16 + B); reserve := 0 
		ELSE
			alloc := ReserveBlockSize + 16 + B;
			adr := AllocBlock(alloc)
		END
	END;
	IF adr # 0 THEN
		ASSERT(adr MOD 4 = 0);
		
		block := S.VAL(SuperBlockPtr, adr);
		block^.next := 0;
		block^.size := alloc;
		block^.firstblock := adr + 16;
		block^.firstblock := block^.firstblock + (-block^.firstblock-4) MOD B;
		ASSERT((block^.firstblock + 4) MOD B = 0);
		
		s := adr + alloc - block^.firstblock; s := s - s MOD B;
		block^.endblock := block^.firstblock + s;
		ASSERT(s MOD B = 0); ASSERT(s >= size);
		
		ASSERT(superblocks # 0);
		Str("Allocate SuperBlock at "); Int(block^.firstblock); Str(" size="); Int(alloc); Ln;

		p0 := NIL;
		p := S.VAL(SuperBlockPtr, superblocks);
		WHILE (p # NIL) & (p^.firstblock < block^.firstblock) DO p0 := p; p := S.VAL(SuperBlockPtr, p.next) END;
		
		IF p0 = NIL THEN (* first block *)
			block.next := S.VAL(LONGINT, p); superblocks := S.VAL(LONGINT, block);
			supermin := block^.firstblock;
			Str("supermin* at "); Int(supermin); Str(" supermax at "); Int(supermax); Str(" size="); Int(supermax-supermin); Ln;
		ELSE
			block.next := S.VAL(LONGINT, p); p0.next := S.VAL(LONGINT, block);
			IF block.next = 0 THEN (* last block *)
				supermax := block^.endblock;
				Str("supermin at "); Int(supermin); Str(" supermax* at "); Int(supermax); Str(" size=");Int(supermax-supermin); Ln;
			END
		END;
		ASSERT(supermin < supermax, 100);
		
		rest := S.VAL(FreeBlockPtr, block^.firstblock);
		rest^.tag := S.VAL(Tag, S.ADR(rest^.size));
		rest^.size := block^.endblock - block^.firstblock - 4;
		
		(* hang into existing free lists *)
		rest^.next := A[N];
		A[N] := S.VAL(LONGINT, rest);
		
		adr := A[N];
	ELSE adr := 0;
		Str("SuperBlock allocation failed. Out of memory."); Ln
	END;
END AllocSuperBlock;

PROCEDURE NewBlock (size: LONGINT): InitPtr;	(* size MOD B = 0 *)
	VAR i, rest: LONGINT; adr, AN: ADDRESS; ptr: InitPtr; restptr: FreeBlockPtr;
BEGIN
	IF size < 0 (* NEW(p, MAX(LONGINT)) *) THEN HALT1 END;
	i := size DIV B;
	IF i > N THEN i := N END;
	adr := S.ADR(A[0]) + 4*i;
	AN := S.ADR(A[N]);	(* constant register *)
	LOOP
		S.GET(adr, ptr);
		IF adr = AN THEN
			LOOP
				IF ptr = NIL THEN
					IF (TrapHandlingLevel = 0) & firstTry THEN 
						Str("out of mem; calling GC"); Ln;
						GC;
						firstTry := FALSE; ptr := NewBlock(size); firstTry := TRUE;
						RETURN ptr
					ELSE (* reserve := NIL; GC; firstTry := TRUE; (* HALT1; *) RETURN NIL *)
						Str("out of mem; allocating superblock"); Ln;
						firstTry := TRUE;
						AllocSuperBlock(adr, size);
						IF adr = 0 THEN HALT1
						ELSE ptr := NewBlock(size); RETURN ptr
						END
					END
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

(** Private compiler interface. Do not use. *)
PROCEDURE NewRec* (tag: Tag; VAR p: ADDRESS);	(* implementation of NEW(ptr) *)
	VAR size: LONGINT; ptr, init: InitPtr;
BEGIN (* tag^.size = rectyp^.size *)
	size := S.VAL(LONGINT, S.VAL(SET, tag^.size + (4 (*tag*) + B-1))-S.VAL(SET, B-1));
	ptr := NewBlock(size);
	IF ptr = NIL THEN p := 0; RETURN END;
	
	init := S.VAL(InitPtr, S.VAL(ADDRESS, ptr) + size - 32);
	init^.z0 := 0; init^.z1 := 0; init^.z2 := 0; init^.z3 := 0; init^.z4 := 0; init^.z5 := 0; init^.z6 := 0;
	WHILE init # ptr DO
		DEC(S.VAL(ADDRESS, init), 32);
		init^.z0 := 0; init^.z1 := 0; init^.z2 := 0; init^.z3 := 0; init^.z4 := 0; init^.z5 := 0; init^.z6 := 0; init^.z7 := 0
	END;
	ptr^.tag := tag;
	p := S.VAL(ADDRESS, ptr) + 4;
END NewRec;

(** Private compiler interface. Do not use. *)
PROCEDURE NewSys* (size: LONGINT; VAR p: ADDRESS);	(* implementation of S.NEW(ptr, size) *)
	VAR ptr, init: InitPtr;
BEGIN
	size := S.VAL(LONGINT, S.VAL(SET, size + (28 + B-1))-S.VAL(SET, B-1));
	ptr := NewBlock(size);
	IF ptr = NIL THEN p := 0; RETURN END;
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
	p := S.VAL(ADDRESS, ptr) + 28;
END NewSys;

(** Private compiler interface. Do not use. *)
PROCEDURE NewArr* (nofdim, nofelem: LONGINT; eltag: Tag; VAR p: ADDRESS);
	(* implementation of NEW(ptr, dim0, dim1, ...) *)
	VAR size, firstElem, elSize, arrSize, vectSize: LONGINT; ptr, init: InitPtr;
BEGIN
	IF eltag = NIL THEN (* ARRAY OF POINTER *) eltag := S.VAL(Tag, PointerTD) END;
	elSize := eltag^.size;
	arrSize := nofelem*elSize;
	vectSize := 8*(nofdim DIV 2) + 4;	(* -> ADR(firstElem) MOD 8 = 0 *)
	IF eltag^.ptroff = -4 THEN (* no pointers in element type *) NewSys(arrSize + vectSize + 12, p); RETURN END;
	size := S.VAL(LONGINT, S.VAL(SET, arrSize + vectSize + (16 + B-1))-S.VAL(SET, B-1));
	ptr := NewBlock(size);
	IF ptr = NIL THEN p := 0; RETURN END;
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
	p := S.VAL(ADDRESS, ptr) + 4
END NewArr;


	(* --------------------------------------------------------------------- *)

(** Return the system time and date. From LSB to MSB, the date is divided into 5 bits for the day, 4 bits for the month, and 7 bits for the year (add 1900 to year to get the correct value). From LSB to MSB, the time is divided into 6 bits for seconds, 6 bits for minutes, and 5 bits for the hour. *)
PROCEDURE GetClock* (VAR time, date: LONGINT);
	TYPE SysTime = RECORD
				year, month, weekday, day: INTEGER;
				hour, min, sec, millisec : INTEGER;
			END;
	VAR t: SysTime;
BEGIN time := 0; date := 0;
	GetLocalTime(S.ADR(t));
	date := t.year - 1900; date := ASH(date, 4);
	date := date + t.month; date := ASH(date, 5);
	date := date + t.day;
	time := t.hour; time := ASH(time, 6);
	time := time + t.min; time := ASH(time, 6);
	time := time + t.sec;
END GetClock;

(** Load a dynamic link library (DLL) of the underlying operating system into memory. The return value is a handle to the DLL for accessing symbols located in the DLL.*)
PROCEDURE LoadLibrary* (file: ARRAY OF CHAR): LONGINT;
BEGIN
	RETURN loadLibrary(S.ADR(file))
END LoadLibrary;

(** Returns the address of a symbol in a DLL. *)
PROCEDURE GetAdr* (lib: LONGINT; symbol: ARRAY OF CHAR; VAR adr: LONGINT);
BEGIN AAgetadr(S.ADR(adr), S.ADR(symbol), lib)
END GetAdr;

PROCEDURE EnableGC*();
BEGIN
	INC(GCenabled)
END EnableGC;

PROCEDURE DisableGC*();
BEGIN
	DEC(GCenabled)
END DisableGC;

PROCEDURE InitKernel;	(* heapAdr, heapSize, firstBlock and modules already initialized *)
	VAR size, i: LONGINT; p: Blockm4Ptr; rest: FreeBlockPtr; tag, tdesc: Tag; m: Module;
		td: POINTER TO RECORD filler: ARRAY 4 OF LONGINT; name: Name END;
BEGIN
	FinObjs := NIL;
	size := heapAdr + heapSize - firstBlock;
	DEC(size, size MOD B);
	endBlock := firstBlock + size;

	m := S.VAL(Module, modules);
	WHILE m.name # "JuiceKernel" DO m := m.link END;
	(* initialise ptrElemTag *)
	i := LEN(m.tdescs^);
	REPEAT DEC(i);
		PointerTD := m.tdescs[i];
		S.GET(PointerTD - 4, td)
	UNTIL td.name = "PtrElemDesc";
	
	i := LEN(m.tdescs^);
	REPEAT DEC(i);
		queueTD := m.tdescs[i];
		S.GET(queueTD - 4, td)
	UNTIL td.name = "QElem";

	p := S.VAL(Blockm4Ptr, firstBlock);
	WHILE p^.tag # NIL DO
		tag := p^.tag;
		tdesc := S.VAL(Tag, S.VAL(SET, tag) - array - mark);
		IF array * S.VAL(SET, tag) # {} THEN (* array block *) size := p^.lastElemToMark + tdesc^.size - S.VAL(ADDRESS, p)
		ELSE size := tdesc^.size + 4
		END;
		size := S.VAL(LONGINT, S.VAL(SET, size + B-1)-S.VAL(SET, B-1));
		INC(S.VAL(ADDRESS, p), size)
	END;
	rest := S.VAL(FreeBlockPtr, p);
	rest^.tag := S.VAL(Tag, S.ADR(rest^.size));
	rest^.size := S.VAL(LONGINT, endBlock) - S.VAL(LONGINT, rest) - 4;
	rest^.next := 0;
	i := 0;
	firstTry := TRUE;
	stackBottom := 0;
	i := 0;
	WHILE i < N DO A[i] := nil; INC(i) END;
	A[N] := S.VAL(LONGINT, rest);
	GCenabled := 1;
	
	oberonsuperblock.next := 0;
	oberonsuperblock.size := heapSize;
	oberonsuperblock.firstblock := firstBlock;
	oberonsuperblock.endblock := endBlock;
	superblocks := S.ADR(oberonsuperblock);
	supermin :=  firstBlock;
	supermax := endBlock;
	stackBottom := 0;
	reserve := AllocBlock(ReserveBlockSize + 16 + B);

	InitQ(mkQ); InitQ(quitQ);
END InitKernel;

PROCEDURE CallBodies;	(* modules already initialized *)
	TYPE Body = PROCEDURE;
	VAR m, last: Module; body: Body;
BEGIN
	last := S.VAL(Module, modules);
	WHILE last.link # NIL DO
		last := last.link;
	END;
	m := S.VAL(Module, modules);
	LOOP
		IF m.name = "JuiceKernel" THEN InitKernel
		ELSE
			body := S.VAL(Body, S.ADR(m.code[0]));
			Str(m.name); Ln;
			body;
		END;
		IF m = last THEN EXIT END; (* initialize modules belonging to bootfile only *)
		m := m.link
	END
END CallBodies;

BEGIN
	(* rely on initialisation of initialised and EventLoop to FALSE and NIL, resp. *)
	IF initialised THEN
		IF EventLoop # NIL THEN EventLoop ELSE Exit(1) END;
	END;
	initialised := TRUE;
	GetAdr(0, "LoadLibrary", S.VAL(LONGINT, loadLibrary));
	GetAdr(0, "FreeLibrary", S.VAL(LONGINT, freeLibrary));
	GetAdr(0, "heapAdr", S.VAL(LONGINT, heapAdr));
	GetAdr(0, "heapSize", S.VAL(LONGINT, heapSize));
	mod := LoadLibrary("Kernel32");
	GetAdr(mod, "GetLocalTime", S.VAL(LONGINT, GetLocalTime));
	GetAdr(mod, "SetLocalTime", S.VAL(LONGINT, SetLocalTime));
	GetAdr(mod, "VirtualAlloc", S.VAL(LONGINT, VirtualAlloc));
	GetAdr(mod, "VirtualFree", S.VAL(LONGINT, VirtualFree));

	IF Debug THEN
		GetAdr(0, "Debug", S.VAL(LONGINT, OutputDebugString));
		Str("JuiceKernel started"); Ln
	ELSE
		OutputDebugString := NIL
	END;

	TrapHandlingLevel := 0; stackBottom := 0;
	firstBlock := heapAdr + ((-heapAdr-4) MOD B);
	modules := firstBlock + 4;
	CallBodies
END JuiceKernel.

(** Remarks:

1. The NEW built-in of the Oberon language is mapped to the NewX procedures of the kernel, where X is Rec, Sys, or Arr. These procedures should never be called directly.

2. The NEW built-in of the Oberon language will return a pointer initialized to NIL when not enough memory can be found to fulfil the request. Note that this version of the Kernel does not initiate an "out of memory" trap (in contrast to other kernels that do).

3. Finalization allows an object to obtain control before it is removed from the heap by the garbage collector. First declare a finalization procedure:

	PROCEDURE Finalize (f: PTR);
	BEGIN
		WITH f: ObjType DO
			...
		END
	END Finalize;

then register a specific object (any pointer based record type) for finalization with:

	Kernel.RegisterObject(obj, Finalize);

At finalization object can prevent being collected by anchoring it again somewhere in a used data-structure or a global pointer variable. Finalization increases the garbage collector time and should thus be used sparingly.

4. Interfacing with the underlying operating system is through loading dynamic link libraries. First load the DLL and then locate the symbol you require, assinging it to a global procedure variable:

	VAR
		GetLocalTime: PROCEDURE (systime: LONGINT);

	PROCEDURE Init;
	VAR mod: LONGINT;
	BEGIN
		mod := Kernel.LoadLibrary("Kernel32");
		Kernel.GetAdr(mod, "GetLocalTime", S.VAL(LONGINT, GetLocalTime));
	END Init;

Calling the procedure variable then results in a call to the DLL procedure. The procedure variable must have the same definition as the procedure called (can often be determined by inspecting the C header files of the OS). Oberon has no possibility of checking interfaces with the OS for type-safety (use at your own risk!). Passing structured types directly to a DLL should be handled with care. Oberon often uses padding between fields of a record to increase access speeds. Your OS might not have the same conventions, causing mis-aligment problems.

*)
