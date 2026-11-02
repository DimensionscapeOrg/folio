package folio.ll;

import folio.ll.Constants.*;

/**
	The List & Label calls, by handle, for a program that was written against List & Label.

	`lib/ListLabelExports.cpp` exports these from the library under List & Label's own
	names and signatures, so such a program links this library in its place and runs
	unchanged. Text arrives here as UTF-8; the exports convert from and to the program's
	code page.
**/
@:keep
class ListLabel {
	static final jobs = new Map<Int, Job>();
	static var nextJob = 1;
	static final storages = new Map<Int, Storage>();
	static var nextStorage = 1;

	public static function jobOpen(language:Int):Int {
		final h = nextJob++;
		jobs.set(h, new Job());
		Trace.log("jobOpen", "", h);
		return h;
	}

	public static function jobClose(job:Int) {
		jobs.remove(job);
	}

	/**
		The one option a program reads back before printing is whether a default printer
		exists, and it refuses the job without one. Nothing here needs a printer, so the
		answer is yes.
	**/
	public static function getOption(job:Int, mode:Int):Int {
		return mode == LL_OPTION_DEFPRINTERINSTALLED ? 1 : 0;
	}

	public static function defineVariableStart(job:Int) {
		final j = jobs.get(job);
		if (j != null) {
			j.variables.clear();
		}
	}

	public static function defineField(job:Int, name:String, value:String):Int {
		final j = jobs.get(job);
		if (j == null) {
			return LL_ERR_BAD_JOBHANDLE;
		}
		j.fields.set(name, value);
		return 0;
	}

	public static function defineVariable(job:Int, name:String, value:String):Int {
		final j = jobs.get(job);
		if (j == null) {
			return LL_ERR_BAD_JOBHANDLE;
		}
		j.variables.set(name, value);
		return 0;
	}

	public static function printStart(job:Int, layout:String):Int {
		final j = jobs.get(job);
		return j == null ? LL_ERR_BAD_JOBHANDLE : j.startPrint(layout);
	}

	public static function printFields(job:Int):Int {
		final j = jobs.get(job);
		return j == null ? LL_ERR_BAD_JOBHANDLE : j.printFields();
	}

	public static function printFieldsEnd(job:Int):Int {
		final j = jobs.get(job);
		return j == null ? LL_ERR_BAD_JOBHANDLE : j.printFieldsEnd();
	}

	public static function printEnd(job:Int):Int {
		final j = jobs.get(job);
		return j == null ? LL_ERR_BAD_JOBHANDLE : j.endPrint();
	}

	/** The table the layout prints next, or "" when there is none or the handle is bad. **/
	public static function currentTable(job:Int):String {
		final j = jobs.get(job);
		return j == null ? "" : j.currentTable();
	}

	/** Every report runs to its last row. **/
	public static function printGetOption(job:Int, index:Int):Int {
		return index == LL_OPTION_LASTPAGE ? 32767 : 0;
	}

	public static function printSetOptionString(job:Int, index:Int, value:String):Int {
		final j = jobs.get(job);
		if (j == null) {
			return LL_ERR_BAD_JOBHANDLE;
		}
		if (index == LL_PRNOPTSTR_PRINTJOBNAME) {
			j.jobName = value;
		}
		return 0;
	}

	public static function currentPage(job:Int):Int {
		return 1;
	}

	public static function storageOpen(file:String):Int {
		final s = Storage.open(Files.localPath(file));
		if (s == null) {
			return 0;
		}
		final h = nextStorage++;
		storages.set(h, s);
		return h;
	}

	public static function storageClose(storage:Int) {
		final s = storages.get(storage);
		if (s != null) {
			s.close();
			storages.remove(storage);
		}
	}

	public static function storageAppend(target:Int, append:Int):Int {
		final t = storages.get(target);
		final a = storages.get(append);
		if (t == null || a == null) {
			return -1;
		}
		t.append(a);
		return 0;
	}

	/**
		Converting to PDF draws the recorded reports on their layouts' pages. Any other
		format gets the recording itself.
	**/
	public static function storageConvert(from:String, to:String, format:String):Int {
		final doc = Files.read(Files.localPath(from));
		if (doc == null) {
			Trace.log("storageConvert", from, -1);
			return -1;
		}
		final dest = Sys.systemName() == "Windows" ? to : StringTools.replace(to, "\\", "/");
		var r = 0;
		if (format.toUpperCase() == "PDF") {
			try {
				sys.io.File.saveBytes(dest, PdfOutput.convert(doc));
			} catch (e:haxe.Exception) {
				Trace.log("storageConvert failed:", e.message + "\n" + e.stack, -1);
				r = -1;
			}
		} else {
			r = Files.write(dest, doc) ? 0 : -1;
		}
		Trace.log("storageConvert", dest, r);
		return r;
	}
}
