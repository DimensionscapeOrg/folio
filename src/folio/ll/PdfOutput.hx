package folio.ll;

import folio.font.FontLibrary;
import folio.layout.ProjectReader;
import folio.layout.Renderer;
import folio.lst.LstParser;
import folio.pdf.PdfDocument;
import folio.text.Encoding;
import haxe.io.Bytes;

/**
	A recorded storage file drawn as a PDF: each report laid out on its own layout's
	pages, one after another, as List & Label's converter makes one PDF of a storage file
	that several reports were appended to.
**/
class PdfOutput {
	static var fonts:FontLibrary;

	public static function convert(storage:String):Bytes {
		if (fonts == null) {
			fonts = new FontLibrary();
		}
		final doc = new PdfDocument();
		final renderer = new Renderer(fonts);
		final records:Array<Dynamic> = haxe.Json.parse(storage).reports;
		for (r in records) {
			final layout = Files.localPath(r.path);
			final project = ProjectReader.read(LstParser.parse(Encoding.decode(sys.io.File.getBytes(layout))), haxe.io.Path.directory(layout));
			renderer.render(doc, project, {
				variables: named(r.variables),
				tables: [for (t in (r.tables : Array<Dynamic>)) {id: t.id, rows: [for (row in (t.rows : Array<Dynamic>)) named(row)]}]
			});
			Trace.log("drawn:", '${r.layout} as ${doc.pages.length} page(s) so far', 0);
		}
		if (fonts.missing.length > 0) {
			Trace.log("fonts not installed, drawn in a fallback:", fonts.missing.join(", "), 0);
		}
		return doc.toBytes();
	}

	static function named(o:Dynamic):Named {
		final n = new Named();
		for (k in Reflect.fields(o)) {
			n.set(k, Std.string(Reflect.field(o, k)));
		}
		return n;
	}
}
