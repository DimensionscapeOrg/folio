package folio.pdf;

import folio.font.TrueType;
import folio.image.Picture;
import haxe.io.Bytes;
import haxe.io.BytesBuffer;

/**
	A PDF document written directly: pages of text, filled and outlined rectangles, lines, gradients and images.

	Coordinates are points from the top left of the page, the way a layout measures; the
	writer turns them into PDF's bottom-left space. Text is set in TrueType fonts embedded
	whole, as composite fonts addressed by glyph (Identity-H), with a ToUnicode map so the
	text can be searched and copied out of the file.
**/
class PdfDocument {
	public final pages:Array<PdfPage> = [];
	public var producer = "folio";
	public var title = "";

	final fonts:Array<EmbeddedFont> = [];
	final pictures:Array<{picture:Picture, image:PdfImage}> = [];

	public function new() {}

	@:allow(folio.pdf.PdfPage)
	function imageFor(pic:Picture):PdfImage {
		for (p in pictures) {
			if (p.picture == pic) {
				return p.image;
			}
		}
		final image = new PdfImage(pic);
		pictures.push({picture: pic, image: image});
		return image;
	}

	public function addPage(width:Float, height:Float):PdfPage {
		final p = new PdfPage(this, width, height);
		pages.push(p);
		return p;
	}

	@:allow(folio.pdf.PdfPage)
	function fontFor(font:TrueType):EmbeddedFont {
		for (f in fonts) {
			if (f.font == font) {
				return f;
			}
		}
		final f = new EmbeddedFont(font, 'F${fonts.length + 1}');
		fonts.push(f);
		return f;
	}

	public function toBytes():Bytes {
		final w = new Writer();
		final catalog = w.reserve();
		final pageTree = w.reserve();
		final info = w.reserve();

		final fontRefs = new Map<String, Int>();
		for (f in fonts) {
			fontRefs.set(f.name, f.write(w));
		}
		final fontDict = [for (f in fonts) '/${f.name} ${fontRefs.get(f.name)} 0 R'].join(" ");

		final pageRefs = [];
		for (p in pages) {
			final content = w.stream("", Bytes.ofString(p.content.toString()), true);
			final images = [for (i in 0...p.images.length) '/Im${i + 1} ${p.images[i].write(w)} 0 R'].join(" ");
			final shadings = [for (i in 0...p.shadings.length) '/Sh${i + 1} ${w.add(p.shadings[i])} 0 R'].join(" ");
			final page = w.add('<< /Type /Page /Parent $pageTree 0 R /MediaBox [0 0 ${num(p.width)} ${num(p.height)}]'
				+ ' /Resources << /Font << $fontDict >> /XObject << $images >> /Shading << $shadings >> >> /Contents $content 0 R >>');
			pageRefs.push(page);
		}
		w.set(pageTree, '<< /Type /Pages /Kids [${[for (r in pageRefs) '$r 0 R'].join(" ")}] /Count ${pageRefs.length} >>');
		w.set(catalog, '<< /Type /Catalog /Pages $pageTree 0 R >>');
		w.set(info, '<< /Producer ${Writer.text(producer)}${title == "" ? "" : " /Title " + Writer.text(title)} >>');
		return w.finish(catalog, info);
	}

	public static function num(v:Float):String {
		final r = Math.round(v * 1000) / 1000;
		if (r == Math.ffloor(r)) {
			return Std.string(Std.int(r));
		}
		return Std.string(r);
	}
}

/**
	A picture as the document stores it, written once however many pages draw it: a JPEG
	as its own file, other pictures as compressed samples with their transparency as a
	soft mask.
**/
class PdfImage {
	final picture:Picture;
	var ref = -1;

	@:allow(folio.pdf.PdfDocument)
	function new(picture:Picture) {
		this.picture = picture;
	}

	@:allow(folio.pdf.PdfDocument)
	function write(w:Writer):Int {
		if (ref >= 0) {
			return ref;
		}
		final p = picture;
		final space = switch p.components {
			case 1: "/DeviceGray";
			case 4: "/DeviceCMYK";
			default: "/DeviceRGB";
		}
		final head = '/Type /XObject /Subtype /Image /Width ${p.width} /Height ${p.height} /ColorSpace $space /BitsPerComponent 8';
		if (p.jpeg != null) {
			ref = w.stream('$head /Filter /DCTDecode${p.inverted ? " /Decode [1 0 1 0 1 0 1 0]" : ""}', p.jpeg, false);
		} else {
			var mask = "";
			if (p.alpha != null) {
				final m = w.stream('/Type /XObject /Subtype /Image /Width ${p.width} /Height ${p.height} /ColorSpace /DeviceGray /BitsPerComponent 8', p.alpha, true);
				mask = ' /SMask $m 0 R';
			}
			ref = w.stream(head + mask, p.samples, true);
		}
		return ref;
	}
}

/** A font as the document embeds it, with the glyphs its pages used. **/
private class EmbeddedFont {
	public final font:TrueType;
	public final name:String;
	public final used = new Map<Int, Int>();

	public function new(font:TrueType, name:String) {
		this.font = font;
		this.name = name;
	}

	/** The text as glyph ids for a hex string, recording the glyphs and what they draw. **/
	public function encode(text:String):String {
		final b = new StringBuf();
		for (c in TrueType.codePoints(text)) {
			final g = font.glyph(c);
			if (!used.exists(g)) {
				used.set(g, c);
			}
			b.add(StringTools.hex(g, 4));
		}
		return b.toString();
	}

