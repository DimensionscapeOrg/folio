import folio.lst.LstParser;
import utest.Assert;

class TestLst extends utest.Test {
	function testTopLevelSectionsTakeTheKeysBelowThem() {
		final root = LstParser.parse("[Description]\n Text=List & Label Project File\n[Object]\n ObjectName=Text\n");
		Assert.equals(2, root.children.length);
		Assert.equals("List & Label Project File", root.child("Description").get("Text"));
		Assert.equals("Text", root.child("Object").get("ObjectName"));
	}

	function testNestedSectionsAreBraced() {
		final root = LstParser.parse(Fixtures.text("Container.lst"));
		final container = root.childrenNamed("Object")[1];
		final tables = container.descendants("Table");
		Assert.equals(3, tables.length);
		Assert.equals("Always", tables[0].get("TableID"));
	}

	function testAKeyAfterANestedSectionBelongsToTheOuterOne() {
		final root = LstParser.parse(Fixtures.text("Container.lst"));
		final first = root.childrenNamed("Object")[1].descendants("Table")[0];
		Assert.equals("True", first.get("Condition"));
		Assert.equals('Cond(Never == "x", True, False)', first.descendants("Line")[0].get("Condition"));
	}

	function testValuesKeepEverythingAfterTheFirstEquals() {
		final root = LstParser.parse("[Object]\n Condition=a = b\n");
		Assert.equals("a = b", root.child("Object").get("Condition"));
	}

	function testTheByteOrderMarkIsNotPartOfTheFirstName() {
		final root = LstParser.parse("\u{FEFF}[List description]\n");
		Assert.equals("List description", root.children[0].name);
	}

	function testAnUnbalancedCloseIsAnError() {
		Assert.raises(() -> LstParser.parse("[Object]\n }\n"), folio.lst.LstParser.LstError);
	}
}
