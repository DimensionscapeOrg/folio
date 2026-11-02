package folio.image;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;

/**
	PNG files decoded: grey, RGB and palette pictures, with or without transparency, of
	any bit depth, interlaced or not. Sixteen-bit samples keep their high byte.
**/
class Png {
	public static function decode(b:Bytes):Null<Picture> {
		var width = 0;
		var height = 0;
		var depth = 8;
		var type = 0;
		var interlaced = false;
		var palette:Null<Bytes> = null;
		var transparency:Null<Bytes> = null;
		var perMetreX = 0, perMetreY = 0;
		final data = new BytesBuffer();
		var at = 8;
		while (at + 8 <= b.length) {
			final length = (b.get(at) << 24) | (b.get(at + 1) << 16) | (b.get(at + 2) << 8) | b.get(at + 3);
			final tag = b.getString(at + 4, 4);
			final body = at + 8;
			switch tag {
				case "IHDR":
					width = int32(b, body);
					height = int32(b, body + 4);
					depth = b.get(body + 8);
					type = b.get(body + 9);
					interlaced = b.get(body + 12) == 1;
				case "PLTE":
					palette = b.sub(body, length);
				case "tRNS":
					transparency = b.sub(body, length);
				case "pHYs" if (length >= 9 && b.get(body + 8) == 1):
					perMetreX = int32(b, body);
					perMetreY = int32(b, body + 4);
				case "IDAT":
					data.addBytes(b, body, length);
				case "IEND":
					break;
			}
			at = body + length + 4;
		}
		if (width <= 0 || height <= 0) {
			return null;
		}
		final raw = haxe.zip.Uncompress.run(data.getBytes());
		final channels = switch type {
			case 0: 1;
			case 2: 3;
			case 3: 1;
			case 4: 2;
			case 6: 4;
			default: return null;
		}
		final bitsPerPixel = channels * depth;
		final colour = type == 2 || type == 3 || type == 6;
		final components = colour ? 3 : 1;
		final samples = Bytes.alloc(width * height * components);
		final alpha = type == 4 || type == 6 || transparency != null ? Bytes.alloc(width * height) : null;
		if (alpha != null) {
			alpha.fill(0, alpha.length, 255);
		}

		// One pass for a plain picture, seven for an interlaced one, each a smaller picture of its own.
		final passes = interlaced ? ADAM7 : [[0, 0, 1, 1]];
		var offset = 0;
		for (p in passes) {
			final pw = Std.int((width - p[0] + p[2] - 1) / p[2]);
			final ph = Std.int((height - p[1] + p[3] - 1) / p[3]);
			if (pw <= 0 || ph <= 0) {
				continue;
			}
			final stride = Std.int((pw * bitsPerPixel + 7) / 8);
			final step = Std.int(Math.max(1, bitsPerPixel / 8));
			var previous = Bytes.alloc(stride);
			previous.fill(0, stride, 0);
			for (y in 0...ph) {
				final filter = raw.get(offset);
				final row = raw.sub(offset + 1, stride);
				offset += stride + 1;
				unfilter(filter, row, previous, step);
				for (x in 0...pw) {
					store(row, x, depth, type, palette, transparency, samples, alpha, (p[1] + y * p[3]) * width + p[0] + x * p[2]);
				}
				previous = row;
			}
		}
		return Picture.decoded(width, height, components, samples, alpha).resolution(perMetreX, perMetreY, 3);
	}

	static final ADAM7 = [[0, 0, 8, 8], [4, 0, 8, 8], [0, 4, 4, 8], [2, 0, 4, 4], [0, 2, 2, 4], [1, 0, 2, 2], [0, 1, 1, 2]];

	static function unfilter(filter:Int, row:Bytes, previous:Bytes, step:Int) {
		for (i in 0...row.length) {
			final a = i >= step ? row.get(i - step) : 0;
			final up = previous.get(i);
			final c = i >= step ? previous.get(i - step) : 0;
			final v = switch filter {
				case 1: a;
				case 2: up;
				case 3: (a + up) >> 1;
				case 4: paeth(a, up, c);
				default: 0;
			}
			row.set(i, (row.get(i) + v) & 0xFF);
		}
	}

	static inline function paeth(a:Int, b:Int, c:Int):Int {
		final p = a + b - c;
		final pa = Std.int(Math.abs(p - a));
		final pb = Std.int(Math.abs(p - b));
		final pc = Std.int(Math.abs(p - c));
		return pa <= pb && pa <= pc ? a : (pb <= pc ? b : c);
	}

	/** A row's sample at `index`, counting samples rather than bytes, scaled to 8 bits. **/
	static inline function sample(row:Bytes, index:Int, depth:Int):Int {
		return switch depth {
			case 8: row.get(index);
			case 16: row.get(index * 2);
			default:
				final bit = index * depth;
				final v = (row.get(bit >> 3) >> (8 - depth - (bit & 7))) & ((1 << depth) - 1);
				Std.int(v * 255 / ((1 << depth) - 1));
		}
	}

	static function store(row:Bytes, x:Int, depth:Int, type:Int, palette:Null<Bytes>, transparency:Null<Bytes>, samples:Bytes, alpha:Null<Bytes>, pixel:Int) {
		switch type {
			case 3:
				final bit = x * depth;
				final i = depth == 8 ? row.get(x) : (row.get(bit >> 3) >> (8 - depth - (bit & 7))) & ((1 << depth) - 1);
				final p = palette != null && i * 3 + 2 < palette.length ? i * 3 : 0;
				samples.set(pixel * 3, palette == null ? 0 : palette.get(p));
				samples.set(pixel * 3 + 1, palette == null ? 0 : palette.get(p + 1));
				samples.set(pixel * 3 + 2, palette == null ? 0 : palette.get(p + 2));
				if (alpha != null && transparency != null && i < transparency.length) {
					alpha.set(pixel, transparency.get(i));
				}
			case 0 | 4:
				final channels = type == 0 ? 1 : 2;
				final g = sample(row, x * channels, depth);
				samples.set(pixel, g);
				if (type == 4) {
					alpha.set(pixel, sample(row, x * 2 + 1, depth));
				} else if (alpha != null && transparency != null && transparency.length >= 2) {
					final key = depth == 16 ? transparency.get(0) : transparency.get(1);
					if (sample(row, x, depth) == (depth == 16 ? key : Std.int(key * 255 / ((1 << depth) - 1)))) {
						alpha.set(pixel, 0);
					}
				}
			default:
				final channels = type == 2 ? 3 : 4;
				final r = sample(row, x * channels, depth);
				final g = sample(row, x * channels + 1, depth);
				final bl = sample(row, x * channels + 2, depth);
				samples.set(pixel * 3, r);
				samples.set(pixel * 3 + 1, g);
				samples.set(pixel * 3 + 2, bl);
				if (type == 6) {
					alpha.set(pixel, sample(row, x * 4 + 3, depth));
				} else if (alpha != null && transparency != null && transparency.length >= 6) {
					final hi = depth == 16 ? 0 : 1;
					if (r == transparency.get(hi) && g == transparency.get(2 + hi) && bl == transparency.get(4 + hi)) {
						alpha.set(pixel, 0);
					}
				}
		}
	}

	static inline function int32(b:Bytes, at:Int):Int {
		return (b.get(at) << 24) | (b.get(at + 1) << 16) | (b.get(at + 2) << 8) | b.get(at + 3);
	}
}
