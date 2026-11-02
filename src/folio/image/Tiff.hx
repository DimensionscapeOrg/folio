package folio.image;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;

/**
	TIFF files decoded, the first picture in the file: grey, palette, RGB and CMYK, of 1 to
	16 bits a sample, in strips or tiles, uncompressed or compressed by LZW, PackBits or
	Deflate, with or without the horizontal predictor. Fax (CCITT) and JPEG compression
	are not read. Sixteen-bit samples keep their high byte.

	A fourth sample beside RGB, or a second beside grey, is transparency, and List & Label
	does not keep it: it draws the colour as if laid over black, measured, so a clear
	pixel prints black. folio draws it the same way, with no mask.
**/
class Tiff {
	public static function decode(b:Bytes):Null<Picture> {
		final t = new Tiff(b);
		return t.picture();
	}

	final b:Bytes;
	final big:Bool;
	final tags = new Map<Int, Array<Float>>();

	function new(b:Bytes) {
		this.b = b;
		big = b.get(0) == 0x4D;
		var at = u32(4);
		final count = u16(at);
		for (i in 0...count) {
			final e = at + 2 + i * 12;
			tags.set(u16(e), values(e));
		}
	}

	function picture():Null<Picture> {
		final width = one(256, 0);
		final height = one(257, 0);
		final compression = one(259, 1);
		final photometric = one(262, -1);
		final spp = one(277, 1);
		final depth = one(258, 1);
		final planar = one(284, 1);
		final predictor = one(317, 1);
		if (width <= 0 || height <= 0 || photometric < 0 || planar != 1 || [1, 5, 8, 32946, 32773].indexOf(compression) < 0
			|| [1, 2, 4, 8, 16].indexOf(depth) < 0) {
			return null;
		}
		final colours = switch photometric {
			case 0 | 1 | 3: 1;
			case 2: 3;
			case 5: 4;
			default: return null;
		}
		if (spp < colours) {
			return null;
		}
		final extra = tags.get(338);
		final hasAlpha = spp > colours && extra != null && (extra[0] == 1 || extra[0] == 2);
		// Associated transparency is already multiplied into the colour; unassociated is multiplied here.
		final unassociated = hasAlpha && extra[0] == 2;

		// Strips are tiles as wide as the picture.
		final tiled = tags.exists(322);
		final tileW = tiled ? one(322, width) : width;
		final tileH = tiled ? one(323, height) : one(278, height);
		final offsets = tags.get(tiled ? 324 : 273);
		final counts = tags.get(tiled ? 325 : 279);
		if (offsets == null || counts == null) {
			return null;
		}
		final across = Std.int((width + tileW - 1) / tileW);
		final stride = Std.int((tileW * spp * depth + 7) / 8);

		final components = photometric == 3 || colours >= 3 ? 3 : 1;
		final out = Bytes.alloc(width * height * components);
		final palette = tags.get(320);
		final maxSample = (1 << depth) - 1;

		for (i in 0...offsets.length) {
			final at = Std.int(offsets[i]);
			final length = Std.int(counts[i]);
			if (at < 0 || at + length > b.length) {
				return null;
			}
			final data = switch compression {
				case 1: b.sub(at, length);
				case 5: lzw(b.sub(at, length));
				case 32773: packBits(b.sub(at, length));
				default: haxe.zip.Uncompress.run(b.sub(at, length));
			}
			final x0 = (i % across) * tileW;
			final y0 = Std.int(i / across) * tileH;
			for (ty in 0...tileH) {
				final y = y0 + ty;
				if (y >= height || (ty + 1) * stride > data.length) {
					break;
				}
				final row = ty * stride;
				if (predictor == 2 && depth == 8) {
					for (k in spp...tileW * spp) {
						data.set(row + k, (data.get(row + k) + data.get(row + k - spp)) & 0xFF);
					}
				}
				for (tx in 0...tileW) {
					final x = x0 + tx;
					if (x >= width) {
						break;
					}
					final p = y * width + x;
					inline function sample(s:Int):Int {
						return read(data, row, (tx * spp + s) * depth, depth);
					}
					inline function byte(v:Int):Int {
						return depth == 16 ? v >> 8 : Std.int(v * 255 / maxSample);
					}
					final a = hasAlpha ? byte(sample(colours)) : 255;
					switch photometric {
						case 0 | 1:
							var v = byte(sample(0));
							if (photometric == 0) {
								v = 255 - v;
							}
							out.set(p, unassociated ? Std.int(v * a / 255) : v);
						case 3:
							if (palette == null) {
								return null;
							}
							final n = 1 << depth;
							final s = sample(0);
							out.set(p * 3, Std.int(palette[s]) >> 8);
							out.set(p * 3 + 1, Std.int(palette[n + s]) >> 8);
							out.set(p * 3 + 2, Std.int(palette[2 * n + s]) >> 8);
						case 2:
							for (c in 0...3) {
								final v = byte(sample(c));
								out.set(p * 3 + c, unassociated ? Std.int(v * a / 255) : v);
							}
						default:
							final k = byte(sample(3));
							for (c in 0...3) {
								out.set(p * 3 + c, Std.int((255 - byte(sample(c))) * (255 - k) / 255));
							}
					}
				}
			}
		}
		final pic = Picture.decoded(width, height, components, out, null);
		final x = tags.get(282);
		final y = tags.get(283);
		// Resolution unit 1 says the numbers are only an aspect; 2 is the default, an inch.
		return x == null || y == null ? pic : pic.resolution(x[0], y[0], switch one(296, 2) {
			case 2: 1;
			case 3: 2;
			default: 0;
		});
	}

