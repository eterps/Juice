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

MODULE JuiceApplets;	(* tk, 28.2.96 *)

	IMPORT S := SYSTEM, NPAPI, Kernel:= JuiceKernel, Reals, JuiceDevices, JuiceModules;

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
	
		WMPaint = 0FH;
		WMMouseMove = 0200H;
		WMLButtonDown = 0201H;
		WMLButtonUp = 0202H;
		WMRButtonDown = 0204H;
		WMRButtonUp = 0205H;
		WMMButtonDown = 0207H;
		WMMButtonUp = 0208H;
		WMSetCursor = 020H;
		WMChar = 0102H;
		WMSetFocus = 07H;
		WMKillFocus = 08H;
		WMCreate = 01H;
		WMTimer = 0113H;

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
		
		(** Applets should redraw all its contents when receiving display messages. *)
		DisplayMsg* = RECORD (AppletMsg)
			id*: SHORTINT;	(** update, resize *)
		END;

		(** Applets receive this message when the focus changes *)
		FocusMsg* = RECORD (AppletMsg)
			id*: SHORTINT;	(** get, loose *)
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
			device-: JuiceDevices.Device;	(** Applet's device to draw to *)
			inited, focus: BOOLEAN;
			x, y, w, h: INTEGER; buttons: SET;
			msg: ARRAY 256 OF CHAR;
			par: ARRAY 512 OF CHAR;
			link: Applet
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
			A: Applet;
			ind: INTEGER;
		END;

		Params = POINTER TO RECORD cmd: ARRAY 32 OF CHAR; data: ARRAY 512 OF CHAR; instRef: LONGINT END;
		
	VAR
		newApplet*, 	(** Newly generated applets are returned here *)
		curApplet,
		appletList: Applet;
		countGC: LONGINT;
			
	PROCEDURE SplitName (VAR name, MName, PName: ARRAY OF CHAR);
		VAR i, j: INTEGER;
	BEGIN i := 0;
		WHILE (CAP(name[i]) >= "A") & (CAP(name[i]) <= "Z") OR (name[i] >= "0") & (name[i] <= "9") DO MName[i] := name[i]; INC(i) END;
		MName[i] := 0X; 
		IF name[i] # 0X THEN INC(i) END; j := 0;
		WHILE (CAP(name[i]) >= "A") & (CAP(name[i]) <= "Z") OR (name[i] >= "0") & (name[i] <= "9") DO PName[j] := name[i]; INC(i); INC(j) END;
		PName[j] := 0X
	END SplitName;
		
	PROCEDURE Display(me: Applet);
		VAR line: ARRAY 64 OF CHAR; i, j, x, y: INTEGER;
	BEGIN
		JuiceDevices.Setup(me.device);
		JuiceDevices.SetForeColor(JuiceDevices.white);
		JuiceDevices.FillRect(0, 0, me.device.w, me.device.h);
		JuiceDevices.SetForeColor(JuiceDevices.black);
		JuiceDevices.FrameRect(0, 0, me.device.w, me.device.h);
		JuiceDevices.SetFontSize(10);
		i := 0; x := 10; y := 10;
		WHILE me.msg[i] # 0X DO
			j := 0; WHILE me.msg[i] >= " " DO
				line[j] := me.msg[i];
				INC(i); INC(j);
			END;
			line[j] := 0X;
			IF me.msg[i] = 0DX THEN
				JuiceDevices.String(x, y, line);
				INC(y, 12);
				INC(i)
			ELSIF me.msg[i] = 0AX THEN INC(i)
			END;
		END;
		JuiceDevices.Restore(me.device);
	END Display;
		
	PROCEDURE AppletHandler* (me: Applet; VAR M: AppletMsg);
	BEGIN
		IF M IS DisplayMsg THEN Display(me) END;
	END AppletHandler;	

	PROCEDURE ExecuteCommand(m: JuiceModules.Module; par: PTR);
		VAR proc: JuiceModules.Command; i: INTEGER;
	BEGIN
		WITH par: Params DO
			curApplet := NIL; newApplet := NIL;
			IF m # NIL THEN
				proc := JuiceModules.ThisCommand(m, par.cmd);
				IF JuiceModules.res = 0 THEN
					proc()
				ELSE
					Kernel.Str(JuiceModules.resMsg);
				END
			ELSE
				Kernel.Str(JuiceModules.resMsg);
			END;
			IF (newApplet = NIL) OR (JuiceModules.res # 0) THEN 
				NEW(newApplet);
				IF JuiceModules.res # 0 THEN COPY(JuiceModules.resMsg, newApplet.msg);
				ELSE newApplet.msg := "Applet not found!";
				END;
				i := 0; WHILE newApplet.msg[i] # 0X DO INC(i) END;
				newApplet.msg[i] := 0DX; newApplet.msg[i+1] := 0X;
			END;
			newApplet.link := appletList; appletList := newApplet;
			NEW(newApplet.device);
			IF newApplet.handle = NIL THEN newApplet.handle := AppletHandler END;
			COPY(par.data, newApplet.par);
			NPAPI.RegisterApplet(par.instRef, newApplet)
		END
	END ExecuteCommand;
	
	PROCEDURE NewApplet(instRef: LONGINT; VAR params: ARRAY OF CHAR);
		VAR modname: ARRAY 32 OF CHAR; par: Params;
	BEGIN
		NEW(par); par.instRef := instRef;
		SplitName(params, modname, par.cmd);
		COPY(params, par.data);
		JuiceModules.LoadMod(modname, ExecuteCommand, par);
	END NewApplet;
	
	PROCEDURE DestroyApplet(applet: PTR);
		VAR list, prev: Applet; DM: DestroyMsg;
	BEGIN
		WITH applet: Applet DO
			curApplet := applet;
			applet.handle(applet, DM);
			JuiceDevices.FinalizeDevice(applet.device);
			prev := NIL; list := appletList;
			WHILE (list # NIL) & (list # applet) DO prev := list; list := list.link END;
			IF prev = NIL THEN appletList := list.link ELSE prev.link := list.link END
		END
	END DestroyApplet;	
		
	PROCEDURE SetAppletDevice(applet: PTR; x, y, w, h: INTEGER; hWnd: LONGINT; new: BOOLEAN);
	BEGIN
		WITH applet: Applet DO
			curApplet := applet;
			JuiceDevices.SetupDevice(applet.device, x, y, w, h, hWnd, new);
		END
	END SetAppletDevice;
		
	PROCEDURE LOWORD (x: LONGINT): LONGINT;
	BEGIN RETURN x MOD 10000H;
	END LOWORD;
	
	PROCEDURE HIWORD (x: LONGINT): LONGINT;
	BEGIN x := S.LSH(x, -16); RETURN S.VAL(LONGINT, S.VAL(SET, x) * S.VAL(SET, 0FFFFH));
	END HIWORD;

	PROCEDURE HandleAppletEvent(applet: PTR; event: NPAPI.NPEvent): BOOLEAN;
		VAR DM: DisplayMsg; MM: MouseMsg; KM: KeyboardMsg; IM: IdleMsg; I: InitMsg; FM: FocusMsg;
	BEGIN
		WITH applet: Applet DO
			curApplet := applet;
			IF (event.message = WMCreate) THEN HALT(88) END;
			IF (event.message = WMSetFocus) OR (event.message = WMSetCursor) THEN 
				JuiceDevices.SetFocus(applet.device); 
				IF ~applet.focus THEN FM.id := get; applet.handle(applet, FM); applet.focus := TRUE END
			 END;
			CASE event.message OF
			| WMKillFocus: FM.id := lose; applet.handle(applet, FM); applet.focus := FALSE
			| WMPaint: 
				IF ~applet.inited THEN applet.handle(applet, I); applet.inited := TRUE;
				END;
				IF (applet.device.h # applet.h) OR (applet.device.w # applet.w) THEN
					applet.h := applet.device.h; applet.w := applet.device.w;
					DM.id := resize
				ELSE
					DM.id := update
				END;
				applet.handle(applet, DM);
			| WMMouseMove:
				applet.x := SHORT(LOWORD(event.lParam)); applet.y := SHORT(HIWORD(event.lParam));
				MM.x := applet.x; MM.y := applet.y; MM.buttons := applet.buttons;
				applet.handle(applet, MM);
			| WMLButtonDown: 
				INCL(applet.buttons, JuiceDevices.leftButton);
				MM.x := applet.x; MM.y := applet.y; MM.buttons := applet.buttons;
				applet.handle(applet, MM);
			| WMLButtonUp: 
				EXCL(applet.buttons, JuiceDevices.leftButton);
				MM.x := applet.x; MM.y := applet.y; MM.buttons := applet.buttons;
				applet.handle(applet, MM);
			| WMMButtonDown: 
				INCL(applet.buttons, JuiceDevices.middleButton);
				MM.x := applet.x; MM.y := applet.y; MM.buttons := applet.buttons;
				applet.handle(applet, MM);
			| WMMButtonUp: 
				EXCL(applet.buttons, JuiceDevices.middleButton);
				MM.x := applet.x; MM.y := applet.y; MM.buttons := applet.buttons;
				applet.handle(applet, MM);
			| WMRButtonDown: 
				INCL(applet.buttons, JuiceDevices.rightButton);
				MM.x := applet.x; MM.y := applet.y; MM.buttons := applet.buttons;
				applet.handle(applet, MM);
			| WMRButtonUp: 
				EXCL(applet.buttons, JuiceDevices.rightButton);
				MM.x := applet.x; MM.y := applet.y; MM.buttons := applet.buttons;
				applet.handle(applet, MM);
			| WMChar:
				KM.ch := CHR(event.wParam);
				applet.handle(applet, KM);
			| WMTimer:
				INC(countGC); IF countGC = 100 THEN countGC:= 0; Kernel.GC; Kernel.Str("GC"); Kernel.Ln END;
				applet.handle(applet, IM); 
			ELSE
				RETURN FALSE;
			END
		END;
		RETURN TRUE
	END HandleAppletEvent;	
	
	(* for internal use only *)	
	PROCEDURE HandleTrap*(msg: ARRAY OF CHAR);
	BEGIN
		IF curApplet # NIL THEN
			curApplet.handle := AppletHandler;
			COPY(msg, curApplet.msg);
			Display(curApplet)
		END
	END HandleTrap; 	

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
			IF S.ind >= LEN(S.A.par) THEN EXIT END;
			ch := S.A.par[S.ind]; INC(S.ind)
		END;
		IF (S.ind < LEN(S.A.par)) & ("A" <= CAP(ch)) & (CAP(ch) <= "Z") OR (ch = ".") THEN (*name*)
			REPEAT
				S.s[i] := ch; INC(i); ch := S.A.par[S.ind]; INC(S.ind)
			UNTIL (ch <= " ") OR (i = LEN(S.s)-1) OR (S.ind >= LEN(S.A.par));
			S.s[i] := 0X;
			IF i = 1 THEN
				S.c := S.s[0]; S.class := Char
			ELSE
				S.len := i; S.nextCh := ch; S.class := String
			END;
		ELSIF ch = 22X THEN (*literal string*)
			ch := S.A.par[S.ind]; INC(S.ind);
			WHILE (ch # 22X) & (ch >= " ") & (i # LEN(S.s)-1) & (S.ind < LEN(S.A.par)) DO
				S.s[i] := ch; INC(i); ch := S.A.par[S.ind]; INC(S.ind)
			END;
			S.s[i] := 0X; S.len := i; ch := S.A.par[S.ind]; INC(S.ind); S.class := String
		ELSIF S.ind < LEN(S.A.par) THEN
			IF ch = "-" THEN sign := TRUE; neg := TRUE; ch := S.A.par[S.ind]; INC(S.ind)
			ELSIF ch = "+" THEN sign := TRUE; neg := FALSE; ch := S.A.par[S.ind]; INC(S.ind)
			ELSE sign := FALSE; neg := FALSE
			END ;
			IF ("0" <= ch) & (ch <= "9") THEN (*number*)
				hex := FALSE; j := 0;
				LOOP d[i] := ch; INC(i); ch := S.A.par[S.ind]; INC(S.ind);
					IF ch < "0" THEN EXIT END;
					IF "9" < ch THEN
						IF ("A" <= ch) & (ch <= "F") THEN hex := TRUE; ch := CHR(ORD(ch)-7)
						ELSIF ("a" <= ch) & (ch <= "f") THEN hex := TRUE; ch := CHR(ORD(ch)-27H)
						ELSE EXIT
						END
					END
				END;
				IF ch = "H" THEN (*hex number*)
					ch := S.A.par[S.ind]; INC(S.ind); S.class := Int;
					IF i-j > 8 THEN j := i-8 END;
					k := ORD(d[j]) - 30H; INC(j);
					IF (i-j = 7) & (k >= 8) THEN DEC(k, 16) END;
					WHILE j < i DO k := k*10H + (ORD(d[j]) - 30H); INC(j) END;
					IF neg THEN S.i := -k ELSE S.i := k END
				ELSIF ch = "." THEN (*read real*)
					ch := S.A.par[S.ind]; INC(S.ind); h := i;
					WHILE ("0" <= ch) & (ch <= "9") DO d[i] := ch; INC(i); ch := S.A.par[S.ind]; INC(S.ind) END;
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
					IF (E = "D") OR (E = "E") THEN ch := S.A.par[S.ind]; INC(S.ind);
						IF ch = "-" THEN negE := TRUE; ch := S.A.par[S.ind]; INC(S.ind)
						ELSE negE := FALSE;
							IF ch = "+" THEN ch := S.A.par[S.ind]; INC(S.ind) END
							END;
							WHILE ("0" <= ch) & (ch <= "9") DO e := e*10 + ORD(ch) - ORD("0"); ch := S.A.par[S.ind]; INC(S.ind) END;
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
					ELSE S.c := ch; ch := S.A.par[S.ind]; INC(S.ind)
				END
			END
		END;
		S.nextCh := ch;
	END Scan;
		
	PROCEDURE GetParam* (me: Applet; name: ARRAY OF CHAR; VAR value: Param);
		VAR str: ARRAY 256 OF CHAR;
	BEGIN
		value.A := me; value.ind := 1; value.nextCh := me.par[0];
		Scan(value);	(* Creator *)
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
		UNTIL value.ind >= LEN(value.A.par);	
	END GetParam;


	PROCEDURE Broadcast* (VAR M: AppletMsg);
		VAR a: Applet;
	BEGIN
		a := appletList; WHILE a # NIL DO a.handle(a, M); a := a.link END
	END Broadcast;
		
BEGIN 
	NPAPI.newApplet := NewApplet;
	NPAPI.destroyApplet := DestroyApplet;
	NPAPI.setAppletDevice := SetAppletDevice;
	NPAPI.handleAppletEvent := HandleAppletEvent;
	countGC:= 0;
END JuiceApplets.