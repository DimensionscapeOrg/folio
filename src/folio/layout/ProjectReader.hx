package folio.layout;

import folio.layout.Model;
import folio.lst.LstSection;

/** Reads a parsed `.lst` into the model folio draws from. **/
class ProjectReader {
	/** `folder` is the layout's own folder, which file names in it are relative to. **/
	public static function read(root:LstSection, folder = ""):Project {
		final layout = root.child("Layout");
		var width = 215900.0;
		var height = 279400.0;
		final pageLayout = first(root.child("PageLayouts"), "PageLayout");
		if (pageLayout != null) {
			width = num(pageLayout.get("PaperFormat.cx"), width);
			height = num(pageLayout.get("PaperFormat.cy"), height);
			// Orientation 1 is portrait and 2 landscape, whichever way round the paper's
			// size is written: one label layout writes it landscape and prints portrait.
			final orientation = pageLayout.get("PaperFormat.Orientation");
			if ((orientation == "2" && width < height) || (orientation == "1" && width > height)) {
				final w = width;
				width = height;
				height = w;
			}
		}
		final layers = new Map<Int, String>();
		for (l in root.childrenNamed("Layer")) {
			layers.set(Std.parseInt(l.get("LayerID")), orTrue(l.get("Condition")));
		}
		final objects = [];
		for (o in root.childrenNamed("Object")) {
			objects.push(object(o));
		}
		return {
			pageWidth: width,
			pageHeight: height,
			defaultFont: layout == null ? {} : defFont(layout.get("DefFont")),
			layers: layers,
			objects: objects,
			// Metric=1 is millimetres; every shipped layout is 2, inches.
			unit: root.child("Description") != null && root.child("Description").get("Metric") == "1" ? 1000 : 25400,
			folder: folder
		};
	}

	static function object(o:LstSection):LayoutObject {
		final c = common(o);
		return switch o.get("ObjectName") {
			case "Text":
				final paragraphs:Array<Paragraph> = [];
				for (line in o.descendants("Line")) {
					paragraphs.push({
						text: formula(line.get("Text")),
						condition: orTrue(line.get("Condition")),
						font: font(line.child("Font")),
						align: int(line.get("Align"), 0),
						wrap: line.get("LineWrap") != "0",
						spaceOptimization: line.get("SpaceOptimization") == "True"
					});
				}
				final frame:Array<FrameSide> = [];
				for (side in ["Left", "Top", "Right", "Bottom"]) {
					final line = orFalse(o.get('Frame/$side/Line'));
					if (line != "False") {
						final color = o.get('Frame/$side/Line/Color');
						frame.push({side: side, line: line, width: num(o.get('Frame/$side/LineWidth'), 0), color: color == null ? "LL.Color.Black" : color});
					}
				}
				OText({common: c, paragraphs: paragraphs, bottomAligned: o.get("bBottomAligned") == "True", frame: frame});
			case "Table":
				// A table object is a container of one table, fed by the rows a report
				// prints without naming a table.
				final tables = [];
				for (t in o.descendants("Table")) {
					tables.push(table(t));
				}
				OContainer({common: c, font: prefixedFont(o, "DefaultFont/"), tables: tables, tableObject: true});
			case "Report Container":
				final tables = [];
				for (t in o.descendants("Table")) {
					tables.push(table(t));
				}
				OContainer({common: c, font: prefixedFont(o, "DefaultFont/"), tables: tables, tableObject: false});
			case "Line":
				OLine({
					common: c,
					direction: int(o.get("LineDirection"), 2),
					width: num(o.get("Width"), 0),
					color: o.get("FgColor") == null ? "LL.Color.Black" : o.get("FgColor")
				});
			case "Rectangle":
				ORectangle({
					common: c,
					frame: orFalse(o.get("bFrame")),
					fill: orFalse(o.get("bFill")),
					width: num(o.get("Width"), 0),
					color: o.get("FgColor") == null ? "LL.Color.Black" : o.get("FgColor"),
					fillColor: o.get("BkColor") == null ? "LL.Color.White" : o.get("BkColor")
				});
			case "Picture" | "Drawing":
				final source = picture(o);
				source == null ? OOther(o.get("ObjectName"), c) : OPicture({
					common: c,
					source: source,
					isotropic: o.get("bIsotropic") != "False",
					alignment: int(o.get("Alignment"), 0),
					originalSize: o.get("OriginalSize") == "True"
				});
			case kind:
				OOther(kind, c);
		}
	}

