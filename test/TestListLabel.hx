import folio.ll.Constants.*;
import folio.ll.ListLabel;
import utest.Assert;

/** The List & Label protocol a list report drives, end to end, against a fixture layout. **/
class TestListLabel extends utest.Test {
	var dir:String;

	function setup() {
		dir = Fixtures.scratch();
		sys.io.File.copy(Fixtures.path("Container.lst"), '$dir/Container.lst');
	}

	function run(listType:String):String {
		final job = ListLabel.jobOpen(1);
		Assert.equals(1, ListLabel.getOption(job, LL_OPTION_DEFPRINTERINSTALLED));
		ListLabel.defineVariableStart(job);
		ListLabel.defineVariable(job, "ListType", listType);
		ListLabel.printSetOptionString(job, LL_PRNOPTSTR_PRINTJOBNAME, "Job");
		Assert.equals(0, ListLabel.printStart(job, '$dir/Container.lst'));

		final seen = [];
		var answer = LL_WRN_TABLECHANGE;
		while (answer == LL_WRN_TABLECHANGE) {
			final table = ListLabel.currentTable(job);
			seen.push(table);
			for (i in 0...2) {
				ListLabel.defineField(job, '$table.Row', Std.string(i));
				ListLabel.printFields(job);
			}
			answer = ListLabel.printFieldsEnd(job);
		}
		Assert.equals(0, answer);
		Assert.equals(0, ListLabel.printEnd(job));
		ListLabel.jobClose(job);
		return seen.join(",");
	}

	function testTablesComeInTheContainersOrder() {
		Assert.equals("Always,TypeAOnly,Last", run("TypeA"));
	}

	function testATableWhoseConditionIsFalseIsNeverOffered() {
		Assert.equals("Always,Last", run("TypeB"));
	}

	function testTheRecordHoldsEachTablesOwnFields() {
		run("TypeB");
		final doc = sys.io.File.getContent('$dir/Container.ll');
		Assert.equals('{"reports":[{"layout":"Container.lst","path":"$dir/Container.lst","jobName":"Job","variables":{"ListType":"TypeB"},"tables":['
			+ '{"id":"Always","rows":[{"Always.Row":"0"},{"Always.Row":"1"}]},'
			+ '{"id":"Last","rows":[{"Last.Row":"0"},{"Last.Row":"1"}]}]}]}', doc);
	}

	function testAMissingLayoutIsRefused() {
		final job = ListLabel.jobOpen(1);
		Assert.equals(LL_ERR_CFGNOTFOUND, ListLabel.printStart(job, '$dir/Missing.lst'));
		ListLabel.jobClose(job);
	}

	function testAppendingStorageAppendsItsReports() {
		run("TypeB");
		sys.io.File.copy('$dir/Container.ll', '$dir/Second.ll');
		final a = ListLabel.storageOpen('$dir/Container.ll');
		final b = ListLabel.storageOpen('$dir/Second.ll');
		Assert.equals(0, ListLabel.storageAppend(a, b));
		ListLabel.storageClose(b);
		ListLabel.storageClose(a);
		final doc = haxe.Json.parse(sys.io.File.getContent('$dir/Container.ll'));
		Assert.equals(2, doc.reports.length);
	}

	function testABadHandleIsRefused() {
		Assert.equals(LL_ERR_BAD_JOBHANDLE, ListLabel.printFields(-5));
		Assert.equals("", ListLabel.currentTable(-5));
	}
}
