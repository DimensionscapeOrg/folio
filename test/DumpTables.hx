import folio.layout.Model;
import folio.layout.ProjectReader;
import folio.lst.LstParser;
import folio.text.Encoding;

/**
	Prints a layout's container tables as folio reads them: each section's lines, their
	conditions, and their cells.

	usage: haxe -cp src -cp test --run DumpTables <layout.lst> [table id]
**/
class DumpTables {
	static function main() {
		final args = Sys.args();
		final project = ProjectReader.read(LstParser.parse(Encoding.decode(sys.io.File.getBytes(args[0]))));
		for (o in project.objects) {
			switch o {
				case OContainer(c):
					for (t in c.tables) {
						if (args.length > 1 && t.id != args[1]) {
							continue;
						}
						Sys.println('table ${t.id} (${t.kind}) if ${t.condition}, ${t.distanceTop} above');
						final sections:Array<{name:String, lines:Array<TableLine>}> = [
							{name: "header", lines: t.header},
							{name: "body", lines: t.body},
							{name: "footer", lines: t.footer}
						];
						for (section in sections) {
							for (l in section.lines) {
								Sys.println('  ${section.name} line if ${l.condition}, reserved ${l.reserved.left}/${l.reserved.top}/${l.reserved.bottom} lfont ${haxe.Json.stringify(l.font)}');
								for (cell in l.cells) {
									Sys.println('    ${cell.width} pad ${cell.padding.left}/${cell.padding.top}/${cell.padding.right}/${cell.padding.bottom} if ${cell.condition} font ${haxe.Json.stringify(cell.font)}: ${cell.text.substr(0, 60)}');
								}
							}
						}
					}
				default:
			}
		}
	}
}
