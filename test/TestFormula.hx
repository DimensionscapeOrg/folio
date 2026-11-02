import folio.formula.Formula;
import folio.formula.Value;
import folio.ll.Named;
import utest.Assert;

class TestFormula extends utest.Test {
	function value(source:String, ?vars:Map<String, String>):Value {
		final scope = new Named();
		if (vars != null) {
			for (k => v in vars) {
				scope.set(k, v);
			}
		}
		return Formula.parse(source).evaluate(scope);
	}

	function truth(source:String, ?vars:Map<String, String>):Bool {
		return Values.truth(value(source, vars));
	}

	function testTheShippedTableConditions() {
		Assert.isTrue(truth('Cond(ListType == "TypeA", True, False)', ["ListType" => "TypeA"]));
		Assert.isFalse(truth('Cond(ListType == "TypeA", True, False)', ["ListType" => "TypeB"]));
		Assert.isTrue(truth('Cond(Code = "ES2", true, Cond(Pass == "True", true, false))', ["Code" => "X", "Pass" => "True"]));
		Assert.isFalse(truth('Cond(Code = "ES2", true, Cond(Pass == "True", true, false))', ["Code" => "X", "Pass" => "False"]));
		Assert.isTrue(truth("Cond(ShowEUCost, true, false)", ["ShowEUCost" => "true"]));
		Assert.isFalse(truth("Cond(ShowEUCost, true, false)", ["ShowEUCost" => "false"]));
	}

	/** A label places its score box at `.210 + (130 - ScorePosition)*(4.140/130)` inches. **/
	function testANumberMayStartAtItsPoint() {
		Assert.floatEquals(0.624, Values.number(value(".210 + (130 - ScorePosition)*(4.140/130)", ["ScorePosition" => "117"])), 1e-9);
	}

	function testFlagsHeldAsTextReadTrueOrOne() {
		Assert.isTrue(truth("Flag", ["Flag" => "TRUE"]));
		Assert.isTrue(truth("Flag", ["Flag" => "1"]));
		Assert.isFalse(truth("Flag", ["Flag" => "yes"]));
		Assert.isFalse(truth("Missing"));
	}

	function testNamesMayContainDots() {
		Assert.equals("12", Values.text(value("Item.Cost", ["Item.Cost" => "12"])));
	}

	function testComparisonIsByNumberOnlyWhenBothSidesAreNumbers() {
		Assert.isTrue(truth("2 < 10"));
		Assert.isFalse(truth('"2" < "10"'));
	}

	function testOperatorsAndPrecedence() {
		Assert.equals(7.0, Values.number(value("1 + 2 * 3")));
		Assert.equals(9.0, Values.number(value("(1 + 2) * 3")));
		Assert.isTrue(truth("not False and (True or False)"));
		Assert.isTrue(truth("1 <> 2"));
		Assert.equals("ab", Values.text(value('"a" + "b"')));
	}

	function testOnlyTheBranchTakenIsEvaluated() {
		Assert.isTrue(truth("Cond(True, True, Unknown(1))"));
	}

	function testUnreadableTextIsAnError() {
		Assert.raises(() -> Formula.parse("Cond(a, b"), FormulaError);
		Assert.raises(() -> value("Unknown(1)"), FormulaError);
	}
}
