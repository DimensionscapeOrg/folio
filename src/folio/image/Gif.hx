package folio.image;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;

/**
	GIF files decoded: the first image, on a screen of the file's own size, interlaced or
	not. List & Label does not keep a GIF's transparent colour, measured: it prints the
	colour the palette gives that index, and so does folio. Where the image does not
	cover the screen the rest is white. A GIF states no resolution; List & Label takes one
	at 75 pixels an inch, measured, and so does folio.
**/
class Gif {
	public static function decode(b:Bytes):Null<Picture> {
		final width = b.getUInt16(6);
		final height = b.getUInt16(8);
		final flags = b.get(10);
		var at = 13;
		var palette:Null<Bytes> = null;
		if (flags & 0x80 != 0) {
			final size = 3 << ((flags & 7) + 1);
			palette = b.sub(at, size);
			at += size;
		}
		while (at < b.length) {
			switch b.get(at) {
				case 0x21:
					// An extension, a graphic control extension's transparent colour among them, read past.
					at = skipBlocks(b, at + 2);
				case 0x2C:
					final left = b.getUInt16(at + 1);
					final top = b.getUInt16(at + 3);
					final w = b.getUInt16(at + 5);
					final h = b.getUInt16(at + 7);
					final local = b.get(at + 9);
					at += 10;
					if (local & 0x80 != 0) {
						final size = 3 << ((local & 7) + 1);
						palette = b.sub(at, size);
						at += size;
					}
					if (palette == null || width <= 0 || height <= 0) {
						return null;
					}
					final minimum = b.get(at);
					final data = new BytesBuffer();
					at++;
					while (at < b.length && b.get(at) != 0) {
						data.addBytes(b, at + 1, b.get(at));
						at += b.get(at) + 1;
					}
					final indices = lzw(data.getBytes(), minimum, w * h);
					final rows = (local & 0x40 != 0) ? interlaced(h) : [for (y in 0...h) y];
					final samples = Bytes.alloc(width * height * 3);
					samples.fill(0, samples.length, 255);
					for (r in 0...h) {
						final y = top + rows[r];
						for (x in 0...w) {
							final i = r * w + x;
							if (i >= indices.length || y >= height || left + x >= width) {
								continue;
							}
							final c = indices.get(i);
							final p = y * width + left + x;
							if (c * 3 + 2 < palette.length) {
								samples.set(p * 3, palette.get(c * 3));
								samples.set(p * 3 + 1, palette.get(c * 3 + 1));
								samples.set(p * 3 + 2, palette.get(c * 3 + 2));
							}
						}
					}
					return Picture.decoded(width, height, 3, samples, null).resolution(75, 75, 1);
				default:
					return null;
			}
		}
		return null;
	}

	/** The row of each of an interlaced image's rows in turn: every 8th from 0, every 8th from 4, every 4th from 2, every 2nd from 1. **/
	static function interlaced(h:Int):Array<Int> {
		final order = [];
		for (pass in [[0, 8], [4, 8], [2, 4], [1, 2]]) {
			var y = pass[0];
			while (y < h) {
				order.push(y);
				y += pass[1];
			}
		}
		return order;
	}

	/** Past the sub-blocks starting at `at`, each a size byte and that many bytes, up to the empty one. **/
	static function skipBlocks(b:Bytes, at:Int):Int {
		while (at < b.length && b.get(at) != 0) {
			at += b.get(at) + 1;
		}
		return at + 1;
	}

	/** GIF's LZW: codes from the minimum size plus one up to 12 bits, least significant bit first. **/
	static function lzw(input:Bytes, minimum:Int, expected:Int):Bytes {
		final clear = 1 << minimum;
		final end = clear + 1;
		final prefix = new Array<Int>();
		final suffix = new Array<Int>();
		final first = new Array<Int>();
		final out = Bytes.alloc(expected);
		var written = 0;
		var width = minimum + 1;
		var next = end + 1;
		var previous = -1;
		var bit = 0;
		for (i in 0...clear) {
			prefix[i] = -1;
			suffix[i] = i;
			first[i] = i;
		}
		final stack = new Array<Int>();
		while (bit + width <= input.length * 8 && written < expected) {
			var code = 0;
			for (k in 0...width) {
				final at = bit + k;
				code |= ((input.get(at >> 3) >> (at & 7)) & 1) << k;
			}
			bit += width;
			if (code == clear) {
				width = minimum + 1;
				next = end + 1;
				previous = -1;
				continue;
			}
			if (code == end) {
				break;
			}
			var c = code;
			if (code >= next) {
				// The code being defined now: the previous string and its own first byte.
				if (previous < 0) {
					break;
				}
				stack.push(first[previous]);
				c = previous;
			}
			while (c >= 0) {
				stack.push(suffix[c]);
				c = prefix[c];
			}
			final head = stack[stack.length - 1];
			while (stack.length > 0) {
				final v = stack.pop();
				if (written < expected) {
					out.set(written++, v);
				}
			}
			if (previous >= 0 && next < 4096) {
				prefix[next] = previous;
				suffix[next] = head;
				first[next] = first[previous];
				next++;
				if (next == 1 << width && width < 12) {
					width++;
				}
			}
			previous = code;
		}
		return written == expected ? out : out.sub(0, written);
	}
}
