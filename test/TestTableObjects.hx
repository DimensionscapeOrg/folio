import folio.font.FontLibrary;
import folio.layout.Renderer;
import folio.layout.ProjectReader;
import folio.ll.Named;
import folio.lst.LstParser;
import folio.pdf.PdfDocument;
import utest.Assert;

/**
	TableObjects.lst laid out: two table objects an inch from the left, fed the same rows.
	Head's header is a framed cell two inches wide over a body line of no cells, an inch
	down; Rows' header is a framed cell an inch and a half wide over one framed cell an
	inch wide, four inches down. Cells are 18 pt tall, and each check names a frame in
	PDF's coordinates, which run up from the foot of the 792 pt page.
**/
class TestTableObjects extends utest.Test {
	static function render(labels:Array<String>):String {
		final rows = [
			for (label in labels) {
				final n = new Named();
				n.set("Label", label);
				n;
			}
		];
		final project = ProjectReader.read(LstParser.parse(Fixtures.text("TableObjects.lst")), "test/fixtures");
		final doc = new PdfDocument();
		new Renderer(new FontLibrary()).render(doc, project, {variables: new Named(), tables: [{id: "", rows: rows}]});
		return doc.pages[0].operators();
	}

	function testOnceARowPrintsEveryTableObjectHasBegun() {
		final page = render(["", "x"]);
		// Head prints no line of its own, but its header prints with Rows'.
		Assert.isTrue(page.indexOf("0 0 0 RG 0 w 72 702 144 18 re S") >= 0);
		Assert.isTrue(page.indexOf("0 0 0 RG 0 w 72 486 108 18 re S") >= 0);
		// The empty row prints nothing; x follows the header.
		Assert.isTrue(page.indexOf("0 0 0 RG 0 w 72 468 72 18 re S") >= 0);
	}

	function testTableObjectsWhoseRowsPrintNothingAreLeftOut() {
		final page = render(["", ""]);
		Assert.equals(-1, page.indexOf("re S"));
	}
}
