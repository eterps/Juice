MODULE JuiceDocs;	(* tk / 13.3.96 *)

	IMPORT Objects, Documents, JuiceApplets, Display, Oberon, Attributes, Desktops, Strings;

	PROCEDURE Load(D: Documents.Document);
		VAR F: JuiceApplets.Frame; url: ARRAY 64 OF CHAR;
	BEGIN
		NEW(F); JuiceApplets.Init(F); 
		COPY("file://", url);
		Strings.Append(url, D.name);
		JuiceApplets.NewFrame(F, NIL, url, 200, 200);
		Documents.Init(D, F); 
	END Load;

	PROCEDURE Handler(D: Objects.Object; VAR M: Objects.ObjMsg);
	BEGIN
		WITH D: Documents.Document DO
			IF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF M.id = Objects.get THEN
						IF M.name = "Gen" THEN M.class := Objects.String; M.s := "JuiceDocs.NewDoc"; M.res := 0
						ELSIF M.name = "Menu" THEN M.class := Objects.String;
							M.s := ""; M.res := 0
						ELSE Documents.Handler(D, M)
						END
					ELSE Documents.Handler(D, M)
					END
				END
			ELSIF (M IS Display.DisplayMsg) & (M(Display.DisplayMsg).device = Display.printer) THEN
				M(Display.DisplayMsg).F := D.dsc; 
				D.dsc.handle(D.dsc, M)
			ELSE Documents.Handler(D, M)
			END
		END
	END Handler;
	
	PROCEDURE InitDoc (D: Documents.Document);
	BEGIN
		D.Load := Load;
		D.handle := Handler;
		D.W := 250; D.H := 200;
	END InitDoc;

	PROCEDURE NewDoc*;
		VAR D: Documents.Document;
	BEGIN
		NEW(D); InitDoc(D); Objects.NewObj := D
	END NewDoc;

(*
	PROCEDURE CreateApplet*;
		VAR D: Documents.Document; F: JuiceApplets.Frame; S: Attributes.Scanner;
	BEGIN
		NEW(D); InitDoc(D);
		Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		Attributes.Scan(S);
		IF S.class IN {Attributes.String, Attributes.Name} THEN
			NEW(F); JuiceApplets.NewFrame(F, S.s, 200, 200);
			Documents.Init(D, F);
			D.name := "Applet";
			D.W := 200; D.H := 200;
			Desktops.ShowDoc(D)
		END
	END CreateApplet;
*)
BEGIN
END JuiceDocs.

System.Free JuiceDocs ~
Desktops.OpenDoc Test (JuiceDocs.NewDoc)
