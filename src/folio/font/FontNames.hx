package folio.font;

import haxe.io.Bytes;

/**
	A font file's family and style, read without loading the file: the table directory,
	then only the head, OS/2 and name tables. Scanning a system's fonts reads hundreds of
	files, some of them tens of megabytes.
**/
class FontNames {
	public static function read(path:String):Null<{family:String, bold:Bool, italic:Bool}> {
		final input = sys.io.File.read(path, true);
		try {
			final header = chunk(input, 0, 12);
			final count = u16(header, 4);
			final dir = chunk(input, 12, count * 16);
			var family = "";
			var preferred = "";
			var bold = false;
			var italic = false;
			for (i in 0...count) {
				final tag = dir.getString(i * 16, 4);
				final offset = u32(dir, i * 16 + 8);
				final length = u32(dir, i * 16 + 12);
				switch tag {
					case "head":
						final t = chunk(input, offset, 54);
						final style = u16(t, 44);
						bold = bold || style & 1 != 0;
						italic = italic || style & 2 != 0;
					case "OS/2":
						final t = chunk(input, offset, 64);
						final selection = u16(t, 62);
						bold = bold || selection & 0x20 != 0;
						italic = italic || selection & 0x01 != 0;
					case "name":
						final t = chunk(input, offset, length);
						final n = u16(t, 2);
						final strings = u16(t, 4);
						for (k in 0...n) {
							final r = 6 + k * 12;
							if (u16(t, r) != 3 || u16(t, r + 4) != 0x409) {
								continue;
							}
							final id = u16(t, r + 6);
							if (id != 1 && id != 16) {
								continue;
							}
							final len = u16(t, r + 8);
							final at = strings + u16(t, r + 10);
							final b = new StringBuf();
							var j = 0;
							while (j + 1 < len) {
								b.addChar(u16(t, at + j));
								j += 2;
							}
							if (id == 1) {
								family = b.toString();
							} else {
								preferred = b.toString();
							}
						}
				}
			}
			input.close();
			// The legacy family is the name Windows and a layout use ("Arial Narrow"); the
			// typographic one can group styles under a shorter name ("Arial").
			final name = family != "" ? family : preferred;
			return name == "" ? null : {family: name, bold: bold, italic: italic};
		} catch (e:Dynamic) {
			input.close();
			return null;
		}
	}

	static function chunk(input:sys.io.FileInput, offset:Int, length:Int):Bytes {
		input.seek(offset, SeekBegin);
		return input.read(length);
	}

	static inline function u16(b:Bytes, at:Int):Int {
		return (b.get(at) << 8) | b.get(at + 1);
	}

	static inline function u32(b:Bytes, at:Int):Int {
		return (b.get(at) << 24) | (b.get(at + 1) << 16) | (b.get(at + 2) << 8) | b.get(at + 3);
	}
}
