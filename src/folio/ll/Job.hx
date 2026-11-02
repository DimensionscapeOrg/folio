package folio.ll;

import folio.formula.Formula;
import folio.formula.Value.Values;
import folio.lst.LstParser;
import folio.lst.LstSection;
import folio.text.Encoding;
import folio.ll.Constants.*;

/**
	One List & Label job: the values a program defines, and the layout it prints them with.

	THE PROTOCOL. A list report does not choose its tables. It asks which table comes
	next (`currentTable`), fills that table's rows (`defineField`, `printFields`), closes
	it (`printFieldsEnd`), and keeps going while the answer is `LL_WRN_TABLECHANGE`. The
	answer comes from the layout's report container: its tables in order, each printed
	only when its condition holds.

	THIS STAGE RECORDS. Each report is kept as the values it was handed, in the shape the
	layout would draw them: the variables, and each table's rows. `printFields` never says
	the page is full (`LL_WRN_REPEAT_DATA`), so every row arrives exactly once.
**/
class Job {
	public final variables = new Named();
	public final fields = new Named();
	public final tables:Array<RecordedTable> = [];
	public var layoutPath(default, null):Null<String>;
	public var storagePath(default, null):Null<String>;
	public var jobName:String = "";
	public var printing(default, null) = false;

	var sequence:Array<ContainerTable> = [];
	var current = 0;
	var recordedFor = -1;

	public function new() {}

	public function startPrint(layout:String):Int {
		final path = Files.localPath(layout);
		if (!sys.FileSystem.exists(path)) {
			Trace.log("printStart", path, LL_ERR_CFGNOTFOUND);
			return LL_ERR_CFGNOTFOUND;
		}
		layoutPath = path;
		storagePath = haxe.io.Path.withoutExtension(path) + ".ll";
		sequence = containerTables(LstParser.parse(Encoding.decode(sys.io.File.getBytes(path))));
		current = 0;
		settle();
		tables.resize(0);
		recordedFor = -1;
		printing = true;
		Trace.log("printStart", '$path (${sequence.length} tables)', 0);
		return 0;
	}

	public function currentTable():String {
		return current < sequence.length ? sequence[current].id : "";
	}

	public function printFields():Int {
		final id = currentTable();
		// A table the layout skipped records nothing, so the recorded tables are counted
		// apart from the layout's: a new one starts when the layout has moved on.
		if (recordedFor != current) {
			tables.push({id: id, rows: []});
			recordedFor = current;
		}
		// The row is this table's fields, named "<table>.<column>". A field of another
		// table is not part of this one's row.
		final prefix = id + ".";
		final row = new Named();
		for (name in fields.names) {
			if (id == "" || StringTools.startsWith(name, prefix)) {
				row.set(name, fields.get(name));
			}
		}
		tables[tables.length - 1].rows.push(row);
		return 0;
	}

	public function printFieldsEnd():Int {
		if (current < sequence.length) {
			current++;
		}
		settle();
		return current < sequence.length ? LL_WRN_TABLECHANGE : 0;
	}

	/** Ends the print and writes the recorded report where the layout's storage file goes. **/
	public function endPrint():Int {
		if (!printing) {
			return LL_ERR_BAD_JOBHANDLE;
		}
		printing = false;
		final r = Files.write(storagePath, Storage.HEAD + recordJson() + Storage.TAIL) ? 0 : -1;
		Trace.log("printEnd", storagePath, r);
		return r;
	}

	public function recordJson():String {
		final b = new StringBuf();
		b.add('{"layout":' + Json.string(haxe.io.Path.withoutDirectory(layoutPath)));
		b.add(',"path":' + Json.string(layoutPath));
		b.add(',"jobName":' + Json.string(jobName));
		b.add(',"variables":' + Json.object(variables));
		b.add(',"tables":[');
		for (t in 0...tables.length) {
			if (t > 0) {
				b.add(",");
			}
			b.add('{"id":' + Json.string(tables[t].id) + ',"rows":[');
			b.add([for (r in tables[t].rows) Json.object(r)].join(","));
			b.add("]}");
		}
		b.add("]}");
		return b.toString();
	}

	/**
		Moves past every table, from the current one on, whose condition says it does not
		print. A condition this cannot read prints the table and says so in the trace, so a
		misread shows as an extra table rather than a missing one.
	**/
	function settle() {
		while (current < sequence.length) {
			final t = sequence[current];
			if (t.condition == null || t.condition == "") {
				return;
			}
			var prints = true;
			try {
				prints = Values.truth(Formula.parse(t.condition).evaluate(variables));
			} catch (e:FormulaError) {
				Trace.log("condition not read, table printed:", t.id + " " + t.condition + " (" + e.message + ")", 1);
				return;
			}
			if (prints) {
				return;
			}
			Trace.log("condition false, table skipped:", t.id + " " + t.condition, 0);
			current++;
		}
	}

	/**
		The tables a layout's report container prints, in order. A layout without a
		container (a certificate or a label) prints none.
	**/
	public static function containerTables(project:LstSection):Array<ContainerTable> {
		final out = [];
		for (object in project.childrenNamed("Object")) {
			if (object.get("ObjectName") != "Report Container") {
				continue;
			}
			for (table in object.descendants("Table")) {
				out.push({id: table.get("TableID"), condition: table.get("Condition")});
			}
		}
		return out;
	}
}

typedef ContainerTable = {
	final id:String;
	final condition:Null<String>;
}

typedef RecordedTable = {
	final id:String;
	final rows:Array<Named>;
}