	public function write(w:Writer):Int {
		final scale = 1000 / font.unitsPerEm;
		final file = w.stream('/Length1 ${font.bytes.length}', font.bytes, true);
		final base = StringTools.replace(font.postScriptName == "" ? font.family : font.postScriptName, " ", "");
		final flags = 32 | (font.italic ? 64 : 0);
		final bbox = [for (v in font.bbox) Math.round(v * scale)].join(" ");
		final descriptor = w.add('<< /Type /FontDescriptor /FontName /$base /Flags $flags /FontBBox [$bbox]'
			+ ' /ItalicAngle ${PdfDocument.num(font.italicAngle)} /Ascent ${Math.round(font.ascent * scale)}'
			+ ' /Descent ${Math.round(font.descent * scale)} /CapHeight ${Math.round(font.capHeight * scale)}'
			+ ' /StemV ${font.bold ? 120 : 80} /FontFile2 $file 0 R >>');
		final glyphs = [for (g in used.keys()) g];
		glyphs.sort(Reflect.compare);
		final widths = [for (g in glyphs) '$g [${Math.round(font.advance(g) * scale)}]'].join(" ");
		final cid = w.add('<< /Type /Font /Subtype /CIDFontType2 /BaseFont /$base'
			+ ' /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >>'
			+ ' /FontDescriptor $descriptor 0 R /W [$widths] /CIDToGIDMap /Identity >>');
		final cmap = w.stream("", Bytes.ofString(toUnicode(glyphs)), true);
		return w.add('<< /Type /Font /Subtype /Type0 /BaseFont /$base /Encoding /Identity-H'
			+ ' /DescendantFonts [$cid 0 R] /ToUnicode $cmap 0 R >>');
	}

	function toUnicode(glyphs:Array<Int>):String {
		final b = new StringBuf();
		b.add("/CIDInit /ProcSet findresource begin\n12 dict begin\nbegincmap\n");
		b.add("/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def\n");
		b.add("/CMapName /Adobe-Identity-UCS def\n/CMapType 2 def\n");
		b.add("1 begincodespacerange\n<0000> <FFFF>\nendcodespacerange\n");
		var i = 0;
		while (i < glyphs.length) {
			final chunk = glyphs.slice(i, i + 100);
			b.add('${chunk.length} beginbfchar\n');
			for (g in chunk) {
				b.add('<${StringTools.hex(g, 4)}> <${utf16Hex(used.get(g))}>\n');
			}
			b.add("endbfchar\n");
			i += 100;
		}
		b.add("endcmap\nCMapName currentdict /CMap defineresource pop\nend\nend\n");
		return b.toString();
	}

	static function utf16Hex(c:Int):String {
		if (c < 0x10000) {
			return StringTools.hex(c, 4);
		}
		final v = c - 0x10000;
		return StringTools.hex(0xD800 + (v >> 10), 4) + StringTools.hex(0xDC00 + (v & 0x3FF), 4);
	}
}

/** Numbered objects written in order, with the cross-reference table at the end. **/
private class Writer {
	final out = new BytesBuffer();
	final offsets:Array<Int> = [0];
	final pending = new Map<Int, String>();

	public function new() {
		raw("%PDF-1.7\n%âãÏÓ\n");
	}

	/** An object number to be written later, for objects that refer to each other. **/
	public function reserve():Int {
		offsets.push(-1);
		return offsets.length - 1;
	}

	public function set(id:Int, body:String) {
		offsets[id] = out.length;
		raw('$id 0 obj\n$body\nendobj\n');
	}

	public function add(body:String):Int {
		final id = reserve();
		set(id, body);
		return id;
	}

	public function stream(dict:String, data:Bytes, compress:Bool):Int {
		final id = reserve();
		offsets[id] = out.length;
		final body = compress ? haxe.zip.Compress.run(data, 6) : data;
		raw('$id 0 obj\n<< $dict /Length ${body.length}${compress ? " /Filter /FlateDecode" : ""} >>\nstream\n');
		out.add(body);
		raw("\nendstream\nendobj\n");
		return id;
	}

	public function finish(root:Int, info:Int):Bytes {
		final xref = out.length;
		raw('xref\n0 ${offsets.length}\n0000000000 65535 f \n');
		for (i in 1...offsets.length) {
			raw(StringTools.lpad(Std.string(offsets[i]), "0", 10) + " 00000 n \n");
		}
		raw('trailer\n<< /Size ${offsets.length} /Root $root 0 R /Info $info 0 R >>\nstartxref\n$xref\n%%EOF\n');
		return out.getBytes();
	}

	function raw(s:String) {
		for (i in 0...s.length) {
			out.addByte(StringTools.fastCodeAt(s, i) & 0xFF);
		}
	}

	/** A PDF text string, as UTF-16 with a byte order mark so any character survives. **/
	public static function text(s:String):String {
		final b = new StringBuf();
		b.add("<FEFF");
		for (c in TrueType.codePoints(s)) {
			if (c < 0x10000) {
				b.add(StringTools.hex(c, 4));
			} else {
				final v = c - 0x10000;
				b.add(StringTools.hex(0xD800 + (v >> 10), 4) + StringTools.hex(0xDC00 + (v & 0x3FF), 4));
			}
		}
		b.add(">");
		return b.toString();
	}
}
