import folio.font.FontLibrary;
import folio.pdf.PdfDocument;

/** Writes bin/smoke.pdf: two fonts, a fill, a line. Checked by eye and by a PDF reader. **/
class PdfSmoke {
	static function main() {
		final t0 = haxe.Timer.stamp();
		final fonts = new FontLibrary();
		final t1 = haxe.Timer.stamp();
		final regular = fonts.find("Trebuchet MS", false, false);
		final bold = fonts.find("Trebuchet MS", true, false);
		final doc = new PdfDocument();
		final page = doc.addPage(612, 792);
		page.text(bold, 26, 0x4169E1, 36, 61.332, "Action Report");
		page.fillRect(146, 370, 430, 14, 0xD3D3D3);
		page.text(regular, 9, 0, 36, 99.081, "I.M. Smith © 1985-2026 € café");
		page.line(36, 120, 576, 120, 0.5, 0xFF0000);
		sys.io.File.saveBytes("bin/smoke.pdf", doc.toBytes());
		Sys.println('font scan ${Math.round((t1 - t0) * 1000)} ms, total ${Math.round((haxe.Timer.stamp() - t0) * 1000)} ms, missing ${fonts.missing}');
	}
}
