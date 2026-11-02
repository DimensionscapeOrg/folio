package folio.ll;

/**
	Compact JSON for recorded reports, written by hand so object keys keep the order the
	report defined them in.
**/
class Json {
	public static function string(s:String):String {
		final b = new StringBuf();
		b.add('"');
		var run = 0;
		for (i in 0...s.length) {
			final c = StringTools.fastCodeAt(s, i);
			final escape = switch c {
				case '"'.code: '\\"';
				case '\\'.code: "\\\\";
				case '\n'.code: "\\n";
				case '\r'.code: "\\r";
				case '\t'.code: "\\t";
				default: c < 0x20 ? "\\u" + StringTools.hex(c, 4).toLowerCase() : null;
			}
			if (escape != null) {
				b.addSub(s, run, i - run);
				b.add(escape);
				run = i + 1;
			}
		}
		b.addSub(s, run, s.length - run);
		b.add('"');
		return b.toString();
	}

	public static function object(n:Named):String {
		final parts = [for (name in n.names) string(name) + ":" + string(n.get(name))];
		return "{" + parts.join(",") + "}";
	}
}
