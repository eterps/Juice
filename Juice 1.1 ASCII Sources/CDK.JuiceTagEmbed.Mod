MODULE JuiceTagEmbed;	(* tk / 13.3.96 *)

	IMPORT Attributes, Texts, HTMLDocs, JuiceApplets;

	PROCEDURE ExtractSuffix(VAR name, suffix: ARRAY OF CHAR);
		VAR i, j: INTEGER;
	BEGIN
		i := 0; j := 0;
		WHILE name[i] # 0X DO
			IF name[i] = "." THEN j := i + 1 END;
			INC(i)
		END;
		i := 0;
		IF j > 0 THEN
			WHILE (name[j] # 0X) & (i < 3) DO
				suffix[i] := name[j];
				INC(i); INC(j)
			END
		END;
		suffix[i] := 0X
	END ExtractSuffix;

	PROCEDURE LoadOmegaApplet(VAR S: HTMLDocs.Scanner; VAR name: ARRAY OF CHAR; width, heigth: INTEGER);
		VAR F: JuiceApplets.Frame; 
	BEGIN
		NEW(F); 
		JuiceApplets.NewFrame(F, S.page.base, name, width, heigth);
		HTMLDocs.WriteObj(S.page, F);
	END LoadOmegaApplet;

	PROCEDURE *Handle(VAR S: HTMLDocs.Scanner; on: BOOLEAN);
		VAR attr, file, suffix: ARRAY 64 OF CHAR; width, height: LONGINT;
	BEGIN
		WHILE HTMLDocs.NextAttr(S, attr) DO
			IF attr = "SRC" THEN
				COPY(S.value, file)
			ELSIF attr = "WIDTH" THEN
				Attributes.StrToInt(S.value, width)
			ELSIF attr = "HEIGHT" THEN
				Attributes.StrToInt(S.value, height)
			ELSIF attr = "ALIGN" THEN
			END
		END;
		
		ExtractSuffix(file, suffix);
		
		IF suffix = "adf" THEN LoadOmegaApplet(S, file, SHORT(width), SHORT(height))
		ELSE (* ... *)
		END
	END Handle;

	PROCEDURE *Start(P: HTMLDocs.Page);
	BEGIN
	END Start;

	PROCEDURE *Stop(P: HTMLDocs.Page);
	BEGIN
	END Stop;

	PROCEDURE New*;
		VAR e: HTMLDocs.ExtTag;
	BEGIN
		NEW(e);
		e.handle := Handle; (* called when tag is found in the current page. *)
		e.start := Start; (* called when the first Skeleton tag is found in the current page. *)
		e.stop := Stop; (* called when the current page is finished. *)
		HTMLDocs.newTag := e
	END New;

END JuiceTagEmbed.

System.Free JuiceTagEmbed ~
System.Set HTMLTags EMBED := JuiceTagEmbed.New ~



