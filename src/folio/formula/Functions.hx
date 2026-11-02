package folio.formula;

import folio.formula.Formula.FormulaError;
import folio.formula.Value;

using folio.formula.Value.Values;

/**
	The designer's built-in functions that do not depend on where the page is. Page
	numbers and print passes are the caller's, through `Scope.call`.
**/
class Functions {
	static final MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];

	public static function call(name:String, a:Array<Value>):Value {
		inline function arg(i:Int):Value {
			return i < a.length ? a[i] : VText("");
		}
		return switch name {
			case "null": VText("");
			case "val": VNumber(arg(0).number());
			case "str$":
				// Str$(number, length, decimals): right aligned in `length` characters.
				final decimals = a.length > 2 ? Std.int(arg(2).number()) : 0;
				final s = fixed(arg(0).number(), decimals);
				final length = a.length > 1 ? Std.int(arg(1).number()) : 0;
				VText(length > 0 ? StringTools.lpad(s, " ", length) : s);
			case "fstr$": VText(fstr(arg(0).number(), arg(1).text(), a.length > 2 ? Std.int(arg(2).number()) : 0));
			case "sign":
				final n = arg(0).number();
				VNumber(n > 0 ? 1 : n < 0 ? -1 : 0);
			case "abs": VNumber(Math.abs(arg(0).number()));
			case "int": VNumber(arg(0).number() < 0 ? Math.fceil(arg(0).number()) : Math.ffloor(arg(0).number()));
			case "round":
				final p = Math.pow(10, a.length > 1 ? arg(1).number() : 0);
				VNumber(Math.fround(arg(0).number() * p) / p);
			case "empty" | "isnullorempty":
				final t = arg(0).text();
				VBool((a.length > 1 && arg(1).truth() ? StringTools.trim(t) : t) == "");
			case "contains": VBool(arg(0).text().indexOf(arg(1).text()) >= 0);
			case "len": VNumber(arg(0).text().length);
			case "left$": VText(arg(0).text().substr(0, Std.int(arg(1).number())));
			case "right$":
				final t = arg(0).text();
				final n = Std.int(arg(1).number());
				VText(n >= t.length ? t : t.substr(t.length - n));
			case "mid$": VText(arg(0).text().substr(Std.int(arg(1).number()), a.length > 2 ? Std.int(arg(2).number()) : null));
			case "upper$": VText(arg(0).text().toUpperCase());
			case "lower$": VText(arg(0).text().toLowerCase());
			case "alltrim$": VText(StringTools.trim(arg(0).text()));
			case "ltrim$": VText(StringTools.ltrim(arg(0).text()));
			case "rtrim$": VText(StringTools.rtrim(arg(0).text()));
			case "rgb": VNumber(Colors.colorref(Std.int(arg(0).number()), Std.int(arg(1).number()), Std.int(arg(2).number())));
			case "now" | "today": VText(DateTools.format(Date.now(), "%Y-%m-%d %H:%M:%S"));
			case "date$": VText(date(arg(0).text(), a.length > 1 ? arg(1).text() : "%m/%d/%Y"));
			case "unitfromscm":
				// Layouts here are in SCM units, so a length in them is unchanged.
				VNumber(arg(0).number());
			default:
				throw new FormulaError('unknown function $name');
		}
	}

	/**
		FStr$(number, format, modifier). In the format, `#` is a digit or a leading space,
		`&` a digit or a leading zero, `.` the decimal point and `,` a thousands separator.
		Modifier 1 removes leading spaces, 2 trailing ones, 3 both.
	**/
	public static function fstr(n:Float, format:String, modifier:Int):String {
		final point = format.indexOf(".");
		final intPart = point < 0 ? format : format.substr(0, point);
		final decPart = point < 0 ? "" : format.substr(point + 1);
		var decimals = 0;
		for (i in 0...decPart.length) {
			if (decPart.charAt(i) == "#" || decPart.charAt(i) == "&") {
				decimals++;
			}
		}
		final digits = fixed(Math.abs(n), decimals);
		final dot = digits.indexOf(".");
		final whole = dot < 0 ? digits : digits.substr(0, dot);
		final fraction = dot < 0 ? "" : digits.substr(dot + 1);

		// The integer part fills the format's positions from the right.
		final out = [];
		var w = whole.length - 1;
		var i = intPart.length - 1;
		while (i >= 0) {
			final c = intPart.charAt(i);
			if (c == "#" || c == "&") {
				out.unshift(w >= 0 ? whole.charAt(w) : (c == "&" ? "0" : " "));
				w--;
			} else if (c == ",") {
				out.unshift(w >= 0 ? "," : " ");
			} else {
				out.unshift(c);
			}
			i--;
		}
		// Digits the format had no room for are kept rather than lost.
		var s = (w >= 0 ? whole.substr(0, w + 1) : "") + out.join("");
		if (n < 0 && Std.parseFloat(digits) != 0) {
			// The sign goes before the first digit, taking a leading space's place.
			final lead = s.length - StringTools.ltrim(s).length;
			s = lead > 0 ? s.substr(0, lead - 1) + "-" + s.substr(lead) : "-" + s;
		}
		if (point >= 0) {
			s += "." + fraction;
		}
		if (modifier & 1 != 0) {
			s = StringTools.ltrim(s);
		}
		if (modifier & 2 != 0) {
			s = StringTools.rtrim(s);
		}
		return s;
	}

	/** A number with a fixed count of decimals, rounded half away from zero. **/
	public static function fixed(n:Float, decimals:Int):String {
		final p = Math.pow(10, decimals);
		final r = Math.fround(Math.abs(n) * p) / p;
		var s = Std.string(Math.ffloor(r));
		if (StringTools.endsWith(s, ".0")) {
			s = s.substr(0, s.length - 2);
		}
		if (decimals > 0) {
			final frac = Std.string(Math.fround((r - Math.ffloor(r)) * p));
			s += "." + StringTools.lpad(frac.split(".")[0], "0", decimals);
		}
		return (n < 0 && r != 0 ? "-" : "") + s;
	}

	/**
		Date$(date, format): `%d` day, `%m` month number, `%M` month name, `%y` and `%Y`
		four-digit year. A date that does not read as one is today.
	**/
	public static function date(text:String, format:String):String {
		var d = Date.now();
		try {
			d = Date.fromString(text);
		} catch (_:Dynamic) {}
		final b = new StringBuf();
		var i = 0;
		while (i < format.length) {
			final c = format.charAt(i);
			if (c == "%" && i + 1 < format.length) {
				final f = format.charAt(i + 1);
				b.add(switch f {
					case "d": Std.string(d.getDate());
					case "m": Std.string(d.getMonth() + 1);
					case "M": MONTHS[d.getMonth()];
					case "y" | "Y": Std.string(d.getFullYear());
					default: "%" + f;
				});
				i += 2;
			} else {
				b.add(c);
				i++;
			}
		}
		return b.toString();
	}
}
