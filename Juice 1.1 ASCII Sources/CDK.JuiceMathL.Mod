MODULE JuiceMathL;	(* mad, 30.10.96 *)

(** Commonly needed Math for LONGREALs.
*)

IMPORT MathL;

CONST
	e* = MathL.e;
	pi* = MathL.pi;


PROCEDURE Sqrt* (x: LONGREAL): LONGREAL;
BEGIN RETURN MathL.sqrt(x)
END Sqrt;

PROCEDURE Exp* (x: LONGREAL): LONGREAL;
BEGIN RETURN MathL.exp(x)
END Exp;

PROCEDURE Ln* (x: LONGREAL): LONGREAL;
BEGIN RETURN MathL.ln(x)
END Ln;

PROCEDURE Sin* (x: LONGREAL): LONGREAL;
BEGIN RETURN MathL.sin(x)
END Sin;

PROCEDURE Cos* (x: LONGREAL): LONGREAL;
BEGIN RETURN MathL.cos(x)
END Cos;

PROCEDURE Arctan* (x: LONGREAL): LONGREAL;
BEGIN RETURN MathL.arctan(x)
END Arctan;


BEGIN
END JuiceMathL.
