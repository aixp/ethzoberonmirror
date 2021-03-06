MODULE WMFigures; (** AUTHOR "Patrick Hunziker, staubesv, gadgets source"; PURPOSE "Geometric shapes"; *)

IMPORT
	KernelLog, Streams, Math, Strings, XML, WMRectangles, WMGraphics, WMGraphicUtilities, WMProperties, WMComponents;

CONST
	(* Figure.state *)
	Filled* = 0;
	Closed* = 1;
	EditPoints* = 2;
	Reshape*=3;
	Arrow*=4;

	PointSize = 6; (* size of the control points. Currently not related to Effects.gravity *)

TYPE
	Point* = POINTER TO RECORD
		x, y : LONGINT;
		previous, next : Point;
		END;

TYPE
	Figure* = OBJECT(WMComponents.VisualComponent) 
	VAR
		width- : WMProperties.Int32Property;
		color-, clHover- : WMProperties.ColorProperty;
		closed-: WMProperties.BooleanProperty;
		filled-: WMProperties.BooleanProperty;
		reshape-: WMProperties.BooleanProperty;
		arrow-: WMProperties.BooleanProperty;

		points- : Point;
		nofPoints : LONGINT;

		hover, selected:WMProperties.Property;
		selectedLine:BOOLEAN;
		mouseOver:BOOLEAN;

		lastKeys, state : SET;
		
		oldx,oldy:LONGINT;
		PArray: WMProperties.PropertyArray;

		PROCEDURE &Init*;
		BEGIN
			Init^;
			SetNameAsString(StrFigure);
			NEW(width, PrototypeWidth, NIL, NIL); properties.Add(width);
			NEW(color, PrototypeColor, NIL, NIL); properties.Add(color);
			NEW(reshape, PrototypeReshape, NIL, NIL); properties.Add(reshape);
			NEW(arrow, PrototypeArrow, NIL, NIL); properties.Add(arrow);
			NEW(closed, PrototypeClosed, NIL, NIL); properties.Add(closed);
			NEW(filled, PrototypeFilled, NIL, NIL); properties.Add(filled);
			NEW(clHover, PrototypeclHover, NIL, NIL); properties.Add(clHover);
			state := {};
			IF closed.Get() THEN INCL(state,Closed)  END; 
			IF filled.Get() THEN INCL(state,Filled) END;
			IF reshape.Get() THEN INCL(state,Reshape) END;
			IF arrow.Get() THEN INCL(state,Arrow) END;
			points := NIL;
			nofPoints := 0;
			hover := NIL;
			selected := NIL;
			lastKeys := {};
			RecachePoints;
			Normalize;
		END Init;
		
		PROCEDURE AddPoint*(x, y : LONGINT);
		VAR 
			s: ARRAY 16 OF CHAR;
			pp:WMProperties.PointProperty; 
		BEGIN
			Strings.IntToStr(nofPoints,s);
			NEW(pp,NIL,Strings.NewString(s),NIL);  
			Acquire;
			properties.Add(pp);
			Release;
			pp.SetCoordinate(x,y); 
			(*pp.Changed; *)(* overkill ?*)
			RecachePoints;
			Normalize;
			Invalidate;
		END AddPoint;

		(* x,y in Figure coordinates, which may change when adding new points etc. Remember that PointProperty is in (stable) parent coordinates*)
		PROCEDURE MovePoint*(point: WMProperties.Property; fx, fy: LONGINT);
		BEGIN
			point(WMProperties.PointProperty).SetCoordinate(fx+bounds.GetLeft(), fy+bounds.GetTop()); 
			Invalidate;
		END MovePoint;
		
		PROCEDURE RemovePoint*(fx, fy : LONGINT);
		VAR 
			pp:WMProperties.Property; 
		BEGIN
			pp:=ThisPoint(fx,fy);
			IF pp#NIL THEN
				Acquire;
				properties.Remove(pp);
				Release;
			END;
			RecachePoints;
			Normalize;
			Invalidate;
		END RemovePoint;
		
		(** Return point located at mouse position mx. my, which are in Figure coordinates that change, e.g. when points are added. (NIL if no point at location). *)
		PROCEDURE ThisPoint*(fx, fy : LONGINT): WMProperties.Property;
		VAR  i:LONGINT; px,py: LONGINT;
		BEGIN
			i:=0;
			WHILE i<LEN(PArray) DO
				IF (PArray[i]#NIL)&(PArray[i] IS WMProperties.PointProperty) THEN
					PArray[i](WMProperties.PointProperty).GetCoordinate(px,py);
					IF Invicinity(fx, fy, px-bounds.GetLeft(), py-bounds.GetTop()) THEN  RETURN PArray[i] END;
				END;
				INC(i);
			END;
			RETURN NIL;
		END ThisPoint;
		
		(** Return point Nr 'index' .  Negative numbers are counted top-down.  *)
		PROCEDURE IndexedPoint*(index : LONGINT): WMProperties.Property;
		VAR  i,j:LONGINT; 
		BEGIN
			i:=0; j:=0;
			IF index >=0 THEN
				WHILE i<LEN(PArray) DO
					IF (PArray[i]#NIL)&(PArray[i] IS WMProperties.PointProperty) THEN
						IF j=index THEN RETURN PArray[i]
						ELSE INC(j)
						END;
					END;
					INC(i);
				END;
			ELSE 
				i:=LEN(PArray)-1; j:=1; index:=-index;
				WHILE i>=0 DO
					IF (PArray[i]#NIL)&(PArray[i] IS WMProperties.PointProperty) THEN
						IF j=index THEN RETURN PArray[i]
						ELSE INC(j)
						END;
					END;
					DEC(i);
				END;
			END;
			RETURN NIL;
		END IndexedPoint;
		
		PROCEDURE MoveFigure*(dx,dy:LONGINT);
		VAR i,x,y:LONGINT;
		BEGIN	
			Acquire;
			IF PArray#NIL THEN PArray:=properties.Enumerate(); END;
			IF PArray=NIL THEN RETURN END;
			FOR i:=0 TO LEN(PArray)-1 DO
				IF (PArray[i]#NIL) & (PArray[i] IS WMProperties.PointProperty) THEN
					PArray[i](WMProperties.PointProperty).GetCoordinate(x, y); 
					PArray[i](WMProperties.PointProperty).SetCoordinate(x+dx, y+dy);
				END;
			END;
			Release;
			Invalidate;
		END MoveFigure;

		(* fx,fy in Figure coordinate system, NOT in parent coordinates*)
		PROCEDURE PointerDown*(fx, fy : LONGINT; keys : SET);
		BEGIN
			lastKeys := keys;
			IF (0 IN keys) THEN
				oldx:=fx+bounds.GetLeft(); oldy:=fy+bounds.GetTop();
				selected := ThisPoint(fx, fy);
				IF (selected # NIL) THEN Invalidate ELSE selectedLine:=TRUE; mouseOver:=FALSE END;
			END;
			Invalidate;
		END PointerDown;

		PROCEDURE PointerUp*(fx, fy : LONGINT; keys : SET);
		VAR dx,dy,bt,bl:LONGINT;
		BEGIN
			bl:=bounds.GetLeft(); 
			bt:=bounds.GetTop();
			IF (keys={0}) & reshape.Get()  THEN
				IF (selected # NIL) THEN MovePoint(selected, fx, fy); selected := NIL;
				ELSE  
					dx:=fx+bl-oldx; oldx:=fx+bl; 
					dy:=fy+bt-oldy; oldy:=fy+bt;
					MoveFigure(dx, dy); 
					selectedLine:=FALSE;
				END;
			END;
			(*IF (2 IN lastKeys) & ~(2 IN keys) THEN
				IF reshape.Get() THEN EXCL(state, Reshape); ELSE INCL(state, Reshape); END;(*??xxx*)
			ELS*)
			IF reshape.Get() & (EditPoints IN state) & (1 IN lastKeys) & ~(1 IN keys)  THEN
				AddPoint(fx, fy); (* Invalidate;*)(*!partly functional - wrong coordinates*)
			ELSIF reshape.Get() & (EditPoints IN state) & (lastKeys={0,2}) & (keys#{0,2}) THEN
				RemovePoint(fx,fy); 
			ELSE(* PointerUp^(x, y, keys);*)
			END;
			selectedLine:=FALSE;
			selected:=NIL;
		END PointerUp;
		
		PROCEDURE PointerMove*(fx, fy : LONGINT; keys : SET);
		VAR dx,dy,bl,bt:LONGINT; pp:WMProperties.Property;
		BEGIN
			IF reshape.Get() & (keys={0}) (*(Reshape IN state)*) & (selected # NIL) THEN 
				MovePoint(selected, fx, fy);
			ELSIF reshape.Get() & (keys={0}) (* (Reshape IN state)*) & selectedLine THEN 
				bl:=bounds.GetLeft(); 
				bt:=bounds.GetTop();
				dx:=fx+bl-oldx; oldx:=fx+bl;
				dy:=fy+bt-oldy; oldy:=fy+bt;
				MoveFigure(dx, dy);
			ELSE
				(*bl:=bounds.GetLeft(); 
				bt:=bounds.GetTop();
				PointerMove^(fx+bl, fy+bt, keys);
				pp := ThisPoint(fx+bl, fy+bt);
				hover:=pp;
				mouseOver := ~mouseOver; *)
			END;
		END PointerMove;
		
				(* Is X, Y somewhere inside the polygon defined by p ? *)
		PROCEDURE Inside*(X, Y: LONGINT): BOOLEAN;
		END Inside;
		
		(** Return if the line is hit at (x, y) in parent coordinates *)
		PROCEDURE IsHit*(x, y: LONGINT): BOOLEAN; 
		END IsHit;		
		
		PROCEDURE PropertyChanged*(sender, property : ANY);
		BEGIN
			IF (property = color) THEN Invalidate;
			ELSIF (property = width) THEN Invalidate;
			ELSIF (property = clHover) THEN Invalidate;
			ELSIF (property = closed) THEN IF closed.Get() THEN INCL(state,Closed) ELSE EXCL(state,Closed);  END; Invalidate;
			ELSIF (property = filled) THEN IF filled.Get() THEN INCL(state,Filled) ELSE EXCL(state,Filled); END; Invalidate;
			ELSIF (property = reshape) THEN IF reshape.Get() THEN INCL(state,Reshape) ELSE EXCL(state,Reshape); END; Invalidate;
			ELSIF (property = arrow) THEN IF arrow.Get() THEN INCL(state,Arrow) ELSE EXCL(state,Arrow); END; Invalidate;
			ELSIF property IS WMProperties.PointProperty THEN Invalidate; RecachePoints; Normalize; 
			ELSIF property=properties THEN RecachePoints; Invalidate; Normalize; PropertyChanged^(sender, property); (*?*)
			ELSE  PropertyChanged^(sender, property); (* e.g, handling bounds by parent *)
			END;
		END PropertyChanged;
		
		(*
		PROCEDURE RecacheProperties;
		BEGIN
			RecachePoints;
			RecacheProperties^;
			
		END RecacheProperties;
		*)
		
	
		PROCEDURE AddDisplayPoint(x, y : LONGINT);
		VAR point, p : Point; 
		BEGIN
			NEW(point); point.x := x; point.y := y; point.previous := NIL; point.next := NIL;
			IF (points = NIL) THEN points := point;
			ELSE
				p := points;
				WHILE (p.next # NIL) DO p := p.next; END;
				p.next := point; point.previous := p;
			END;
			INC(nofPoints);
		END AddDisplayPoint;
		
		PROCEDURE MoveDisplayPoints(dx, dy : LONGINT); 
		VAR p : Point;
		BEGIN
			p := points;
			WHILE (p # NIL) DO	p.x := p.x + dx; p.y := p.y + dy; p := p.next; END;
		END MoveDisplayPoints;

		PROCEDURE Normalize; 
		VAR p:Point; rect: WMRectangles.Rectangle;
		BEGIN
			rect.l := MAX(LONGINT); rect.t := MAX(LONGINT); rect.r := MIN(LONGINT); rect.b := MIN(LONGINT);
			p:=points;
			WHILE p#NIL DO (* adapt display point coordinates to new bounds *)
				rect.l:=MIN(rect.l, p.x-PointSize DIV 2 -1); rect.r:=MAX(rect.r, p.x+PointSize DIV 2+1);  (*compute bounds*)
				rect.t:=MIN(rect.t, p.y-PointSize DIV 2 -1); rect.b:=MAX(rect.b, p.y+PointSize DIV 2+1);
				p:=p.next; 
			END;
			p:=points;
			WHILE p#NIL DO (* adapt display point coordinates to new bounds *)
				p.x:=p.x-rect.l; p.y:=p.y-rect.t; 
				p:=p.next; 
			END;
			bounds.Set(rect);
		END Normalize;

		PROCEDURE Scale;
		END Scale;

		PROCEDURE GetBoundingBox() : WMRectangles.Rectangle; (*! will be eliminated*)
		VAR rect : WMRectangles.Rectangle; i:LONGINT;
		BEGIN
			rect.l := MAX(LONGINT); rect.t := MAX(LONGINT);
			rect.r := MIN(LONGINT); rect.b := MIN(LONGINT);
			IF PArray#NIL THEN PArray:=properties.Enumerate(); END;
			IF PArray=NIL THEN RETURN rect END;
			FOR i:=0 TO LEN(PArray)-1 DO
				IF PArray[i] IS WMProperties.PointProperty THEN
					rect.l:=MIN(rect.l, PArray[i](WMProperties.PointProperty).GetX());
					rect.r:=MAX(rect.r, PArray[i](WMProperties.PointProperty).GetX());
					rect.t:=MIN(rect.t, PArray[i](WMProperties.PointProperty).GetY());
					rect.b:=MAX(rect.b, PArray[i](WMProperties.PointProperty).GetY());
				END;
			END;
			RETURN rect;
		END GetBoundingBox;
		
		PROCEDURE RecachePoints; (*build point list in parent coordinates*)
		VAR p:Point;	i,x,y:LONGINT;
		BEGIN
			(* called by sequencer -> hierarchy is locked, see WMVisualComponentSkeleton.Mod *)
			PArray:=properties.Enumerate();
			points:=NIL; p:=NIL; nofPoints:=0;
			FOR i:=0 TO LEN(PArray)-1 DO
				IF (PArray[i]#NIL)&(PArray[i] IS WMProperties.PointProperty) THEN
					PArray[i](WMProperties.PointProperty).GetCoordinate(x,y);
					AddDisplayPoint(x, y);
				END;
			END;
		END RecachePoints;
		
		PROCEDURE DrawDisplayPoint(canvas : WMGraphics.Canvas; pp: WMProperties.PointProperty);
		VAR rect : WMRectangles.Rectangle; color, x,y,fx,fy : LONGINT;
		BEGIN
			ASSERT(pp # NIL);
			IF (pp = selected) THEN color := WMGraphics.Yellow;
			ELSIF (pp = hover) THEN color := WMGraphics.Blue;
			ELSE color := WMGraphics.White;
			END;
			
			pp.GetCoordinate(x,y); 
			fx:=x-bounds.GetLeft(); 
			fy:=y-bounds.GetTop();
			rect := WMRectangles.MakeRect(fx- PointSize DIV 2, fy - PointSize DIV 2, fx + PointSize DIV 2, fy + PointSize DIV 2);
			canvas.Fill(rect, WMGraphics.White, WMGraphics.ModeSrcOverDst);
			WMGraphicUtilities.DrawRect(canvas, rect, WMGraphics.Black, WMGraphics.ModeSrcOverDst);
		END DrawDisplayPoint;

		PROCEDURE DrawForeground*(canvas : WMGraphics.Canvas);
		VAR a: BOOLEAN; i:LONGINT;
		BEGIN
			DrawForeground^(canvas);
			a:=arrow.Get();
			IF reshape.Get() THEN
				FOR i:=0 TO LEN(PArray)-1 DO
					IF (PArray[i]#NIL)&(PArray[i] IS WMProperties.PointProperty) THEN 
						DrawDisplayPoint(canvas, PArray[i](WMProperties.PointProperty)); 
					END;
				END;
			END;
		END DrawForeground;
		
		PROCEDURE DrawArrow*(canvas : WMGraphics.Canvas; p0,p1: Point);
		CONST pi=3.1516; 
		VAR  alpha: REAL;
			 head: LONGREAL;
			col:LONGINT;
		BEGIN
				alpha:=arctan2(p1.x-p0.x, p1.y-p0.y);
				head:=MAX( 4,  0.05 * MAX(ABS(p1.x-p0.x), ABS(p1.y-p0.y))); (*avoid sqrt for performance reasons*) 
				col:=color.Get();
				canvas.Line(p1.x,p1.y, p1.x - ENTIER(0.5+head * Math.cos(alpha + pi/8)), p1.y - ENTIER(0.5+head * Math.sin(alpha + pi/8)), col, WMGraphics.ModeSrcOverDst);
				canvas.Line(p1.x,p1.y, p1.x - ENTIER(0.5+head * Math.cos(alpha - pi/8)), p1.y - ENTIER(0.5+head * Math.sin(alpha - pi/8)), col, WMGraphics.ModeSrcOverDst);
		END DrawArrow;

		(*
		PROCEDURE FromXML*(xml: XML.Element);
		BEGIN
			FromXML^(xml);
			RecachePoints; (* these three commands might be dropped, and the procedure left out, as the parent will handle it.*)
			Invalidate;
			Normalize;
		END FromXML;
		*)
		
	END Figure;

TYPE

	PointArray = POINTER TO ARRAY OF WMGraphics.Point2d;

	Line* = OBJECT(Figure)
	VAR
		pointArray : PointArray; (* {pointArray # NIL} *)

		PROCEDURE &Init*;
		BEGIN
			Init^;
			SetGenerator("WMFigures.GenLine");
			SetNameAsString(StrLine);
			INCL(state, EditPoints);
			NEW(pointArray, nofPoints);		
			RecachePoints;
			Normalize;
			Invalidate;
		END Init;

		PROCEDURE Scale;
		VAR p : Point; bounds, box : WMRectangles.Rectangle; oldWidth, oldHeight, newWidth, newHeight, n : LONGINT;
		BEGIN
			Acquire;
			bounds := SELF.bounds.Get();
			box := GetBoundingBox();
			oldWidth := box.r - box.l;
			oldHeight := box.b - box.t;
			n := (PointSize DIV 2) + (width.Get() DIV 2) + 1;
			newWidth := bounds.r - bounds.l - 2*n;
			newHeight := bounds.b - bounds.t - 2*n;
			IF (oldWidth # 0) & (oldHeight # 0) THEN
				p := points;
				WHILE (p # NIL) DO
					p.x := (p.x - box.l) * newWidth DIV oldWidth + box.l;
					p.y := (p.y - box.t) * newHeight DIV oldHeight + box.t;
					p := p.next;
				END;
			END;
			Release;
		END Scale;

		(* Is X, Y somewhere inside the polygon defined by p ? *)
		PROCEDURE Inside*(X, Y: LONGINT): BOOLEAN;
		VAR c: LONGINT; p, q: Point;
		BEGIN
			c := 0;
			IF (points # NIL) THEN
				p := points; q:=p.next;
				WHILE q#NIL DO
					IF Intersect(X, Y, p.x, p.y, q.x, q.y) THEN INC(c) END;
					p:=q; q:=q.next; 
				END;
				IF (nofPoints > 1) & Intersect(X, Y, p.x, p.y, points.x, points.y) THEN INC(c) END; 
			END;
			RETURN ODD(c);
		END Inside;
		
		PROCEDURE IsHit*(mx, my: LONGINT): BOOLEAN;
		VAR p, q: Point; i : LONGINT;
		BEGIN
			IF (points = NIL) OR (points.next = NIL) THEN RETURN FALSE; END;
			IF Filled IN state THEN
				IF Inside(mx, my) THEN RETURN TRUE END;
			END;
			p := points; q := points.next;
			WHILE (q # NIL) DO
				IF InLineVicinity(mx, my, p.x, p.y, q.x, q.y) THEN RETURN TRUE END;
				p:=q; q:=q.next; INC(i);
			END;
			IF (Closed IN state) OR (Filled IN state) THEN
				IF InLineVicinity(mx, my, p.x, p.y, points.x, points.y) THEN RETURN TRUE END;
			END;
			RETURN FALSE
		END IsHit;

		PROCEDURE DrawBackground*(canvas : WMGraphics.Canvas);
		VAR p, plast : Point; i : LONGINT; 
		BEGIN
			DrawBackground^(canvas);
			IF (nofPoints # LEN(pointArray)) THEN NEW(pointArray, nofPoints); END;
			p := points; i := 0;
			WHILE (p # NIL) DO
				pointArray[i].x := p.x;	
				pointArray[i].y := p.y;
				INC(i);
				plast:=p; p := p.next;
			END;
			IF arrow.Get() (*(Arrow IN state)*) & (plast#NIL) THEN DrawArrow(canvas, plast.previous, plast) END;
			IF filled.Get() THEN    canvas.FillPolygonFlat(pointArray^, nofPoints, color.Get(), WMGraphics.ModeSrcOverDst);
			ELSE					canvas.PolyLine(pointArray^, nofPoints, closed.Get(), color.Get(), WMGraphics.ModeSrcOverDst);
			END;
		END DrawBackground;
	END Line;

TYPE

	Circle* = OBJECT(Figure) (*! to do: computation of bounding box is wrong. Do specific "RecachePoints()" for circle*)

		PROCEDURE &Init*;
		BEGIN
			Init^;
			SetGenerator("WMFigures.GenCircle");
			SetNameAsString(StrCircle);
			AddPoint(15, 15);
			AddPoint(20, 20);
			INCL(state, EditPoints);
			RecachePoints;
			Normalize;
			Invalidate;
		END Init;

		PROCEDURE Normalize;
		VAR oldBounds,rect : WMRectangles.Rectangle; p, q : Point; dx,dy, r, n : LONGINT;
		BEGIN
			oldBounds := bounds.Get();
			IF (p=NIL) OR (p.next=NIL) THEN RETURN END;
			rect.l := MAX(LONGINT); rect.t := MAX(LONGINT); rect.r := MIN(LONGINT); rect.b := MIN(LONGINT);
			p := points; q := p.next;
			r := Distance(p.x, p.y, q.x, q.y);
			n := r + (PointSize DIV 2) + (width.Get() DIV 2) + 1;
			rect.l := oldBounds.l + p.x - n;
			rect.r := oldBounds.l + 2*n;
			rect.t := oldBounds.t + p.y - n;
			rect.b := oldBounds.t + 2*n;
			dx:=rect.l-oldBounds.l;
			dy:=rect.t-oldBounds.t;
			p.x:=p.x-dx; q.x:=q.x-dx;
			p.y:=p.y-dy; q.y:=q.y-dy;
			bounds.Set(rect)
		END Normalize;
		
		(*PROCEDURE IsHit;(*!TBD*)
		BEGIN
			
		END IsHit;*)
		

		PROCEDURE DrawBackground*(canvas : WMGraphics.Canvas);
		VAR p, q : Point; newRect:WMRectangles.Rectangle;
		BEGIN
			DrawBackground^(canvas);
			Normalize;
			p := points;
			q := points.next;
			canvas.SetColor(color.Get());
			WMGraphicUtilities.Circle(canvas, p.x, p.y, Distance(p.x, p.y, q.x, q.y));
			IF (Arrow IN state) THEN DrawArrow(canvas, p,q); END;
		END DrawBackground;

	END Circle;

TYPE

	Rectangle* = OBJECT(Figure)

		PROCEDURE &Init*;
		BEGIN
			Init^;
			SetGenerator("WMFigures.GenRectangle");
			SetNameAsString(StrRectangle);
			AddPoint(10, 10);
			AddPoint(20, 20);
			INCL(state, EditPoints);
			Normalize;
			Invalidate;
		END Init;

		PROCEDURE Normalize; (* might be done by generic Normalize*)
		VAR p, q : Point; oldBounds, box, newBounds : WMRectangles.Rectangle; n : LONGINT;
		BEGIN
			IF (points=NIL) OR (points.next=NIL) THEN RETURN END;
			Acquire;
			p := points;
			q := p.next;
			oldBounds := bounds.Get();
			n := (PointSize DIV 2) + (width.Get() DIV 2) + 1;
			box.l := Min(p.x, q.x) - n;
			box.r := Max(p.x, q.x) + n;
			box.t := Min(p.y, q.y) - n;
			box.b := Max(p.y, q.y) + n;
			newBounds.l := oldBounds.l + box.l;
			newBounds.t := oldBounds.t + box.t;
			newBounds.r := oldBounds.l + (box.r - box.l);
			newBounds.b := oldBounds.t + (box.b - box.t);
			MoveDisplayPoints(-box.l, -box.t);
			bounds.Set(newBounds);
			Release;
		END Normalize;
		
		(*PROCEDURE IsHit;(*!TBD*)
		BEGIN
			
		END IsHit;*)
		

		PROCEDURE DrawBackground*(canvas : WMGraphics.Canvas);
		VAR p, q : Point; rect : WMRectangles.Rectangle;
		BEGIN
			DrawBackground^(canvas);
			p := points;
			q := points.next;
			rect.l := Min(p.x, q.x);
			rect.r := Max(p.x, q.x);
			rect.t := Min(p.y, q.y);
			rect.b := Max(p.y, q.y);
			WMGraphicUtilities.DrawRect(canvas, rect, color.Get(), WMGraphics.ModeSrcOverDst);
		END DrawBackground;

	END Rectangle;

TYPE

	Spline* = OBJECT(Figure)
	VAR
		pointArray : ARRAY 2048 OF WMGraphics.Point2d;
		nSegments:LONGINT;

		PROCEDURE &Init*;
		BEGIN
			Init^;
			SetGenerator("WMFigures.GenSpline");
			SetNameAsString(StrSpline);
			INCL(state, EditPoints);
			IF nofPoints=0 THEN (* prototype*)
				AddPoint(0, 20);
				AddPoint(20, 0);
				AddPoint(20, 20);
				AddPoint(30, 30);
			END;
			RecachePoints;
			SplineToPoly(points, Closed IN state, pointArray, nSegments);
			Normalize;
			Invalidate;
		END Init;
		
				(* Is X, Y somewhere inside the polygon defined by p ? *) (*! to be implemented for pointarray; eliminate bias*)
		PROCEDURE Inside(X, Y: LONGINT): BOOLEAN;
		VAR c: LONGINT; p,q: Point;
		BEGIN
			c := 0;
			IF (points # NIL) THEN
				p := points; q := p.next;
				WHILE q#NIL DO
					IF Intersect(X, Y, p.x, p.y, q.x, q.y) THEN INC(c) END;
					p:=q; q:=q.next;
				END;
				IF (nofPoints > 1) & Intersect(X, Y, p.x, p.y, points.x, points.y) THEN INC(c) END; 
			END;
			RETURN ODD(c);
		END Inside;
		
		PROCEDURE IsHit*(mx, my: LONGINT): BOOLEAN;
		VAR p, q: Point; i : LONGINT;
		BEGIN
			IF (points = NIL) OR (points.next = NIL) THEN RETURN FALSE; END;
			IF Filled IN state THEN
				IF Inside(mx, my) THEN RETURN TRUE END;
			END;
			FOR i:=0 TO nSegments-1 DO
				IF (ABS(mx-pointArray[i].x)<gravity) & (ABS(my-pointArray[i].y)<gravity) THEN RETURN TRUE END; (* here only testing segment points, can be refined*)
			END;
			 (*!the following code is  for line hiting above. does not work so well for spline yet*)
			(*p := points; q := points.next;
			WHILE (q # NIL) DO
				IF InLineVicinity(mx, my, p.x, p.y, q.x, q.y) THEN RETURN TRUE END;
				p:=q; q:=q.next; INC(i);
			END;
			IF (Closed IN state) OR (Filled IN state) THEN
				IF InLineVicinity(mx, my, p.x, p.y, points.x, points.y) THEN RETURN TRUE END;
			END;*)
			RETURN FALSE
		END IsHit;

		PROCEDURE Normalize; 
		VAR i:LONGINT; oldrect, rect:WMRectangles.Rectangle; p:Point; (*! to do: there is a mixup of parent/child coordinates after moving, here and in Spline.HitTest. repair*)
		BEGIN
			oldrect:=bounds.Get();
			rect.l := MAX(LONGINT); rect.t := MAX(LONGINT); rect.r := MIN(LONGINT); rect.b := MIN(LONGINT);
			FOR i:=0 TO nSegments-1 DO
				rect.l:=MIN(rect.l, pointArray[i].x-PointSize DIV 2 -1); rect.r:=MAX(rect.r, pointArray[i].x+PointSize DIV 2+1);  (*compute bounds*)
				rect.t:=MIN(rect.t, pointArray[i].y-PointSize DIV 2 -1); rect.b:=MAX(rect.b, pointArray[i].y+PointSize DIV 2+1);
			END;
			FOR i:=0 TO nSegments-1 DO
				pointArray[i].x:=pointArray[i].x-rect.l;
				pointArray[i].y:=pointArray[i].y-rect.t;
			END;
			p:=points;
			WHILE p#NIL DO (* adapt display point coordinates to new bounds *)
				p.x:=p.x-rect.l; p.y:=p.y-rect.t; 
				p:=p.next; 
			END;
			bounds.Set(rect);
		END Normalize;

		PROCEDURE DrawBackground*(canvas : WMGraphics.Canvas);
		VAR p: Point; col: LONGINT; 
		BEGIN
			
			DrawBackground^(canvas); 
			RecachePoints;
			SplineToPoly(points, Closed IN state, pointArray, nSegments); (* spline boundary computation requires prior spline expansion, not normalized *)
			Normalize; 
			
			IF mouseOver THEN col:=clHover.Get() ELSE col:=color.Get() END;
			IF filled.Get() THEN
				canvas.FillPolygonFlat(pointArray, nSegments, col, WMGraphics.ModeSrcOverDst);
			ELSE
				canvas.PolyLine(pointArray, nSegments, closed.Get(), col, WMGraphics.ModeSrcOverDst);
			END;
			IF arrow.Get() (*(Arrow IN state)*) & (p#NIL) THEN DrawArrow(canvas, p.previous, p) END;
		END DrawBackground;

	END Spline;



VAR
	log: Streams.Writer;
	
	(* Size of gravity spot used for "snapping" the cursor *)
	gravity : LONGINT;

	PrototypeWidth : WMProperties.Int32Property;
	PrototypeColor, PrototypeclHover : WMProperties.ColorProperty;
	PrototypeClosed: WMProperties.BooleanProperty;
	PrototypeFilled: WMProperties.BooleanProperty;
	PrototypeReshape: WMProperties.BooleanProperty;
	PrototypeArrow: WMProperties.BooleanProperty;
	
	StrFigure, StrLine, StrCircle, StrRectangle, StrSpline : Strings.String;

PROCEDURE arctan2(x,y: REAL): REAL; (*arctan in range 0..2pi*)
	BEGIN
		IF (x>0) & (y>=0) THEN RETURN Math.arctan(y/x)
		ELSIF (x>0) & (y<0) THEN RETURN Math.arctan(y/x)+2*Math.pi
		ELSIF x<0 THEN RETURN Math.arctan(y/x)+Math.pi
		ELSIF (x=0) & (y>0) THEN RETURN Math.pi/2
		ELSIF (x=0) & (y<0) THEN RETURN 3*Math.pi/2
		ELSE (*( x=0) & (y=0) *) RETURN 0 (*or RETURN NaN ?*) 
		END
	END arctan2;

(* start of Rege code *)

PROCEDURE MakePoly(CONST RX, RY, RXstrich, RYstrich, RS: ARRAY OF REAL; n: LONGINT; VAR points : ARRAY OF WMGraphics.Point2d; VAR k: LONGINT);
 TYPE
 	Polynom = RECORD A, B, C, D: REAL END;
 VAR
 	i, cs, smax, k1: LONGINT; px, py: Polynom;
	x, dx1, dx2, dx3, y, dy1, dy2, dy3: REAL; L, B, R, T,dW  : LONGINT;

	PROCEDURE GetPolynom((* VAR *) y1, y2, y1s, y2s: REAL; VAR p: Polynom);
		VAR dx1, dyx: REAL;
	BEGIN
		IF RS[i] # RS[i+1] THEN dx1 := 1.0/(RS[i + 1] - RS[i]) ELSE dx1 := 1.0 END;
		dyx := (y2 - y1)*dx1;
		p.A := dx1*dx1*(-2.0*dyx + y1s + y2s);
		p.B := dx1*(3.0*dyx - 2.0*y1s - y2s);
		p.C := y1s;
		p.D := y1
	END GetPolynom;

BEGIN
	points[0].x := SHORT(ENTIER(RX[1])); points[0].y := SHORT(ENTIER(RY[1]));
	L := MAX(LONGINT);  B := MAX(LONGINT); R := MIN(LONGINT); T := MIN(LONGINT);
	i := 1; WHILE i <= n DO
		L := Min(L,SHORT(ENTIER(RX[i]))); B := Min(B,SHORT(ENTIER(RY[i])));
		R := Max(R,SHORT(ENTIER(RX[i]))); T := Max(T,SHORT(ENTIER(RY[i])));
		INC(i);
	END;

	dW := Max(1,Min((Max(R-L ,T-B)  * 3 DIV n DIV 20),4));
	i := 1; k := 1;
	WHILE i < n DO
		GetPolynom(RX[i], RX[i+1], RXstrich[i], RXstrich[i+1], px);
		x := px.D;
		dx1 := px.A + px.B + px.C;
		dx3 := 6.0*px.A;
		dx2 := dx3 + 2.0*px.B;
		GetPolynom(RY[i], RY[i+1], RYstrich[i], RYstrich[i+1], py);
		y := py.D;
		dy1 := py.A + py.B + py.C;
		dy3 := 6.0*py.A;
		dy2 := dy3 + 2.0*py.B;
		smax := SHORT(ENTIER(RS[i+1]-RS[i]));
		cs := 0;
		WHILE cs <= smax DO
			points[k].x := SHORT(ENTIER(x)); points[k].y := SHORT(ENTIER(y));
			k1 := k-1;
			IF (ABS(points[k].x - points[k1].x) > dW) OR (ABS(points[k].y - points[k1].y) > dW) THEN INC(k) END;
			x   := x + dx1;    y   := y + dy1;
			dx1 := dx1 + dx2;  dy1 := dy1 + dy2;
			dx2 := dx2 + dx3;  dy2 := dy2 + dy3;
			INC(cs);
		END;
		INC(i);
	END; (* FOR i *)
	points[k].x := SHORT(ENTIER(RX[n])); points[k].y := SHORT(ENTIER(RY[n])); INC(k);
END MakePoly;

PROCEDURE SplineToPoly(c: Point; closed: BOOLEAN; VAR points : ARRAY OF WMGraphics.Point2d; VAR k: LONGINT);
TYPE
	RealVect = ARRAY 256 OF REAL;
VAR
	n, i: LONGINT; RS, RX, RY ,RXstrich, RYstrich : RealVect; dx, dy: REAL;
	helpR: REAL;

	PROCEDURE NatSplineDerivates(VAR x, y, d: ARRAY OF REAL; n: LONGINT);
	VAR i: LONGINT; d1, d2: REAL; a, b, c: RealVect;

		PROCEDURE SolveTriDiag(VAR a, b, c: ARRAY OF REAL; n: LONGINT; VAR y: ARRAY OF REAL);
		VAR i: LONGINT; t: REAL;
		BEGIN i := 1;
			WHILE i < n DO t := a[i]; c[i] := c[i]/t; helpR := c[i]*b[i]; a[i+1] := a[i+1] -  helpR; INC(i); END;
			i := 2;
			WHILE i <= n DO helpR := c[i-1]*y[i-1]; y[i] := y[i] - helpR; INC(i); END;
			t := a[n]; y[n] := y[n]/t; i := n-1;
			WHILE i > 0 DO  t := y[i+1]; helpR :=y[i] - b[i]*t; y[i] := helpR/a[i]; DEC(i) END
		END SolveTriDiag;

		BEGIN  (* NatSplineDerivates *)
			IF x[1] # x[2] THEN b[1] := 1.0/(x[2] - x[1]); ELSE b[1] := 1.0 END;
			a[1] := 2.0*b[1]; c[1] := b[1];
			d1 := (y[2] - y[1])*3.0*b[1]*b[1];
			d[1] := d1;
			i :=2;
			WHILE i < n DO
				IF x[i] # x[i+1] THEN b[i] := 1.0 /(x[i+1] - x[i]) ELSE b[i] := 1.0 END;
				a[i] := 2.0*(c[i-1] + b[i]); c[i] := b[i];
				d2 := (y[i+1] - y[i])*3.0*b[i]*b[i];
				d[i] := d1 + d2; d1 := d2;
				INC(i);
			END;
			a[n] := 2.0*b[n-1]; d[n] := d1;
			SolveTriDiag(a, b, c, n, d)
		END NatSplineDerivates;

	PROCEDURE ClSplineDerivates(VAR x, y, d: ARRAY OF REAL; n: LONGINT);
		VAR i: LONGINT; hn1, dn1, d1, d2: REAL; a, b, c, u: RealVect;

		PROCEDURE SolveTriDiag2(VAR a, b, c: ARRAY OF REAL; n:LONGINT; VAR y1, y2: ARRAY OF REAL);
		VAR i: LONGINT; t: REAL;
		BEGIN
			i := 1;
			WHILE i < n DO
				t := a[i]; c[i] := c[i]/t;
				helpR := c[i]*b[i]; a[i+1] := a[i+1] - helpR;
				INC(i)
			END;
			i :=2;
			WHILE i <= n DO
				helpR := c[i-1]*y1[i-1];  y1[i] := y1[i] - helpR;
				helpR :=  c[i-1]*y2[i-1]; y2[i] := y2[i] - helpR;
				INC(i);
			END;
			t := a[n]; y1[n] := y1[n]/t; t := a[n]; y2[n] := y2[n]/t;
			i := n-1;
			WHILE i > 0 DO
				t := y1[i+1]; helpR := y1[i] - b[i]* t; y1[i] := helpR/a[i];
				t := y2[i+1]; helpR :=y2[i] - b[i]*t; y2[i] := helpR/a[i];
				DEC(i)
			END
		END SolveTriDiag2;

	BEGIN  (* ClSplineDerivates *)
		hn1 := 1.0/(x[n] - x[n-1]);
		dn1 := (y[n] - y[n-1])*3.0*hn1*hn1;
		IF x[2] # x[1] THEN
			b[1] := 1.0/(x[2] - x[1]);
		ELSE
			b[1] := 0
		END;
		a[1] := hn1 + 2.0*b[1];
		c[1] := b[1];
		d1 := (y[2] - y[1])*3.0*b[1]*b[1];
		d[1] := dn1 + d1;
		u[1] := 1.0;
		i := 2;
		WHILE i < n-1 DO
			IF x[i+1] # x[i] THEN b[i] := 1.0/(x[i+1] - x[i]) ELSE b[i] := 0 END;
			a[i] := 2.0*(c[i-1] + b[i]);
			c[i] := b[i];
			d2 := (y[i+1] - y[i])*3.0*b[i]*b[i];
			d[i] := d1 + d2;
			d1 := d2;
			u[i] := 0.0;
			INC(i)
		END;
		a[n-1] := 2.0*b[n-2] + hn1;
		d[n-1] := d1 + dn1;
		u[n-1] := 1.0;
		SolveTriDiag2(a, b, c, n-1, u, d);
		helpR := u[1] + u[n-1] + x[n] - x[n-1];
		d1 := (d[1] + d[n-1])/helpR;
		i := 1;
		WHILE i < n DO
			d[i] := d[i] - d1*u[i];
			INC(i)
		END;
		d[n] := d[1]
	END ClSplineDerivates;

BEGIN
	IF c=NIL THEN k:=0; RETURN END;
	 
	n := 0; WHILE c # NIL DO RX[n+1] := c.x ; RY[n+1] := c.y; INC(n); c := c.next END;
	IF closed THEN RX[n+1] := RX[1]; RY[n+1] := RY[1]; INC(n) ; END;
	RS[1] := 0.0; i := 2;
	WHILE i <= n DO
		dx := RX[i] - RX[i-1];  dy := RY[i] - RY[i-1];
		RS[i] := RS[i-1] + Math.sqrt(dx*dx + dy*dy);
		INC(i);
	END;
	IF ~closed THEN
		NatSplineDerivates(RS, RX, RXstrich, n);
		NatSplineDerivates(RS, RY, RYstrich, n);
	ELSE
		ClSplineDerivates(RS, RX, RXstrich, n);
		ClSplineDerivates(RS, RY, RYstrich, n)
	END;
	MakePoly(RX, RY, RXstrich, RYstrich, RS, n, points, k);
END SplineToPoly;

(* end of Rege code *)


(** Returns TRUE if mx, my is within gravity pixels from X, Y. *)
PROCEDURE Invicinity(mx, my, X, Y: LONGINT): BOOLEAN;
BEGIN RETURN (mx - X) * (mx - X) + (my - Y) * (my - Y) < gravity * gravity
END Invicinity;

(** Returns TRUE if mx, my is within gravity pixels of the line from X, Y to X1, Y1. *)
PROCEDURE InLineVicinity(mx, my, X, Y, X1, Y1: LONGINT): BOOLEAN;
VAR  w, h, pw, ph, det,len : LONGINT;

	PROCEDURE Between(x, a, b: LONGINT): BOOLEAN;
	VAR min, max: LONGINT;
	BEGIN
		min := Min(a, b); max := Max(a, b);
		RETURN (min - gravity <= x) & (x <= max + gravity);
	END Between;

BEGIN
	IF ABS(X - X1) > gravity  THEN
		IF ABS(Y - Y1) > gravity THEN
			IF Invicinity(mx, my,X, Y) OR Invicinity(mx, my,X1, Y1) THEN RETURN TRUE END;
			pw := mx - X; ph := my - Y; w := X1 -X;  h := Y1 - Y;
			det := pw * h - ph * w; len := w * w + h * h;
			RETURN  Between(mx, X, X1) & Between(my, Y, Y1) & (det / len * det < gravity * gravity)
		ELSE
			RETURN Between(mx, X, X1) & (ABS(my - Y) < gravity)
		END
	ELSE
		RETURN Between(my, Y, Y1) & (ABS(mx - X) < gravity)
	END
END InLineVicinity;

PROCEDURE Intersect(X, Y, x0,y0,x1,y1 : LONGINT) : BOOLEAN;
BEGIN
	IF ((Y >= y0) & (Y < y1)) OR ((Y >= y1) & (Y < y0)) THEN
		IF y1 > y0 THEN RETURN x0 + (Y - y0) * (x1 -x0) DIV (y1 - y0) - X >= 0
		ELSIF y1 <  y0 THEN RETURN x0 + (Y - y0) * (x0 -x1) DIV (y0 - y1) - X >= 0
		ELSE RETURN (x0 > X) OR (x1 > X)
		END
	ELSE RETURN FALSE
	END
END Intersect;

PROCEDURE Distance(x, y, x0, y0: LONGINT): LONGINT;
VAR dx, dy: LONGINT;
BEGIN dx := x - x0; dy := y - y0;
	RETURN ENTIER(Math.sqrt(dx * dx + dy * dy))
END Distance;

PROCEDURE Min(x, y: LONGINT): LONGINT;
BEGIN IF x < y THEN RETURN x ELSE RETURN y END
END Min;

PROCEDURE Max(x, y: LONGINT): LONGINT;
BEGIN IF x > y THEN RETURN x ELSE RETURN y END
END Max;

PROCEDURE GenLine*() : XML.Element; (* needs AddPoint(); AddPoint(), before a prototype becomes visible  *)
VAR line : Line;
BEGIN
	NEW(line); RETURN line;
END GenLine;

PROCEDURE GenCircle*() : XML.Element;
VAR circle : Circle;
BEGIN
	NEW(circle); RETURN circle;
END GenCircle;

PROCEDURE GenRectangle*() : XML.Element;
VAR rectangle : Rectangle;
BEGIN
	NEW(rectangle); RETURN rectangle;
END GenRectangle;

PROCEDURE GenSpline*() : XML.Element;
VAR spline : Spline;
BEGIN
	NEW(spline); RETURN spline;
END GenSpline;

PROCEDURE InitPrototypes;
BEGIN
	NEW(PrototypeWidth, NIL, Strings.NewString("width"), Strings.NewString("Width of stroke")); PrototypeWidth.Set(1);
	NEW(PrototypeColor, NIL, Strings.NewString("color"), Strings.NewString("Color"));	PrototypeColor.Set(WMGraphics.Red);
	NEW(PrototypeclHover, NIL, Strings.NewString("clHover"), Strings.NewString("Color HOver"));	PrototypeclHover.Set(WMGraphics.Yellow);
	NEW(PrototypeClosed, NIL, Strings.NewString("closed"), Strings.NewString("Figure is closed")); PrototypeClosed.Set(FALSE);
	NEW(PrototypeFilled, NIL, Strings.NewString("filled"), Strings.NewString("Figure is filled")); PrototypeFilled.Set(FALSE);
	NEW(PrototypeReshape, NIL, Strings.NewString("reshape"), Strings.NewString("Control Points can be individually moved"));	PrototypeReshape.Set(TRUE);
	NEW(PrototypeArrow, NIL, Strings.NewString("arrow"), Strings.NewString("Draw arrow at end of line")); PrototypeArrow.Set(FALSE);
END InitPrototypes;

PROCEDURE InitStrings;
BEGIN
	StrFigure := Strings.NewString("Figure");
	StrLine := Strings.NewString("Line");
	StrCircle := Strings.NewString("Circle");
	StrRectangle := Strings.NewString("Rectangle");
	StrSpline := Strings.NewString("Spline");
END InitStrings;

BEGIN
	gravity := 6;
	InitStrings;
	InitPrototypes;
	Streams.OpenWriter(log, KernelLog.Send);
END WMFigures.

SystemTools.FreeDownTo WMFigures ~

ComponentViewer.Open WMFigures.GenLine ~
ComponentViewer.Open WMFigures.GenSpline ~
ComponentViewer.Open WMFigures.GenCircle ~
ComponentViewer.Open WMFigures.GenRectangle ~

ComponentViewer.Open WMShapes.GenLine ~

Example application for Line:

MODULE FigureTester; 
	IMPORT ComponentViewer, Commands, XML, WMFigures;
	PROCEDURE Test*(context:Commands.Context);
	VAR line: XML.Element; window: ComponentViewer.Window;
	BEGIN
		line:=WMFigures.GenLine();
		line(WMFigures.Line).AddPoint(30,20); 
		line(WMFigures.Line).AddPoint(40,50); 
		line(WMFigures.Line).AddPoint(10,70); 
		line.Write(context.out, NIL, 0); context.out.Ln; context.out.Update; (* show XML structure*)
		ComponentViewer.DoShow(line(WMFigures.Figure), window, 200,300,200,200, FALSE,FALSE,FALSE, {});
	END Test;
END FigureTester.

FigureTester.Test  ~

