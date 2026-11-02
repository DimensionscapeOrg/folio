package folio.font;

import sys.FileSystem;

/**
	The fonts installed where folio runs, found by family name and style.

	A layout names a font the way a font picker does ("Trebuchet MS", bold). Each font
	file says which family and style it is, so the library reads every file's names once
	and answers from that. A family that is not installed falls back to one that is, so a
	report always prints; `missing` lists the families that fell back.
**/
class FontLibrary {
	public final missing:Array<String> = [];

	final faces:Array<Face> = [];
	final loaded = new Map<String, TrueType>();

	public function new(?dirs:Array<String>) {
		for (dir in (dirs == null ? systemDirs() : dirs)) {
			scan(dir, 0);
		}
	}

	/**
		The folders searched for fonts: those `FOLIO_FONTS` lists first, separated as the
		system separates a path list (";" on Windows, ":" elsewhere), so a server can carry
		the fonts its layouts name; then the system's own.
	**/
	public static function systemDirs():Array<String> {
		final own = Sys.getEnv("FOLIO_FONTS");
		final first = own == null || own == "" ? [] : own.split(Sys.systemName() == "Windows" ? ";" : ":");
		return first.concat(installedDirs());
	}

	static function installedDirs():Array<String> {
		return switch Sys.systemName() {
			case "Windows":
				final root = Sys.getEnv("WINDIR");
				final user = Sys.getEnv("LOCALAPPDATA");
				[(root == null ? "C:\\Windows" : root) + "\\Fonts"].concat(user == null ? [] : [user + "\\Microsoft\\Windows\\Fonts"]);
			case "Mac":
				["/System/Library/Fonts", "/Library/Fonts", Sys.getEnv("HOME") + "/Library/Fonts"];
			default:
				["/usr/share/fonts", "/usr/local/share/fonts", Sys.getEnv("HOME") + "/.local/share/fonts", Sys.getEnv("HOME") + "/.fonts"];
		}
	}

	/** The font for a family and style, or the closest one installed. **/
	public function find(family:String, bold:Bool, italic:Bool):TrueType {
		final want = family.toLowerCase();
		var match = pick(f -> f.family == want, bold, italic);
		if (match == null) {
			if (missing.indexOf(family) < 0) {
				missing.push(family);
			}
			for (fallback in ["arial", "liberation sans", "dejavu sans", "helvetica"]) {
				match = pick(f -> f.family == fallback, bold, italic);
				if (match != null) {
					break;
				}
			}
		}
		if (match == null && faces.length > 0) {
			match = faces[0];
		}
		if (match == null) {
			throw new haxe.Exception('no fonts found for "$family"');
		}
		var font = loaded.get(match.path);
		if (font == null) {
			font = TrueType.load(match.path);
			loaded.set(match.path, font);
		}
		return font;
	}

	function pick(test:Face->Bool, bold:Bool, italic:Bool):Null<Face> {
		var best:Null<Face> = null;
		var bestScore = -1;
		for (f in faces) {
			if (!test(f)) {
				continue;
			}
			final score = (f.bold == bold ? 2 : 0) + (f.italic == italic ? 1 : 0);
			if (score > bestScore) {
				best = f;
				bestScore = score;
			}
		}
		return best;
	}

	function scan(dir:String, depth:Int) {
		if (dir == null || !FileSystem.exists(dir) || !FileSystem.isDirectory(dir) || depth > 4) {
			return;
		}
		for (name in FileSystem.readDirectory(dir)) {
			final path = haxe.io.Path.join([dir, name]);
			final lower = name.toLowerCase();
			if (FileSystem.isDirectory(path)) {
				scan(path, depth + 1);
			} else if (StringTools.endsWith(lower, ".ttf") || StringTools.endsWith(lower, ".otf")) {
				final names = FontNames.read(path);
				if (names != null) {
					faces.push({
						path: path,
						family: names.family.toLowerCase(),
						bold: names.bold,
						italic: names.italic
					});
				}
			}
		}
	}
}

private typedef Face = {
	final path:String;
	final family:String;
	final bold:Bool;
	final italic:Bool;
}
