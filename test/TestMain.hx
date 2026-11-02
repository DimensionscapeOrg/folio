class TestMain {
	static function main() {
		utest.UTest.run([new TestLst(), new TestFormula(), new TestEncoding(), new TestFunctions(), new TestListLabel(), new TestChart(), new TestPictures(), new TestDrawing(), new TestColumns(), new TestTableObjects()]);
	}
}
