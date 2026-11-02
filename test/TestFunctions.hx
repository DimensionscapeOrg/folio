import folio.formula.Colors;
import folio.formula.Functions;
import folio.layout.ProjectReader;
import utest.Assert;

class TestFunctions extends utest.Test {
	function testFStrFillsTheFormatFromTheRight() {
		Assert.equals("  2", Functions.fstr(2, "###", 0));
		Assert.equals("2", Functions.fstr(2, "###", 1));
		Assert.equals("002", Functions.fstr(2, "&&&", 0));
		Assert.equals("1,234.50", Functions.fstr(1234.5, "#,###.##", 1));
		Assert.equals(" -5", Functions.fstr(-5, "###", 0));
	}

	function testFStrKeepsDigitsTheFormatHasNoRoomFor() {
		Assert.equals("12345", Functions.fstr(12345, "###", 1));
	}

	function testFixedRoundsHalfAwayFromZero() {
		Assert.equals("2.5", Functions.fixed(2.45, 1));
		Assert.equals("-3", Functions.fixed(-2.5, 0));
		Assert.equals("10.00", Functions.fixed(9.999, 2));
	}

	function testColoursAreColorrefs() {
		Assert.equals(0xE16941, Colors.named("RoyalBlue"));
		Assert.equals(0x4169E1, Colors.toRgb(Colors.named("royalblue")));
		Assert.equals(Colors.colorref(173, 215, 227), Colors.parse("(173,215,227)"));
	}

	function testADesignerAnnotationIsNotPartOfTheFormula() {
		Assert.equals('"Text"', ProjectReader.formula('"Text"¤  ¤'));
		Assert.equals('"a¤b"', ProjectReader.formula('"a¤b"'));
	}

	function testTheLayoutsDefaultFont() {
		final f = ProjectReader.defFont("{(0,0,0),9.000000,-12,0,0,0,400,0,0,0,0,3,2,1,34,Trebuchet MS}");
		Assert.equals('"Trebuchet MS"', f.face);
		Assert.equals("9.000000", f.size);
		Assert.equals("False", f.bold);
	}
}