	/**
		Where a picture object's picture comes from. Mode 2 names a variable holding a
		file's name; otherwise the layout names a file, or carries the file itself as
		`@2@` and base64 of a length, `ChK_Packed` and the file deflated.
	**/
	static function picture(o:LstSection):Null<PictureSource> {
		if (o.get("Mode") == "2") {
			final name = o.get("Variablename");
			return name == null || name == "" ? null : PVariable(name);
		}
		final contents = o.get("Contents");
		if (contents != null && StringTools.startsWith(contents, "@2@")) {
			final raw = haxe.crypto.Base64.decode(contents.substr(3));
			var end = 4;
			while (end < raw.length && raw.get(end) != 0) {
				end++;
			}
			final packed = raw.getString(4, end - 4) == "ChK_Packed";
			final body = raw.sub(end + 1, raw.length - end - 1);
			return PEmbedded(packed ? haxe.zip.Uncompress.run(body) : body);
		}
		final file = o.get("Filename");
		return file == null || file == "" || file == "<embedded>" ? null : PFile(file);
	}

	static function table(t:LstSection):Table {
		function lines(name:String):Array<TableLine> {
			final s = t.child(name);
			if (s == null) {
				return [];
			}
			final out:Array<TableLine> = [];
			final holder = s.child("Lines");
			for (line in (holder == null ? [] : holder.childrenNamed("Line"))) {
				final options = line.child("Options");
				final columns = line.child("Columns");
				final reserved = options == null ? null : options.child("ReservedSpace");
				function space(side:String):Float {
					return reserved == null ? 0 : num(reserved.get(side), 0);
				}
				out.push({
					condition: options == null ? "True" : orTrue(options.get("LCondition")),
					font: options == null ? {} : font(options.child("LFont")),
					cells: columns == null ? [] : [for (c in columns.childrenNamed("Column")) cell(c, t.child("DefaultFrame"))],
					reserved: {left: space("Left"), top: space("Top"), right: space("Right"), bottom: space("Bottom")}
				});
			}
			return out;
		}
		return {
			id: t.get("TableID") == null ? "" : t.get("TableID"),
			kind: t.get("TableType"),
			condition: orTrue(t.get("Condition")),
			distanceTop: num(t.get("DistanceTop"), 0),
			wrapBefore: t.get("WrapBefore") == "True",
			header: lines("Header"),
			body: lines("Body"),
			footer: lines("Footer"),
			columns: int(t.get("ColumnCount"), 0),
			columnGap: num(t.get("ColumnCount.Distance"), 0),
			columnBreakBefore: t.get("ColumnBreakBefore") == "True",
			height: num(t.get("Height"), 0),
			chart: t.get("TableType") == "Chart" ? chart(t.child("LLXParameters")) : null
		};
	}

	/** The colours a chart takes in turn when its layout names the designer's scheme. **/
	static final SCHEME = [
		"RGB(255,51,0)", "RGB(0,102,204)", "RGB(102,204,51)", "RGB(255,204,0)", "RGB(255,121,75)",
		"RGB(153,153,255)", "RGB(180,220,180)", "RGB(255,219,157)", "RGB(255,153,51)", "RGB(102,102,204)"
	];

	static function chart(p:Null<LstSection>):Null<Chart> {
		if (p == null) {
			return null;
		}
		final y = at(p, "Engine/yAxis");
		final z = at(p, "Engine/zAxis0");
		final byCategory = at(p, "Engine/AdditionalProperties") == null || at(p, "Engine/AdditionalProperties").get("DataMode") != "2";
		// A chart of one series may name its categories on either axis across.
		final x = at(p, "Engine/xAxis") != null || !byCategory ? at(p, "Engine/xAxis") : y;
		final series:Array<Series> = [];
		if (byCategory) {
			series.push({
				value: formula(z.get("FormulaValue")),
				label: "",
				color: null,
				barWidth: num(z.get("BarWidthPercentage"), 60),
				showValues: z.get("FormulaCoordOnObjects") == "1",
				decimals: decimals(z.child("FormulaCoordOnObjects"), "OutputFormatter"),
				thousands: thousands(z.child("FormulaCoordOnObjects"), "OutputFormatter")
			});
		} else {
			for (row in (y == null ? [] : y.descendants("RowItem"))) {
				series.push({
					value: formula(row.get("FormulaValue")),
					label: formula(row.get("FormulaCoord")),
					color: row.get("Color"),
					barWidth: num(row.get("BarWidthPercentage"), 60),
					showValues: row.get("FormulaCoordOnObjects") == "1",
					decimals: decimals(row.child("FormulaCoordOnObjects"), "OutputFormatter"),
					thousands: thousands(row.child("FormulaCoordOnObjects"), "OutputFormatter")
				});
			}
		}
		final colors = [];
		for (i in 0...SCHEME.length) {
			final c = p.get('Colors\\Color$i');
			colors.push(c == null || StringTools.startsWith(c, "LL.Scheme.") ? SCHEME[i] : c);
		}
		final fill = at(p, "Background/Filling");
		final zebra = z.child("ZebraPattern");
		return {
			title: formula(p.get("TitleFormula")),
			titleFont: font(p.child("TitleFormula.Font")),
			category: x == null ? "" : formula(x.get("FormulaValue")),
			categoryUp: x != null && num(x.get("FormulaCoord.RotationAngle"), 0) == 90,
			categoryTitle: x == null ? "" : formula(x.get("FormulaLabel")),
			series: series,
			byCategory: byCategory,
			legend: !byCategory && y != null && y.get("CoordTextPlacement") == "5",
			valueTitle: formula(z.get("FormulaLabel")),
			valueDecimals: decimals(z, "FormulaCoord.OutputFormatter"),
			zebra: z.get("CoordGridZebraPattern") == "1",
			zebraColor: zebra == null || zebra.get("Color") == null ? "LL.Color.WhiteSmoke" : zebra.get("Color"),
			background: fill == null || fill.get("Color") == null ? "LL.Color.White" : fill.get("Color"),
			background2: fill == null || fill.get("Color2") == null ? "LL.Color.White" : fill.get("Color2"),
			backgroundGradient: fill != null && fill.get("bShow") == "3",
			frame: at(p, "Background/Frame") != null && at(p, "Background/Frame").get("bShow") == "1",
			plotFrameColor: at(p, "Engine").get("FrameColor") == null ? "RGB(180,180,180)" : at(p, "Engine").get("FrameColor"),
			colors: colors
		};
	}

