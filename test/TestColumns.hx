import folio.font.FontLibrary;
import folio.layout.Renderer;
import folio.layout.ProjectReader;
import folio.ll.Named;
import folio.lst.LstParser;
import folio.pdf.PdfDocument;
import utest.Assert;

/**
	Columns.lst laid out: list tables in three columns of a container an inch from the top
	left of the page, six inches wide and two tall. Every row is one framed cell 18 pt tall,
	an inch wide but for Tail's, so each check names the frame a row draws, in PDF's coordinates, which
	run up from the foot of the 792 pt page.
**/
class TestColumns extends utest.Test {
	var doc:PdfDocument;

	function setup() {
		function rows(labels:Array<String>):Array<Named> {
			return [
				for (label in labels) {
					final n = new Named();
					n.set("Label", label);
					n;
				}
			];
		}
		final project = ProjectReader.read(LstParser.parse(Fixtures.text("Columns.lst")), "test/fixtures");
		doc = new PdfDocument();
		new Renderer(new FontLibrary()).render(doc, project, {
			variables: new Named(),
			tables: [
				{id: "Head", rows: rows(["H"])},
				{id: "A", rows: rows(["A1", "A2", "A3"])},
				{id: "B", rows: rows(["B1", "B2", "B3", "B4"])},
				{id: "C", rows: rows(["C1"])},
				{id: "Empty", rows: rows(["", ""])},
				{id: "Tail", rows: rows(["T"])},
				{id: "D", rows: rows(["D1", "D2", "D3", "D4", "D5"])},
				{id: "E", rows: rows(["E1"])}
			]
		});
	}

	function row(page:Int, x:Float, y:Float, ?pos:haxe.PosInfos) {
		final frame = '0 0 0 RG 0 w $x $y 72 18 re S';
		Assert.isTrue(doc.pages[page].operators().indexOf(frame) >= 0, 'page ${page + 1} has "$frame"', pos);
	}

	function testTheFirstColumnTakesItsTablesSpaceAbove() {
		row(0, 72, 702);
		// 18 pt of Head, then 7.2 pt above A.
		row(0, 72, 676.8);
		row(0, 72, 658.8);
		row(0, 72, 640.8);
	}

	function testATableBreaksToTheTopOfTheNextColumn() {
		// Level with where A began, without the space above it.
		row(0, 216, 684);
		row(0, 216, 630);
		row(0, 360, 684);
	}

	function testATableWhoseRowsPrintNothingLeavesNoTrace() {
		for (page in doc.pages) {
			Assert.equals(-1, page.operators().indexOf("144 18 re S"));
		}
	}

	function testTheNextTableStartsBelowTheDeepestColumn() {
		// B's four rows reach 90 pt down the container, below A's three; Tail's cell is 108 pt wide.
		Assert.isTrue(doc.pages[0].operators().indexOf("0 0 0 RG 0 w 72 612 108 18 re S") >= 0);
	}

	function testRowsRunOnIntoTheNextColumn() {
		row(0, 72, 594);
		row(0, 72, 576);
		row(0, 216, 594);
		row(0, 216, 576);
		row(0, 360, 594);
	}

	function testABreakPastTheLastColumnStartsANewPage() {
		Assert.equals(2, doc.pages.length);
		row(1, 72, 702);
	}
}
