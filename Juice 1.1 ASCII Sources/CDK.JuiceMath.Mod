MODULE JuiceMath;	(* mad, 30.10.96 *)

(** Commonly needed Math for REALs.
*)

IMPORT Math;

CONST
	e* = Math.e;
	pi* = Math.pi;

PROCEDURE Sqrt* (x: REAL): REAL;
BEGIN RETURN Math.sqrt(x)
END Sqrt;

PROCEDURE Exp* (x: REAL): REAL;
BEGIN RETURN Math.exp(x)
END Exp;

PROCEDURE Ln* (x: REAL): REAL;
BEGIN RETURN Math.ln(x)
END Ln;

PROCEDURE Sin* (x: REAL): REAL;
BEGIN RETURN Math.sin(x)
END Sin;

PROCEDURE Cos* (x: REAL): REAL;
BEGIN RETURN Math.cos(x)
END Cos;

PROCEDURE Arctan* (x: REAL): REAL;
BEGIN RETURN Math.arctan(x)
END Arctan;


BEGIN
END JuiceMath.
