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

MODULE JuiceFileDir; (* FileDir for Oberon for Windows 95/NT, ejz 31.1.95 *)
	IMPORT S := SYSTEM, Kernel:= JuiceKernel (*, Registry *);

(* Base on FileDir from MH Feb 93 / 2.6.94 jm 6.7.95 *)

(** The FileDir module implements the naming of files in directories. *)

	CONST
		False = 0;
		MaxName = 260+1;
		WinPathChar = "\";
		pathChar = "/";
		WorkingDirectory = "Juice";

	TYPE
		FileName* = ARRAY MaxName OF CHAR;

	VAR
		GetLastError: PROCEDURE (): LONGINT;
		GetCurrentDirectory: PROCEDURE (lenCurDir, curDir: LONGINT): LONGINT;
		SetCurrentDirectory: PROCEDURE (curDir: LONGINT): LONGINT;
		GetTempPath: PROCEDURE (lenTempDir, tempDir: LONGINT): LONGINT;
		GetFullPathName: PROCEDURE (file, path, lenPath: LONGINT; VAR pos: LONGINT): LONGINT;
		GetFileAttributes: PROCEDURE (fileName: LONGINT): LONGINT;
		createDirectory: PROCEDURE (newDir, lpsa: LONGINT): LONGINT;
		SearchPath: PROCEDURE (path, file, ext, lenBuf, buf: LONGINT; VAR lpLPart: LONGINT): LONGINT;
		RemoveDirectory: PROCEDURE (path: LONGINT): LONGINT;
		FindFirstFile: PROCEDURE (searchFile, lpFD: LONGINT): LONGINT;
		FindNextFile: PROCEDURE (hFindFile, lpFD: LONGINT): LONGINT;
		FindClose: PROCEDURE (hFindFile: LONGINT): LONGINT;
		FileTimeToSystemTime: PROCEDURE (lpFT, lpST: LONGINT): LONGINT;
		ret, err: LONGINT;
		workPath: FileName;
		PathChar-: CHAR; (** directory separator *)

 (** Replace all occurences of character from in name by to. *)
	PROCEDURE ConvertChar*(VAR name: ARRAY OF CHAR; from, to: CHAR);
		VAR i: LONGINT;
	BEGIN
		i := 0;
		WHILE name[i] # 0X DO
			IF name[i] = from THEN
				name[i] := to
			END;
			INC(i)
		END
	END ConvertChar;

 (** Search the (relative) filename name in the current directory. If it could not be found all directories in the search path
 	are searched for name. fileName returns the full (absolute) name for the file found. *)
	PROCEDURE FindFile*(VAR relFileName, fileName: ARRAY OF CHAR; useSearchPath: BOOLEAN): BOOLEAN;
		VAR i: LONGINT;
	BEGIN
		ConvertChar(relFileName, pathChar, WinPathChar);
		ret := SearchPath(S.ADR(workPath), S.ADR(relFileName), 0, LEN(fileName), S.ADR(fileName), i);
		ConvertChar(fileName, WinPathChar, pathChar);
		RETURN ret > 0
	END FindFile;

	PROCEDURE CheckPath(VAR fullName: ARRAY OF CHAR): BOOLEAN;
		VAR
			wpath: FileName;
			i, j, k: LONGINT;
	BEGIN
		ret := GetCurrentDirectory(LEN(wpath), S.ADR(wpath));
		IF ret <= 0 THEN
			err := GetLastError(); HALT(99)
		END;
		i := 0; j := -1;
		WHILE fullName[i] # 0X DO
			IF fullName[i] = WinPathChar THEN
				j := i
			END;
			INC(i)
		END;
		IF j > 0 THEN
			fullName[j] := 0X
		END;
		k := SetCurrentDirectory(S.ADR(fullName));
		IF j > 0 THEN
			fullName[j] := WinPathChar
		END;
		ret := SetCurrentDirectory(S.ADR(wpath));
		IF ret = False THEN
			err := GetLastError(); HALT(99)
		END;
		RETURN k # False
	END CheckPath;

(** Change to directory path. *)
	PROCEDURE ChangeDirectory*(path: ARRAY OF CHAR; VAR done: BOOLEAN);
	BEGIN
		ConvertChar(path, pathChar, WinPathChar);
		ret := SetCurrentDirectory(S.ADR(path));
		IF ret = False THEN
			err := GetLastError()
		ELSE
			ret := GetCurrentDirectory(LEN(workPath), S.ADR(workPath));
			IF ret <= 0 THEN
				err := GetLastError(); HALT(99)
			END
		END;
		done := ret # False
	END ChangeDirectory;

(** Create a new directory. *)
	PROCEDURE CreateDirectory*(path: ARRAY OF CHAR; VAR done: BOOLEAN);
	BEGIN
		ConvertChar(path, pathChar, WinPathChar);
		ret := createDirectory(S.ADR(path), 0);
		IF ret = False THEN
			err := GetLastError()
		END;
		done := ret # False
	END CreateDirectory;

