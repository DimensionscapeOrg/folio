package folio.ll;

/** FOLIO_TRACE=1 prints each call that decides what a report produces, to stderr. **/
class Trace {
	static var on:Null<Bool> = null;

	public static function log(what:String, detail:String, result:Int) {
		if (on == null) {
			final v = Sys.getEnv("FOLIO_TRACE");
			on = v != null && v != "" && v != "0";
		}
		if (on) {
			Sys.stderr().writeString('folio: $what $detail -> $result\n');
		}
	}
}
