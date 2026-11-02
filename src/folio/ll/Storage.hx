package folio.ll;

/**
	A storage file: the reports one print wrote, which a program can append to another
	and convert. A recorded storage file holds

	```
	{"reports":[{"layout":..., "jobName":..., "variables":{...}, "tables":[...]}]}
	```

	so appending one to another appends its reports.
**/
class Storage {
	public static inline final HEAD = '{"reports":[';
	public static inline final TAIL = "]}";

	public final path:String;

	/** The reports, comma separated, without the brackets around them. **/
	public var items(default, null):String;

	public var changed(default, null) = false;

	function new(path:String, items:String) {
		this.path = path;
		this.items = items;
	}

	public static function open(path:String):Null<Storage> {
		final doc = Files.read(path);
		if (doc == null || doc.length < HEAD.length + TAIL.length || !StringTools.startsWith(doc, HEAD) || !StringTools.endsWith(doc, TAIL)) {
			return null;
		}
		return new Storage(path, doc.substring(HEAD.length, doc.length - TAIL.length));
	}

	public function append(other:Storage) {
		if (other.items != "") {
			items = items == "" ? other.items : items + "," + other.items;
			changed = true;
		}
	}

	public function close() {
		if (changed) {
			Files.write(path, HEAD + items + TAIL);
		}
	}
}
