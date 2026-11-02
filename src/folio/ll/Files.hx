package folio.ll;

import sys.FileSystem;

/** Paths as a Windows program spells them, made into paths the disk it runs on has. **/
class Files {
	/**
		On Windows a path is used as given. Elsewhere the separator is always wrong and the
		letter case can be, since a program's own files keep the spelling it ships with
		and its code does not always use it.
	**/
	public static function localPath(path:String):String {
		if (Sys.systemName() == "Windows" || path == null) {
			return path;
		}
		final p = StringTools.replace(path, "\\", "/");
		if (FileSystem.exists(p)) {
			return p;
		}
		final dir = haxe.io.Path.directory(p);
		final want = haxe.io.Path.withoutDirectory(p).toLowerCase();
		final where = dir == "" ? "." : dir;
		if (FileSystem.exists(where) && FileSystem.isDirectory(where)) {
			for (have in FileSystem.readDirectory(where)) {
				if (have.toLowerCase() == want) {
					return dir == "" ? have : haxe.io.Path.join([dir, have]);
				}
			}
		}
		return p;
	}

	public static function write(path:String, text:String):Bool {
		try {
			sys.io.File.saveContent(path, text);
			return true;
		} catch (_:Dynamic) {
			return false;
		}
	}

	public static function read(path:String):Null<String> {
		try {
			return sys.io.File.getContent(path);
		} catch (_:Dynamic) {
			return null;
		}
	}
}
