package folio.font;

import haxe.io.Bytes;

/**
	A TrueType font file, read for what laying out and embedding text needs: the family
	and style it names, its vertical metrics, which glyph draws each character, and each
	glyph's advance and outline bounds. The file's bytes are kept whole, to be embedded as
	they are.
**/
class TrueType {
	public final bytes:Bytes;
	public var family(default, null) = "";
	public var subfamily(default, null) = "";
	public var postScriptName(default, null) = "";
	public var unitsPerEm(default, null) = 1000;
	public var ascent(default, null) = 0;
	public var descent(default, null) = 0;
	public var winAscent(default, null) = 0;
	public var winDescent(default, null) = 0;
	public var capHeight(default, null) = 0;
	public var italicAngle(default, null) = 0.0;
	/** Where an underline's middle sits, in font units above the baseline (so below is negative), and how thick it is. **/
	public var underlinePosition(default, null) = -100;
	public var underlineThickness(default, null) = 50;
	public var bold(default, null) = false;
	public var italic(default, null) = false;
	public var bbox(default, null):Array<Int> = [0, 0, 0, 0];
	public var embeddable(default, null) = true;

	final tables = new Map<String, {offset:Int, length:Int}>();
	var advances:Array<Int> = [];
	final glyphOf = new Map<Int, Int>();

	public function new(bytes:Bytes, offset = 0) {
		this.bytes = bytes;
		final count = u16(offset + 4);
		for (i in 0...count) {
			final at = offset + 12 + i * 16;
			tables.set(bytes.getString(at, 4), {offset: u32(at + 8), length: u32(at + 12)});
		}
		readHead();
		readHhea();
		readOs2();
		readPost();
		readName();
		readCmap();
	}

	public static function load(path:String):TrueType {
		return new TrueType(sys.io.File.getBytes(path));
	}

	/** The glyph that draws a character, 0 (the missing glyph) when the font has none. **/
	public function glyph(codePoint:Int):Int {
		final g = glyphOf.get(codePoint);
		return g == null ? 0 : g;
	}

	public function hasGlyph(codePoint:Int):Bool {
		return glyphOf.exists(codePoint);
	}

	/** A glyph's advance in font units. **/
	public function advance(glyph:Int):Int {
		if (advances.length == 0) {
			return 0;
		}
		return glyph < advances.length ? advances[glyph] : advances[advances.length - 1];
	}

	/**
		How far a text's ink reaches above and below its baseline at a size, and how far
		right of the text's start it begins, in the size's unit, from each glyph's outline
		bounds. All are 0 for a text with no ink.
	**/
	public function ink(text:String, size:Float):{above:Float, below:Float, left:Float} {
		final glyf = table("glyf");
		final loca = table("loca");
		final head = table("head");
		if (glyf == null || loca == null || head == null) {
			return {above: 0, below: 0, left: 0};
		}
		final longOffsets = s16(head + 50) == 1;
		var lowest = 0;
		var highest = 0;
		var left:Null<Int> = null;
		var x = 0;
		for (c in codePoints(text)) {
			final g = glyph(c);
			final start = longOffsets ? u32(loca + g * 4) : u16(loca + g * 2) * 2;
			final end = longOffsets ? u32(loca + g * 4 + 4) : u16(loca + g * 2 + 2) * 2;
			// An empty glyph, a space, has no outline and no bounds.
			if (end > start) {
				lowest = Std.int(Math.min(lowest, s16(glyf + start + 4)));
				highest = Std.int(Math.max(highest, s16(glyf + start + 8)));
				if (left == null) {
					left = x + s16(glyf + start + 2);
				}
			}
			x += advance(g);
		}
		final scale = size / unitsPerEm;
		return {above: highest * scale, below: -lowest * scale, left: left == null ? 0 : left * scale};
	}

	/** The width of a text at a size, in the size's unit. **/
	public function width(text:String, size:Float):Float {
		var units = 0;
		for (c in codePoints(text)) {
			units += advance(glyph(c));
		}
		return units * size / unitsPerEm;
	}

	public static function codePoints(text:String):Array<Int> {
		final out = [];
		var i = 0;
		while (i < text.length) {
			var c:Int = StringTools.fastCodeAt(text, i);
			if (c >= 0xD800 && c <= 0xDBFF && i + 1 < text.length) {
				final lo:Int = StringTools.fastCodeAt(text, i + 1);
				if (lo >= 0xDC00 && lo <= 0xDFFF) {
					c = 0x10000 + ((c - 0xD800) << 10) + (lo - 0xDC00);
					i++;
				}
			}
			out.push(c);
			i++;
		}
		return out;
	}

	function table(tag:String):Null<Int> {
		final t = tables.get(tag);
		return t == null ? null : t.offset;
	}

