package folio.image;

import haxe.io.Bytes;

/**
	A picture as a PDF takes it. A JPEG file is kept as it is, since a PDF draws one
	directly; PNG, BMP, TIFF and GIF files are decoded to 8-bit samples, colour or grey,
	with their transparency apart as a mask.
**/
class Picture {
	public final width:Int;
	public final height:Int;
	/** 1 for grey, 3 for RGB, 4 for CMYK (JPEG only). **/
	public final components:Int;
	/** The JPEG file itself, or null for decoded samples. **/
	public final jpeg:Null<Bytes>;
	/** An Adobe CMYK JPEG stores its samples inverted. **/
	public final inverted:Bool;
	/** The samples, rows top first, `components` bytes a pixel, when not a JPEG. **/
	public final samples:Null<Bytes>;
	/** One byte of opacity a pixel, or null when the picture is opaque throughout. **/
	public final alpha:Null<Bytes>;
	/** Pixels an inch across and down, as the file states them, or 0 where it does not. **/
	public var dpiX:Float = 0;
	public var dpiY:Float = 0;

	/** Pixels an inch where a file states none: the screen's. **/
	public static inline final SCREEN_DPI = 96.0;

	/** The picture's own size in points, at the resolution its file states. **/
	public function pointWidth():Float {
		return width * 72 / (dpiX > 0 ? dpiX : SCREEN_DPI);
	}

	public function pointHeight():Float {
		return height * 72 / (dpiY > 0 ? dpiY : SCREEN_DPI);
	}

	/** Sets the resolution from pixels per unit: 1 an inch, 2 a centimetre, 3 a metre; anything else states none. **/
	public function resolution(x:Float, y:Float, unit:Int):Picture {
		final scale = switch unit {
			case 1: 1.0;
			case 2: 2.54;
			case 3: 0.0254;
			default: 0.0;
		}
		dpiX = x * scale;
		dpiY = y * scale;
		return this;
	}

	function new(width:Int, height:Int, components:Int, jpeg:Null<Bytes>, inverted:Bool, samples:Null<Bytes>, alpha:Null<Bytes>) {
		this.width = width;
		this.height = height;
		this.components = components;
		this.jpeg = jpeg;
		this.inverted = inverted;
		this.samples = samples;
		this.alpha = alpha;
	}

	public static function decoded(width:Int, height:Int, components:Int, samples:Bytes, alpha:Null<Bytes>):Picture {
		return new Picture(width, height, components, null, false, samples, alpha);
	}

	/** A picture from a file's bytes, by what the bytes are rather than by a name; null for a kind folio does not read. **/
	public static function read(b:Bytes):Null<Picture> {
		if (b.length > 8 && b.get(0) == 0x89 && b.getString(1, 3) == "PNG") {
			return Png.decode(b);
		}
		if (b.length > 4 && b.get(0) == 0xFF && b.get(1) == 0xD8) {
			return jpegOf(b);
		}
		if (b.length > 54 && b.getString(0, 2) == "BM") {
			return Bmp.decode(b);
		}
		final intel = b.length > 8 && b.get(0) == 0x49 && b.get(1) == 0x49 && b.get(2) == 42 && b.get(3) == 0;
		final motorola = b.length > 8 && b.get(0) == 0x4D && b.get(1) == 0x4D && b.get(2) == 0 && b.get(3) == 42;
		if (intel || motorola) {
			return Tiff.decode(b);
		}
		if (b.length > 13 && (b.getString(0, 6) == "GIF87a" || b.getString(0, 6) == "GIF89a")) {
			return Gif.decode(b);
		}
		return null;
	}

	/** A JPEG's size and colours, from its frame header, whether an Adobe marker inverts it, and its JFIF resolution. **/
	static function jpegOf(b:Bytes):Null<Picture> {
		var adobe = false;
		var unit = 0, dpiX = 0, dpiY = 0;
		var i = 2;
		while (i + 4 <= b.length) {
			if (b.get(i) != 0xFF) {
				i++;
				continue;
			}
			final marker = b.get(i + 1);
			if (marker == 0xFF || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
				i += marker == 0xFF ? 1 : 2;
				continue;
			}
			final length = (b.get(i + 2) << 8) | b.get(i + 3);
			if (marker == 0xEE && length >= 7 && b.getString(i + 4, 5) == "Adobe") {
				adobe = true;
			}
			if (marker == 0xE0 && length >= 14 && b.getString(i + 4, 4) == "JFIF") {
				unit = b.get(i + 11);
				dpiX = (b.get(i + 12) << 8) | b.get(i + 13);
				dpiY = (b.get(i + 14) << 8) | b.get(i + 15);
			}
			// Any start-of-frame but the huffman table, arithmetic conditioning and JPEG-LS markers.
			if (marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC) {
				final height = (b.get(i + 5) << 8) | b.get(i + 6);
				final width = (b.get(i + 7) << 8) | b.get(i + 8);
				final components = b.get(i + 9);
				return new Picture(width, height, components, b, adobe && components == 4, null, null).resolution(dpiX, dpiY, unit);
			}
			i += 2 + length;
		}
		return null;
	}
}
