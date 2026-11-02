import haxe.io.Path;
import sys.FileSystem;

class Fixtures {
	static var counter = 0;

	/** Tests run from the repository root. **/
	public static function path(name:String):String {
		return 'test/fixtures/$name';
	}

	public static function text(name:String):String {
		return sys.io.File.getContent(path(name));
	}

	/** A fresh, empty directory under bin/test-scratch. **/
	public static function scratch():String {
		final dir = 'bin/test-scratch/${counter++}';
		if (FileSystem.exists(dir)) {
			for (f in FileSystem.readDirectory(dir)) {
				FileSystem.deleteFile('$dir/$f');
			}
		} else {
			FileSystem.createDirectory(dir);
		}
		return dir;
	}
}
