MODULE JuiceFiles;	(*mf 10.11.94/tk 27.10.95*)

	IMPORT
		Registry, Files, FileDir, Strings, HyperDocs, NetTools, HTTPDocs0, Out;
		
	CONST
		SectionName = "Juice";

	TYPE
		FileName = ARRAY 256 OF CHAR;
		File* = POINTER TO Handle;
		Handle = RECORD 
			F: Files.File;
		END;
		
		Rider* = RECORD
			res*: LONGINT;
			eof*: BOOLEAN;
			R: Files.Rider;
		END;
		
		Notifier* = PROCEDURE (F: File; data: PTR);
		
	VAR
		base, lastbase: HyperDocs.DefURL;
		DirectoryName: ARRAY 256 OF CHAR;
		
(* Oberon Routines *)

	PROCEDURE Update(VAR R: Rider);
	BEGIN
		R.res := R.R.res;
		R.eof := R.R.eof;
	END Update;

	PROCEDURE MakeName(VAR name0, name1: ARRAY OF CHAR);
		VAR i, j: INTEGER; ch: CHAR;
	BEGIN	
		i:=0; j:=0;
		REPEAT	ch:=name0[i]; INC(i);
			IF	(ch=":") OR (ch=FileDir.PathChar)	THEN	j:=i	END
		UNTIL	ch=0X;
		(*	IF j#0 THEN name1[0]:=0X; RETURN END;	*)
		COPY(DirectoryName, name1); i:= 0; WHILE name1[i] # 0X DO INC(i) END;
		ch:=name0[j];
		WHILE	ch#0X	DO
			name1[i]:=ch; INC(i);
			INC(j); ch:=name0[j]
		END; 
		name1[i]:=0X
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


	(** Open an existing file. The same file descriptor is returned if a file is opened multiple times. *)
	PROCEDURE Old*(name: ARRAY OF CHAR): File;
		VAR F: Files.File; F1: File; name2: FileName;
	BEGIN 
		MakeName(name, name2);
		F := Files.Old(name2);
		IF F # NIL THEN NEW(F1); F1.F := F; RETURN F1
		ELSE RETURN NIL
		END
	END Old;

	(** Flushes the changes made to a file to disk. Register will automatically Close a file. *)
	PROCEDURE Close*(f: File);
	BEGIN 
		IF f # NIL THEN Files.Close(f.F) END
	END Close;

	(** Register a file created with New in the directory, replacing the previous file in the directory with the same name. The file is automatically closed. *)
	PROCEDURE Register*(f: File);
	BEGIN 
		IF f # NIL THEN Files.Register(f.F) END
	END Register;


	(** Deletes a file. res = 0 indicates success. *)
	PROCEDURE Delete*(name: ARRAY OF CHAR; VAR res: INTEGER);
		VAR name2: FileName;
	BEGIN 
		MakeName(name, name2);
		Files.Delete(name2, res)
	END Delete;

	(** Renames a file. res = 0 indicates success. *)
	PROCEDURE Rename*(old, new: ARRAY OF CHAR; VAR res: INTEGER);
		VAR old2, new2: FileName;
	BEGIN 
		MakeName(old, old2); MakeName(new, new2);
		Files.Rename(old2, new2, res)
	END Rename;


	(** Deletes a file. *)
	PROCEDURE Purge*(f: File);
	BEGIN 
	END Purge;

	(** Returns length of file in bytes *)
	PROCEDURE Length*(f: File): LONGINT;
	BEGIN 
		IF f # NIL THEN RETURN Files.Length(f.F) ELSE RETURN 0 END
	END Length;

	(** Returns the time (t) and date (d) of a file. *)
	PROCEDURE GetDate*(f: File; VAR t, d: LONGINT);
	BEGIN 
		IF f # NIL THEN Files.GetDate(f.F, t, d) END
	END GetDate;

	(** Returns the name of the file *)
	PROCEDURE GetName*(f: File; VAR name: ARRAY OF CHAR);
		VAR name2: FileName;
	BEGIN 
		IF f # NIL THEN Files.GetName(f.F, name2) END;
		ReMakeName(name2, name);
	END GetName;

	(** Positions a Rider at a certain position in a file. Multiple Riders can be positioned at different locations in a file. A Rider cannot be positioned beyond the end of a file. *)
	PROCEDURE Set*(VAR r: Rider; f: File; pos: LONGINT);
	BEGIN 
		IF f # NIL THEN Files.Set(r.R, f.F, pos); Update(r) END;
	END Set;


	(** Returns the File a Rider is based on. *)
	PROCEDURE Base*(VAR r: Rider): File;
		VAR F: Files.File; F1: File;
	BEGIN 
		F := Files.Base(r.R);
		IF F # NIL THEN NEW(F1); F1.F := F; RETURN F1
		ELSE RETURN NIL
		END
	END Base;

	(** Returns the offset of a Rider positioned on a file. *)
	PROCEDURE Pos*(VAR r: Rider): LONGINT;
	BEGIN RETURN Files.Pos(r.R)
	END Pos;


(* Extended Routines *)

	PROCEDURE ReadChar*(VAR R: Rider; VAR x: CHAR);
	BEGIN Files.Read(R.R, x); Update(R)
	END ReadChar;

	PROCEDURE ReadSInt*(VAR R: Rider; VAR x: SHORTINT);
	BEGIN Files.Read(R.R, x); Update(R)
	END ReadSInt;

	PROCEDURE ReadInt*(VAR R: Rider; VAR x: INTEGER);
	BEGIN Files.ReadInt(R.R, x); Update(R)
	END ReadInt;

	PROCEDURE ReadLInt*(VAR R: Rider; VAR x: LONGINT);
	BEGIN Files.ReadLInt(R.R, x); Update(R)
	END ReadLInt;

	PROCEDURE ReadSet*(VAR R: Rider; VAR x: SET);
	BEGIN Files.ReadSet(R.R, x); Update(R)
	END ReadSet;

	PROCEDURE ReadBool*(VAR R: Rider; VAR x: BOOLEAN);
	BEGIN Files.ReadBool(R.R, x); Update(R)
	END ReadBool;

	PROCEDURE ReadReal*(VAR R: Rider; VAR x: REAL);
	BEGIN Files.ReadReal(R.R, x); Update(R)
	END ReadReal;

	PROCEDURE ReadLReal*(VAR R: Rider; VAR x: LONGREAL);
	BEGIN Files.ReadLReal(R.R, x); Update(R)
	END ReadLReal;

	PROCEDURE ReadString*(VAR R: Rider; VAR x: ARRAY OF CHAR);
	BEGIN Files.ReadString(R.R, x); Update(R)
	END ReadString;

	PROCEDURE ReadNum*(VAR R: Rider; VAR x: LONGINT);
	BEGIN Files.ReadNum(R.R, x); Update(R)
	END ReadNum;



	PROCEDURE WriteChar*(VAR R: Rider; x: CHAR);
	BEGIN Files.Write(R.R, x); Update(R)
	END WriteChar;

	PROCEDURE WriteSInt*(VAR R: Rider; x: SHORTINT);
	BEGIN Files.Write(R.R, x); Update(R)
	END WriteSInt;

	PROCEDURE WriteInt*(VAR R: Rider; x: INTEGER);
	BEGIN Files.WriteInt(R.R, x); Update(R)
	END WriteInt;

	PROCEDURE WriteLInt*(VAR R: Rider; x: LONGINT);
	BEGIN Files.WriteLInt(R.R, x); Update(R)
	END WriteLInt;

	PROCEDURE WriteSet*(VAR R: Rider; x: SET);
	BEGIN Files.WriteSet(R.R, x); Update(R)
	END WriteSet;

	PROCEDURE WriteBool*(VAR R: Rider; x: BOOLEAN);
	BEGIN Files.WriteBool(R.R, x); Update(R)
	END WriteBool;

	PROCEDURE WriteReal*(VAR R: Rider; x: REAL);
	BEGIN Files.WriteReal(R.R, x); Update(R)	
	END WriteReal;

	PROCEDURE WriteLReal*(VAR R: Rider; x: LONGREAL);
	BEGIN Files.WriteLReal(R.R, x); Update(R)
	END WriteLReal;

	PROCEDURE WriteString*(VAR R: Rider; x: ARRAY OF CHAR);
	BEGIN Files.WriteString(R.R, x); Update(R)
	END WriteString;

	PROCEDURE WriteNum*(VAR R: Rider; x: LONGINT);
	BEGIN Files.WriteNum(R.R, x); Update(R)
	END WriteNum;


	(** Creates a new file with the specified name. The same file descriptor is not returned with multiple calls the New with the same filename (this results in multiple copies of a file with the same name. i.e. the files are not registered in the directory). *)
	PROCEDURE New*(name: ARRAY OF CHAR): File;
		VAR F: Files.File; F1: File; name2: FileName;
	BEGIN 
		MakeName(name, name2);
		F := Files.New(name2); 
		IF F # NIL THEN NEW(F1); F1.F := F; RETURN F1
		ELSE RETURN NIL
		END
	END New;

	PROCEDURE GetBase* (VAR base: HyperDocs.DefURL);
	BEGIN base := lastbase
	END GetBase;

	PROCEDURE SetBase* (newbase: HyperDocs.DefURL);
	BEGIN base := newbase;
	END SetBase;

	PROCEDURE BASE(key: LONGINT);
		VAR
			value: ARRAY HyperDocs.PrefixStrLen+NetTools.ServerStrLen+NetTools.PathStrLen+8 OF CHAR;
			label: ARRAY 64 OF CHAR;
			s: HyperDocs.LinkScheme;
	BEGIN
		s := HyperDocs.LinkSchemeByKey(key);
		IF s # NIL THEN
			NEW(lastbase);
			lastbase.key := key;
			COPY(s.prefix, lastbase.prefix);
			HyperDocs.RetrieveLink(key, value);
			IF lastbase.prefix = "http" THEN
				lastbase.key := HTTPDocs0.SplitHTTPAdr(value, lastbase.host, lastbase.path, label, lastbase.port)
			ELSIF lastbase.prefix = "file" THEN
				lastbase.key := HyperDocs.SplitFileAdr(value, lastbase.path, label);
				lastbase.host := ""; lastbase.port := 0
			ELSE
				HALT(99)
			END
		ELSE lastbase := base
		END
	END BASE;

	PROCEDURE LoadURL* (name: ARRAY OF CHAR): File;
		VAR key: LONGINT; FM: HyperDocs.FetchMsg; L: HyperDocs.LinkScheme;
			F: Files.File; F1: File; fname, outputDir: ARRAY 64 OF CHAR; i, j: INTEGER;
	BEGIN
		FM.res := -1;
				
		FM.key := HyperDocs.BuildKey(base, name);
		key := FM.key;
		IF FM.key # HyperDocs.UndefKey THEN
			BASE(key);
			L := HyperDocs.LinkSchemeByKey(FM.key);
			IF L # NIL THEN
				COPY(DirectoryName, fname); 
				i := 0; j := 0; WHILE name[i] # 0X DO
					IF name[i] = FileDir.PathChar THEN j := i + 1 END;
					INC(i)
				END;
				i := 0; WHILE fname[i] # 0X DO INC(i) END;
				WHILE name[j] # 0X DO fname[i] := name[j]; INC(i); INC(j) END;
				fname[i]:= 0X;
				F := Files.New(fname);
				IF F # NIL THEN
					Files.Set(FM.R, F, 0);
					L.handle(L, FM);
					IF FM.res = 0 THEN NEW(F1); F1.F := F; RETURN F1
					ELSE RETURN NIL
					END
				ELSE
					Out.String("Directory "); Out.String(DirectoryName);
					Out.String(" cannot be located in the current working directory."); Out.Ln;
					RETURN NIL
				END
			ELSE RETURN NIL
			END
		END
	END LoadURL;

	(** Request a file *)
	PROCEDURE RequestURL* (name: ARRAY OF CHAR; notify: Notifier; data: PTR);
	BEGIN
		notify(LoadURL(name), data)
	END RequestURL;

BEGIN 				
	Registry.Get(SectionName, "Directory", DirectoryName);
	Strings.AppendCh(DirectoryName, FileDir.PathChar);
END JuiceFiles.