(** Get the directory for temporary files. *)
	PROCEDURE GetTempDirectory*(VAR path: ARRAY OF CHAR);
	BEGIN
		ret := GetTempPath(LEN(path), S.ADR(path));
		IF ret <= 0 THEN
			err := GetLastError(); HALT(99)
		END;
		ConvertChar(path, WinPathChar, pathChar)
	END GetTempDirectory;

(** Compare two filenames. *)
	PROCEDURE SameName*(VAR a, b: ARRAY OF CHAR): BOOLEAN;
		VAR i, j: LONGINT;
	BEGIN
		i := 0; j := 0;
		WHILE (CAP(a[i]) = CAP(b[j])) & (a[i] # 0X) & (b[j] # 0X) DO
			INC(i); INC(j)
		END;
		RETURN (a[i] = 0X) & (b[j] = 0X)
	END SameName;

	PROCEDURE CheckName*(name: ARRAY OF CHAR): BOOLEAN;
		VAR
			fullName: FileName;
			i: LONGINT;
			ch: CHAR;
	BEGIN
		ConvertChar(name, pathChar, WinPathChar);
		ret := GetFullPathName(S.ADR(name), LEN(fullName), S.ADR(fullName), i);
		IF ret <= 0 THEN
			err := GetLastError(); RETURN FALSE
		ELSIF ~CheckPath(fullName) THEN
			RETURN FALSE
		ELSE
			i := i-S.ADR(fullName);
			fullName[i-1] := 0X; ch := fullName[i];
			WHILE ch # 0X DO
				IF ~( ((CAP(ch) >= "A") & (CAP(ch) <= "Z"))  OR  ((ch >= "0") & (ch <= "9"))  OR
						(ch = ".") OR (ch = "_") OR (ch = "-") ) THEN RETURN FALSE
				END;
				INC(i); ch := fullName[i]
			END;
			RETURN TRUE
		END
	END CheckName;

	PROCEDURE InitAPI();
		VAR mod: LONGINT;
	BEGIN
		mod := Kernel.LoadLibrary("Kernel32");
		Kernel.GetAdr(mod, "GetLastError", S.VAL(LONGINT, GetLastError));
		Kernel.GetAdr(mod, "GetCurrentDirectoryA", S.VAL(LONGINT, GetCurrentDirectory));
		Kernel.GetAdr(mod, "GetFullPathNameA", S.VAL(LONGINT, GetFullPathName));
		Kernel.GetAdr(mod, "GetFileAttributesA", S.VAL(LONGINT, GetFileAttributes));
		Kernel.GetAdr(mod, "SetCurrentDirectoryA", S.VAL(LONGINT, SetCurrentDirectory));
		Kernel.GetAdr(mod, "GetTempPathA", S.VAL(LONGINT, GetTempPath));
		Kernel.GetAdr(mod, "CreateDirectoryA", S.VAL(LONGINT, createDirectory));
		Kernel.GetAdr(mod, "SearchPathA", S.VAL(LONGINT, SearchPath));
		Kernel.GetAdr(mod, "RemoveDirectoryA", S.VAL(LONGINT, RemoveDirectory));
		Kernel.GetAdr(mod, "FindFirstFileA", S.VAL(LONGINT, FindFirstFile));
		Kernel.GetAdr(mod, "FindNextFileA", S.VAL(LONGINT, FindNextFile));
		Kernel.GetAdr(mod, "FindClose", S.VAL(LONGINT, FindClose));
		Kernel.GetAdr(mod, "FileTimeToSystemTime", S.VAL(LONGINT, FileTimeToSystemTime))
	END InitAPI;

	PROCEDURE Init();
		VAR
			done: BOOLEAN;
	BEGIN
		PathChar := pathChar;
		ret := GetCurrentDirectory(LEN(workPath), S.ADR(workPath));
		IF ret <= 0 THEN
			err := GetLastError(); HALT(99)
		END;
		ChangeDirectory(WorkingDirectory, done);
		IF ~done THEN 
			CreateDirectory(WorkingDirectory, done);
			IF ~done THEN HALT(77) END;
			ChangeDirectory(WorkingDirectory, done);
			IF ~done THEN HALT(77) END
		END;
	END Init;

	PROCEDURE ResetPath*;
		VAR done: BOOLEAN;
	BEGIN
		ChangeDirectory(workPath, done);
	END ResetPath;

BEGIN
	InitAPI(); Init();
END JuiceFileDir.

(** Remarks:

1. Newly created files are always written in the working directory when no absolute filename is specified. Opening a file
searches in the current directory, followed by each directory in the path in return.

2. The search path for files is specified by the Directories key in the System section of the Registry. *)