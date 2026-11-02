package folio.formula;

import folio.formula.Formula;
import folio.formula.Value;

using folio.formula.Value.Values;

/**
	Evaluates a parsed formula.

	Comparison is by number when both sides are numbers and by text otherwise, so a
	report's "True" compares equal to the literal "True" and a flag held as text compares
	as the text it is.
**/
class Evaluator {
	public static function evaluate(e:Expr, scope:Scope):Value {
		return switch e {
			case ELiteral(v): v;
			case EName(name):
				final v = scope.lookup(name);
				if (v != null) {
					v;
				} else if (StringTools.startsWith(name, "LL.Color.")) {
					final c = Colors.named(name.substr(9));
					c == null ? VText("") : VNumber(c);
				} else {
					VText("");
				}
			case EUnary("not", a): VBool(!evaluate(a, scope).truth());
			case EUnary("-", a): VNumber(-evaluate(a, scope).number());
			case EUnary(op, _): throw new FormulaError('unknown operator $op');
			case EBinary("and", a, b): VBool(evaluate(a, scope).truth() && evaluate(b, scope).truth());
			case EBinary("or", a, b): VBool(evaluate(a, scope).truth() || evaluate(b, scope).truth());
			case EBinary(op, a, b): binary(op, evaluate(a, scope), evaluate(b, scope));
			case ECall(name, args): call(name, args, scope);
		}
	}

	static function binary(op:String, a:Value, b:Value):Value {
		final numeric = a.match(VNumber(_)) && b.match(VNumber(_));
		switch op {
			case "==" | "!=" | "<" | ">" | "<=" | ">=":
				final c = numeric ? Reflect.compare(a.number(), b.number()) : Reflect.compare(a.text(), b.text());
				return VBool(switch op {
					case "==": c == 0;
					case "!=": c != 0;
					case "<": c < 0;
					case ">": c > 0;
					case "<=": c <= 0;
					default: c >= 0;
				});
			case "+":
				return numeric ? VNumber(a.number() + b.number()) : VText(a.text() + b.text());
			case "-":
				return VNumber(a.number() - b.number());
			case "*":
				return VNumber(a.number() * b.number());
			case "/":
				return VNumber(a.number() / b.number());
			case "%":
				return VNumber(a.number() % b.number());
			default:
				throw new FormulaError('unknown operator $op');
		}
	}

	static function call(name:String, args:Array<Expr>, scope:Scope):Value {
		switch name {
			case "cond" | "if":
				// Only the branch taken is evaluated, as in the designer.
				if (args.length != 2 && args.length != 3) {
					throw new FormulaError('$name takes 2 or 3 arguments, given ${args.length}');
				}
				if (evaluate(args[0], scope).truth()) {
					return evaluate(args[1], scope);
				}
				return args.length == 3 ? evaluate(args[2], scope) : VText("");
			default:
		}
		final values = [for (a in args) evaluate(a, scope)];
		final answered = scope.call(name, values);
		if (answered != null) {
			return answered;
		}
		return Functions.call(name, values);
	}
}
