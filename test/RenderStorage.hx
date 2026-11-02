import folio.ll.PdfOutput;

/**
	Draws recorded storage files as PDF, outside any program: for working on layouts.

	usage: haxe -cp src -cp test --run RenderStorage <storage.ll> <out.pdf> [<storage.ll> <out.pdf>...]
**/
class RenderStorage {
	static function main() {
		final args = Sys.args();
		var i = 0;
		while (i + 1 < args.length) {
			final t = haxe.Timer.stamp();
			sys.io.File.saveBytes(args[i + 1], PdfOutput.convert(sys.io.File.getContent(args[i])));
			Sys.println('${args[i + 1]} in ${Math.round((haxe.Timer.stamp() - t) * 1000)} ms');
			i += 2;
		}
	}
}
