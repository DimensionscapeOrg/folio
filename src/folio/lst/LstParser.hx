package folio.lst;

/**
	Reads a List & Label project file (`.lst`, `.lbl`) into sections.

	The result is a nameless root whose children are the file's top-level sections, in
	order. Keys keep their spelling and their values are the rest of the line, so a
	formula reads exactly as the designer wrote it.
**/
class LstParser {
	public static function parse(text:String):LstSection {
		final root = new LstSection("");
		final stack = [root];
		var pending:Null<LstSection> = null;

		if (StringTools.startsWith(text, "\u{FEFF}")) {
			text = text.substr(1);
		}
		for (raw in text.split("\n")) {
			final line = StringTools.rtrim(raw);
			final t = StringTools.ltrim(line);
			if (t.length == 0) {
				continue;
			}
			final atMargin = line.length == t.length;
			if (atMargin && isHeader(t)) {
				// A top-level section closes whatever was open.
				final s = new LstSection(t.substring(1, t.length - 1));
				root.children.push(s);
				stack.resize(1);
				stack.push(s);
				pending = null;
			} else if (isHeader(t)) {
				final s = new LstSection(t.substring(1, t.length - 1));
				stack[stack.length - 1].children.push(s);
				pending = s;
			} else if (t == "{") {
				if (pending == null) {
					throw new LstError('"{" with no section before it');
				}
				stack.push(pending);
				pending = null;
			} else if (t == "}") {
				if (stack.length <= 2) {
					throw new LstError('"}" closes nothing');
				}
				stack.pop();
			} else {
				final eq = t.indexOf("=");
				if (eq > 0) {
					stack[stack.length - 1].keys.push({key: t.substr(0, eq), value: t.substr(eq + 1)});
				}
			}
		}
		return root;
	}

	static inline function isHeader(t:String):Bool {
		return StringTools.startsWith(t, "[") && StringTools.endsWith(t, "]");
	}
}

class LstError extends haxe.Exception {}
