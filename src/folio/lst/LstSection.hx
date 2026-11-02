package folio.lst;

/**
	One section of a List & Label project file: its name, the keys written directly in it
	in file order, and the sections nested in it.

	A project file is text. A section at the left margin opens a top-level section whose
	keys follow it; a section further in is followed by a `{` and closed by a `}`:

	```
	[Object]
	 ObjectName=Report Container
	 [@Tables]
	  {
	  [Tables]
	   {
	   [Table]
	   	{
	   	TableID=ProjInfo
	```
**/
class LstSection {
	public final name:String;
	public final keys:Array<LstKey> = [];
	public final children:Array<LstSection> = [];

	public function new(name:String) {
		this.name = name;
	}

	/** The value of the first key of this name written directly in this section, or null. **/
	public function get(key:String):Null<String> {
		for (k in keys) {
			if (k.key == key) {
				return k.value;
			}
		}
		return null;
	}

	/** The first section of this name directly inside this one, or null. **/
	public function child(name:String):Null<LstSection> {
		for (c in children) {
			if (c.name == name) {
				return c;
			}
		}
		return null;
	}

	/** Every section of this name directly inside this one, in file order. **/
	public function childrenNamed(name:String):Array<LstSection> {
		return children.filter(c -> c.name == name);
	}

	/** Every section of this name at any depth inside this one, in file order. **/
	public function descendants(name:String):Array<LstSection> {
		final found = [];
		function walk(s:LstSection) {
			for (c in s.children) {
				if (c.name == name) {
					found.push(c);
				}
				walk(c);
			}
		}
		walk(this);
		return found;
	}
}

typedef LstKey = {
	final key:String;
	final value:String;
}
