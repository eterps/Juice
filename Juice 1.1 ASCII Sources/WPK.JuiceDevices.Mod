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

MODULE JuiceDevices;
	IMPORT SYSTEM, Kernel:= JuiceKernel;

	CONST
		plainFace* = 0;	(** Plain font face *)
		boldFace* = 1;	(** Bold font face *)
		italicFace* = 2;	(** italic font face *)

		replace = 0;	(* Replace paint mode *)
	
		leftButton* = 0;
		middleButton* = 1;
		rightButton* = 2;

		SRCCopy = 0CC0020H;
		PSInsideFrame = 6;
		TRANSPARENT = 1; LFFaceSize = 32;
		BitsPixel = 12; LogPixelsX = 88; LogPixelsY = 90;
		FWNormal = 400; FWBold = 700;
		DefaultQuality = 0X; DefaultCharSet= 01X; DefaultPitch = 0;
		OUTDefaultPrecis = 0X; CLIPDefaultPrecis = 0X; FFDontCare = 0;
		
		RGNAnd = 1;
		RGNOr = 2;
		RGNDiff = 4;
		RGNCopy = 5;
		
		NULLBRUSH = 5;

	TYPE
		LOGFONT = RECORD
			height, width, escapement, orientation, weight: LONGINT;
			italic, underline, strikeOut, charSet: CHAR;
			outPrecision, clipPrecision, quality, pitchAndFamily: CHAR;
			faceName: ARRAY LFFaceSize OF CHAR
		END;

		Device* = POINTER TO DeviceDesc;	(** graphic device, might me a screen, printer or offscreen device *)
		DeviceDesc* = RECORD
			hwnd: LONGINT;	(* must be first *)
			w*, h*: INTEGER;	(** top left position, width and height of device *)
			depth*: INTEGER;	(** device color depth *)
			hres*, vres*: INTEGER;	(** horizontal and vertical resolution in pixel per inch *)
			hdc, hbrush, hpen, hfont, hbitmap, col, backC, width, resY: LONGINT;
			logFont: LOGFONT; ascent: INTEGER;
		END;

		Mask* = POINTER TO MaskDesc;	(** Clip mask *)
		MaskDesc = RECORD
			hrgn: LONGINT
		END;

		RGBColor* = RECORD	(** Rgb color, red, green and blue in [0..255] *)
			red*, green*, blue*: INTEGER
		END;

		Point* = RECORD x*, y*: INTEGER END;

		Rect = RECORD
			left, top, right, bottom: LONGINT
		END;

		FontMetric* = RECORD
			ascent*: INTEGER;	(** Max distance above baseline *)
			descent*: INTEGER;	(** Max distance below baseline *)
			leading*: INTEGER;	(** Distance between lines *)
		END;	

	VAR
		white*, black*, red*, green*, blue*: RGBColor;	(** Default colors *)
		cur: Device;
		ret: LONGINT;
		rect: Rect;
		(* GDI32 *)
		GetWindowDC: PROCEDURE (hwnd: LONGINT): LONGINT;
		ReleaseDC: PROCEDURE (hwnd, hdc: LONGINT): LONGINT;
		GdiFlush: PROCEDURE (): LONGINT;
		fillRect: PROCEDURE (hdc, rect, hbrush: LONGINT): LONGINT;
		FillRgn: PROCEDURE (hdc, hrgn, hbrush: LONGINT);
		MoveTo: PROCEDURE (hdc, x, y, old: LONGINT): LONGINT;
		LineTo: PROCEDURE (hdc, x, y: LONGINT): LONGINT;
		SetPixel: PROCEDURE (hdc, x, y, color: LONGINT): LONGINT;
		Ellipse: PROCEDURE (hdc, x0, y0, x1, y1: LONGINT): LONGINT;
		Rectangle: PROCEDURE (hdc, x0, y0, x1, y1: LONGINT): LONGINT;
		Polyline: PROCEDURE (hdx, points, cpoints: LONGINT): LONGINT;
		CreateSolidBrush: PROCEDURE (colorref: LONGINT): LONGINT;
		DeleteObject: PROCEDURE (hobj: LONGINT): LONGINT;
		GetNearestColor: PROCEDURE (hdc, color: LONGINT): LONGINT;
		SetTextColor: PROCEDURE (hdc, color: LONGINT): LONGINT;
		CreatePen: PROCEDURE (style, width, color: LONGINT): LONGINT;
		SelectObject: PROCEDURE (hdc, obj: LONGINT): LONGINT;
		TextOut: PROCEDURE (hdc, x, y, str, len: LONGINT): LONGINT;
		SetBkMode: PROCEDURE (hdc, mode: LONGINT): LONGINT;
		GetDeviceCaps: PROCEDURE (hdc, index: LONGINT): LONGINT;
		CreateFontIndirect: PROCEDURE (lplf: LONGINT): LONGINT;
		CreateRectRgn: PROCEDURE (left, top, right, bottom: LONGINT): LONGINT;
		CreateEllipticRgn: PROCEDURE (left, top, right, bottom: LONGINT): LONGINT;
		CreatePolygonRgn: PROCEDURE (ptrs, cpoints, fillmode: LONGINT): LONGINT;
		CombineRgn: PROCEDURE (dstrgn, srcrgn1, srcrgn2, mode: LONGINT): LONGINT;
		SelectClipRgn: PROCEDURE (hdc, hrgn: LONGINT): LONGINT;
		SetBkColor: PROCEDURE (hdc, color: LONGINT): LONGINT;
		CreateCompatibleDC: PROCEDURE (hdc: LONGINT): LONGINT;
		CreateCompatibleBitmap: PROCEDURE (hdc, width, height: LONGINT): LONGINT;
		BitBlt: PROCEDURE (dest, xDest, yDest, w, h, src, xSrc, ySrc, rop: LONGINT): LONGINT;
		CreateDC: PROCEDURE (driver, device, output, initData: LONGINT): LONGINT;
		SetWindowPos: PROCEDURE (hwnd, hwndInsert, x, y, w, h: LONGINT; flags: LONGINT);
		SetFocusA: PROCEDURE (wnd: LONGINT);
		ValidateRect: PROCEDURE (hWindow: LONGINT; lpRect: LONGINT);
		InvalidateRect: PROCEDURE (wnd: LONGINT; rect: LONGINT; eraseBack: INTEGER);
		UpdateWindow: PROCEDURE (wnd: LONGINT);
		GetLastError: PROCEDURE (): LONGINT;
		GetTextExtentPoint: PROCEDURE (hdc: LONGINT; str: LONGINT; len: LONGINT; size: LONGINT): LONGINT;
		GetTextMetrics: PROCEDURE (hdc: LONGINT; tm: LONGINT): LONGINT;
		GetStockObject: PROCEDURE (type: LONGINT): LONGINT;
		hNullBrush: LONGINT;

	PROCEDURE RGB(r, g, b: INTEGER): LONGINT;
		VAR cref: LONGINT;
	BEGIN
		cref := LONG(r)+256*LONG(g)+256*256*LONG(b);
		RETURN cref
	END RGB;

	(** Restore the device after previous drawing calls *)
	PROCEDURE Restore*(D: Device);
	BEGIN
		ret := GdiFlush();
		ret := SelectClipRgn(D.hdc, 0);
		ValidateRect(D.hwnd, 0);
	END Restore;

	(** default is black *)
	PROCEDURE SetForeColor*(col: RGBColor);
		VAR hpen: LONGINT;
	BEGIN
		ret := DeleteObject(cur.hbrush); cur.hbrush := 0;
		hpen := cur.hpen; cur.hpen := 0;
		cur.col := RGB(col.red, col.green, col.blue);
		cur.col := GetNearestColor(cur.hdc, cur.col);
		cur.hbrush := CreateSolidBrush(cur.col);
		ret := SetTextColor(cur.hdc, cur.col);
		cur.hpen := CreatePen(PSInsideFrame, cur.width, cur.col);
		ret := SelectObject(cur.hdc, cur.hpen);
		ret := DeleteObject(hpen);
	END SetForeColor;

	(* Set the background color for subsequent calls; default is white *)
	PROCEDURE SetBackColor(col: RGBColor);
	BEGIN
		cur.backC := RGB(col.red, col.green, col.blue);
		cur.backC := GetNearestColor(cur.hdc, cur.backC);
		ret := SetBkColor(cur.hdc, cur.backC);
		ret := SetBkMode(cur.hdc, TRANSPARENT);
	END SetBackColor;
	
	(* Set the drawing mode for subsequent calls; default is replace *)
	PROCEDURE SetMode (mode: INTEGER);
	BEGIN
	END SetMode;
	
	(** default is 1 *)
	PROCEDURE SetLineWidth*(width: INTEGER);
		VAR hpen: LONGINT;
	BEGIN
		hpen := cur.hpen; cur.hpen := 0;
		cur.width := width;
		cur.hpen := CreatePen(PSInsideFrame, cur.width, cur.col);
		ret := SelectObject(cur.hdc, cur.hpen);
		ret := DeleteObject(hpen); 
	END SetLineWidth;

	PROCEDURE ^ GetFontMetrics* (VAR metric: FontMetric);

	(** default is Times *)
	PROCEDURE SetFont*(fnt: ARRAY OF CHAR);
		VAR hfont: LONGINT; metrics: FontMetric;
	BEGIN
		hfont := cur.hfont; cur.hfont := 0;
		COPY(fnt, cur.logFont.faceName);
		cur.hfont := CreateFontIndirect(SYSTEM.ADR(cur.logFont));
		ret := SelectObject(cur.hdc, cur.hfont);
		ret := DeleteObject(hfont); 
		GetFontMetrics(metrics); cur.ascent := metrics.ascent;
	END SetFont;

	(** default is plainFace *)
	PROCEDURE SetFontFace*(face: INTEGER);
		VAR hfont: LONGINT; metrics: FontMetric;
	BEGIN
		hfont := cur.hfont; cur.hfont := 0;
		IF face = boldFace THEN
			cur.logFont.italic := 0X; cur.logFont.weight := FWBold
		ELSIF face = italicFace THEN
			cur.logFont.italic := 01X; cur.logFont.weight := FWNormal
		ELSE
			cur.logFont.italic := 0X; cur.logFont.weight := FWNormal
		END;
		cur.hfont := CreateFontIndirect(SYSTEM.ADR(cur.logFont));
		ret := SelectObject(cur.hdc, cur.hfont);
		ret := DeleteObject(hfont); 
		GetFontMetrics(metrics); cur.ascent := metrics.ascent;
	END SetFontFace;

	PROCEDURE PointToLogSize(D: Device; point: LONGINT): LONGINT;
		VAR h: LONGINT;
	BEGIN
		h := point*D.resY;
		IF (h MOD 72) >= 36 THEN
			RETURN -(1 + (h DIV 72))
		ELSE
			RETURN -(h DIV 72)
		END
	END PointToLogSize;

	(** default is 10 *)
	PROCEDURE SetFontSize*(size: INTEGER);
		VAR hfont: LONGINT; metrics: FontMetric;
	BEGIN
		hfont := cur.hfont; cur.hfont := 0;
		cur.logFont.height := PointToLogSize(cur, size);
		cur.hfont := CreateFontIndirect(SYSTEM.ADR(cur.logFont));
		ret := SelectObject(cur.hdc, cur.hfont);
		ret := DeleteObject(hfont);
		GetFontMetrics(metrics); cur.ascent := metrics.ascent;
	END SetFontSize;

	(** Draw dot at coordinate (x, y) with given color *)
	PROCEDURE Dot* (x, y: INTEGER);
	BEGIN
		ret := SetPixel(cur.hdc, x, y, cur.col);
	END Dot;

	(** Draw a line from (x0, y0) to (x1, y1) with given line width and color *)
	PROCEDURE Line*(x0, y0, x1, y1: INTEGER);
	BEGIN
		ret := MoveTo(cur.hdc, x0, y0, 0);
		ret := LineTo(cur.hdc, x1, y1);
		ret := LineTo(cur.hdc, x1+1, y1+1);
	END Line;

	(** Draw a rectangle (x, y, w, h) with given line width and color *)
	PROCEDURE FrameRect*(x, y, w, h: INTEGER);
	BEGIN
		ret := SelectObject(cur.hdc, hNullBrush);
		ret := Rectangle(cur.hdc, x, y, x+w, y+h);
		ret := SelectObject(cur.hdc, cur.hbrush);
	END FrameRect;

	(** Draw a filled rectangle (x, y, w, h) with given color *)
	PROCEDURE FillRect*(x, y, w, h: INTEGER);
	BEGIN
		rect.left := x; rect.bottom := y;
		rect.right := x+w; rect.top := y+h;
		ret := fillRect(cur.hdc, SYSTEM.ADR(rect), cur.hbrush);
	END FillRect;

	(** Draw a polyline with points P. Len should contains the number of points *)
	PROCEDURE FramePolyLine* (VAR P: ARRAY OF Point; len: INTEGER);
		VAR pts: POINTER TO ARRAY OF RECORD x, y: LONGINT END; i: INTEGER;
	BEGIN
		ret := SelectObject(cur.hdc, hNullBrush);
		NEW(pts, len);
		i := 0;
		WHILE (i < LEN(P)) & (i < len) DO
			pts[i].x := P[i].x; pts[i].y := P[i].y;
			INC(i)
		END;
		ret := Polyline(cur.hdc, SYSTEM.ADR(pts[0]), len);
		ret := SelectObject(cur.hdc, cur.hbrush);
	END FramePolyLine;

	(** Draw a filled polyline with points P. Len should contains the number of points *)
	PROCEDURE FillPolyLine* (VAR P: ARRAY OF Point; len: INTEGER);
		VAR pts: POINTER TO ARRAY OF RECORD x, y: LONGINT END; i: INTEGER; hrgn: LONGINT;
	BEGIN
		NEW(pts, len);
		i := 0;
		WHILE (i < LEN(P)) & (i < len) DO
			pts[i].x := P[i].x; pts[i].y := P[i].y;
			INC(i)
		END;
		hrgn := CreatePolygonRgn(SYSTEM.ADR(pts[0]), len, 0);
		FillRgn(cur.hdc, hrgn, cur.hbrush);
		IF hrgn # 0 THEN ret := DeleteObject(hrgn) END;  
	END FillPolyLine;

	(** Draw a circle or ellipse with boundary (x, y, w, h) *)
	PROCEDURE FrameOval* (x, y, w, h: INTEGER);
	BEGIN
		ret := SelectObject(cur.hdc, hNullBrush);
		ret := Ellipse(cur.hdc, x, y, x+w, y+h);
		ret := SelectObject(cur.hdc, cur.hbrush);
	END FrameOval;

	(** Draw a filled circle or ellipse with boundary (x, y, w, h) *)
	PROCEDURE FillOval* (x, y, w, h: INTEGER);
		VAR hrgn: LONGINT;
	BEGIN
		hrgn := CreateEllipticRgn(x, y, x+w, y+h);
		FillRgn(cur.hdc, hrgn, cur.hbrush);
		IF hrgn # 0 THEN ret := DeleteObject(hrgn) END;
	END FillOval;


	(** Draw a string s at position (x, y) with given color, fontname, fontsize and fontface *)
	PROCEDURE String*(x, y: INTEGER; s: ARRAY OF CHAR);
		VAR len: LONGINT;
	BEGIN
		len := 0;
		WHILE s[len] # 0X DO
			INC(len)
		END;
		IF len > 0 THEN
			ret := TextOut(cur.hdc, x, y-cur.ascent, SYSTEM.ADR(s), len)
		END
	END String;

	(** Get metric data of current font *)
	PROCEDURE GetFontMetrics* (VAR metric: FontMetric);
		VAR m: RECORD tmHeight, tmAscent, tmDescent, tmInternalLeading, tmExternalLeading, tmAveCharWidth,
			tmMaxCharWidth: LONGINT; dummy: ARRAY 25 OF SHORTINT END;
	BEGIN
		ret := GetTextMetrics(cur.hdc, SYSTEM.ADR(m.tmHeight));
		metric.ascent := SHORT(m.tmAscent);
		metric.descent := SHORT(m.tmDescent);
		metric.leading := SHORT(m.tmExternalLeading);
	END GetFontMetrics;


	(** Get width and height of given string s. Increment y by h to draw the next line *)
	PROCEDURE GetStringSize* (s: ARRAY OF CHAR; VAR w, h: INTEGER);
		VAR size: RECORD w, h: LONGINT END; len: LONGINT; metric: FontMetric;
	BEGIN
		len := 0; WHILE s[len] # 0X DO Kernel.Str("x"); INC(len) END;
		IF len = 0 THEN
			GetFontMetrics(metric);
			Kernel.Int(metric.ascent); Kernel.Str(" "); Kernel.Int(metric.descent); Kernel.Str(" "); Kernel.Int(metric.leading); Kernel.Ln;
			h := metric.ascent + metric.descent + metric.leading;
			w := 0
		ELSE
			ret := GetTextExtentPoint(cur.hdc, SYSTEM.ADR(s[0]), len, SYSTEM.ADR(size.w));
			w := SHORT(size.w); h := SHORT(size.h)
		END
	END GetStringSize;

	(** Copy block (sx, sy, w, h) from source device S to (dx, dy, w, h) in destination device D *)
	PROCEDURE CopyBlock*(S, D: Device; sx, sy, w, h, dx, dy: INTEGER);
	BEGIN
		ret := BitBlt(D.hdc, dx, dy, w, h, S.hdc, sx, sy, SRCCopy);
		ValidateRect(D.hwnd, 0);
	END CopyBlock;	

	PROCEDURE *FinalizeMask(M: PTR);
	BEGIN
		WITH M: Mask DO
			IF M.hrgn # 0 THEN
				ret := DeleteObject(M.hrgn);  M.hrgn := 0
			END
		END
	END FinalizeMask;

	(** Create new clip mask with a rectangular boundary x, y, w, h *)
	PROCEDURE NewRectMask*(VAR M: Mask; x, y, w, h: INTEGER);
	BEGIN
		NEW(M); 
		M.hrgn := CreateRectRgn(x, y, x+w, y+h);
		Kernel.RegisterObject(M, FinalizeMask)
	END NewRectMask;

	(** Create new clip mask with an oval boundary x, y, w, h *)
	PROCEDURE NewOvalMask*(VAR M: Mask; x, y, w, h: INTEGER);
	BEGIN
		NEW(M);
		M.hrgn := CreateEllipticRgn(x, y, x+w, y+h);
		Kernel.RegisterObject(M, FinalizeMask);
	END NewOvalMask;

	(** Create new clip mask with a polyline boundary *)
	PROCEDURE NewPolyMask* (VAR M: Mask; VAR P: ARRAY OF Point; len: INTEGER);
		VAR pts: POINTER TO ARRAY OF RECORD x, y: LONGINT END; i: INTEGER;
	BEGIN
		NEW(M);
		NEW(pts, len);
		i := 0;
		WHILE (i < LEN(P)) & (i < len) DO
			pts[i].x := P[i].x; pts[i].y := P[i].y;
			INC(i)
		END;
		M.hrgn := CreatePolygonRgn(SYSTEM.ADR(pts[0]), len, 0);
		Kernel.RegisterObject(M, FinalizeMask);
	END NewPolyMask;		
	
	(** Copy source mask S to destination mask D *)												
	PROCEDURE CopyMask* (S: Mask; VAR D: Mask);
		VAR res: LONGINT;
	BEGIN
		NEW(D); 		
		D.hrgn := CreateRectRgn(0, 0, 0, 0); Kernel.RegisterObject(D, FinalizeMask);
		res := CombineRgn(D.hrgn, S.hrgn, 0, RGNCopy);
		Kernel.RegisterObject(D, FinalizeMask);		
	END CopyMask;

	(** Calculate the difference D of source mask S0 and S1 *)		
	PROCEDURE DiffMask* (S0, S1: Mask; VAR D: Mask);
		VAR res: LONGINT;
	BEGIN
		NEW(D); D.hrgn := CreateRectRgn(0, 0, 0, 0); Kernel.RegisterObject(D, FinalizeMask);
		res := CombineRgn(D.hrgn, S0.hrgn, S1.hrgn, RGNDiff);
		Kernel.RegisterObject(D, FinalizeMask);
	END DiffMask;
	
	(** Calculate the union D of source mask S0 and S1 *)		
	PROCEDURE UnionMask* (S0, S1: Mask; VAR D: Mask);
		VAR res: LONGINT;
	BEGIN
		NEW(D); D.hrgn := CreateRectRgn(0, 0, 0, 0); Kernel.RegisterObject(D, FinalizeMask);
		res := CombineRgn(D.hrgn, S0.hrgn, S1.hrgn, RGNOr);
		Kernel.RegisterObject(D, FinalizeMask);
	END UnionMask;
	
	(** Calculate the intersection D of source mask S0 and S1 *)		
	PROCEDURE SectMask* (S0, S1: Mask; VAR D: Mask);
		VAR res: LONGINT;
	BEGIN
		NEW(D); D.hrgn := CreateRectRgn(0, 0, 0, 0); Kernel.RegisterObject(D, FinalizeMask);
		res := CombineRgn(D.hrgn, S0.hrgn, S1.hrgn, RGNAnd);
		Kernel.RegisterObject(D, FinalizeMask);
	END SectMask;

	(** Set the clip mask M for subsequent drawing operations *)		
	PROCEDURE SetMask*(M: Mask);
	BEGIN
		ret := SelectClipRgn(cur.hdc, M.hrgn)
	END SetMask;		

	PROCEDURE LongOr(a, b: LONGINT): LONGINT;
		VAR res: SET;
	BEGIN
		res := SYSTEM.VAL(SET, a) + SYSTEM.VAL(SET, b);
		RETURN SYSTEM.VAL(LONGINT, res)
	END LongOr;

	(* for internal use only *)
	PROCEDURE FinalizeDevice*(D: Device);
	BEGIN
		IF cur = D THEN
			cur := NIL
		END;
		IF D.hbrush # 0 THEN
			ret := DeleteObject(D.hbrush); D.hbrush := 0
		END;
		IF D.hpen # 0 THEN
			ret := DeleteObject(D.hpen); D.hpen := 0
		END;
		IF D.hfont # 0 THEN
			ret := DeleteObject(D.hfont); D.hfont := 0
		END;
		IF D.hbitmap # 0 THEN
			ret := DeleteObject(D.hbitmap); D.hbitmap := 0
		END;
		(*
		IF D.hdc # 0 THEN
			IF D.hwnd # 0 THEN
				ret := ReleaseDC(D.hwnd, D.hdc); D.hwnd := 0
			END;
			ret := DeleteObject(D.hdc); D.hdc := 0
		END
		*)
	END FinalizeDevice;

	(** Setup the device for subsequent drawing calls *)
	PROCEDURE Setup*(D: Device);
	BEGIN
		cur := D;
		SetForeColor(black);
		SetBackColor(white);
		SetMode(replace);
		SetLineWidth(1);
		SetFont("Times");
		SetFontSize(10);
		SetFontFace(plainFace);
	END Setup;

	PROCEDURE InitDevice(D: Device; hdc: LONGINT);
	BEGIN
		D.hdc := hdc; D.hbrush := 0; D.hpen := 0;
		D.col := RGB(0, 0, 0); D.backC := RGB(255, 255, 255); D.width := 1;
		ret := GetDeviceCaps(D.hdc, BitsPixel); D.depth := SHORT(ret);
		ret := GetDeviceCaps(D.hdc, LogPixelsX); D.hres := SHORT(ret);
		ret := GetDeviceCaps(D.hdc, LogPixelsY); D.vres := SHORT(ret);
		D.resY := GetDeviceCaps(D.hdc, LogPixelsY);
		D.logFont.faceName := "Times";
		D.logFont.height := PointToLogSize(D, 10);
		D.logFont.italic := 0X;
		D.logFont.underline := 0X;
		D.logFont.strikeOut := 0X;
		D.logFont.weight := FWNormal;
		D.logFont.width := 0;
		D.logFont.escapement := 0;
		D.logFont.orientation := 0;
		D.logFont.charSet := DefaultCharSet;
		D.logFont.outPrecision := OUTDefaultPrecis;
		D.logFont.clipPrecision := CLIPDefaultPrecis;
		D.logFont.quality := DefaultQuality;
		D.logFont.pitchAndFamily := CHR(LongOr(DefaultPitch, FFDontCare));
		D.hfont := CreateFontIndirect(SYSTEM.ADR(D.logFont));
		D.col := GetNearestColor(D.hdc, D.col);
		D.hbrush := CreateSolidBrush(D.col);
		ret := SetTextColor(D.hdc, D.col);
		ret := SetBkMode(D.hdc, TRANSPARENT);
		D.hpen := CreatePen(PSInsideFrame, D.width, D.col);
		ret := SelectObject(D.hdc, D.hpen);
		ret := SelectObject(D.hdc, D.hfont);
		D.backC := GetNearestColor(D.hdc, D.backC);
		ret := SetBkColor(D.hdc, D.backC);
		(* Kernel.RegisterObject(D, FinalizeDevice) *)
	END InitDevice;

	(** Allocate a new offscreen device with width w, height h and given depth *)		
	PROCEDURE NewDevice*(VAR D: Device; w, h, depth: INTEGER);
		VAR
			hdcScreen: LONGINT;
			driver: ARRAY 16 OF CHAR;
	BEGIN
		driver := "DISPLAY";
		hdcScreen := CreateDC(SYSTEM.ADR(driver), 0, 0, 0);
		NEW(D); D.hwnd := 0;
		D.w := w; D.h := h;
		D.hdc := CreateCompatibleDC(hdcScreen);
		D.hbitmap := CreateCompatibleBitmap(hdcScreen, w, h);
		ret := SelectObject(D.hdc, D.hbitmap);
		InitDevice(D, D.hdc);
		ret := DeleteObject(hdcScreen);
	END NewDevice;

	(* for internal use only *)
	PROCEDURE SetupDevice*(D: Device; x, y, w, h: INTEGER; hwnd: LONGINT; new: BOOLEAN);
	BEGIN
		D.w := w; D.h := h;
		D.hdc := GetWindowDC(hwnd); D.hwnd := hwnd;
		IF new THEN
			D.hbitmap := 0;
			InitDevice(D, D.hdc)
		END;
		InvalidateRect(hwnd, 0, 0);
		UpdateWindow(hwnd);
	END SetupDevice;
	
	(* for internal use only *)
	PROCEDURE SetFocus*(D: Device);
	BEGIN
		SetFocusA(D.hwnd);
	END SetFocus;

	PROCEDURE InitAPI();
		VAR mod: LONGINT;
	BEGIN
		mod := Kernel.LoadLibrary("User32");
		Kernel.GetAdr(mod, "GetWindowDC", SYSTEM.VAL(LONGINT, GetWindowDC));
		Kernel.GetAdr(mod, "ReleaseDC", SYSTEM.VAL(LONGINT, ReleaseDC));
		Kernel.GetAdr(mod, "FillRect", SYSTEM.VAL(LONGINT, fillRect));
		Kernel.GetAdr(mod, "SetWindowPos", SYSTEM.VAL(LONGINT, SetWindowPos));
		Kernel.GetAdr(mod, "SetFocus", SYSTEM.VAL(LONGINT, SetFocusA));
		Kernel.GetAdr(mod, "ValidateRect", SYSTEM.VAL(LONGINT, ValidateRect));
		Kernel.GetAdr(mod, "InvalidateRect", SYSTEM.VAL(LONGINT, InvalidateRect));
		Kernel.GetAdr(mod, "UpdateWindow", SYSTEM.VAL(LONGINT, UpdateWindow));
		
		mod := Kernel.LoadLibrary("Kernel32");
		Kernel.GetAdr(mod, "GetLastError", SYSTEM.VAL(LONGINT, GetLastError));

		mod := Kernel.LoadLibrary("GDI32");
		Kernel.GetAdr(mod, "GdiFlush", SYSTEM.VAL(LONGINT, GdiFlush));
		Kernel.GetAdr(mod, "MoveToEx", SYSTEM.VAL(LONGINT, MoveTo));
		Kernel.GetAdr(mod, "LineTo", SYSTEM.VAL(LONGINT, LineTo));
		Kernel.GetAdr(mod, "SetPixel", SYSTEM.VAL(LONGINT, SetPixel));
		Kernel.GetAdr(mod, "Ellipse", SYSTEM.VAL(LONGINT, Ellipse));
		Kernel.GetAdr(mod, "Rectangle", SYSTEM.VAL(LONGINT, Rectangle));
		Kernel.GetAdr(mod, "Polyline", SYSTEM.VAL(LONGINT, Polyline));
		Kernel.GetAdr(mod, "CreateSolidBrush", SYSTEM.VAL(LONGINT, CreateSolidBrush));
		Kernel.GetAdr(mod, "DeleteObject", SYSTEM.VAL(LONGINT, DeleteObject));
		Kernel.GetAdr(mod, "GetNearestColor", SYSTEM.VAL(LONGINT, GetNearestColor));
		Kernel.GetAdr(mod, "SetTextColor", SYSTEM.VAL(LONGINT, SetTextColor));
		Kernel.GetAdr(mod, "CreatePen", SYSTEM.VAL(LONGINT, CreatePen));
		Kernel.GetAdr(mod, "SelectObject", SYSTEM.VAL(LONGINT, SelectObject));
		Kernel.GetAdr(mod, "TextOutA", SYSTEM.VAL(LONGINT, TextOut));
		Kernel.GetAdr(mod, "SetBkMode", SYSTEM.VAL(LONGINT, SetBkMode));
		Kernel.GetAdr(mod, "GetDeviceCaps", SYSTEM.VAL(LONGINT, GetDeviceCaps));
		Kernel.GetAdr(mod, "CreateFontIndirectA", SYSTEM.VAL(LONGINT, CreateFontIndirect));
		Kernel.GetAdr(mod, "CreateRectRgn", SYSTEM.VAL(LONGINT, CreateRectRgn));
		Kernel.GetAdr(mod, "CreateEllipticRgn", SYSTEM.VAL(LONGINT, CreateEllipticRgn));
		Kernel.GetAdr(mod, "CreatePolygonRgn", SYSTEM.VAL(LONGINT, CreatePolygonRgn));
		Kernel.GetAdr(mod, "FillRgn", SYSTEM.VAL(LONGINT, FillRgn));
		Kernel.GetAdr(mod, "CombineRgn", SYSTEM.VAL(LONGINT, CombineRgn));
		Kernel.GetAdr(mod, "SelectClipRgn", SYSTEM.VAL(LONGINT, SelectClipRgn));
		Kernel.GetAdr(mod, "SetBkColor", SYSTEM.VAL(LONGINT, SetBkColor));
		Kernel.GetAdr(mod, "CreateCompatibleDC", SYSTEM.VAL(LONGINT, CreateCompatibleDC));
		Kernel.GetAdr(mod, "CreateCompatibleBitmap", SYSTEM.VAL(LONGINT, CreateCompatibleBitmap));
		Kernel.GetAdr(mod, "BitBlt", SYSTEM.VAL(LONGINT, BitBlt));
		Kernel.GetAdr(mod, "CreateDCA", SYSTEM.VAL(LONGINT, CreateDC));
		Kernel.GetAdr(mod, "GetTextExtentPointA", SYSTEM.VAL(LONGINT, GetTextExtentPoint));
		Kernel.GetAdr(mod, "GetTextMetricsA", SYSTEM.VAL(LONGINT, GetTextMetrics));
		Kernel.GetAdr(mod, "GetStockObject", SYSTEM.VAL(LONGINT, GetStockObject));

		hNullBrush := GetStockObject(NULLBRUSH);
	END InitAPI;

BEGIN
	white.red := 255; white.green := 255; white.blue := 255;
	black.red := 0; black.green := 0; black.blue := 0;
	red.red := 255; red.green := 0; red.blue := 0;
	green.red := 0; green.green := 255; green.blue := 0;
	blue.red := 0; blue.green := 0; blue.blue := 255;
	cur := NIL; InitAPI();
END JuiceDevices.