	/**
		The decimals a number formatter shows: `key=DOUBLE` with its `Decimals`, or the
		two List & Label shows when a value has no formatter.
	**/
	static function decimals(s:Null<LstSection>, key:String):Int {
		if (s == null || s.get(key) != "DOUBLE") {
			return 2;
		}
		final d = s.child(key + ".DOUBLE");
		return d == null ? 2 : int(d.get("Decimals"), 2);
	}

	/**
		Whether a number formatter groups thousands: `ThousandsCharType=-2`, the system's
		separator, does; 0, or no formatter, does not.
	**/
	static function thousands(s:Null<LstSection>, key:String):Bool {
		final d = s == null || s.get(key) != "DOUBLE" ? null : s.child(key + ".DOUBLE");
		return d != null && d.get("ThousandsCharType") == "-2";
	}

	/** The section at a path of nested section names, or null. **/
	static function at(s:LstSection, path:String):Null<LstSection> {
		var here = s;
		for (name in path.split("/")) {
			here = here.child(name);
			if (here == null) {
				return null;
			}
		}
		return here;
	}

	/**
		A table cell. A cell frame of `Default=True` is the table's default frame, whatever
		spacing the cell's own frame still records.
	**/
	static function cell(c:LstSection, tableFrame:Null<LstSection>):Cell {
		final own = c.child("Frame");
		final frame = own != null && own.get("Default") == "True" && tableFrame != null ? tableFrame : own;
		function pad(side:String):Float {
			final s = frame == null ? null : frame.child(side);
			return s == null ? 0 : num(s.get("Spacing"), 0);
		}
		final sides:Array<FrameSide> = [];
		for (side in ["Left", "Top", "Right", "Bottom"]) {
			final s = frame == null ? null : frame.child(side);
			final line = s == null ? "False" : orFalse(s.get("Line"));
			if (line != "False") {
				final style = s.child("Line");
				final color = style == null ? null : style.get("Color");
				sides.push({side: side, line: line, width: num(s.get("LineWidth"), 0), color: color == null ? "LL.Color.Black" : color});
			}
		}
		final text = formula(c.get("Text"));
		final drawing = ~/^Drawing\s*\((.*)\)$/i;
		final fixed = c.get("FixedHeight");
		final fixedFormula = fixed != null && StringTools.startsWith(fixed, "#");
		return {
			text: drawing.match(text) ? "" : text,
			picture: drawing.match(text) ? {
				source: PVariable(drawing.matched(1)),
				height: num(c.get("Height"), 0),
				isotropic: c.get("bIsotropic") != "False",
				alignment: int(c.get("DrawingAlignment"), 0)
			} : null,
			background: c.get("Bitmap") == "2" && c.get("Variablename") != null ? {
				source: PVariable(c.get("Variablename")),
				height: 0,
				isotropic: c.get("Bk.Dwg.bIsotropic") != "False",
				alignment: int(c.get("Bk.Dwg.Alignment"), 0)
			} : null,
			fixedHeight: fixedFormula ? 0 : num(fixed, 0),
			fixedHeightFormula: fixedFormula ? formula(fixed.substr(1)) : "",
			condition: orTrue(c.get("Condition")),
			width: num(c.get("Width"), 0),
			widthFormula: c.get("Width") != null && StringTools.startsWith(c.get("Width"), "#") ? formula(c.get("Width").substr(1)) : "",
			align: int(c.get("Align"), 0),
			valign: int(c.get("VAlign"), 0),
			wrap: c.get("LineWrap") != "0",
			font: font(c.child("Font")),
			padding: {left: pad("Left"), top: pad("Top"), right: pad("Right"), bottom: pad("Bottom")},
			fill: orFalse(c.get("bFill")),
			fillColor: c.get("BkColor") == null ? "LL.Color.White" : c.get("BkColor"),
			spaceOptimization: c.get("SpaceOptimization") == "True",
			frame: sides
		};
	}

