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

MODULE NPAPI;	(* tk 19.2.96 *)

	IMPORT S := SYSTEM, Kernel:= JuiceKernel;

	CONST
		GWLWndProc = -4;
		WMPaint = 0FH;
	
		NPFULL = 2;

		NPERRBASE = 0;
		NPERRNOERROR = NPERRBASE + 0;


	TYPE
		ADDRESS = LONGINT;
		NPString* = ARRAY 256 OF CHAR;
		NPAllocator = ARRAY 512 OF CHAR;
		NPBuffer* = ARRAY 4*1024 OF CHAR;
		NPBool = BOOLEAN;
		NPError* = INTEGER;
		NPMIMEType = ARRAY 256 OF CHAR;

		WriteStreamProc* = PROCEDURE (VAR buf: NPBuffer; len: LONGINT; data: PTR);
		DestroyStreamProc* = PROCEDURE (reason: NPError; data: PTR);

		NPStreamData = POINTER TO NPStreamDataDesc;
		NPStreamDataDesc = RECORD
			url: NPString;
			pdata: PTR;
			link: NPStreamData;
			write: WriteStreamProc;
			destroy: DestroyStreamProc;
		END;
		
		NPStream = POINTER- TO NPStreamDesc;
		NPStreamDesc = RECORD
			pdata: NPStreamData;
			ndata: ADDRESS;
			url: ADDRESS;
			end, lastmodified: LONGINT
		END;
		
		NPP = POINTER- TO NPPDesc;
		NPPDesc = RECORD
			pdata, ndata: ADDRESS;
		END;

		NPByteRangePtr = POINTER- TO NPByteRange;
		NPByteRange = RECORD
			offset, length: LONGINT;
			next: NPByteRangePtr
		END;

		NPRect* = RECORD 
			top*, left*, bottom*, right*: INTEGER
		END;

		NPWindow* = POINTER TO NPWindowDesc;
		NPWindowDesc* = RECORD
			window*: ADDRESS;	(* hWnd *)
			x*, y*, width*, height*: LONGINT;
			clipRect*: NPRect
		END;
		
		NPFullPrint = POINTER- TO RECORD
			mode: INTEGER;
			pluginPrinted: NPBool;
			printOne: NPBool;
			platfomrPrint: LONGINT;
		END;
		
		NPEmbedPrint = POINTER- TO RECORD
			mode: INTEGER;
			window: NPWindowDesc;
			platformPrint: LONGINT;
		END;
		
		NPPrint = POINTER- TO RECORD mode: INTEGER END;

		NPSavedDataPtr = POINTER- TO NPSavedData;
		NPSavedData = RECORD
			len: LONGINT;
			buf: ADDRESS
		END;

		NPEvent* = RECORD
			message*: LONGINT;
			wParam*: LONGINT;
			lParam*: LONGINT
		END;

		WindowProc = PROCEDURE (window: LONGINT; msg: LONGINT; uParam, lParam: LONGINT): LONGINT;

		Instance = POINTER TO InstanceDesc;
		InstanceDesc = RECORD
			allocator: NPAllocator;
			directory: NPString;
			window: NPWindow;
			hWnd: LONGINT;
			timer: LONGINT;
			lpfnOldWndProc: WindowProc;
			applet: PTR;
			link: Instance;
		END;

	VAR
		NPNVersion: PROCEDURE (VAR pluginMajor, pluginMinor, netscapeMajor, netscapeMinor: LONGINT);
		NPNGetURL: PROCEDURE (instance: NPP; VAR url: NPString; window: LONGINT): NPError;
		NPNPostURL: PROCEDURE (instance: NPP; VAR url: NPString; len: LONGINT; VAR buf: NPString; file: NPBool): NPError;
			(* currently unimplemented in Netscape *)
		NPNRequestRead: PROCEDURE (stream: NPStream; rangeList: NPByteRange): NPError;
		NPNNewStream: PROCEDURE (instance: NPP; type: NPMIMEType; stream: NPStream): NPError;
		NPNWrite: PROCEDURE (instance: NPP; stream: NPStream; len: LONGINT; buffer: ADDRESS): LONGINT;
		NPNDestroyStream: PROCEDURE (instance: NPP; stream: NPStream; reason: NPError): NPError;
		NPNStatus: PROCEDURE (instance: NPP; message: NPString);
		NPNMemAlloc*: PROCEDURE (size: LONGINT): ADDRESS;
		NPNMemFree*: PROCEDURE (adr: ADDRESS);
		NPNMemFlush: PROCEDURE (size: LONGINT): LONGINT;
		NPNWindowHandler: WindowProc;
		InstallUpCall: PROCEDURE (name: NPString; VAR proc: LONGINT);

		nppShutdown: PROCEDURE ();
		nppNew: PROCEDURE (VAR pluginType: NPMIMEType; instance: NPP; mode, argc: INTEGER; argn, argv: ADDRESS; saved: NPSavedDataPtr): NPError;
		nppDestroy: PROCEDURE (instance: NPP; VAR save: NPSavedDataPtr): NPError;
		nppSetWindow: PROCEDURE (instance: NPP; window: NPWindow): NPError;
		nppNewStream: PROCEDURE (instance: NPP; type: NPMIMEType; stream: NPStream; seekable: NPBool; VAR stype: INTEGER): NPError;
		nppWriteReady: PROCEDURE (instance: NPP; stream: NPStream): LONGINT;
		nppWrite: PROCEDURE (instance: NPP; stream: NPStream; offset, len: LONGINT; VAR buf: NPBuffer): LONGINT;
		nppDestroyStream: PROCEDURE (instance: NPP; stream: NPStream; reason: NPError): NPError;
		nppStreamAsFile: PROCEDURE (instance: NPP; stream: NPStream; VAR fname: NPString);
		nppHandleEvent: PROCEDURE (instance: NPP; event: ADDRESS): INTEGER;
		nppPrint: PROCEDURE (instance: NPP; printInfo: NPPrint);
		nppWindowHandler: WindowProc;

		newApplet*: PROCEDURE (instRef: LONGINT; VAR cmd: ARRAY OF CHAR);
		destroyApplet*: PROCEDURE (applet: PTR);
		setAppletDevice*: PROCEDURE (applet: PTR; x, y, w, h: INTEGER; hWnd: LONGINT; new: BOOLEAN);
		handleAppletEvent*: PROCEDURE (applet: PTR; event: NPEvent): BOOLEAN;
		
		SetWindowLong: PROCEDURE (wnd: LONGINT; offs: LONGINT; newVal: WindowProc): WindowProc;
		SetTimer: PROCEDURE (hwnd: LONGINT; id, timeOut: LONGINT; timeProc: LONGINT): LONGINT;
		KillTimer: PROCEDURE (hwnd: LONGINT; id: LONGINT);

		instanceList: Instance;
		theInstance: NPP;
		openStreamList: NPStreamData; 
		
	PROCEDURE ^ NPPWindowHandler(hWnd: LONGINT; message: LONGINT; wParam: LONGINT; lParam: LONGINT): LONGINT;
	
	PROCEDURE NPPShutdown();
	BEGIN
		Kernel.Exit(0);
	END NPPShutdown;
	
	PROCEDURE NPPNew(VAR pluginType: NPMIMEType; instance: NPP; mode, argc: INTEGER; argn, argv: ADDRESS; saved: NPSavedDataPtr): NPError;
		VAR inst: Instance; 
	BEGIN
		theInstance := instance;
		NEW(inst); inst.link := instanceList; instanceList := inst;
		instance.pdata := S.VAL(ADDRESS, inst);
		inst.hWnd := 0;
		RETURN NPERRNOERROR
	END NPPNew;
	
	PROCEDURE NPPDestroy(instance: NPP; VAR save: NPSavedDataPtr): NPError;
		VAR inst, prev: Instance; p: WindowProc; 
	BEGIN
		theInstance := instance;
		prev := NIL; inst := instanceList;
		WHILE (inst # NIL) & (inst # S.VAL(Instance, instance.pdata)) DO prev := inst; inst := inst.link END;
		IF inst # NIL THEN
			IF inst.applet # NIL THEN destroyApplet(inst.applet) END;
			IF prev = NIL THEN instanceList := inst.link ELSE prev.link := inst.link END;
			IF inst.hWnd # 0 THEN
				p := SetWindowLong(inst.hWnd, GWLWndProc, inst.lpfnOldWndProc)
			END
		END;
		RETURN NPERRNOERROR
	END NPPDestroy;
	
	PROCEDURE NPPSetWindow(instance: NPP; window: NPWindow): NPError;
		VAR inst: Instance; p: WindowProc; new: BOOLEAN;
	BEGIN
		theInstance := instance; new := TRUE;
		inst := S.VAL(Instance, instance.pdata);
		
		IF (window.window # 0) & (inst.hWnd = 0) THEN
			inst.window := window;
			inst.hWnd := inst.window.window;
		
			inst.lpfnOldWndProc := SetWindowLong(inst.hWnd, GWLWndProc, NPNWindowHandler);
		ELSE
			IF inst.hWnd # window.window THEN
				(* KillTimer(inst.hWnd, inst.timer); *)
				inst.window := window;
				p := SetWindowLong(inst.hWnd, GWLWndProc, inst.lpfnOldWndProc);
				inst.hWnd := inst.window.window;
				
				IF inst.hWnd # 0 THEN
					inst.lpfnOldWndProc := SetWindowLong(inst.hWnd, GWLWndProc, NPNWindowHandler);
				END
			ELSE new := FALSE
			END
		END;
		
		IF inst.applet # NIL THEN
			setAppletDevice(inst.applet, SHORT(window.x), SHORT(window.y), SHORT(window.width), 
				SHORT(window.height), inst.hWnd, new);
		END;
		inst.timer := SetTimer(inst.hWnd, 0, 10, 0);
		RETURN NPERRNOERROR
	END NPPSetWindow;
	
	
	(* Streams *)
	
	PROCEDURE NPPNewStream(instance: NPP; type: NPMIMEType; stream: NPStream; seekable: NPBool; VAR stype: INTEGER): NPError;
		VAR url, dir: NPString; adr, i, j: LONGINT; ch: CHAR; inst: Instance; prev, list: NPStreamData;
	BEGIN
		theInstance := instance;
		inst := S.VAL(Instance, instance.pdata);
		
		adr := stream.url; i := 0; j := -1;
		REPEAT
			S.GET(adr, ch); url[i] := ch; dir[i] := ch;
			IF ch = "/" THEN j := i END;
			INC(adr); INC(i)
		UNTIL ch = 0X;
		IF j # -1 THEN dir[j+1] := 0X END;
				
		prev := NIL; list := openStreamList;
		WHILE (list # NIL) & (list.url # url) DO prev := list; list := list.link END;
		IF list = NIL THEN (* main stream *)
			stream.pdata := NIL;
			inst.directory := dir;
		ELSE
			stream.pdata := list;
			IF prev = NIL THEN openStreamList := list.link ELSE prev.link := list.link END
		END;
		
		RETURN NPERRNOERROR
	END NPPNewStream;
	
	PROCEDURE NPPWriteReady(instance: NPP; stream: NPStream): LONGINT;
	BEGIN
		theInstance := instance;
		RETURN SIZE(NPBuffer)
	END NPPWriteReady;
	
	PROCEDURE NPPWrite(instance: NPP; stream: NPStream; offset, len: LONGINT; VAR buf: NPBuffer): LONGINT;
		VAR i: LONGINT; inst: Instance; 
	BEGIN
		theInstance := instance;
		inst := S.VAL(Instance, instance.pdata);
		IF stream.pdata = NIL THEN
			i := 0; WHILE i < len DO
				inst.allocator[offset+i] := buf[i];
				INC(i)
			END;
			inst.allocator[offset+i] := 0X
		ELSE stream.pdata.write(buf, len, stream.pdata.pdata)
		END;
		RETURN len
	END NPPWrite;
	
	PROCEDURE NPPDestroyStream(instance: NPP; stream: NPStream; reason: NPError): NPError;
		VAR inst: Instance;
	BEGIN
		theInstance := instance;
		inst := S.VAL(Instance, instance.pdata);
		IF stream.pdata = NIL THEN
			Kernel.Str("New applet ");
			Kernel.Str(inst.allocator); Kernel.Ln;
			newApplet(S.VAL(LONGINT, inst), inst.allocator);
		ELSE 
			stream.pdata.destroy(reason, stream.pdata.pdata)
		END;
		RETURN NPERRNOERROR
	END NPPDestroyStream;
	
	PROCEDURE RegisterApplet* (instRef: LONGINT; applet: PTR);
		VAR inst: Instance;
	BEGIN
		inst := S.VAL(Instance, instRef);
		inst.applet := applet;
		setAppletDevice(inst.applet, SHORT(inst.window.x), SHORT(inst.window.y), SHORT(inst.window.width), SHORT(inst.window.height), inst.hWnd, TRUE);
	END RegisterApplet;
	
	PROCEDURE NPPStreamAsFile(instance: NPP; stream: NPStream; VAR fname: NPString);
	BEGIN
		theInstance := instance;
	END NPPStreamAsFile;
	
	(* Macintosh Version *)
	PROCEDURE NPPHandleEvent(instance: NPP; evt: ADDRESS): INTEGER;
	BEGIN
		RETURN 1
	END NPPHandleEvent;
	
	(* Windows Version *)
	PROCEDURE GetInstance(hWnd: LONGINT): Instance;
		VAR inst: Instance; 
	BEGIN
		inst := instanceList;
		WHILE (inst # NIL) & (inst.hWnd # hWnd) DO inst := inst.link END;
		RETURN inst
	END GetInstance;
	
	PROCEDURE NPPWindowHandler(hWnd: LONGINT; message: LONGINT; wParam: LONGINT; lParam: LONGINT): LONGINT;
		VAR event: NPEvent; inst: Instance; res: LONGINT;
	BEGIN
		inst := GetInstance(hWnd); res := 0;
		IF inst.applet # NIL THEN 
			event.message := message;
			event.wParam := wParam;
			event.lParam := lParam;
			IF handleAppletEvent(inst.applet, event) THEN res := inst.lpfnOldWndProc(hWnd, message, wParam, lParam)
			ELSE res := inst.lpfnOldWndProc(hWnd, message, wParam, lParam)
			END;
		ELSE res := inst.lpfnOldWndProc(hWnd, message, wParam, lParam)
		END;
		RETURN res;
	END NPPWindowHandler;
	
	PROCEDURE NPPPrint(instance: NPP; printInfo: NPPrint);
		VAR inst: Instance; event: NPEvent; oldWindow, printWindow: NPWindow; res: NPError; done: BOOLEAN; 
			fullPrint: NPFullPrint; embedPrint: NPEmbedPrint;
	BEGIN
		Kernel.Str("print"); Kernel.Ln;
		IF printInfo.mode = NPFULL THEN
			fullPrint := S.VAL(NPFullPrint, printInfo);
			fullPrint.pluginPrinted := FALSE;
		ELSE
			embedPrint := S.VAL(NPEmbedPrint, printInfo);
			theInstance := instance;
			inst := S.VAL(Instance, instance.pdata);
			oldWindow := inst.window;
			printWindow := S.VAL(NPWindow, S.ADR(embedPrint.window));
			Kernel.Str("print "); Kernel.Int(printWindow.window); Kernel.Ln;
			
			res := NPPSetWindow(instance, printWindow);
			event.message := WMPaint;
			done := handleAppletEvent(inst.applet, event);
			res := NPPSetWindow(instance, oldWindow)
			
		END
	END NPPPrint;

	PROCEDURE GetLocalFile* (name: ARRAY OF CHAR; write: WriteStreamProc; destroy: DestroyStreamProc; pdata: PTR);
		VAR nppURL: NPString; res: NPError; streamData: NPStreamData; url: NPString; inst: Instance; i, j: INTEGER;
	BEGIN
		inst := S.VAL(Instance, theInstance.pdata);
		COPY(inst.directory, url);
		i := 0; WHILE url[i] # 0X DO INC(i) END;
		j := 0; WHILE name[j] # 0X DO url[i] := name[j]; INC(i); INC(j) END;
		url[i] := 0X;
				
		NEW(streamData);
		COPY(url, streamData.url);
		streamData.link := openStreamList; openStreamList := streamData;
		streamData.write := write;
		streamData.destroy := destroy;
		streamData.pdata := pdata;
		
		COPY(url, nppURL); 
		res := NPNGetURL(theInstance, nppURL, 0);
	END GetLocalFile;

	PROCEDURE Init;
		VAR mod: LONGINT;
	BEGIN
		Kernel.GetAdr(0, "NPN_Version", S.VAL(LONGINT, NPNVersion));
		Kernel.GetAdr(0, "NPN_GetURL", S.VAL(LONGINT, NPNGetURL));
		Kernel.GetAdr(0, "NPN_PostURL", S.VAL(LONGINT, NPNPostURL));
		Kernel.GetAdr(0, "NPN_RequestRead", S.VAL(LONGINT, NPNRequestRead));
		Kernel.GetAdr(0, "NPN_NewStream", S.VAL(LONGINT, NPNNewStream));
		Kernel.GetAdr(0, "NPN_Write", S.VAL(LONGINT, NPNWrite));
		Kernel.GetAdr(0, "NPN_DestroyStream", S.VAL(LONGINT, NPNDestroyStream));
		Kernel.GetAdr(0, "NPN_Status", S.VAL(LONGINT, NPNStatus));	
		Kernel.GetAdr(0, "NPN_MemAlloc", S.VAL(LONGINT, NPNMemAlloc));	
		Kernel.GetAdr(0, "NPN_MemFree", S.VAL(LONGINT, NPNMemFree));	
		Kernel.GetAdr(0, "NPN_MemFlush", S.VAL(LONGINT, NPNMemFlush));
		Kernel.GetAdr(0, "NPN_WindowHandler", S.VAL(LONGINT, NPNWindowHandler));
		Kernel.GetAdr(0, "NPP_UpCall", S.VAL(LONGINT, InstallUpCall));

		nppShutdown := NPPShutdown; InstallUpCall("NPP_Shutdown", S.VAL(LONGINT, nppShutdown));
		nppNew := NPPNew; InstallUpCall("NPP_New", S.VAL(LONGINT, nppNew));
		nppDestroy := NPPDestroy; InstallUpCall("NPP_Destroy", S.VAL(LONGINT, nppDestroy));
		nppSetWindow := NPPSetWindow; InstallUpCall("NPP_SetWindow", S.VAL(LONGINT, nppSetWindow));
		nppNewStream := NPPNewStream; InstallUpCall("NPP_NewStream", S.VAL(LONGINT, nppNewStream));
		nppWriteReady := NPPWriteReady; InstallUpCall("NPP_WriteReady", S.VAL(LONGINT, nppWriteReady));
		nppWrite := NPPWrite; InstallUpCall("NPP_Write", S.VAL(LONGINT, nppWrite));
		nppDestroyStream := NPPDestroyStream; InstallUpCall("NPP_DestroyStream", S.VAL(LONGINT, nppDestroyStream));
		nppStreamAsFile := NPPStreamAsFile; InstallUpCall("NPP_StreamAsFile", S.VAL(LONGINT, nppStreamAsFile));
		nppHandleEvent := NPPHandleEvent; InstallUpCall("NPP_HandleEvent", S.VAL(LONGINT, nppHandleEvent));
		nppPrint := NPPPrint; InstallUpCall("NPP_Print", S.VAL(LONGINT, nppPrint));
		nppWindowHandler := NPPWindowHandler; InstallUpCall("NPP_WindowHandler", S.VAL(LONGINT, nppWindowHandler));
		
		mod := Kernel.LoadLibrary("User32");
		Kernel.GetAdr(mod, "SetWindowLongA", S.VAL(LONGINT, SetWindowLong));
		Kernel.GetAdr(mod, "SetTimer", S.VAL(LONGINT, SetTimer));
		Kernel.GetAdr(mod, "KillTimer", S.VAL(LONGINT, KillTimer));
	END Init;

BEGIN Init
END NPAPI.
