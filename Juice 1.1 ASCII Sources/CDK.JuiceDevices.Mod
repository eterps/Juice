MODULE JuiceDevices;

	IMPORT Display, Display3, Fonts, Regions, Raster, Mappings, Pens, FancyPens;

	CONST
		leftButton* = 0;	(** Left mouse button *)
		middleButton* = 1;	(** Middle mouse button *)
		rightButton* = 2;	(** Right mouse button *)

		plainFace* = 0;	(** Plain font face *)
		boldFace* = 1;	(** Bold font face *)
		italicFace* = 2;	(** italic font face *)

		replace = 0;	(* Replace paint mode *)

	TYPE
		RGBColor* = RECORD	(** RGB color, red, green and blue in [0..255] *)
			red*, green*, blue*: INTEGER
		END;		

		Point* = RECORD x*, y*: INTEGER END;

		Mask* = POINTER TO MaskDesc;	(** Clipping mask *)
		MaskDesc = RECORD
			rgn: Regions.Region;
		END;

		FontMetric* = RECORD
			ascent*: INTEGER;	(** Max distance above baseline *)
			descent*: INTEGER;	(** Max distance below baseline *)
			leading*: INTEGER;	(** Distance between lines *)
		END;	

		Device* = POINTER TO DeviceDesc;	(** Graphic device, might me a screen, printer or offscreen device *)
		DeviceDesc* = RECORD	
			w*, h*: INTEGER;	(** Width and height of device, top left ist always (0, 0) *)
			depth*: INTEGER;	(** Device color depth *)
			hres*, vres*: INTEGER;	(** Horizontal and vertical resolution in pixel per inch *)
			portx, porty: INTEGER;
			port: Raster.Port;
			fgCol: Raster.Color;
			mode, width: INTEGER;
			stroker: Pens.ColorStrokePen;
			filler: Pens.ColorFillPen;
			wide: FancyPens.BevelPen;
			rgn: Raster.Region;
			printer: BOOLEAN;
			fnt: ARRAY 32 OF CHAR;
			face, size: INTEGER;
			offscreen: BOOLEAN;
		END;
	
				
	VAR
		white*, black*, red*, green*, blue*: RGBColor;	(** Default colors *)
		cur: Device;
		rgn1, rgn2: Regions.Region;
	
	(* auxiliaries *)
	
	PROCEDURE SwapY(VAR y: INTEGER; h: INTEGER);
	BEGIN
		y := cur.h - y - h;
	END SwapY;
	
	PROCEDURE NormalizeXYWH(VAR x, y, w, h: INTEGER);
	BEGIN
		IF w < 0 THEN w:= -w; x:= x - w + 1 END;
		IF h < 0 THEN h:= -h; y:= y - h + 1 END;
	END NormalizeXYWH;
	
	(** Mask operations *)
	
	(** Create new clipping mask with a rectangular boundary x, y, w, h *)
	PROCEDURE NewRectMask* (VAR M: Mask; x, y, w, h: INTEGER);
		VAR rect: Regions.Rectangle;
	BEGIN
		SwapY(y, h);
		rect.x := x; rect.y := y; rect.w := w; rect.h := h;
		NEW(M); NEW(M.rgn); Regions.InitRegion(M.rgn, 0);
		Regions.SetRegionToRect(M.rgn, rect);
	END NewRectMask;
	
	(** Create new elliptic clipping mask with boundary x, y, w, h *)
	PROCEDURE NewOvalMask* (VAR M: Mask; x, y, w, h: INTEGER);
		VAR pen: Pens.Pen;
	BEGIN
		SwapY(y, h);
		NEW(M); 
		pen := cur.filler;
		pen.do.Open(pen, cur.port, Mappings.Identity);
		pen.do.Begin(pen, x, y + h DIV 2, 0, 0, 0);
		pen.do.AddArc(pen, x, y + h DIV 2, x + w DIV 2, y + h DIV 2, 0, h DIV 2, w DIV 2, 0);
		pen.do.End(pen, 0, 0);
		M.rgn := pen(Pens.FillPen).reg;
	END NewOvalMask;		
	
	(** Create new clipping mask with a polyline boundary *)
	PROCEDURE NewPolyMask* (VAR M: Mask; VAR P: ARRAY OF Point; len: INTEGER);
		VAR pen: Pens.Pen; i, y: INTEGER;
	BEGIN
		NEW(M);
		i := 0; pen := cur.filler;
		pen.do.Open(pen, cur.port, Mappings.Identity);
		IF (len > 0) & (LEN(P) > 0) THEN 
			y:= P[i].y; SwapY(y, 0);
			pen.do.Begin(pen, P[i].x, y, 0, 0, 0); INC(i) 
		END;
		WHILE (i < len) & (i < LEN(P)) DO
			y:= P[i].y; SwapY(y, 0);
			pen.do.AddLine(pen, P[i].x, y);
			INC(i)
		END;
		pen.do.End(pen, 0, 0);
		M.rgn := pen(Pens.FillPen).reg;
	END NewPolyMask;		
	
	(** Copy source mask S to destination mask D *)												
	PROCEDURE CopyMask* (S: Mask; VAR D: Mask);
	BEGIN
		NEW(D); NEW(D.rgn); Regions.CopyOfRegion(S.rgn, D.rgn);
	END CopyMask;
	
	(** Calculate the difference D of source masks S0 and S1 *)		
	PROCEDURE DiffMask* (S0, S1: Mask; VAR D: Mask);
	BEGIN
		NEW(D); NEW(D.rgn); Regions.CopyOfRegion(S0.rgn, D.rgn);
		Regions.SubtractRegion(D.rgn, S1.rgn);
	END DiffMask;
	
	(** Calculate the union D of source masks S0 and S1 *)		
	PROCEDURE UnionMask* (S0, S1: Mask; VAR D: Mask);
	BEGIN
		NEW(D); NEW(D.rgn); Regions.CopyOfRegion(S0.rgn, D.rgn);
		Regions.AddRegion(D.rgn, S1.rgn);
	END UnionMask;
	
	(** Calculate the intersection D of source masks S0 and S1 *)		
	PROCEDURE SectMask* (S0, S1: Mask; VAR D: Mask);
	BEGIN
		NEW(D); NEW(D.rgn); Regions.CopyOfRegion(S0.rgn, D.rgn);
		Regions.IntersectRegion(D.rgn, S1.rgn);
	END SectMask;
			
	(** Set the clipping mask M for subsequent drawing operations *)		
	PROCEDURE SetMask* (M: Mask);
		VAR rgn: Raster.Region;
	BEGIN
		IF M # NIL THEN
			NEW(rgn);
			IF cur.rgn # NIL THEN
				Regions.CopyOfRegion(cur.rgn, rgn);
				Regions.IntersectRegion(rgn, M.rgn);
			ELSE
				Regions.CopyOfRegion(M.rgn, rgn);
			END;
			IF cur.printer THEN Raster.InitPort(cur.port, Raster.Printer, cur.portx, cur.porty, cur.w, cur.h, rgn)
			ELSE Raster.InitPort(cur.port, Raster.Screen, cur.portx, cur.porty, cur.w, cur.h, rgn)
			END
		END
	END SetMask;		
		
	
	(** Offscreen devices *)		
				
	(** Allocate a new offscreen device with width w, height h and given depth *)					
	PROCEDURE NewDevice* (VAR D: Device; w, h, depth: INTEGER);
		VAR buffer: Raster.Buffer;
	BEGIN
		NEW(D); D.portx := 0; D.porty := 0; D.w := w; D.h := h; D.depth := 8; D.width := 1; D.offscreen:= TRUE;
		NEW(buffer); Raster.InitBuffer(buffer, w, h, Raster.ScreenDPI);
		NEW(D.port); Raster.InitPort(D.port, buffer, 0, 0, w, h, NIL);
		NEW(D.stroker); NEW(D.filler); NEW(D.wide);
	END NewDevice;

	PROCEDURE ^ Setup* (D: Device);
	PROCEDURE ^ Restore* (D: Device);

	(** Copy block (sx, sy, w, h) from source device S to block (dx, dy, w, h) in destination device D *)
	PROCEDURE CopyBlock* (S, D: Device; sx, sy, w, h, dx, dy: INTEGER);
	BEGIN
		ASSERT(S.offscreen = TRUE);
		(* this might be a bug *)
		dy := D.h - h -dy; sy := S.h - h - sy; 
		IF w < 0 THEN w:= -w; sx:= sx - w + 1; dx:= dx - w + 1 END;
		IF h < 0 THEN h:= -h; sy:= sy - h + 1; dy:= dy - h + 1 END;
		IF (h # 0) & (w # 0) THEN Raster.CopyBuffer(D.port, S.port.rp(Raster.Buffer), sx, sy, w, h, dx, dy, replace) END
	END CopyBlock;	

	
	(** Drawing operations *)

	(** Set foreground color for subsequent calls; default is black *)
	PROCEDURE SetForeColor* (col: RGBColor);
	BEGIN
		Raster.GetColor(col.red/255, col.green/255, col.blue/255, cur.fgCol);
		Pens.InitColorStrokePen(cur.stroker, cur.fgCol, cur.mode);
		Pens.InitColorFillPen(cur.filler, cur.fgCol, cur.mode);
		FancyPens.InitBevelPen(cur.wide, cur.width, cur.stroker, cur.filler);
	END SetForeColor;
	
	(* Set background color for subsequent calls; default is white *)
	PROCEDURE SetBackColor (col: RGBColor);
	BEGIN
	END SetBackColor;
	
	(* Set drawing mode for subsequent calls; default is replace *)
	PROCEDURE SetMode (mode: INTEGER);
	BEGIN
		cur.mode := mode;
		Pens.InitColorStrokePen(cur.stroker, cur.fgCol, cur.mode);
		Pens.InitColorFillPen(cur.filler, cur.fgCol, cur.mode);
		FancyPens.InitBevelPen(cur.wide, cur.width, cur.stroker, cur.filler);
	END SetMode;
	
	(** Set line width for subsequent calls; default is 1 *)
	PROCEDURE SetLineWidth* (width: INTEGER);
	BEGIN
		cur.width := width;
		FancyPens.InitBevelPen(cur.wide, width, cur.stroker, cur.filler);
	END SetLineWidth;
	
	(** Set font for subsequent calls; default is Times *)
	PROCEDURE SetFont* (fnt: ARRAY OF CHAR);
	BEGIN
		COPY(fnt, cur.fnt);
	END SetFont;
	
	(** Set font face (plain, italic, bold) for subsequent calls; default is plainFace *)
	PROCEDURE SetFontFace* (face: INTEGER);
	BEGIN
		cur.face := face
	END SetFontFace;
	
	(** Set font szie for subsequent calls; default is 10 *)
	PROCEDURE SetFontSize* (size: INTEGER);
	BEGIN
		cur.size := size
	END SetFontSize;
	
	(** Draw dot at position (x, y) with given color *)
	PROCEDURE Dot* (x, y: INTEGER);
	BEGIN
		SwapY(y, 0);
		Raster.Dot(cur.port, cur.fgCol, x, y, cur.mode);
	END Dot;
	
	(** Draw a line from (x0, y0) to (x1, y1). The point (x1, y1) is included *)
	PROCEDURE Line* (x0, y0, x1, y1: INTEGER);
		VAR pen: Pens.Pen;
	BEGIN
		SwapY(y0, 0);
		SwapY(y1, 0);
		IF cur.width > 1 THEN pen := cur.wide ELSE pen := cur.stroker END;
		pen.do.Open(pen, cur.port, Mappings.Identity);
		pen.do.Begin(pen, x0, y0, 0, 0, 0);
		pen.do.AddLine(pen, x1, y1);
		pen.do.End(pen, 0, 0);
		pen.do.Close(pen);
	END Line;
	
	(** Draw a polyline with points P. Len contains the number of points *)
	PROCEDURE FramePolyLine* (VAR P: ARRAY OF Point; len: INTEGER);
		VAR pen: Pens.Pen; i, y: INTEGER;
	BEGIN
		i := 0; 
		IF cur.width > 1 THEN pen := cur.wide ELSE pen := cur.stroker END;
		pen.do.Open(pen, cur.port, Mappings.Identity);
		IF (len > 0) & (LEN(P) > 0) THEN 
			y:= P[i].y; SwapY(y, 0);
			pen.do.Begin(pen, P[i].x, y, 0, 0, 0); INC(i) 
		END;
		WHILE (i < len) & (i < LEN(P)) DO
			y:= P[i].y; SwapY(y, 0);
			pen.do.AddLine(pen, P[i].x, y);
			INC(i)
		END;
		pen.do.End(pen, 0, 0);
		pen.do.Close(pen);
	END FramePolyLine;
	
	(** Draw a filled polyline with points P. Len contains the number of points *)
	PROCEDURE FillPolyLine* (VAR P: ARRAY OF Point; len: INTEGER);
		VAR pen: Pens.Pen; i, y: INTEGER;
	BEGIN
		i := 0; pen := cur.filler;
		pen.do.Open(pen, cur.port, Mappings.Identity);
		IF (len > 0) & (LEN(P) > 0) THEN
			y:= P[i].y; SwapY(y, 0);
			pen.do.Begin(pen, P[i].x, y, 0, 0, 0); INC(i)
		END;
		WHILE (i < len) & (i < LEN(P)) DO
			y:= P[i].y; SwapY(y, 0);
			pen.do.AddLine(pen, P[i].x, y);
			INC(i)
		END;
		pen.do.End(pen, 0, 0);
		pen.do.Close(pen);
	END FillPolyLine;

	(** Draw a rectangle (x, y, w, h). The rectangle is inside the boundary, even if the linewidth is greater than 0 *)
	PROCEDURE FrameRect* (x, y, w, h: INTEGER);
		VAR pen: Pens.Pen;
	BEGIN
		SwapY(y, h);
		NormalizeXYWH(x, y, w, h);
		IF cur.width > 1 THEN 
			pen := cur.wide; INC(x, cur.width DIV 2); INC(y, cur.width DIV 2); DEC(w, cur.width); DEC(h, cur.width)
		ELSE pen := cur.stroker END;
		pen.do.Open(pen, cur.port, Mappings.Identity);
		pen.do.Begin(pen, x, y, 0, 0, 0);
		pen.do.AddLine(pen, x+w-1, y);
		pen.do.End(pen, 0, 0);
		pen.do.Begin(pen, x+w-1, y, 0, 0, 0);
		pen.do.AddLine(pen, x+w-1, y+h-1);
		pen.do.End(pen, 0, 0);
		pen.do.Begin(pen, x+w-1, y+h-1, 0, 0, 0);
		pen.do.AddLine(pen, x, y+h-1);
		pen.do.End(pen, 0, 0);
		pen.do.Begin(pen, x, y+h-1, 0, 0, 0);
		pen.do.AddLine(pen, x, y);
		pen.do.End(pen, 0, 0);
		pen.do.Close(pen);
	END FrameRect;
	
	(** Draw a filled rectangle (x, y, w, h) *)
	PROCEDURE FillRect* (x, y, w, h: INTEGER);
		VAR pen: Pens.Pen;
	BEGIN
		SwapY(y, h);
		NormalizeXYWH(x, y, w, h);
		pen := cur.filler;
		pen.do.Open(pen, cur.port, Mappings.Identity);
		pen.do.Begin(pen, x, y, 0, 0, 0);
		pen.do.AddLine(pen, x+w, y);
		pen.do.AddLine(pen, x+w, y+h);
		pen.do.AddLine(pen, x, y+h);
		pen.do.AddLine(pen, x, y);
		pen.do.End(pen, 0, 0);
		pen.do.Close(pen);
	END FillRect;

	(** Draw a circle or ellipse with boundary (x, y, w, h). The oval is inside the boundary, even if the linewidth is greater than 0 *)
	PROCEDURE FrameOval* (x, y, w, h: INTEGER);
		VAR pen: Pens.Pen;
	BEGIN
		SwapY(y, h);
		NormalizeXYWH(x, y, w, h);
		IF cur.width > 1 THEN 
			pen := cur.wide; INC(x, cur.width DIV 2); INC(y, cur.width DIV 2); DEC(w, cur.width); DEC(h, cur.width)
		ELSE pen := cur.stroker END;
		pen.do.Open(pen, cur.port, Mappings.Identity);
		pen.do.Begin(pen, x, y + h DIV 2, 0, 0, 0);
		pen.do.AddArc(pen, x, y + h DIV 2, x + w DIV 2, y + h DIV 2, 0, h DIV 2, w DIV 2, 0);
		pen.do.End(pen, 0, 0);
		pen.do.Close(pen);
	END FrameOval;
	
	(** Draw a filled circle or ellipse with boundary (x, y, w, h) *)
	PROCEDURE FillOval* (x, y, w, h: INTEGER);
		VAR pen: Pens.Pen;
	BEGIN
		SwapY(y, h);
		NormalizeXYWH(x, y, w, h);
		pen := cur.filler;
		pen.do.Open(pen, cur.port, Mappings.Identity);
		pen.do.Begin(pen, x, y + h DIV 2, 0, 0, 0);
		pen.do.AddArc(pen, x, y + h DIV 2, x + w DIV 2, y + h DIV 2, 0, h DIV 2, w DIV 2, 0);
		pen.do.End(pen, 0, 0);
		pen.do.Close(pen);
	END FillOval;

	PROCEDURE GetFName(VAR f: ARRAY OF CHAR);
		VAR i, j: INTEGER; size: ARRAY 64 OF CHAR;
	BEGIN
		i := 0; j := cur.size;
		WHILE j # 0 DO
			size[i] := CHR((j MOD 10) + ORD("0"));
			j := j DIV 10;
			i := i + 1
		END;
		DEC(i);
		
		COPY(cur.fnt, f);
		j := 0; WHILE f[j] # 0X DO INC(j) END;
		WHILE i >=0 DO f[j] := size[i]; INC(j); DEC(i) END;
		
		IF cur.face = boldFace THEN f[j] := "b"; INC(j)
		ELSIF cur.face = italicFace THEN f[j] := "i"; INC(j)
		END;
		
		f[j] := "."; f[j+1] := "S"; f[j+2] := "c"; f[j+3] := "n"; f[j+4] := "."; f[j+5] := "F"; f[j+6] := "n"; f[j+7] := "t"; f[j+8] := 0X;
	END GetFName;

	PROCEDURE GetFFace(VAR face: CHAR);
	BEGIN
		IF cur.face = plainFace THEN face:= 0X
		ELSIF cur.face = boldFace THEN face:= "b"
		ELSIF cur.face = italicFace THEN face:= "i"
		END
	END GetFFace;
	
	(** Draw a string s at position (x, y) with previously set color, fontname, fontsize and fontface *)
	PROCEDURE String* (x, y: INTEGER; s: ARRAY OF CHAR);
		VAR f: ARRAY 64 OF CHAR; face: CHAR;
	BEGIN
		SwapY(y, 0);
		(* GetFName(f); *) GetFFace(face);
		Raster.String(cur.port, cur.fgCol, 0, s, cur.fnt, face, cur.size, x, y, Display.paint);
	END String;

	(** Font metrics *)

	(** Get metric data of current font *)
	PROCEDURE GetFontMetrics* (VAR metric: FontMetric);
		VAR f: ARRAY 64 OF CHAR; fnt: Fonts.Font;
	BEGIN
		GetFName(f);
		fnt := Fonts.This(f);
		metric.ascent := fnt.maxY;
		metric.descent := -fnt.minY;
		metric.leading := fnt.height - fnt.maxY + fnt.minY;
	END GetFontMetrics;

	(** Get width and height of given string s. Increment y by h to draw the next line *)
	PROCEDURE GetStringSize* (s: ARRAY OF CHAR; VAR w, h: INTEGER);
		VAR f: ARRAY 64 OF CHAR; dsr: INTEGER; fnt: Fonts.Font; dmy: LONGINT;
	BEGIN
		GetFName(f);
		fnt := Fonts.This(f);
		Fonts.GetChar(fnt, "I", w, w, w, w, h, dmy);
		Raster.GetStringWidth(fnt, s, dmy); w:= SHORT(dmy);
	END GetStringSize;

	(** Setup the device for subsequent drawing calls - This procedure MUST be invoked before the first drawing operation on a device *)
	PROCEDURE Setup* (D: Device);
	BEGIN
		cur := D;
		
		SetForeColor(black); SetBackColor(white); SetMode(replace);
		SetLineWidth(1); SetFont("Times"); SetFontFace(plainFace); SetFontSize(10);
	END Setup;
	
	(** Restore the device after previous drawing calls. This procedure MUST be invoked after the last drawing operation on a device *)
	PROCEDURE Restore* (D: Device);
	BEGIN
		cur:= NIL;
	END Restore;

	PROCEDURE InitMainDevice* (VAR D: Device; w, h: INTEGER; printer: BOOLEAN);
	BEGIN
		NEW(D); D.offscreen:= FALSE; NEW(D.port); 
		D.printer := printer;
		IF printer THEN Raster.InitPrinter; Raster.InitPort(D.port, Raster.Printer, 0, 0, w, h, NIL)
		ELSE Raster.InitPort(D.port, Raster.Screen, 0, 0, w, h, NIL)
		END;
		D.w := w; D.h := h;
		IF printer THEN
			D.hres := Raster.Printer.dpi;
		ELSE
			D.hres := Raster.Screen.dpi
		END;
		D.vres := D.hres;
		D.depth := Display.Depth(0);
		D.width := 1;
		D.portx := 0; D.porty := 0;
		
		NEW(D.stroker); NEW(D.filler); NEW(D.wide);
	END InitMainDevice;

	PROCEDURE AddMask(x, y, w, h: INTEGER);
		VAR rect: Regions.Rectangle;
	BEGIN
		rect.x := x - cur.portx; rect.y := y - cur.porty; rect.w := w; rect.h := h;
		Regions.SetRegionToRect(rgn2, rect);
		Regions.AddRegion(rgn1, rgn2);
	END AddMask;

	PROCEDURE SetDevicePos* (D: Device; M: Display3.Mask; x, y, w, h: INTEGER);
		VAR rect: Regions.Rectangle;
	BEGIN
		cur := D;
		D.portx := x;
		D.porty := y;
		D.w := w;
		D.h := h;
		
		rect.x := 0; rect.y := 0; rect.w := w; rect.h := h;
		NEW(D.rgn); Regions.InitRegion(D.rgn, 0); Regions.SetRegionToRect(D.rgn, rect);

		IF M # NIL THEN
			Regions.ClearRegion(rgn1);
			Display3.Enum(M, AddMask);
			Regions.IntersectRegion(D.rgn, rgn1);
		END;

		rect.x := M.X - D.portx; rect.y := M.Y - D.porty; rect.w := M.W; rect.h := M.H;
		Regions.SetRegionToRect(rgn1, rect);
		Regions.IntersectRegion(D.rgn, rgn1);
		
		IF D.printer THEN Raster.InitPort(D.port, Raster.Printer, x, y, w, h, D.rgn)
		ELSE Raster.InitPort(D.port, Raster.Screen, x, y, w, h, D.rgn)
		END
	END SetDevicePos;

BEGIN
	white.red := 255; white.green := 255; white.blue := 255;
	black.red := 0; black.green := 0; black.blue := 0;
	red.red := 255; red.green := 0; red.blue := 0;
	green.red := 0; green.green := 255; green.blue := 0;
	blue.red := 0; blue.green := 0; blue.blue := 255;
	NEW(rgn1); Regions.InitRegion(rgn1, 0);
	NEW(rgn2); Regions.InitRegion(rgn2, 0);
END JuiceDevices.