import folio.font.FontLibrary;
import folio.layout.Renderer;
import folio.layout.ProjectReader;
import folio.ll.Named;
import folio.lst.LstParser;
import folio.pdf.PdfDocument;
import utest.Assert;

/**
	Drawing.lst laid out and drawn: lines, rectangles, pictures, frames and the positions
	and sizes a layout gives as formulas. Each check names the PDF operators a page holds,
	in PDF's coordinates, which run up from the foot of the 792 pt page.
**/
class TestDrawing extends utest.Test {
	var doc:PdfDocument;

	function setup() {
		final picture = sys.FileSystem.absolutePath(Fixtures.path("pictures/rgba.png"));
		final variables = new Named();
		variables.set("Logo", picture);
		function row(label:String, sig:String):Named {
			final n = new Named();
			n.set("Rows.Label", label);
			n.set("Rows.Sig", sig);
			return n;
		}
		final project = ProjectReader.read(LstParser.parse(Fixtures.text("Drawing.lst")), "test/fixtures");
		doc = new PdfDocument();
		new Renderer(new FontLibrary()).render(doc, project, {
			variables: variables,
			tables: [{id: "Rows", rows: [row("One", ""), row("Two", picture), row("Three", "")]}]
		});
	}

	function has(page:Int, operators:String, ?pos:haxe.PosInfos) {
		Assert.isTrue(doc.pages[page].operators().indexOf(operators) >= 0, 'page ${page + 1} has "$operators"', pos);
	}

	function testOrientationDecidesWhicheverWayThePaperIsWritten() {
		Assert.equals(612.0, doc.pages[0].width);
		Assert.equals(792.0, doc.pages[0].height);
	}

	function testALineRunsThroughTheMiddleOfItsRectangle() {
		has(0, "0 0 0 RG 0.72 w 72 716.4 m 216 716.4 l S");
		has(0, "0 0 1 RG 0 w 75.6 648 m 75.6 576 l S");
	}

	function testARectangleIsFilledAndOutlined() {
		has(0, "1 0 0 rg 72 432 144 72 re f");
		has(0, "0 0 0 RG 0.36 w 72 432 144 72 re S");
	}

	function testAPictureIsFittedInProportion() {
		// Carried in the layout: as large as fits, and centred.
		has(0, "q 72 0 0 72 396 648 cm /Im1 Do Q");
		// Named by a variable, aligned 6: at the left.
		has(0, "q 72 0 0 72 360 504 cm /Im2 Do Q");
		// A file beside the layout, not kept in proportion: stretched.
		has(0, "q 72 0 0 36 360 396 cm /Im3 Do Q");
	}

	function testAPictureIsPlacedAsItsAlignmentSays() {
		// 40 x 10 fitted to an inch square is 72 x 18; alignment 3 puts it at the left foot.
		has(0, "q 72 0 0 18 468 648 cm");
	}

	function testAlignmentOneTilesThePictureInsideItsRectangle() {
		has(0, "q 468 540 72 72 re W n");
		for (y in [594, 576, 558, 540]) {
			has(0, 'q 72 0 0 18 468 $y cm');
		}
		Assert.equals(-1, doc.pages[0].operators().indexOf("q 72 0 0 18 468 522 cm"));
	}

	function testAPictureAtItsOwnSizeTakesItsFilesResolution() {
		// 40 x 10 pixels at 72 an inch, centred in its inch square.
		has(0, "q 40 0 0 10 484 463 cm");
	}

	function testAPositionMayBeAFormulaInInches() {
		// Left 1 + UnitFromSCM(25400) is two inches; top is 7 inches on page 1 and 8 after.
		has(0, "144 278.28 Td");
		has(1, "144 206.28 Td");
	}

	function testUnderlineIsTheFontsOwn() {
		has(0, "0.62 w 144 277.006 m");
	}

	function testAFramedTextObjectIsFramedRoundItsLines() {
		has(0, "0 0 0 RG 0 w 144 276.058 144 11.942 re S");
	}

	function testATextObjectsFirstLinePrintsEvenIfItOverruns() {
		has(0, "72 278.28 Td");
		Assert.equals(-1, doc.pages[0].operators().indexOf("72 265.729 Td"));
	}

	function testALinePrintsWhileItsBaselineIsInsideTheObject() {
		// A 22.5 pt object: B's baseline is 22.27 pt down, inside it; C's, 34.82 pt down, is not.
		has(0, "432 278.28 Td");
		has(0, "432 265.729 Td");
		Assert.equals(-1, doc.pages[0].operators().indexOf("432 253.177 Td"));
	}

	function testAContainerPlacedByFormulaStandsWhereEachPageSays() {
		Assert.equals(2, doc.pages.length);
		// Page 1 from 8 inches down; the third row goes over to page 2, from 1 inch down.
		has(0, "0 0 0 RG 0 w 216 180 72 36 re S");
		has(1, "0 0 0 RG 0 w 216 684 72 36 re S");
	}

	function testAPictureCellIsAsTallAsItsPicturesSpace() {
		// Empty for row One, which is still 36 pt tall; row Two's picture is fitted in it.
		has(0, "q 36 0 0 36 234 122.4 cm");
	}

	function testTextBesideATallerCellGoesWhereItsAlignmentSays() {
		// Centred in the 36 pt row: (36 - 12.5514) / 2 below the top.
		has(0, "72 194.736 Td");
	}

	function testAFrameSideMayDependOnTheRow() {
		has(0, "0 0.502 0 RG 0 w 72 122.4 m 216 122.4 l S");
		Assert.equals(-1, doc.pages[0].operators().indexOf("0 0.502 0 RG 0 w 72 180 m"));
	}

	function testACellsWidthAndFixedHeightMayBeItsOwn() {
		has(0, "0 0 0 RG 0 w 72 158.4 72 21.6 re S");
		has(0, "0 0 0 RG 0 w 72 100.8 36 21.6 re S");
	}
}