	/** One sample of `bits` bits at bit `bit` of the row starting at byte `row`, the most significant bit first. **/
	static function read(data:Bytes, row:Int, bit:Int, bits:Int):Int {
		final at = row + (bit >> 3);
		return switch bits {
			case 8: data.get(at);
			case 16: (data.get(at) << 8) | data.get(at + 1);
			default: (data.get(at) >> (8 - bits - (bit & 7))) & ((1 << bits) - 1);
		}
	}

	/** TIFF's LZW: codes from 9 to 12 bits, most significant bit first, each wider one code early. **/
	static function lzw(input:Bytes):Bytes {
		final out = new BytesBuffer();
		final table:Array<Bytes> = [];
		var width = 9;
		var bit = 0;
		var previous:Null<Bytes> = null;
		function reset() {
			table.resize(0);
			for (i in 0...256) {
				final one = Bytes.alloc(1);
				one.set(0, i);
				table.push(one);
			}
			table.push(null);
			table.push(null);
			width = 9;
			previous = null;
		}
		reset();
		while (bit + width <= input.length * 8) {
			var code = 0;
			for (k in 0...width) {
				final at = bit + k;
				code = (code << 1) | ((input.get(at >> 3) >> (7 - (at & 7))) & 1);
			}
			bit += width;
			if (code == 257) {
				break;
			}
			if (code == 256) {
				reset();
				continue;
			}
			var entry:Bytes;
			if (code < table.length && table[code] != null) {
				entry = table[code];
				if (previous != null) {
					table.push(join(previous, entry.get(0)));
				}
			} else if (previous != null) {
				entry = join(previous, previous.get(0));
				table.push(entry);
			} else {
				break;
			}
			out.addBytes(entry, 0, entry.length);
			previous = entry;
			if (table.length + 1 >= 1 << width && width < 12) {
				width++;
			}
		}
		return out.getBytes();
	}

	static function join(a:Bytes, last:Int):Bytes {
		final r = Bytes.alloc(a.length + 1);
		r.blit(0, a, 0, a.length);
		r.set(a.length, last);
		return r;
	}

	/** PackBits: a count n below 128 copies n + 1 bytes, above 128 repeats the next byte 257 - n times, 128 is nothing. **/
	static function packBits(input:Bytes):Bytes {
		final out = new BytesBuffer();
		var i = 0;
		while (i < input.length) {
			final n = input.get(i++);
			if (n < 128) {
				out.addBytes(input, i, Std.int(Math.min(n + 1, input.length - i)));
				i += n + 1;
			} else if (n > 128 && i < input.length) {
				final v = input.get(i++);
				for (_ in 0...257 - n) {
					out.addByte(v);
				}
			}
		}
		return out.getBytes();
	}

	function one(tag:Int, otherwise:Int):Int {
		final v = tags.get(tag);
		return v == null || v.length == 0 ? otherwise : Std.int(v[0]);
	}

	/** An entry's values: its numbers, a rational as a fraction worked out. **/
	function values(e:Int):Array<Float> {
		final type = u16(e + 2);
		final count = u32(e + 4);
		final size = switch type {
			case 1 | 2 | 6 | 7: 1;
			case 3 | 8: 2;
			case 4 | 9 | 11: 4;
			case 5 | 10 | 12: 8;
			default: 0;
		}
		if (size == 0 || count <= 0) {
			return [];
		}
		final at = size * count <= 4 ? e + 8 : u32(e + 8);
		if (at < 0 || at + size * count > b.length) {
			return [];
		}
		return [for (i in 0...count) {
			final p = at + i * size;
			switch type {
				case 3 | 8: u16(p);
				case 4 | 9: u32(p);
				case 5 | 10: u32(p + 4) == 0 ? 0 : u32(p) / u32(p + 4);
				default: b.get(p);
			}
		}];
	}

	function u16(at:Int):Int {
		return big ? (b.get(at) << 8) | b.get(at + 1) : b.get(at) | (b.get(at + 1) << 8);
	}

	function u32(at:Int):Int {
		return big ? (u16(at) << 16) | u16(at + 2) : u16(at) | (u16(at + 2) << 16);
	}
}
