MODULE JuiceApplets;

	IMPORT JuiceDevices, HTTPDocs, HTMLDocs, JuiceFiles, JuiceModules, Input, Modules, Gadgets, 
		Printer, Objects, Files, Display, Oberon, Display3, Reals, HyperDocs;

	CONST
		(** Parameter symbol classes.*)
		Inval* = 0;          (** Invalid symbol. *)
		String* = 2;        (** string s (length len). *)
		Int* = 3;             (** Integer i (decimal or hexadecimal). *)
		Real* = 4;          (** Real number x. *)
		LongReal* = 5;  (** Long real number y. *)
		Char* = 6;          (** Special character c. *)
		NotFound* = 7;	(** Parameter not found *)

		update* = 0; resize* = 1;	(** DisplayMsg modes *)
		get* = 0; lose* = 1;	(** FocusMsg modes *)
		
	TYPE		
		(** Base type of all messages sent to applets. *)
		AppletMsg* = RECORD END;		
		
		(** Applets receive mouse messages to respond to mouse movement and button clicks. *)
		MouseMsg* = RECORD (AppletMsg)	
			x*, y*: INTEGER;			
			buttons*: SET
		END;
		
		(** Applets receive keyboard messages to respond to keyboard input. *)
		KeyboardMsg* = RECORD (AppletMsg) 
			ch*: CHAR
		END;
		
		(* Applets should redraw all its contents when receiving display messages. *)
		DisplayMsg* = RECORD (AppletMsg)
			id*: SHORTINT;	(** draw, resize *)
		END;

		(** Applets are notified when they get or loose the focus *)
		FocusMsg* = RECORD (AppletMsg)
			id*: SHORTINT;	(** set, loose *)
		END;

			(** An init message is sent to every applet after it has been allocated. *)
		InitMsg* = RECORD (AppletMsg) END;

		(** A destroy message is sent to every applet before reclaiming its storage. *)
		DestroyMsg* = RECORD (AppletMsg) END;
		
		(** Idle messages are sent to applets at fixed time intervals to facilitate background tasks. *)
		IdleMsg* = RECORD (AppletMsg) END;


		Applet* = POINTER TO AppletDesc;
		Handler* = PROCEDURE (applet: Applet; VAR M: AppletMsg);
		AppletDesc* = RECORD
			handle*: Handler;	(** message handler *)
			device-: JuiceDevices.Device;	(** Applet's output device to draw to *)
			link: Applet;
			urlbase: HyperDocs.DefURL;
			params: JuiceFiles.Rider;
			w, h: INTEGER; inited: BOOLEAN
		END;
				
		Frame* = POINTER TO FrameDesc;
		FrameDesc* = RECORD (Gadgets.FrameDesc)
			applet*: Applet;
			adf: ARRAY 64 OF CHAR;
		END;
		
		Param* = RECORD
			class*: INTEGER;	(** Scan result: Int, Real, String etc. *)
			i*: LONGINT;
			x*: REAL;
			y*: LONGREAL;
			c*: CHAR;
			s*: ARRAY 256 OF CHAR;
			len*: SHORTINT;	(** Length of name or string scanned. *)
			nextCh: CHAR;
			R: JuiceFiles.Rider;
		END;
		
		BackgroundTaskMsg = RECORD (Display.FrameMsg) END;
		
		VisibilityMsg = RECORD (Display.FrameMsg)
			applet: Applet;
			visible: BOOLEAN;
		END;
				
	VAR
		newApplet*, appletList: Applet;
		dummy, focus: Frame;
		
	(* Generic Applet *)	
		
	PROCEDURE SplitName (VAR name, MName, PName: ARRAY OF CHAR);
		VAR i, j: INTEGER;
	BEGIN i := 0;
		WHILE (name[i] # 0X) & (name[i] # ".") DO MName[i] := name[i]; INC(i) END;
		MName[i] := 0X; 
		IF name[i] # 0X THEN INC(i) END; j := 0;
		WHILE name[i] # 0X DO PName[j] := name[i]; INC(i); INC(j) END;
		PName[j] := 0X
	END SplitName;
	
	PROCEDURE AppletHandler* (me: Applet; VAR M: AppletMsg);
	BEGIN
		IF M IS DisplayMsg THEN
			JuiceDevices.Setup(me.device);
			JuiceDevices.FrameRect(0, 0, me.device.w, me.device.h);
			JuiceDevices.String(10, 10, "Applet not found!");
			JuiceDevices.Restore(me.device)
		END
	END AppletHandler;
	
	PROCEDURE NewGenericApplet(w, h: INTEGER);
	BEGIN
		NEW(newApplet);
		newApplet.link := appletList; appletList := newApplet;
		newApplet.handle := AppletHandler;
		JuiceDevices.InitMainDevice(newApplet.device, w, h, FALSE); 
	END NewGenericApplet;

	PROCEDURE NewApplet*(command: ARRAY OF CHAR; w, h: INTEGER);
		VAR modname, cmdname: ARRAY 32 OF CHAR; mod: JuiceModules.Module; proc: JuiceModules.Command;
	BEGIN
		newApplet:= NIL;
		SplitName(command, modname, cmdname);
		mod := JuiceModules.ThisMod(modname);
		(* IF mod = NIL THEN mod := JuiceModules.ThisMod(modname) END; *)
		IF (mod # NIL) & (Modules.res = 0) THEN
			proc := JuiceModules.ThisCommand(mod, cmdname);
			IF Modules.res = 0 THEN
				proc()
			END
		END;
		IF (Modules.res # 0) OR (newApplet = NIL) THEN NEW(newApplet) END;
		newApplet.link := appletList; appletList := newApplet;
		IF newApplet.handle = NIL THEN newApplet.handle := AppletHandler END;
		JuiceDevices.InitMainDevice(newApplet.device, w, h, FALSE); 
	END NewApplet;
	
	
	(* Frame Handler *)
	
	PROCEDURE PP(x: INTEGER): INTEGER;
	BEGIN RETURN SHORT(x * LONG(10000) DIV Printer.Unit)
	END PP;

	PROCEDURE Restore(F: Frame; Q: Display3.Mask; x, y, w, h: INTEGER; background: BOOLEAN);
		VAR D: DisplayMsg; IM: InitMsg;
	BEGIN
		IF background THEN Display3.ReplConst(Q, Display3.textbackC, x, y, w, h, Display.replace) END; 
		IF ~F.applet.inited THEN F.applet.handle(F.applet, IM); F.applet.inited := TRUE END;
		IF (F.applet.device.w # F.applet.w) OR (F.applet.device.h # F.applet.h) THEN
			D.id := resize;  
			F.applet.w := F.applet.device.w; F.applet.h := F.applet.device.h
		ELSE
			D.id := update
		END;
		F.applet.handle(F.applet, D); 
	END Restore;	
		
	PROCEDURE ^ NewFrame* (A: Frame; P: HyperDocs.DefURL; name: ARRAY OF CHAR; width, height: INTEGER);

	PROCEDURE Handle* (F: Objects.Object; VAR M: Objects.ObjMsg);
		VAR x, y, mx, my, w, h, id: INTEGER; Q: Display3.Mask; keys: SET; F1: Frame; saveD: JuiceDevices.Device;
			adf: ARRAY 64 OF CHAR; K: KeyboardMsg; MM: MouseMsg; D: DisplayMsg; I: IdleMsg; FM: FocusMsg;
			CM: Oberon.ControlMsg; 
	BEGIN
		WITH F: Frame DO
			IF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF M.id = Objects.get THEN
						IF M.name = "Gen" THEN 
							M.class := Objects.String; COPY("JuiceApplets.New", M.s); M.res := 0
						END
					END
				END
			ELSIF M IS Display.FrameMsg THEN
				JuiceFiles.SetBase(F.applet.urlbase);
				WITH M: Display.FrameMsg DO
					IF (M.F = NIL) OR (M.F = F) OR (M.F = dummy) THEN (* message addressed to box *)
						x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H;
						IF M IS  Display.DisplayMsg THEN
							WITH M: Display.DisplayMsg  DO
								IF (M.device = Display.screen) THEN
									IF (M.id = Display.full) OR (M.F = NIL) THEN
										Gadgets.MakeMask(F, x, y, M.dlink, Q);
										JuiceDevices.SetDevicePos(F.applet.device, Q, x, y, w, h);
										Restore(F, Q, x, y, w, h, TRUE); 
									ELSIF M.id = Display.area THEN
										Gadgets.MakeMask(F, x, y, M.dlink, Q);
										Display3.AdjustMask(Q, x + M.u, y + h - 1 + M.v, M.w, M.h);
										JuiceDevices.SetDevicePos(F.applet.device, Q, x, y, w, h);
										Restore(F, Q, x, y, w, h, TRUE)
									ELSE Gadgets.framehandle(F, M)
									END
								ELSIF (M.device = Display.printer) THEN
									IF M.id = Display.contents THEN
										NEW(Q); Display3.Open(Q); Display3.Add(Q, 0, 0, Printer.Width, Printer.Height);
										Q.X := 0; Q.Y := 0; Q.W := Printer.Width; Q.H := Printer.Height; Q.x := 0; Q.y := 0;
										saveD := F.applet.device;
										JuiceDevices.InitMainDevice(F.applet.device, Printer.Width, Printer.Height, TRUE);
										JuiceDevices.SetDevicePos(F.applet.device, Q, 0, 0, Printer.Width, Printer.Height);
										Restore(F, Q, 0, 0, Printer.Width, Printer.Height, FALSE);
										F.applet.device := saveD;
									ELSE
										Gadgets.MakePrinterMask(F, M.x, M.y, M.dlink, Q);
										saveD := F.applet.device;
										JuiceDevices.InitMainDevice(F.applet.device, PP(F.W), PP(F.H), TRUE);
										JuiceDevices.SetDevicePos(F.applet.device, Q, M.x, M.y, PP(F.W), PP(F.H));
										Restore(F, Q, M.x, M.y, PP(F.W), PP(F.H), FALSE);
										F.applet.device := saveD;
									END
								END
							END						
						ELSIF M IS Oberon.InputMsg THEN
							WITH M: Oberon.InputMsg DO
								IF M.id = Oberon.track THEN
									Input.Mouse(keys, mx, my); MM.buttons := {};
									IF 0 IN keys THEN INCL(MM.buttons, JuiceDevices.rightButton) END;
									IF 1 IN keys THEN INCL(MM.buttons, JuiceDevices.middleButton) END;
									IF 2 IN keys THEN 
										IF focus # F THEN
											CM.id := Oberon.defocus; Display.Broadcast(CM);
											FM.id := get; F.applet.handle(F.applet, FM);
											focus := F
										END;
										INCL(MM.buttons, JuiceDevices.leftButton) 
									END;
									MM.x := mx-x; MM.y := h-my+y; 
									F.applet.handle(F.applet, MM);
								ELSIF (M.id = Oberon.consume) & (focus = F) THEN
									K.ch := M.ch;
									F.applet.handle(F.applet, K)
								ELSE Gadgets.framehandle(F, M)
								END
							END
						ELSIF M IS Oberon.ControlMsg THEN
							WITH M: Oberon.ControlMsg DO
								IF F = focus THEN
									FM.id := lose; F.applet.handle(F.applet, FM);
									focus := NIL
								END
							END
						ELSIF M IS BackgroundTaskMsg THEN
							Gadgets.MakeMask(F, x, y, M.dlink, Q);
							JuiceDevices.SetDevicePos(F.applet.device, Q, x, y, w, h);
							F.applet.handle(F.applet, I);
						ELSIF (M IS VisibilityMsg) & (M(VisibilityMsg).applet = F.applet) THEN M(VisibilityMsg).visible:= TRUE
						ELSE Gadgets.framehandle(F, M)
						END
					ELSE Gadgets.framehandle(F, M)
					END
				END
			ELSIF M IS Objects.CopyMsg THEN
				WITH M: Objects.CopyMsg DO
					IF M.stamp = F.stamp THEN M.obj := F.dlink
					ELSE
						NEW(F1); F.stamp := M.stamp; F.dlink := F1;
						F1.applet := F.applet; F1.handle := F.handle; M.obj := F1
					END
				END
			ELSIF M IS Objects.FileMsg THEN
				WITH M: Objects.FileMsg DO
					IF M.id = Objects.store THEN
						Files.WriteInt(M.R, 100);
						Files.WriteString(M.R, F.adf);
						Files.WriteInt(M.R, F.W);
						Files.WriteInt(M.R, F.H);
					ELSIF M.id = Objects.load THEN
						Files.ReadInt(M.R, id);
						Files.ReadString(M.R, adf);
						Files.ReadInt(M.R, w);
						Files.ReadInt(M.R, h);
						NewFrame(F, NIL, adf, w, h);
						F.W := w;
						F.H := h;
					END
				END
			ELSE Gadgets.framehandle(F, M)
			END
		END
	END Handle;
		
	PROCEDURE Init*(F: Frame);
	BEGIN
		F.handle := Handle; 
	END Init;	
	
	PROCEDURE NewFrame* (A: Frame; P: HyperDocs.DefURL; name: ARRAY OF CHAR; width, height: INTEGER);
		VAR F: JuiceFiles.File; R: JuiceFiles.Rider; creator: ARRAY 64 OF CHAR; ch: CHAR; i: INTEGER;
			base: HyperDocs.DefURL;
	BEGIN
		JuiceFiles.SetBase(P);
		F := JuiceFiles.LoadURL(name);
		IF F # NIL THEN
			JuiceFiles.GetBase(base); JuiceFiles.SetBase(base);
			Init(A); A.W := width; A.H := height;
			JuiceFiles.Set(R, F, 0);
			JuiceFiles.ReadChar(R, ch); i := 0;
			WHILE ((ch >= "a") & (ch <= "z") OR (ch >= "A") & (ch <= "Z") OR (ch >= "0") & (ch <= "9") OR (ch = ".")) & ~R.eof DO
				creator[i] := ch;
				INC(i);
				JuiceFiles.ReadChar(R, ch)
			END;
			creator[i] := 0X;
			NewApplet(creator, width, height);
			A.applet := newApplet; newApplet.params := R;
			A.applet.urlbase := base;
			COPY(name, A.adf);
		ELSE
			Init(A); A.W := width; A.H := height;
			NewGenericApplet(width, height);
			A.applet := newApplet;
			COPY(name, A.adf)
		END
	END NewFrame;
	
	PROCEDURE New*;
		VAR F: Frame;
	BEGIN
		NEW(F); Init(F); F.W := 200; F.H := 200;
		Objects.NewObj := F; 
	END New;
	
	(* Idle task *)
	
	PROCEDURE Timer(me: Oberon.Task);
		VAR TM: BackgroundTaskMsg;
	BEGIN 
		Display.Broadcast(TM);
	END Timer;
	
	PROCEDURE InstallTask;
		VAR task: Oberon.Task;
	BEGIN
		NEW(dummy);
		NEW(task);
		task.handle := Timer;
		Oberon.Install(task);
	END InstallTask;

	PROCEDURE Scan(VAR S: Param);
		CONST maxD = 32; (* fixed size: maxD <= LEN(S.s)! *)
		VAR
			ch, E: CHAR;
			neg, negE, hex, sign: BOOLEAN;
			i, j, h: SHORTINT;
			e: INTEGER; k, k1, k2, k3: LONGINT;
			y: LONGREAL;
			d: ARRAY maxD OF CHAR;
	BEGIN
		ch := S.nextCh; i := 0; sign := FALSE;
		LOOP
			IF ch > " " THEN EXIT END;
			IF S.R.eof THEN EXIT END;
			JuiceFiles.ReadChar(S.R, ch)
		END;
		IF ~S.R.eof & ("A" <= CAP(ch)) & (CAP(ch) <= "Z") OR (ch = ".") THEN (*name*)
			REPEAT
				S.s[i] := ch; INC(i); JuiceFiles.ReadChar(S.R, ch)
			UNTIL (ch <= " ") OR (i = LEN(S.s)-1) OR S.R.eof;
			S.s[i] := 0X;
			IF i = 1 THEN
				S.c := S.s[0]; S.class := Char
			ELSE
				S.len := i; S.nextCh := ch; S.class := String
			END;
		ELSIF ch = 22X THEN (*literal string*)
			JuiceFiles.ReadChar(S.R, ch);
			WHILE (ch # 22X) & (ch >= " ") & (i # LEN(S.s)-1) & ~S.R.eof DO
				S.s[i] := ch; INC(i); JuiceFiles.ReadChar(S.R, ch)
			END;
			S.s[i] := 0X; S.len := i; JuiceFiles.ReadChar(S.R, ch); S.class := String
		ELSIF ~S.R.eof THEN
			IF ch = "-" THEN sign := TRUE; neg := TRUE; JuiceFiles.ReadChar(S.R, ch)
			ELSIF ch = "+" THEN sign := TRUE; neg := FALSE; JuiceFiles.ReadChar(S.R, ch)
			ELSE sign := FALSE; neg := FALSE
			END ;
			IF ("0" <= ch) & (ch <= "9") THEN (*number*)
				hex := FALSE; j := 0;
				LOOP d[i] := ch; INC(i); JuiceFiles.ReadChar(S.R, ch);
					IF ch < "0" THEN EXIT END;
					IF "9" < ch THEN
						IF ("A" <= ch) & (ch <= "F") THEN hex := TRUE; ch := CHR(ORD(ch)-7)
						ELSIF ("a" <= ch) & (ch <= "f") THEN hex := TRUE; ch := CHR(ORD(ch)-27H)
						ELSE EXIT
						END
					END
				END;
				IF ch = "H" THEN (*hex number*)
					JuiceFiles.ReadChar(S.R, ch); S.class := Int;
					IF i-j > 8 THEN j := i-8 END;
					k := ORD(d[j]) - 30H; INC(j);
					IF (i-j = 7) & (k >= 8) THEN DEC(k, 16) END;
					WHILE j < i DO k := k*10H + (ORD(d[j]) - 30H); INC(j) END;
					IF neg THEN S.i := -k ELSE S.i := k END
				ELSIF ch = "." THEN (*read real*)
					JuiceFiles.ReadChar(S.R, ch); h := i;
					WHILE ("0" <= ch) & (ch <= "9") DO d[i] := ch; INC(i); JuiceFiles.ReadChar(S.R, ch) END;
					(*-------- begin floating-point handling BM 1993.3.10 -----------------------------------*)
					WHILE i MOD 8 # 0 DO d[i] := "0"; INC(i) END;
					j := 0; k := 0; k1 := 0; k2 := 0; k3 := 0; (* store digits 0..7, 8..15, 16..23, 24..31 in k, k1, k2, k3 *)
					WHILE j < 8 DO k := k*10 + ORD(d[j]) - ORD("0"); INC(j) END;
					IF 8 < i THEN
						WHILE j < 16 DO k1 := k1*10 + ORD(d[j]) - ORD("0"); INC(j) END
					END;
					IF 16 < i THEN
						WHILE j < 24 DO k2 := k2*10 + ORD(d[j]) - ORD("0"); INC(j) END
					END;
					IF 24 < i THEN
						WHILE j < 32 DO k3 := k3*10 + ORD(d[j]) - ORD("0"); INC(j) END
					END;
					e := 0; E := ch;
					IF (E = "D") OR (E = "E") THEN JuiceFiles.ReadChar(S.R, ch);
						IF ch = "-" THEN negE := TRUE; JuiceFiles.ReadChar(S.R, ch)
						ELSE negE := FALSE;
							IF ch = "+" THEN JuiceFiles.ReadChar(S.R, ch) END
							END;
							WHILE ("0" <= ch) & (ch <= "9") DO e := e*10 + ORD(ch) - ORD("0"); JuiceFiles.ReadChar(S.R, ch) END;
							IF negE THEN e := - e END
						END;
						y := k3*Reals.Ten(-32) + k2*Reals.Ten(-24); y := y + k1*Reals.Ten(-16);
						IF ABS(e+h) < 308 THEN y := (y + k*Reals.Ten(-8)) / Reals.Ten(-e-h)
						ELSE y := (y + k*Reals.Ten(-8)) * Reals.Ten(h);
							IF (e <= 308-32) OR (e <= 308) & (y < MAX(LONGREAL) / Reals.Ten(e)) THEN y := y * Reals.Ten(e)
							ELSE y := MAX(LONGREAL)
							END
						END;
						IF E = "D" THEN
							IF y = MAX(LONGREAL) THEN S.class := Inval (* NaN *)
						ELSE S.class := LongReal;
							IF neg THEN S.y := - y ELSE S.y := y END;
							IF Reals.ExpoL(S.y) = 0 THEN S.y := 0 END
						END
					ELSIF MAX(REAL) < y THEN S.class:= Inval (* NaN *)
					ELSE S.class := Real;
						IF neg THEN S.x := SHORT(- y) ELSE S.x := SHORT(y) END;
						IF Reals.Expo(S.x) = 0 THEN S.x := 0 END
					END;
					(*-------- end floating-point handling BM 1993.3.10 -----------------------------------*)
					IF hex THEN S.class := Inval END
				ELSE (*decimal integer*)
					S.class := Int; k := 0;
					WHILE (j # i) & ((k < MAX(LONGINT) DIV 10) OR
					(k = MAX(LONGINT) DIV 10) & ((ORD(d[j]) - 30H) <= MAX(LONGINT) MOD 10)) DO (*JG*)
						k := k*10 + (ORD(d[j]) - 30H); INC(j)
					END;
					IF j # i THEN S.class := Inval
					ELSE
						IF neg THEN S.i := -k ELSE S.i := k END;
						IF hex THEN S.class := Inval ELSE S.class := Int END
					END
				END
			ELSE S.class := Char;
				IF sign THEN IF neg THEN S.c := "-" ELSE S.c := "+" END
					ELSE S.c := ch; JuiceFiles.ReadChar(S.R, ch)
				END
			END
		END;
		S.nextCh := ch;
	END Scan;

	PROCEDURE GetParam* (me: Applet; name: ARRAY OF CHAR; VAR value: Param);
		VAR str: ARRAY 256 OF CHAR;
	BEGIN
		value.R := me.params; JuiceFiles.ReadChar(value.R, value.nextCh);
		REPEAT
			Scan(value);
			IF value.class = String THEN
				COPY(value.s, str);
				Scan(value);
				IF (value.class = Char) & (value.c = "=") THEN
					Scan(value);
					IF str = name THEN RETURN END;
				ELSE
					value.class := NotFound; RETURN
				END
			ELSE
				value.class := NotFound; RETURN
			END
		UNTIL value.R.eof;	
	END GetParam;

	PROCEDURE Broadcast* (VAR M: AppletMsg);
		VAR a: Applet; VM: VisibilityMsg;
	BEGIN
		a := appletList;
		WHILE a # NIL DO
			VM.visible:= FALSE; VM.applet:= a; Display.Broadcast(VM);
			IF VM.visible THEN a.handle(a, M) END;
			a := a.link
		END
	END Broadcast;

BEGIN InstallTask;
END JuiceApplets.