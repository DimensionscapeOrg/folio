package folio.ll;

import folio.formula.Formula.Scope;
import folio.formula.Value;

/**
	Names and their values, in the order the names were first defined. List & Label keeps
	one value per name, so defining a name again replaces its value where it stands.
**/
class Named implements Scope {
	public final names:Array<String> = [];

	final values = new Map<String, String>();

	public function new() {}

	public function set(name:String, value:String) {
		if (!values.exists(name)) {
			names.push(name);
		}
		values.set(name, value);
	}

	public function get(name:String):Null<String> {
		return values.get(name);
	}

	public function clear() {
		names.resize(0);
		values.clear();
		lower = null;
	}

	public function copy():Named {
		final c = new Named();
		for (n in names) {
			c.set(n, values.get(n));
		}
		return c;
	}

	/** A formula's name, matched as the designer matches it: without regard to case. **/
	public function lookup(name:String):Null<Value> {
		var v = values.get(name);
		if (v == null) {
			if (lower == null || lowerCount != names.length) {
				lower = new Map();
				for (n in names) {
					lower.set(n.toLowerCase(), n);
				}
				lowerCount = names.length;
			}
			final actual = lower.get(name.toLowerCase());
			v = actual == null ? null : values.get(actual);
		}
		return v == null ? null : VText(v);
	}

	var lower:Null<Map<String, String>> = null;
	var lowerCount = -1;

	public function call(name:String, args:Array<Value>):Null<Value> {
		return null;
	}
}
