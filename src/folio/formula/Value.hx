package folio.formula;

/**
	A value a formula works with. A report hands every value over as text; a formula
	makes numbers and booleans of its own.
**/
enum Value {
	VText(v:String);
	VNumber(v:Float);
	VBool(v:Bool);
}

class Values {
	/**
		Whether a value counts as true. Text is true when it reads "true" or "1", in any
		case, which is how the reports hand a flag over.
	**/
	public static function truth(v:Value):Bool {
		return switch v {
			case VBool(b): b;
			case VNumber(n): n != 0;
			case VText(t):
				final l = t.toLowerCase();
				l == "true" || l == "1";
		}
	}

	public static function text(v:Value):String {
		return switch v {
			case VText(t): t;
			case VBool(b): b ? "true" : "false";
			case VNumber(n): formatNumber(n);
		}
	}

	/** A value as a number: text that does not read as one is 0. **/
	public static function number(v:Value):Float {
		return switch v {
			case VNumber(n): n;
			case VBool(b): b ? 1 : 0;
			case VText(t):
				final n = Std.parseFloat(StringTools.trim(t));
				Math.isNaN(n) ? 0 : n;
		}
	}

	static function formatNumber(n:Float):String {
		if (n == Math.ffloor(n) && Math.abs(n) < 1e15) {
			return Std.string(Std.int(n));
		}
		return Std.string(n);
	}
}