	function readHead() {
		final at = table("head");
		if (at == null) {
			return;
		}
		unitsPerEm = u16(at + 18);
		bbox = [s16(at + 36), s16(at + 38), s16(at + 40), s16(at + 42)];
		final style = u16(at + 44);
		bold = style & 1 != 0;
		italic = style & 2 != 0;
	}

	function readHhea() {
		final at = table("hhea");
		if (at == null) {
			return;
		}
		ascent = s16(at + 4);
		descent = s16(at + 6);
		final count = u16(at + 34);
		final hmtx = table("hmtx");
		if (hmtx != null) {
			advances = [for (i in 0...count) u16(hmtx + i * 4)];
		}
	}

	function readOs2() {
		final at = table("OS/2");
		if (at == null) {
			winAscent = ascent;
			winDescent = -descent;
			capHeight = ascent;
			return;
		}
		final version = u16(at);
		final fsType = u16(at + 8);
		// Bit 1 alone forbids embedding; 4 (print and preview) and 8 (editable) allow it.
		embeddable = fsType & 0x000E != 0x0002;
		final selection = u16(at + 62);
		bold = bold || selection & 0x20 != 0;
		italic = italic || selection & 0x01 != 0;
		winAscent = u16(at + 74);
		winDescent = u16(at + 76);
		capHeight = version >= 2 ? s16(at + 88) : ascent;
	}

	function readPost() {
		final at = table("post");
		if (at != null) {
			italicAngle = s16(at + 4) + u16(at + 6) / 65536;
			underlinePosition = s16(at + 8);
			underlineThickness = s16(at + 10);
		}
	}

	function readName() {
		final at = table("name");
		if (at == null) {
			return;
		}
		final count = u16(at + 2);
		final strings = at + u16(at + 4);
		for (i in 0...count) {
			final r = at + 6 + i * 12;
			final platform = u16(r);
			final language = u16(r + 4);
			final id = u16(r + 6);
			final length = u16(r + 8);
			final offset = strings + u16(r + 10);
			// Windows Unicode, US English: the names a font picker shows.
			if (platform != 3 || language != 0x409) {
				continue;
			}
			final b = new StringBuf();
			var k = 0;
			while (k + 1 < length) {
				b.addChar(u16(offset + k));
				k += 2;
			}
			switch id {
				case 1: family = b.toString();
				case 2: subfamily = b.toString();
				case 6: postScriptName = b.toString();
			}
		}
	}

	function readCmap() {
		final at = table("cmap");
		if (at == null) {
			return;
		}
		final count = u16(at + 2);
		var best = -1;
		var bestFormat = 0;
		for (i in 0...count) {
			final r = at + 4 + i * 8;
			final platform = u16(r);
			final encoding = u16(r + 2);
			final sub = at + u32(r + 4);
			final format = u16(sub);
			final unicode = (platform == 3 && (encoding == 1 || encoding == 10)) || platform == 0;
			if (unicode && (format == 12 || (format == 4 && bestFormat != 12))) {
				best = sub;
				bestFormat = format;
			}
		}
		if (best < 0) {
			return;
		}
		if (bestFormat == 4) {
			final segments = u16(best + 6) >> 1;
			final ends = best + 14;
			final starts = ends + segments * 2 + 2;
			final deltas = starts + segments * 2;
			final ranges = deltas + segments * 2;
			for (s in 0...segments) {
				final end = u16(ends + s * 2);
				final start = u16(starts + s * 2);
				final delta = s16(deltas + s * 2);
				final range = u16(ranges + s * 2);
				for (c in start...end + 1) {
					if (c == 0xFFFF) {
						continue;
					}
					var g;
					if (range == 0) {
						g = (c + delta) & 0xFFFF;
					} else {
						final p = ranges + s * 2 + range + (c - start) * 2;
						g = u16(p);
						if (g != 0) {
							g = (g + delta) & 0xFFFF;
						}
					}
					if (g != 0) {
						glyphOf.set(c, g);
					}
				}
			}
		} else {
			final groups = u32(best + 12);
			for (i in 0...groups) {
				final r = best + 16 + i * 12;
				final start = u32(r);
				final end = u32(r + 4);
				final first = u32(r + 8);
				for (c in start...end + 1) {
					glyphOf.set(c, first + c - start);
				}
			}
		}
	}

	inline function u16(at:Int):Int {
		return (bytes.get(at) << 8) | bytes.get(at + 1);
	}

	inline function s16(at:Int):Int {
		final v = u16(at);
		return v >= 0x8000 ? v - 0x10000 : v;
	}

	inline function u32(at:Int):Int {
		return (bytes.get(at) << 24) | (bytes.get(at + 1) << 16) | (bytes.get(at + 2) << 8) | bytes.get(at + 3);
	}
}
