package folio.formula;

/**
	A List & Label formula, parsed once and evaluated against a report's values.

	The grammar is the designer's:

	```
	Cond(ListType == "TypeA", True, False)
	Cond(Code = "ES2", true, Cond(Pass == "True", true, false))
	Val(Item.Cost) > 0 and not Empty(Notes)
	```

	Names are the report's variables and fields, and may contain dots. Function names and
	the words True, False, and, or, not are matched without regard to case, as the
	designer matches them.
**/
class Formula {
	public final source:String;

	final expr:Expr;

	function new(source:String, expr:Expr) {
		this.source = source;
		this.expr = expr;
	}

	/** Parses a formula. Throws `FormulaError` on text it cannot read. **/
	public static function parse(source:String):Formula {
		return new Formula(source, new Parser(source).parseAll());
	}

	public function evaluate(scope:Scope):Value {
		return Evaluator.evaluate(expr, scope);
	}
}

/**
	Where a formula's names get their values, and the functions only the caller can answer,
	such as `Page()` while a page is being laid out. Either returns null for what it does
	not have: a name is then empty, and a function falls to the built-in ones.
**/
interface Scope {
	function lookup(name:String):Null<Value>;
	function call(name:String, args:Array<Value>):Null<Value>;
}

enum Expr {
	ELiteral(v:Value);
	EName(name:String);
	ECall(name:String, args:Array<Expr>);
	EUnary(op:String, e:Expr);
	EBinary(op:String, a:Expr, b:Expr);
}

class FormulaError extends haxe.Exception {}

private enum Token {
	TNumber(v:Float);
	TString(v:String);
	TName(v:String);
	TSymbol(v:String);
	TEnd;
}

private class Parser {
	final s:String;
	var at = 0;
	var token:Token;

	public function new(source:String) {
		s = source;
		token = next();
	}

	public function parseAll():Expr {
		final e = parseOr();
		if (!token.match(TEnd)) {
			fail("unexpected text");
		}
		return e;
	}

	function fail(why:String):Dynamic {
		throw new FormulaError('$why at ${at} in: $s');
	}

	function advance() {
		token = next();
	}

	function isSymbol(v:String):Bool {
		return switch token {
			case TSymbol(x): x == v;
			default: false;
		}
	}

	function isWord(v:String):Bool {
		return switch token {
			case TName(x): x.toLowerCase() == v;
			default: false;
		}
	}

	function expect(v:String) {
		if (!isSymbol(v)) {
			fail('expected "$v"');
		}
		advance();
	}

	function parseOr():Expr {
		var e = parseAnd();
		while (isWord("or") || isSymbol("||")) {
			advance();
			e = EBinary("or", e, parseAnd());
		}
		return e;
	}

	function parseAnd():Expr {
		var e = parseNot();
		while (isWord("and") || isSymbol("&&")) {
			advance();
			e = EBinary("and", e, parseNot());
		}
		return e;
	}

	function parseNot():Expr {
		if (isWord("not") || isSymbol("!")) {
			advance();
			return EUnary("not", parseNot());
		}
		return parseCompare();
	}

	function parseCompare():Expr {
		final e = parseAdd();
		for (op in ["==", "=", "!=", "<>", "<=", ">=", "<", ">"]) {
			if (isSymbol(op)) {
				advance();
				final normal = switch op {
					case "=": "==";
					case "<>": "!=";
					default: op;
				}
				return EBinary(normal, e, parseAdd());
			}
		}
		return e;
	}

	function parseAdd():Expr {
		var e = parseMul();
		while (isSymbol("+") || isSymbol("-")) {
			final op = isSymbol("+") ? "+" : "-";
			advance();
			e = EBinary(op, e, parseMul());
		}
		return e;
	}

	function parseMul():Expr {
		var e = parseUnary();
		while (isSymbol("*") || isSymbol("/") || isSymbol("%")) {
			final op = switch token {
				case TSymbol(x): x;
				default: "";
			}
			advance();
			e = EBinary(op, e, parseUnary());
		}
		return e;
	}

	function parseUnary():Expr {
		if (isSymbol("-")) {
			advance();
			return EUnary("-", parseUnary());
		}
		return parsePrimary();
	}

	function parsePrimary():Expr {
		switch token {
			case TNumber(v):
				advance();
				return ELiteral(VNumber(v));
			case TString(v):
				advance();
				return ELiteral(VText(v));
			case TSymbol("("):
				advance();
				final e = parseOr();
				expect(")");
				return e;
			case TName(name):
				advance();
				if (isSymbol("(")) {
					advance();
					final args = [];
					if (!isSymbol(")")) {
						args.push(parseOr());
						while (isSymbol(",")) {
							advance();
							args.push(parseOr());
						}
					}
					expect(")");
					return ECall(name.toLowerCase(), args);
				}
				return switch name.toLowerCase() {
					case "true": ELiteral(VBool(true));
					case "false": ELiteral(VBool(false));
					default: EName(name);
				}
			default:
				return fail("expected a value");
		}
	}

	function next():Token {
		while (at < s.length && StringTools.isSpace(s, at)) {
			at++;
		}
		if (at >= s.length) {
			return TEnd;
		}
		final c = s.charAt(at);
		if (c == '"' || c == "'") {
			final end = s.indexOf(c, at + 1);
			if (end < 0) {
				fail("unterminated text");
			}
			final v = s.substring(at + 1, end);
			at = end + 1;
			return TString(v);
		}
		// A number may start at its decimal point, as in `.210`.
		if (isDigit(c) || (c == "." && at + 1 < s.length && isDigit(s.charAt(at + 1)))) {
			final start = at;
			while (at < s.length && (isDigit(s.charAt(at)) || s.charAt(at) == ".")) {
				at++;
			}
			return TNumber(Std.parseFloat(s.substring(start, at)));
		}
		if (isNameStart(c)) {
			final start = at;
			while (at < s.length && (isNameStart(s.charAt(at)) || isDigit(s.charAt(at)) || s.charAt(at) == ".")) {
				at++;
			}
			return TName(s.substring(start, at));
		}
		for (sym in ["==", "!=", "<>", "<=", ">=", "&&", "||"]) {
			if (s.substr(at, 2) == sym) {
				at += 2;
				return TSymbol(sym);
			}
		}
		if ("()=<>+-*/%,!".indexOf(c) >= 0) {
			at++;
			return TSymbol(c);
		}
		return fail('unexpected "$c"');
	}

	static inline function isDigit(c:String):Bool {
		return c >= "0" && c <= "9";
	}

	static inline function isNameStart(c:String):Bool {
		return (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || c == "_" || c == "@" || c == "$";
	}
}
