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

MODULE JuiceFiles; (* Files for Oberon for Windows 95/NT, ejz 31.1.95 *)
	IMPORT S := SYSTEM, Kernel:= JuiceKernel, FileDir := JuiceFileDir, NPAPI;

(* Base on Files from MH Feb 93 / 5.5.94 *)

(** The Files module provided access to the file system of the host operating system by simulating an Oberon-like file system. *)

	CONST
		NULL = 0; False = 0;
		InvalidHandleValue = -1;
		ErrorAccessDenied = 5; ErrorWriteProtect = 19; ErrorSharingViolation = 32;
		GenericRead = 080000000H; GenericWrite = 040000000H;
		FileShareRead = 1; FileShareWrite = 2;
		FileAttributeNormal = 080H; FileAttributeTemporary = 0100H;
		FileFlagRandomAccess = 010000000H; 
		FileBegin = 0;
		CreateAlways = 2; OpenExisting = 3;
		MaxFiles = 128+64;
		BufSize = 4*1024;
		MaxBufs = 4;
		WinPathChar = "\";

	TYPE
		FileTime = RECORD
			lowDT, highDT: LONGINT
		END;
		SystemTime = RECORD
			year, month, dayOfWeek, day: INTEGER;
			hour, min, sec, millisec: INTEGER;
		END;
		File* = POINTER TO Handle; (** file descriptor *)
		Buffer = POINTER TO BufDesc;
		BufDesc = RECORD
			F: File;
			org, size: LONGINT;
			data: ARRAY BufSize OF S.BYTE;
			dirty: BOOLEAN
		END;
		Handle = RECORD
			name: FileDir.FileName;
			temp: POINTER TO RECORD
					temp, name: FileDir.FileName
				END;
			handle, pos, len: LONGINT;
			bufs: ARRAY MaxBufs OF Buffer;
			entry, swap: INTEGER;
			readOnly: BOOLEAN
		END;
		Rider* = RECORD (** Riders are the access mechanisms for files. *)
			eof*: BOOLEAN; (** Rider has reached the end of the file. *)
			res*: LONGINT; (** Rider operation result code. *)
			buf: Buffer;
			org, offset: LONGINT
		END;

		Notifier* = PROCEDURE (F: File; data: PTR);
	
		Request = POINTER TO RequestDesc;
		RequestDesc = RECORD
			F: File;
			R: Rider;
			data: PTR;
			proc: Notifier;
		END;

	VAR
		FileTab: ARRAY MaxFiles OF LONGINT;
		GetLastError: PROCEDURE (): LONGINT;
		SetHandleCount: PROCEDURE (nofHandles: LONGINT): LONGINT;
		CreateFile: PROCEDURE (name, accessMode, shareMode, securityAttr, createOpts, attrAndFlags, template: LONGINT): LONGINT;
		CloseHandle: PROCEDURE (h: LONGINT): LONGINT;
		SetFilePointer: PROCEDURE (hFile, dist, lpHighDIst: LONGINT; method: LONGINT): LONGINT;
		GetFileSize: PROCEDURE (hFile, lpHighDIst: LONGINT): LONGINT;
		WriteFile: PROCEDURE (hFile, buf, lenBuf: LONGINT; VAR nWr: LONGINT; lpOverlapp: LONGINT): LONGINT;
		ReadFile: PROCEDURE (hFile, buf, lenBuf: LONGINT; VAR nRe: LONGINT; lpOverlapp: LONGINT): LONGINT;
		GetFileTime: PROCEDURE (hFile, lpFTCreate, lpFTLastA, lpFTWrite: LONGINT): LONGINT;
		SetFileTime: PROCEDURE (hFile, lpFTCreate, lpFTLastA, lpFTWrite: LONGINT): LONGINT;
		FileTimeToSystemTime: PROCEDURE (lpFT, lpST: LONGINT): LONGINT;
		SystemTimeToFileTime: PROCEDURE (lpST, lpFT: LONGINT): LONGINT;
		DeleteFile: PROCEDURE (name: LONGINT): LONGINT;
		GetTempFileName: PROCEDURE (path, prefix, unique, tempName: LONGINT): LONGINT;
		CopyFile: PROCEDURE (existing, new, failIfExist: LONGINT): LONGINT;
		MoveFile: PROCEDURE (existing, new: LONGINT): LONGINT;
		ret, err: LONGINT;

	PROCEDURE MakeName(VAR name0, name1: ARRAY OF CHAR);
		VAR i, j: INTEGER; ch: CHAR;
	BEGIN	
		i:=0; j:=0;
		REPEAT	ch:=name0[i]; INC(i);
			IF	(ch=":") OR (ch=FileDir.PathChar)	THEN	j:=i	END
		UNTIL	ch=0X;
	(*	IF j#0 THEN name1[0]:=0X; RETURN END; *)
		i:=0; ch:=name0[j];
		WHILE	ch#0X	DO
			name1[i]:=ch; INC(i);
			INC(j); ch:=name0[j]
		END; 
		name1[i]:=0X;
	END MakeName;

	PROCEDURE ReMakeName(VAR name0, name1: ARRAY OF CHAR);
		VAR i, j: INTEGER; ch: CHAR;
	BEGIN	
		i:=0; j:=0;
		REPEAT	ch:=name0[i]; INC(i);
			IF	(ch=":") OR (ch=FileDir.PathChar)	THEN	j:=i	END
		UNTIL	ch=0X;
		i:=0; ch:=name0[j];
		WHILE	ch#0X	DO
			name1[i]:=ch; INC(i);
			INC(j); ch:=name0[j]
		END; 
		name1[i]:=0X
	END ReMakeName;


	PROCEDURE FindRegEntry(VAR name: ARRAY OF CHAR): File;
		VAR
			i: LONGINT;
			F: File;
	BEGIN
		FOR i := 0 TO MaxFiles-1 DO
			F := S.VAL(File, FileTab[i]);
			IF (F # NIL) & (F.temp = NIL) & FileDir.SameName(F.name, name) THEN
				RETURN F
			END
		END;
		RETURN NIL
	END FindRegEntry;

	PROCEDURE FreeEntry(): LONGINT;
		VAR i, j: LONGINT;
	BEGIN
		FOR j := 0 TO 1 DO
			FOR i := 0 TO MaxFiles-1 DO
				IF FileTab[i] = S.VAL(LONGINT, NIL) THEN
					RETURN i
				END
			END;
			Kernel.GC()
		END;
		HALT(99)
	END FreeEntry;

	PROCEDURE LongOr(a, b: LONGINT): LONGINT;
	BEGIN
		RETURN S.VAL(LONGINT, S.VAL(SET, a) + S.VAL(SET, b))
	END LongOr;

	PROCEDURE ClosePhysical(F: File);
	BEGIN
		ret := CloseHandle(F.handle);
		F.handle := InvalidHandleValue;
		IF ret = False THEN
			err := GetLastError(); HALT(99)
		END
	END ClosePhysical;

	PROCEDURE DeletePhysical(VAR name: ARRAY OF CHAR);
	BEGIN
		ret := DeleteFile(S.ADR(name));
		IF ret = False THEN
			err := GetLastError(); HALT(99)
		END
	END DeletePhysical;

	PROCEDURE SetPhysicalPos(F: File; pos: LONGINT);
	BEGIN
		ret := SetFilePointer(F.handle, pos, 0, FileBegin);
		IF ret # pos THEN
			err := GetLastError(); HALT(99)
		END;
		F.pos := pos
	END SetPhysicalPos;

	PROCEDURE MovePhysical(F: File; VAR from, to: ARRAY OF CHAR);
	BEGIN
		ret := MoveFile(S.ADR(from), S.ADR(to));
		IF ret = False THEN
			ret := CopyFile(S.ADR(from), S.ADR(to), False);
			IF ret = False THEN
				err := GetLastError(); HALT(99)
			ELSE
				DeletePhysical(from)
			END
		END
	END MovePhysical;

	PROCEDURE *FinalizeFile(F: PTR);
	BEGIN
		WITH F: File DO
			IF F.handle # InvalidHandleValue THEN
				ClosePhysical(F);
				IF F.temp # NIL THEN
					DeletePhysical(F.temp.temp); F.temp := NIL
				END
			END;
			IF F.entry >= 0 THEN
				FileTab[F.entry] := S.VAL(LONGINT, NIL); F.entry := -1
			END
		END
	END FinalizeFile;

	PROCEDURE init(F: File);
		VAR i: LONGINT;
	BEGIN
		FOR i := 0 TO MaxBufs-1 DO
			F.bufs[i] := NIL
		END;
		SetPhysicalPos(F, 0);
		ret := GetFileSize(F.handle, 0);
		IF ret >= 0 THEN
			F.len := ret; F.swap := -1;
			FileTab[F.entry] := S.VAL(LONGINT, F);
			Kernel.RegisterObject(F, FinalizeFile);
			RETURN
		END;
		err := GetLastError();
		ClosePhysical(F); HALT(99)
	END init;

	PROCEDURE old(VAR fName: ARRAY OF CHAR): File;
		VAR
			F: File;
			i: LONGINT;
	BEGIN
		F := FindRegEntry(fName);
		IF F = NIL THEN
			i := FreeEntry();
			ret := CreateFile(S.ADR(fName), LongOr(GenericRead, GenericWrite), FileShareRead, NULL, OpenExisting, LongOr(FileAttributeNormal, FileFlagRandomAccess), NULL);
			IF ret = InvalidHandleValue THEN
				err := GetLastError();
				IF (err = ErrorAccessDenied) OR (err = ErrorWriteProtect) OR (err = ErrorSharingViolation) THEN
					ret := CreateFile(S.ADR(fName), GenericRead, LongOr(FileShareRead, FileShareWrite), NULL, OpenExisting, LongOr(FileAttributeNormal, FileFlagRandomAccess), NULL);
					IF ret = InvalidHandleValue THEN
						err := GetLastError()
					END
				END
			ELSE
				err := 0
			END;
			IF ret # InvalidHandleValue THEN
				NEW(F);
				COPY(fName, F.name); F.temp := NIL;
				F.handle := ret; F.readOnly := err # 0;
				F.entry := SHORT(i); init(F)
			END
		END;
		RETURN F
	END old;

(** Open an existing file. The same file descriptor is returned if a file is opened multiple times. *)
	PROCEDURE Old*(name: ARRAY OF CHAR): File;
		VAR fName, name1: FileDir.FileName;
	BEGIN
		FileDir.ResetPath;
		MakeName(name, name1);
		IF (name1 # "") & FileDir.FindFile(name1, fName, TRUE) THEN
			FileDir.ConvertChar(fName, FileDir.PathChar, WinPathChar);
			RETURN old(fName)
		ELSE
			RETURN NIL
		END
	END Old;

	PROCEDURE TempName(F: File; VAR name: ARRAY OF CHAR);
		VAR
			tempDir: FileDir.FileName;
			pref: ARRAY 8 OF CHAR;
	BEGIN
		FileDir.GetTempDirectory(tempDir); FileDir.ConvertChar(tempDir, FileDir.PathChar, WinPathChar);
		pref := "Oberon";
		ret := GetTempFileName(S.ADR(tempDir), S.ADR(pref), 0, S.ADR(name));
		IF ret = 0 THEN
			err := GetLastError(); HALT(99)
		END
	END TempName;

	PROCEDURE new(): File;
		VAR
			F: File;
			i: LONGINT;
	BEGIN
		i := FreeEntry();
		NEW(F); NEW(F.temp);
		TempName(F, F.temp.temp); F.name := "";
		ret := CreateFile(S.ADR(F.temp.temp), LongOr(GenericRead, GenericWrite), FileShareRead, NULL, CreateAlways, LongOr(LongOr(FileAttributeNormal, FileFlagRandomAccess), FileAttributeTemporary), NULL);
		IF ret = InvalidHandleValue THEN
			err := GetLastError(); HALT(99)
		END;
		F.readOnly := FALSE; F.handle := ret;
		F.entry := SHORT(i); init(F);
		RETURN F
	END new;

(** Creates a new file with the specified name. The same file descriptor is not returned with multiple calls the New with the
	same filename (this results in multiple copies of a file with the same name. i.e. the files are not registered in the directory). *)
	PROCEDURE New*(name: ARRAY OF CHAR): File;
		VAR F: File; name1: FileDir.FileName;
	BEGIN
		FileDir.ResetPath;
		MakeName(name, name1);
		IF name1 = "" THEN
			F := new(); F.temp.name := ""
		ELSIF FileDir.CheckName(name1) THEN
			F := new();
			FileDir.ConvertChar(name1, FileDir.PathChar, WinPathChar); COPY(name1, F.temp.name)
		ELSE
			RETURN NIL
		END;
		RETURN F
	END New;

	PROCEDURE WriteBuf(buf: Buffer);
		VAR
			F: File;
			nWr: LONGINT;
	BEGIN
		F := buf.F;
		IF buf.dirty & (buf.size > 0) THEN
			IF F.readOnly THEN
				(* reset file length and buffers to real data *)
				HALT(99)
			ELSIF F.pos # buf.org THEN
				SetPhysicalPos(F, buf.org)
			END;
			ret := WriteFile(F.handle, S.ADR(buf.data), buf.size, nWr, NULL);
			IF ret = False THEN
				err := GetLastError(); HALT(99)
			ELSIF nWr # buf.size THEN
				HALT(99)
			END;
			IF (buf.org+buf.size) > F.len THEN
				F.len := buf.org+buf.size
			END;
			INC(F.pos, nWr)
		END;
		buf.dirty := FALSE
	END WriteBuf;

	PROCEDURE ReadBuf(buf: Buffer);
		VAR
			F: File;
			nRe: LONGINT;
	BEGIN
		F := buf.F;
		IF (buf.org+BufSize) > F.len THEN
			buf.size := F.len-buf.org
		ELSE
			buf.size := BufSize
		END;
		IF buf.size > 0 THEN
			IF F.pos # buf.org THEN
				SetPhysicalPos(F, buf.org)
			END;
			ret := ReadFile(F.handle, S.ADR(buf.data), buf.size, nRe, NULL);
			IF ret = False THEN
				err := GetLastError(); HALT(99)
			ELSIF nRe # buf.size THEN
				HALT(99)
			END;
			INC(F.pos, nRe)
		END;
		buf.dirty := FALSE
	END ReadBuf;

	PROCEDURE set(VAR R: Rider; F: File; pos: LONGINT);
		VAR
			buf: Buffer;
			org, offset, i: LONGINT;
	BEGIN
		IF F # NIL THEN
			IF pos > F.len THEN
				pos := F.len
			ELSIF pos < 0 THEN
				pos := 0
			END;
			offset := pos MOD BufSize; org := pos - offset; buf := NIL;
			i := 0;
			WHILE (i < MaxBufs) & (F.bufs[i] # NIL) & (F.bufs[i].org # org) DO
				INC(i)
			END;
			IF i < MaxBufs THEN
 				IF F.bufs[i] # NIL THEN
 					buf := F.bufs[i]
 				ELSE
 					NEW(buf); F.bufs[i] := buf; buf.F := F; buf.dirty := FALSE;
 					buf.org := -1; buf.size := 0
 				END
 			ELSE
 				F.swap := (F.swap+1) MOD MaxBufs;
 				buf := F.bufs[F.swap];
 				(*IF ~F.readOnly THEN*) WriteBuf(buf) (*END*)
 			END;
 			IF buf.org # org THEN
 				buf.org := org;
 				IF org = F.len THEN
 					buf.size := 0; buf.dirty := FALSE
 				ELSE
 					buf.org := org; ReadBuf(buf)
 				END
 			END
		ELSE
			buf := NIL; org := 0; offset := 0
		END;
		R.buf := buf; R.org := org; R.offset := offset; R.eof := FALSE; R.res := 0
	END set;

(** Positions a Rider at a certain position in a file. Multiple Riders can be positioned at different locations in a file. A Rider
	cannot be positioned beyond the end of a file. *)
	PROCEDURE Set*(VAR R: Rider; F: File; pos: LONGINT);
	BEGIN
		set(R, F, pos)
	END Set;

(** Returns the File a Rider is based on. *)
	PROCEDURE Base*(VAR R: Rider): File;
	BEGIN
		RETURN R.buf.F
	END Base;

(** Returns the length of a file. *)
	PROCEDURE Length*(F: File): LONGINT;
	BEGIN
		RETURN F.len
	END Length;

(** Returns the offset of a Rider positioned on a file. *)
	PROCEDURE Pos*(VAR R: Rider): LONGINT;
	BEGIN
		RETURN R.org+R.offset
	END Pos;

(** Returns the full name of a file. *)
	PROCEDURE GetName*(F: File; VAR name: ARRAY OF CHAR);
		VAR name1: FileDir.FileName;
	BEGIN
		COPY(F.name, name1); FileDir.ConvertChar(name1, WinPathChar, FileDir.PathChar);
		ReMakeName(name1, name);
	END GetName;

(** Flushes the changes made to a file to disk. Register will automatically Close a file. *)
	PROCEDURE Close*(F: File);
		VAR i: LONGINT;
	BEGIN
		i := 0;
		WHILE (i < MaxBufs) & (F.bufs[i] # NIL) DO
			WriteBuf(F.bufs[i]); INC(i)
		END
	END Close;

	PROCEDURE Delete0(name: ARRAY OF CHAR; VAR res: INTEGER);
		VAR
			fName: FileDir.FileName;
			F: File;
	BEGIN
		res := 1;
		IF (name # "") & FileDir.FindFile(name, fName, FALSE) THEN
			FileDir.ConvertChar(fName, FileDir.PathChar, WinPathChar);
			F := FindRegEntry(fName);
			IF F # NIL THEN
				Close(F);
				ClosePhysical(F);
				NEW(F.temp); COPY(F.name, F.temp.name); F.name := "";
				TempName(F, F.temp.temp);
				MovePhysical(F, F.temp.name, F.temp.temp);
				ret := CreateFile(S.ADR(F.temp.temp), LongOr(GenericRead, GenericWrite), FileShareRead, NULL, OpenExisting, LongOr(LongOr(FileAttributeNormal, FileFlagRandomAccess), FileAttributeTemporary), NULL);
				IF ret = InvalidHandleValue THEN
					err := GetLastError(); HALT(99)
				END;
				F.handle := ret;
				SetPhysicalPos(F, F.pos)
			ELSE
				DeletePhysical(fName)
			END;
			res := 0
		END;
	END Delete0;

(** Deletes a file. res = 0 indicates success. *)
	PROCEDURE Delete*(name: ARRAY OF CHAR; VAR res: INTEGER);
		VAR name1: FileDir.FileName;
	BEGIN
		FileDir.ResetPath;
		MakeName(name, name1);
		Delete0(name1, res);
	END Delete;

(** Register a file created with New in the directory, replacing the previous file in the directory with the same name. The file
	is automatically closed. *)
	PROCEDURE Register*(F: File);
		VAR res: INTEGER;
	BEGIN
		FileDir.ResetPath;
		Close(F);
		IF (F.temp # NIL) & (F.temp.name # "") THEN
			IF FileDir.FindFile(F.temp.name, F.name, FALSE) THEN
				FileDir.ConvertChar(F.name, FileDir.PathChar, WinPathChar);
				Delete0(F.name, res);
				IF res # 0 THEN
					Kernel.Str("not deleted"); Kernel.Ln;
					HALT(99)
				END
			ELSE
				COPY(F.temp.name, F.name)
			END;
			ClosePhysical(F);
			ret := CreateFile(S.ADR(F.name), LongOr(GenericRead, GenericWrite), FileShareRead, NULL, CreateAlways, LongOr(FileAttributeNormal, FileFlagRandomAccess), NULL);
			IF ret = InvalidHandleValue THEN
				Kernel.Str("could not create file 1"); Kernel.Ln;
				err := GetLastError(); HALT(99)
			END;
			F.handle := ret; ClosePhysical(F);
			COPY(F.name, F.temp.name);
			IF FileDir.FindFile(F.temp.name, F.name, FALSE) THEN
				FileDir.ConvertChar(F.name, FileDir.PathChar, WinPathChar);
				MovePhysical(F, F.temp.temp, F.name);
				ret := CreateFile(S.ADR(F.name), LongOr(GenericRead, GenericWrite), FileShareRead, NULL, OpenExisting, LongOr(FileAttributeNormal, FileFlagRandomAccess), NULL);
				IF ret = InvalidHandleValue THEN
					Kernel.Str("could not create file 2"); Kernel.Ln;
					err := GetLastError(); HALT(99)
				END;
				F.handle := ret;
				SetPhysicalPos(F, F.pos);
				F.temp := NIL
			ELSE
				Kernel.Str("not found"); Kernel.Ln;
				HALT(99)
			END
		END
	END Register;

(** Returns the time (t) and date (d) of a file. *)
	PROCEDURE GetDate*(F: File; VAR t, d: LONGINT);
		VAR
			ft: FileTime;
			st: SystemTime;
	BEGIN
		ret := GetFileTime(F.handle, NULL, NULL, S.ADR(ft));
		IF ret = False THEN
			err := GetLastError(); HALT(99)
		ELSE
			ret := FileTimeToSystemTime(S.ADR(ft), S.ADR(st));
			IF ret = False THEN
				err := GetLastError(); HALT(99)
			ELSE
				d := LONG(st.year-1900)*200H + LONG(st.month)*20H + LONG(st.day);
				t := LONG(st.hour)*1000H + LONG(st.min)*40H + LONG(st.sec)
			END
		END
	END GetDate;

(** Sets the time (t) and date (d) of a file. *)
	PROCEDURE SetDate*(F: File; t, d: LONGINT);
		VAR
			ft: FileTime;
			st: SystemTime;
	BEGIN
		st.day := SHORT(d MOD 20H); d := ASH(d, -5);
		st.month := SHORT(d MOD 10H); d := ASH(d, -4);
		st.year := SHORT(d MOD 80H) + 1900;
		st.millisec := 0;
		st.sec := SHORT(t MOD 40H); t := ASH(t, -6);
		st.min := SHORT(t MOD 40H); t := ASH(t, -6);
		st.hour := SHORT(t MOD 20H);
		ret := SystemTimeToFileTime(S.ADR(st), S.ADR(ft));
		IF ret = False THEN
			err := GetLastError(); HALT(99)
		ELSE
			ret := SetFileTime(F.handle, NULL, NULL, S.ADR(ft));
			IF ret = False THEN
				err := GetLastError(); HALT(99)
			END
		END
	END SetDate;

(** Read a byte from a file, advancing the Rider one byte further. R.eof indicates if the end of the file has been reached. *)
	PROCEDURE Read(VAR R: Rider; VAR x: S.BYTE);
		VAR
			F: File;
			buf: Buffer;
			offset: LONGINT;
	BEGIN
		buf := R.buf; F := buf.F;
		offset := R.offset;
		IF R.org # buf.org THEN
			set(R, F, R.org+offset); buf := R.buf; offset := R.offset
		END;
		IF offset < buf.size THEN
			x := buf.data[offset]; R.offset := offset+1
		ELSIF (R.org+offset) < F.len THEN
			set(R, F, R.org+offset); x := R.buf.data[0]; R.offset := 1
		ELSE
			x := 0X; R.eof := TRUE
		END
	END Read;

(** Reads a sequence of length n bytes into the buffer x, advancing the Rider. Less bytes will be read when reading over the
	length of the file. *)
	PROCEDURE ReadBytes(VAR R: Rider; VAR x: ARRAY OF S.BYTE; n: LONGINT);
		VAR
			F: File;
			xpos, min, remaining, offset: LONGINT;
			buf: Buffer;
	BEGIN
		ASSERT(LEN(x) >= n);
		buf := R.buf; F := buf.F;
		xpos := 0; offset := R.offset;
		WHILE n > 0 DO
			IF (R.org # buf.org) OR (offset >= BufSize) THEN
				set(R, F, R.org + offset); buf := R.buf; offset := R.offset;
			END;
			remaining := buf.size - offset;
			IF remaining = 0 THEN R.res := n; R.eof := TRUE; RETURN
			ELSE (* min := MIN(remaining, n) *)
				IF n > remaining THEN min := remaining ELSE min := n END;
			END;
			S.MOVE(S.ADR(buf.data) + offset, S.ADR(x) + xpos, min);
			INC(offset, min); R.offset := offset; INC(xpos, min); DEC(n, min);
		END;
		R.res := 0; R.eof := FALSE
	END ReadBytes;

(** Writes a byte into the file at the Rider position, advancing the Rider by one. *)
	PROCEDURE Write(VAR R: Rider; x: S.BYTE);
		VAR
			F: File;
			buf: Buffer;
			offset: LONGINT;
	BEGIN
		buf := R.buf; F := buf.F;
		offset := R.offset;
		IF (R.org # buf.org) OR (offset >= BufSize) THEN
			set(R, F, R.org+offset); buf := R.buf; offset := R.offset
		END;
		buf.data[offset] := x; buf.dirty := TRUE;
		IF offset = buf.size THEN
			INC(buf.size); INC(F.len)
		END;
		R.offset := offset+1; R.res := 0 
	END Write;

(** Writes the buffer x containing n bytes into a file at the Rider position. *)
	PROCEDURE WriteBytes(VAR R: Rider; VAR x: ARRAY OF S.BYTE; n: LONGINT);
		VAR
			F: File;
			xpos, min, restInBuf, offset: LONGINT;
			buf: Buffer;
	BEGIN
		ASSERT(LEN(x) >= n);
		buf := R.buf; F := buf.F;
		xpos := 0; offset := R.offset;
		WHILE n > 0 DO
			IF (R.org # buf.org) OR (offset >= BufSize) THEN
				set(R, F, R.org + offset); buf := R.buf; offset := R.offset;
			END;
			restInBuf := BufSize - offset;
			IF n < restInBuf THEN min := n ELSE min := restInBuf END;
			S.MOVE(S.ADR(x) + xpos, S.ADR(buf.data) + offset, min);
			INC(offset, min); R.offset := offset;
			IF offset > buf.size THEN INC(F.len, offset - buf.size); buf.size := offset END;
			INC(xpos, min); DEC(n, min); buf.dirty := TRUE
		END;
		R.res := 0 
	END WriteBytes;

(** Portable routines to write and read the standard Oberon types. Each procedure is provided in a read and write pair. *)

	PROCEDURE ReadChar*(VAR R: Rider; VAR x: CHAR);
	BEGIN
		ReadBytes(R, x, 1)
	END ReadChar;

	PROCEDURE ReadSInt*(VAR R: Rider; VAR x: SHORTINT);
	BEGIN
		ReadBytes(R, x, 1)
	END ReadSInt;

	PROCEDURE ReadInt*(VAR R: Rider; VAR x: INTEGER);
	BEGIN
		ReadBytes(R, x, 2)
	END ReadInt;

	PROCEDURE ReadLInt*(VAR R: Rider; VAR x: LONGINT);
	BEGIN
		ReadBytes(R, x, 4)
	END ReadLInt;

	PROCEDURE ReadSet*(VAR R: Rider; VAR x: SET);
	BEGIN
		ReadBytes(R, x, 4)
	END ReadSet;

	PROCEDURE ReadBool*(VAR R: Rider; VAR x: BOOLEAN);
	BEGIN
		Read(R, S.VAL(S.BYTE, x))
	END ReadBool;

	PROCEDURE ReadReal*(VAR R: Rider; VAR x: REAL);
	BEGIN
		ReadBytes(R, x, 4)
	END ReadReal;

	PROCEDURE ReadLReal*(VAR R: Rider; VAR x: LONGREAL);
	BEGIN
		ReadBytes(R, x, 8)
	END ReadLReal;

	PROCEDURE ReadString*(VAR R: Rider; VAR x: ARRAY OF CHAR);
		VAR
			i: LONGINT;
			ch: CHAR;
	BEGIN
		i := 0;
		REPEAT
			Read(R, ch);
			x[i] := ch; INC(i)
		UNTIL ch = 0X
	END ReadString;

(** Reads a number in compressed variable length notation using the minimum amount of bytes. *)
	PROCEDURE ReadNum*(VAR R: Rider; VAR x: LONGINT);
		VAR s: SHORTINT; ch: CHAR; n: LONGINT;
	BEGIN s := 0; n := 0; Read(R, ch);
		WHILE ORD(ch) >= 128 DO INC(n, ASH(ORD(ch) - 128, s) ); INC(s, 7); Read(R, ch) END;
		x := n + ASH(ORD(ch) MOD 64 - ORD(ch) DIV 64 * 64, s)
	END ReadNum;

	PROCEDURE WriteChar*(VAR R: Rider; x: CHAR);
	BEGIN
		WriteBytes(R, x, 1)
	END WriteChar;

	PROCEDURE WriteSInt*(VAR R: Rider; x: SHORTINT);
	BEGIN
		WriteBytes(R, x, 1)
	END WriteSInt;

	PROCEDURE WriteInt*(VAR R: Rider; x: INTEGER);
	BEGIN
		WriteBytes(R, x, 2)
	END WriteInt;

	PROCEDURE WriteLInt*(VAR R: Rider; x: LONGINT);
	BEGIN
		WriteBytes(R, x, 4)
	END WriteLInt;

	PROCEDURE WriteSet*(VAR R: Rider; x: SET);
	BEGIN
		WriteBytes(R, x, 4)
	END WriteSet;

	PROCEDURE WriteBool*(VAR R: Rider; x: BOOLEAN);
	BEGIN
		Write(R, S.VAL(S.BYTE, x))
	END WriteBool;

	PROCEDURE WriteReal*(VAR R: Rider; x: REAL);
	BEGIN
		WriteBytes(R, x, 4)
	END WriteReal;

	PROCEDURE WriteLReal*(VAR R: Rider; x: LONGREAL);
	BEGIN
		WriteBytes(R, x, 8)
	END WriteLReal;

	PROCEDURE WriteString*(VAR R: Rider; x: ARRAY OF CHAR);
		VAR i: LONGINT;
	BEGIN
		i := 0;
		WHILE x[i] # 0X DO INC(i) END;
		WriteBytes(R, x, i+1)
	END WriteString;

(** Writes a number in a compressed format. *)
	PROCEDURE WriteNum*(VAR R: Rider; x: LONGINT);
	BEGIN
		WHILE (x < - 64) OR (x > 63) DO Write(R, CHR(x MOD 128 + 128)); x := x DIV 128 END;
		Write(R, CHR(x MOD 128))
	END WriteNum;

	PROCEDURE write(VAR buf: NPAPI.NPBuffer; len: LONGINT; data: PTR);
	BEGIN
		WITH data: Request DO WriteBytes(data.R, buf, len) END
	END write;

	PROCEDURE destroy(reason: NPAPI.NPError; data: PTR);
	BEGIN
		WITH data: Request DO
			data.proc(data.F, data.data)
		END;
	END destroy;
	
	PROCEDURE RequestURL* (name: ARRAY OF CHAR; notify: Notifier; data: PTR);
		VAR r: Request;
	BEGIN
		NEW(r); r.F := New(""); Set(r.R, r.F, 0);
		r.data := data; r.proc := notify;
		NPAPI.GetLocalFile(name, write, destroy, r)
	END RequestURL;

	PROCEDURE InitAPI();
		VAR mod: LONGINT;
	BEGIN
		mod := Kernel.LoadLibrary("Kernel32");
		Kernel.GetAdr(mod, "SetHandleCount", S.VAL(LONGINT, SetHandleCount));
		Kernel.GetAdr(mod, "GetLastError", S.VAL(LONGINT, GetLastError));
		Kernel.GetAdr(mod, "CreateFileA", S.VAL(LONGINT, CreateFile));
		Kernel.GetAdr(mod, "CloseHandle", S.VAL(LONGINT, CloseHandle));
		Kernel.GetAdr(mod, "SetFilePointer", S.VAL(LONGINT, SetFilePointer));
		Kernel.GetAdr(mod, "GetFileSize", S.VAL(LONGINT, GetFileSize));
		Kernel.GetAdr(mod, "WriteFile", S.VAL(LONGINT, WriteFile));
		Kernel.GetAdr(mod, "ReadFile", S.VAL(LONGINT, ReadFile));
		Kernel.GetAdr(mod, "GetFileTime", S.VAL(LONGINT, GetFileTime));
		Kernel.GetAdr(mod, "SetFileTime", S.VAL(LONGINT, SetFileTime));
		Kernel.GetAdr(mod, "FileTimeToSystemTime", S.VAL(LONGINT, FileTimeToSystemTime));
		Kernel.GetAdr(mod, "SystemTimeToFileTime", S.VAL(LONGINT, SystemTimeToFileTime));
		Kernel.GetAdr(mod, "DeleteFileA", S.VAL(LONGINT, DeleteFile));
		Kernel.GetAdr(mod, "GetTempFileNameA", S.VAL(LONGINT, GetTempFileName));
		Kernel.GetAdr(mod, "CopyFileA", S.VAL(LONGINT, CopyFile));
		Kernel.GetAdr(mod, "MoveFileA", S.VAL(LONGINT, MoveFile));
		ret := SetHandleCount(MaxFiles);
		IF ret # MaxFiles THEN
			err := GetLastError();  HALT(99)
		END
	END InitAPI;

	PROCEDURE Init();
		VAR i: LONGINT;
	BEGIN
		FOR i := 0 TO MaxFiles-1 DO
			FileTab[i] := S.VAL(LONGINT, NIL)
		END
	END Init;

(** Renames a file. res = 0 indicates success. *)
PROCEDURE Rename*(old, new: ARRAY OF CHAR; VAR res: INTEGER);
	VAR
		oF, nF: File;
		oR, nR: Rider;
		t, d: LONGINT;
		ch: CHAR;
BEGIN
	FileDir.ResetPath;
	res := 1; oF := Old(old);
	IF oF # NIL THEN
		GetDate(oF, t, d); Set(oR, oF, 0);
		nF := New(new); Set(nR, nF, 0);
		Read(oR, ch);
		WHILE ~oR.eof DO
			Write(nR, ch); Read(oR, ch)
		END;
		Register(nF); SetDate(nF, t, d);
		Delete(old, res)
	END; 
END Rename;

BEGIN
	InitAPI(); Init()
END JuiceFiles.

(** Remarks:

1. Oberon uses the little-endian byte ordering for exchanging files between different Oberon platforms.

2. Files are separate entities from directory entries. Files may be anonymous by having no name and not being registered in a
	directory. Files only become visible to other clients of the Files module by explicitly passing a File descriptor or by registering
	a file and then openening it from the other client. Deleting a file of which a file descriptor is still used, results in the file
	being renamed to a temporary file. The deleted file may be re-registered at any time.

3. Files and their access mechanism (Riders) are separated. A file might have more than one rider operating on it at different
	offsets in the file.

4. The garbage collector will automatically close files when they are not required any more. File buffers will be discarded
	without flushing them to disk.

5. Relative and absolute filenames written in the directory syntax of the host operating system is used. By convention, Oberon
	filenames consists of the letters A..Z, a..z, 0..9, and ".". The directory separator is typically /, \ or :. Oberon filenames are
	case sensitive (not true for this implementation!!!). *)