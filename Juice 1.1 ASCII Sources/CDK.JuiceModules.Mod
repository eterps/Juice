MODULE JuiceModules;

	IMPORT SYSTEM, JuiceFiles, Modules, Files, FileDir, Registry, Strings;
	
	
	CONST
		SectionName = "Juice";

	TYPE
		Module* = POINTER TO ModDesc;
		ModDesc = RECORD mod: Modules.Module END;
		Command* = PROCEDURE;
		NotifierProc* = PROCEDURE (M: Module; data: PTR);
	
	VAR
		DirectoryName: ARRAY 256 OF CHAR;
			
	PROCEDURE ReadString(VAR R: JuiceFiles.Rider; VAR string: ARRAY OF CHAR);
		VAR i: INTEGER; ch: CHAR;
	BEGIN	i:=0;
		LOOP	JuiceFiles.ReadChar(R, ch);
			IF	ch=0X	THEN	string[i]:=0X; RETURN
			ELSIF	ch < 7FX	THEN	string[i]:=ch; INC(i)	
			ELSIF	ch > 7FX	THEN	string[i]:=CHR(ORD(ch)-80H); string[i+1]:=0X; RETURN
			ELSE	(* ch = 7FX *)	EXIT	(* continue reading uncompressed string *)
			END
		END;
		LOOP	JuiceFiles.ReadChar(R, ch);
			IF	ch=0X	THEN	string[i]:=0X; RETURN
			ELSE	string[i]:=ch; INC(i)	END
		END;
	END ReadString;

	PROCEDURE ThisMod* (name: ARRAY OF CHAR): Module;
		VAR mod: Modules.Module; iname, fname: ARRAY 64 OF CHAR; F: JuiceFiles.File; R, R1: JuiceFiles.Rider; ch0, ch1: CHAR;
		i, size: LONGINT; res: INTEGER; m, imp: Module;
	BEGIN
		mod := Modules.ThisMod(name);
		IF mod = NIL THEN
			COPY(name, fname); i:=0;
			WHILE fname[i]#0X DO INC(i) END;
			fname[i]:="."; fname[i+1]:="O"; fname[i+2]:="b"; fname[i+3]:="j"; fname[i+4]:=0X;
			
			F := JuiceFiles.LoadURL(fname);
			IF F # NIL THEN
				JuiceFiles.Set(R, F, 0);
				JuiceFiles.ReadChar(R, ch0); JuiceFiles.ReadChar(R, ch1);
				IF (ch0 = 0BBX) & (ch1 = 088X) THEN 
					JuiceFiles.ReadNum(R, size); R1:=R; JuiceFiles.Set(R1, JuiceFiles.Base(R1), JuiceFiles.Pos(R1)+size); 
					ReadString(R, iname);
					WHILE iname#"" DO 
						imp := ThisMod(iname);
						ReadString(R, iname);
					END;
					JuiceFiles.ReadNum(R1, size); JuiceFiles.ReadNum(R1, size); JuiceFiles.ReadNum(R1, size); 
					ReadString(R1, iname);
					WHILE iname#"" DO 
						imp := ThisMod(iname); 
						ReadString(R1, iname);
					END;
					JuiceFiles.Register(F);
					mod := Modules.ThisMod(name);
					COPY(DirectoryName, iname);
					Strings.Append(iname, fname);
					Files.Delete(iname, res)
				END
			END
		END;
		IF mod = NIL THEN RETURN NIL
		ELSE NEW(m); m.mod:= mod; RETURN m
		END
	END ThisMod;
	
	PROCEDURE LoadMod* (name: ARRAY OF CHAR; proc: NotifierProc; data: PTR);
	BEGIN proc(ThisMod(name), data)
	END LoadMod;
	
	PROCEDURE ThisCommand* (mod: Module; name: ARRAY OF CHAR): Command;
	BEGIN RETURN SYSTEM.VAL(Command, Modules.ThisCommand(mod.mod, name))
	END ThisCommand;

BEGIN
	Registry.Get(SectionName, "Directory", DirectoryName);
	Strings.AppendCh(DirectoryName, FileDir.PathChar);
END JuiceModules.