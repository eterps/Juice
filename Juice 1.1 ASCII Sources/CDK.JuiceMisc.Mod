MODULE JuiceMisc;

	IMPORT Kernel;

	(** Return the current time in hours, minutes and seconds. *)
	PROCEDURE GetTime*(VAR hour, min, sec: INTEGER);
		VAR t, d: LONGINT;
	BEGIN
		Kernel.GetClock(t, d);
		sec := SHORT(t MOD 40H);
		min := SHORT((t DIV 40H) MOD 40H);
		hour := SHORT(t DIV 1000H);
	END GetTime;

	(** Return the current date in days, months and years. *)
	PROCEDURE GetDate*(VAR day, month, year: INTEGER);
		VAR t, d: LONGINT;
	BEGIN
		Kernel.GetClock(t, d);
		day := SHORT(d MOD 20H);
		month := SHORT((d DIV 20H) MOD 10H);
		year := SHORT((d DIV 200H) MOD 80H) + 1900
	END GetDate;

END JuiceMisc.
