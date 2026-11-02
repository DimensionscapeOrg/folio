package folio.pdf;

import folio.font.TrueType;
import folio.image.Picture;
import folio.pdf.PdfDocument.PdfImage;
import haxe.io.Bytes;

/**
	One page's drawing. Positions are points from the top left; colours are 0xRRGGBB.
**/
class PdfPage {
	public final width:Float;
	public final height:Float;

	@:allow(folio.pdf.PdfDocument)
	final content = new StringBuf();
	@:allow(folio.pdf.PdfDocument)
	final images:Array<PdfImage> = [];
	@:allow(folio.pdf.PdfDocument)
	final shadings:Array<String> = [];

	final doc:PdfDocument;

	@:allow(folio.pdf.PdfDocument)
	function new(doc:PdfDocument, width:Float, height:Float) {
		this.doc = doc;
		this.width = width;
		this.height = height;
	}

	/** The page's drawing so far, as PDF operators in PDF's own bottom-up coordinates. **/
	public function operators():String {
		return content.toString();
	}

	/** Text on a baseline starting at x. **/
	public function text(font:TrueType, size:Float, color:Int, x:Float, baseline:Float, s:String) {
		if (s.length == 0) {
			return;
		}
		final f = doc.fontFor(font);
		content.add('BT ${rgb(color)} rg /${f.name} ${n(size)} Tf ${n(x)} ${n(height - baseline)} Td <${f.encode(s)}> Tj ET\n');
	}

	/** Text turned a quarter left, read from the bottom up; `x` is the baseline. **/
	public function textUp(font:TrueType, size:Float, color:Int, x:Float, start:Float, s:String) {
		if (s.length == 0) {
			return;
		}
		final f = doc.fontFor(font);
		content.add('BT ${rgb(color)} rg /${f.name} ${n(size)} Tf 0 1 -1 0 ${n(x)} ${n(height - start)} Tm <${f.encode(s)}> Tj ET\n');
	}

	public function fillRect(x:Float, y:Float, w:Float, h:Float, color:Int) {
		content.add('${rgb(color)} rg ${n(x)} ${n(height - y - h)} ${n(w)} ${n(h)} re f\n');
	}

	/** A rectangle's outline. Width 0 is the thinnest line the device can draw. **/
	public function strokeRect(x:Float, y:Float, w:Float, h:Float, lineWidth:Float, color:Int) {
		content.add('${rgb(color)} RG ${n(lineWidth)} w ${n(x)} ${n(height - y - h)} ${n(w)} ${n(h)} re S\n');
	}

	/**
		A rectangle filled with colours blended along it, left to right or top to bottom.
		Each stop is a position from 0 to 1 and the colour there.
	**/
	public function gradient(x:Float, y:Float, w:Float, h:Float, vertical:Bool, stops:Array<{at:Float, color:Int}>) {
		function c(v:Int):String {
			return '[${rgb(v)}]';
		}
		final parts = [for (i in 1...stops.length) '<< /FunctionType 2 /Domain [0 1] /C0 ${c(stops[i - 1].color)} /C1 ${c(stops[i].color)} /N 1 >>'];
		final bounds = [for (i in 1...stops.length - 1) n(stops[i].at)].join(" ");
		final encode = [for (_ in 1...stops.length) "0 1"].join(" ");
		final fn = '<< /FunctionType 3 /Domain [${n(stops[0].at)} ${n(stops[stops.length - 1].at)}] /Functions [${parts.join(" ")}] /Bounds [$bounds] /Encode [$encode] >>';
		final bottom = height - y - h;
		final coords = vertical ? '0 ${n(height - y)} 0 ${n(bottom)}' : '${n(x)} 0 ${n(x + w)} 0';
		shadings.push('<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [$coords] /Function $fn /Extend [true true] >>');
		content.add('q ${n(x)} ${n(bottom)} ${n(w)} ${n(h)} re W n /Sh${shadings.length} sh Q\n');
	}

	public function line(x1:Float, y1:Float, x2:Float, y2:Float, lineWidth:Float, color:Int) {
		content.add('${rgb(color)} RG ${n(lineWidth)} w ${n(x1)} ${n(height - y1)} m ${n(x2)} ${n(height - y2)} l S\n');
	}

	/** An image stretched over a rectangle. `pixels` are 8-bit RGB rows, top row first. **/
	public function image(x:Float, y:Float, w:Float, h:Float, pixelWidth:Int, pixelHeight:Int, pixels:Bytes) {
		picture(x, y, w, h, Picture.decoded(pixelWidth, pixelHeight, 3, pixels, null));
	}

	/**
		A picture stretched over a rectangle. A picture drawn on several pages is stored in
		the document once.
	**/
	public function picture(x:Float, y:Float, w:Float, h:Float, pic:Picture) {
		final image = doc.imageFor(pic);
		var index = images.indexOf(image);
		if (index < 0) {
			images.push(image);
			index = images.length - 1;
		}
		content.add('q ${n(w)} 0 0 ${n(h)} ${n(x)} ${n(height - y - h)} cm /Im${index + 1} Do Q\n');
	}

	/** Draws only inside a rectangle until `unclip`. **/
	public function clip(x:Float, y:Float, w:Float, h:Float) {
		content.add('q ${n(x)} ${n(height - y - h)} ${n(w)} ${n(h)} re W n\n');
	}

	public function unclip() {
		content.add('Q\n');
	}

	static inline function n(v:Float):String {
		return PdfDocument.num(v);
	}

	static function rgb(c:Int):String {
		return '${n(((c >> 16) & 0xFF) / 255)} ${n(((c >> 8) & 0xFF) / 255)} ${n((c & 0xFF) / 255)}';
	}
}
