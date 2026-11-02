package folio.image;

import haxe.io.Bytes;

/**
	Windows bitmaps decoded: 1, 4, 8, 24 and 32 bits a pixel, uncompressed, rows stored
	from the bottom up or, for a negative height, from the top down. A 32-bit bitmap's
	fourth byte is not taken as transparency, as Windows does not take it so either.
**/
class Bmp {
	public static function decode(b:Bytes):Null<Picture> {
		final dataAt = b.getInt32(10);
		final headerSize = b.getInt32(14);
		if (headerSize < 40) {
			return null;
		}
		final width = b.getInt32(18);
		final rawHeight = b.getInt32(22);
		final height = Std.int(Math.abs(rawHeight));
		final bits = b.getUInt16(28);
		final compression = b.getInt32(30);
		// 0 is uncompressed; 3 (bit fields) is read as the usual byte order, as 32-bit bitmaps write it.
		if (width <= 0 || height <= 0 || (compression != 0 && compression != 3)) {
			return null;
		}
		var colours = b.getInt32(46);
		if (colours == 0 && bits <= 8) {
			colours = 1 << bits;
		}
		final paletteAt = 14 + headerSize;
		final stride = ((width * bits + 31) >> 5) << 2;
		final samples = Bytes.alloc(width * height * 3);
		for (y in 0...height) {
			final row = dataAt + (rawHeight > 0 ? height - 1 - y : y) * stride;
			for (x in 0...width) {
				var r = 0, g = 0, bl = 0;
				switch bits {
					case 24 | 32:
						final p = row + x * (bits >> 3);
						bl = b.get(p);
						g = b.get(p + 1);
						r = b.get(p + 2);
					case 1 | 4 | 8:
						final bit = x * bits;
						final i = (b.get(row + (bit >> 3)) >> (8 - bits - (bit & 7))) & ((1 << bits) - 1);
						final p = paletteAt + (i < colours ? i : 0) * 4;
						bl = b.get(p);
						g = b.get(p + 1);
						r = b.get(p + 2);
					default:
						return null;
				}
				final o = (y * width + x) * 3;
				samples.set(o, r);
				samples.set(o + 1, g);
				samples.set(o + 2, bl);
			}
		}
		return Picture.decoded(width, height, 3, samples, null).resolution(b.getInt32(38), b.getInt32(42), 3);
	}
}