	static function common(o:LstSection):Common {
		// A position written `#formula` is worked out as the page is drawn.
		final placed = new Map<String, String>();
		function position(key:String):Float {
			final v = o.get('Position/$key');
			if (v != null && StringTools.startsWith(v, "#")) {
				placed.set(key.toLowerCase(), formula(v.substr(1)));
				return 0;
			}
			return num(v, 0);
		}
		return {
			identifier: o.get("Identifier") == null ? "" : o.get("Identifier"),
			rect: {
				left: position("Left"),
				top: position("Top"),
				width: position("Width"),
				height: position("Height")
			},
			placed: placed,
			layer: int(o.get("LayerID"), 0),
			condition: orTrue(o.get("Condition"))
		};
	}

	/** A `[Font]` section. `Default=True` means the enclosing font throughout. **/
	static function font(s:Null<LstSection>):FontSpec {
		if (s == null || s.get("Default") != "False") {
			return {};
		}
		return {
			face: nullable(s.get("FaceName")),
			size: nullable(s.get("Size")),
			bold: nullable(s.get("Bold")),
			italic: nullable(s.get("Italic")),
			underline: nullable(s.get("Underline")),
			color: nullable(s.get("Color"))
		};
	}

	/**
		A font written as keys with a prefix, as a report container writes its default.
		`Default=True` means the layout's font, whatever the keys beside it still say.
	**/
	static function prefixedFont(s:LstSection, p:String):FontSpec {
		if (s.get(p + "Default") == "True") {
			return {};
		}
		return {
			face: nullable(s.get(p + "FaceName")),
			size: nullable(s.get(p + "Size")),
			bold: nullable(s.get(p + "Bold")),
			italic: nullable(s.get(p + "Italic")),
			underline: nullable(s.get(p + "Underline")),
			color: nullable(s.get(p + "Color"))
		};
	}

	/**
		The layout's default font, `{(r,g,b),size,height,…,weight,italic,…,face}`: a colour,
		then the size in points, a weight of 700 or more for bold, and the face last.
	**/
	public static function defFont(s:Null<String>):FontSpec {
		if (s == null) {
			return {};
		}
		final t = ~/^\{\((\d+),(\d+),(\d+)\),(.*)\}$/;
		if (!t.match(s)) {
			return {};
		}
		final v = t.matched(4).split(",");
		return {
			face: '"${v[v.length - 1]}"',
			size: v[0],
			bold: Std.parseInt(v[5]) >= 700 ? "True" : "False",
			italic: v[6] != "0" ? "True" : "False",
			color: 'RGB(${t.matched(1)},${t.matched(2)},${t.matched(3)})'
		};
	}

	/**
		A formula as the designer stores it. Text after a `¤` outside quotes is the
		designer's own annotation, not part of the expression.
	**/
	public static function formula(s:Null<String>):String {
		if (s == null) {
			return "";
		}
		var quoted = false;
		for (i in 0...s.length) {
			final c = s.charAt(i);
			if (c == '"') {
				quoted = !quoted;
			} else if (c == "¤" && !quoted) {
				return StringTools.trim(s.substr(0, i));
			}
		}
		return StringTools.trim(s);
	}

	static function first(s:Null<LstSection>, name:String):Null<LstSection> {
		if (s == null) {
			return null;
		}
		final all = s.descendants(name);
		return all.length == 0 ? null : all[0];
	}

	static function nullable(s:Null<String>):Null<String> {
		return s == null || s == "" || s == "Null()" || s == "#Null()" ? null : s;
	}



	static function num(s:Null<String>, fallback:Float):Float {
		if (s == null) {
			return fallback;
		}
		final v = Std.parseFloat(s);
		return Math.isNaN(v) ? fallback : v;
	}

	static function int(s:Null<String>, fallback:Int):Int {
		final v = s == null ? null : Std.parseInt(s);
		return v == null ? fallback : v;
	}

	static function orTrue(s:Null<String>):String {
		final v = formula(s);
		return v == "" ? "True" : v;
	}

	static function orFalse(s:Null<String>):String {
		final v = formula(s);
		return v == "" ? "False" : v;
	}
}
