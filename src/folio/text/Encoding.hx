package folio.text;

import haxe.io.Bytes;

/**
	Text files as List & Label writes them. Project files are UTF-8 with a byte order mark
	in current versions, and Windows-1252 in files last saved by older ones; both occur
	among shipped layouts, so a file that is not valid UTF-8 is read as Windows-1252.
**/
class Encoding {
	static final CP1252_80_9F = [
		0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
		0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
		0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
		0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178
	];

	public static function decode(b:Bytes):String {
		var start = 0;
		if (b.length >= 3 && b.get(0) == 0xEF && b.get(1) == 0xBB && b.get(2) == 0xBF) {
			start = 3;
		}
		if (isUtf8(b, start)) {
			return b.getString(start, b.length - start, UTF8);
		}
		return decodeCp1252(b);
	}

	public static function decodeCp1252(b:Bytes):String {
		final out = new StringBuf();
		for (i in 0...b.length) {
			final c = b.get(i);
			out.addChar(c >= 0x80 && c <= 0x9F ? CP1252_80_9F[c - 0x80] : c);
		}
		return out.toString();
	}

	public static function isUtf8(b:Bytes, start = 0):Bool {
		var i = start;
		while (i < b.length) {
			final c = b.get(i);
			final extra = if (c < 0x80) 0 else if (c >= 0xC2 && c <= 0xDF) 1 else if (c >= 0xE0 && c <= 0xEF) 2 else if (c >= 0xF0 && c <= 0xF4) 3 else -1;
			if (extra < 0) {
				return false;
			}
			for (k in 1...extra + 1) {
				if (i + k >= b.length || b.get(i + k) & 0xC0 != 0x80) {
					return false;
				}
			}
			i += extra + 1;
		}
		return true;
	}
}
