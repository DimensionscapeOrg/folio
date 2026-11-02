package folio.layout;

import folio.font.FontLibrary;
import folio.font.TrueType;
import folio.formula.Colors;
import folio.formula.Formula;
import folio.formula.Value;
import folio.layout.Model;
import folio.image.Picture;
import folio.ll.Files;
import folio.ll.Named;
import folio.ll.Trace;
import folio.pdf.PdfDocument;
import folio.pdf.PdfPage;

using folio.formula.Value.Values;

/** A report as the program handed it over: its variables and each table's rows. **/
typedef ReportData = {
	final variables:Named;
	final tables:Array<{id:String, rows:Array<Named>}>;
}

/**
	Lays a recorded report out on a layout's pages and draws them into a PDF.

	Every object but the report container is drawn on every page its layer and condition
	allow. The container's tables flow down its rectangle, in the order the report filled
	them, onto as many pages as they need: a row is never split, and a table's header lines
	are repeated at the top of each page or column it continues in. A list table of several
	columns runs down each in turn, and a table may break to the next. A container's table
	whose rows print nothing is left out whole, as are a report's table objects when none
	of them prints a row. A chart is a block of its own height, never split,
	beside the next chart when both are of two columns. The pages are
	laid out once to count them, so `TotalPages$()` is known when they are drawn.
**/
@:allow(folio.layout.ChartRenderer)
class Renderer {
	final fonts:FontLibrary;
	final formulas = new Map<String, Formula>();
	final charts:ChartRenderer;

	public function new(fonts:FontLibrary) {
		this.fonts = fonts;
		charts = new ChartRenderer(this);
	}

	public function render(doc:PdfDocument, project:Project, data:ReportData) {
		// Each container flows on its own; the report has as many pages as the longest.
		final flows = new Map<Container, Array<Array<Placed>>>();
		// Table objects start together, once a row prints a line in any of them.
		var started = false;
		for (o in project.objects) {
			switch o {
				case OContainer(c) if (c.tableObject):
					started = started || printsALine(project, c, data);
				default:
			}
		}
		var count = 1;
		for (o in project.objects) {
			switch o {
				case OContainer(c):
					final pages = paginate(project, c, data, started);
					flows.set(c, pages);
					count = Std.int(Math.max(count, pages.length));
				default:
			}
		}
		final scope = scopeFor(project, data.variables);
		scope.totalPages = count;
		for (p in 0...count) {
			scope.page = p + 1;
			final page = doc.addPage(Units.pt(project.pageWidth), Units.pt(project.pageHeight));
			for (object in project.objects) {
				switch object {
					case OText(o):
						if (visible(project, o.common, scope)) {
							drawText(page, project, o, scope);
						}
					case OLine(o):
						if (visible(project, o.common, scope)) {
							drawLineObject(page, project, o, scope);
						}
					case ORectangle(o):
						if (visible(project, o.common, scope)) {
							drawRectangle(page, project, o, scope);
						}
					case OPicture(o):
						if (visible(project, o.common, scope)) {
							drawPicture(page, project, o, scope);
						}
					case OContainer(o):
						final pages = flows.get(o);
						if (p < pages.length && visible(project, o.common, scope)) {
							for (placed in pages[p]) {
								if (placed.chart != null) {
									charts.draw(page, project, o, placed, data.variables);
								} else {
									drawLine(page, project, o, placed);
								}
							}
						}
					case OOther(kind, c):
						if (p == 0) {
							Trace.log("not drawn yet:", '$kind ${c.identifier}', 0);
						}
				}
			}
		}
	}


	static function scopeFor(project:Project, variables:Named):RenderScope {
		final scope = new RenderScope(variables);
		scope.unit = project.unit;
		scope.pageWidth = project.pageWidth;
		scope.pageHeight = project.pageHeight;
		return scope;
	}

	function visible(project:Project, c:Common, scope:RenderScope):Bool {
		final layer = project.layers.get(c.layer);
		return truth(c.condition, scope) && (layer == null || truth(layer, scope));
	}

	// PAGINATION ------------------------------------------------------------------

	/** Whether any row a container's tables are handed prints a line in one of them. **/
	function printsALine(project:Project, container:Container, data:ReportData):Bool {
		for (table in container.tables) {
			for (recorded in data.tables) {
				if (recorded.id == table.id && table.kind == "List") {
					for (row in recorded.rows) {
						if (measureLines(project, container, table.body, data.variables, row).length > 0) {
							return true;
						}
					}
				}
			}
		}
		return false;
	}

	/**
		A container's tables laid out page by page. `started` says whether the report's
		table objects have started, for a container that is one.
	**/
	function paginate(project:Project, container:Container, data:ReportData, started:Bool):Array<Array<Placed>> {
		final pages:Array<Array<Placed>> = [[]];
		// A container placed by formula can stand differently on each page, as one report's
		// is lower on the first page than on the rest.
		final scope = scopeFor(project, data.variables);
		var top = 0.0;
		var bottom = 0.0;
		function area() {
			scope.page = pages.length;
			final r = rectOf(project, container.common, scope);
			top = r.top;
			bottom = r.top + r.height;
		}
		area();
		var y = top;
		// List tables of several columns run down one column and on into the next:
		// `listColumns` of them, 0 when none, starting at `listTop`, filling `listColumn`,
		// and reaching down to `listBottom` in the deepest so far.
		var listColumns = 0;
		var listColumn = 0;
		var listTop = 0.0;
		var listBottom = 0.0;
		var listOffset = 0.0;
		function newPage() {
			pages.push([]);
			area();
			y = top;
			listColumn = 0;
			listTop = y;
			listBottom = y;
		}
		function nextColumn() {
			if (listColumns > 1 && listColumn + 1 < listColumns) {
				listColumn++;
				y = listTop;
			} else {
				newPage();
			}
		}
		function endColumns() {
			if (listColumns > 0) {
				y = Math.max(y, listBottom);
				listColumns = 0;
				listColumn = 0;
			}
		}
		final used = [for (_ in container.tables) false];
		// Charts of several columns fill a row of them left to right; `column` is the next
		// free one in the current row, and `rowHeight` how far the row reaches down.
		var column = 0;
		var rowHeight = 0.0;
		function endRow() {
			if (column > 0) {
				y += rowHeight;
				column = 0;
				rowHeight = 0;
			}
		}

		for (recorded in data.tables) {
			final table = matchTable(container, used, recorded.id);
			if (table == null) {
				Trace.log("no layout table for", recorded.id, 0);
				continue;
			}
			if (table.chart != null) {
				endColumns();
				final columns = table.columns < 1 ? 1 : table.columns;
				final width = (container.common.rect.width - table.columnGap * (columns - 1)) / columns;
				if (column >= columns) {
					endRow();
				}
				if (column == 0) {
					if (table.wrapBefore && y > top + 0.5) {
						newPage();
					}
					if (y > top + 0.5) {
						y += table.distanceTop;
					}
					// A chart is never split: it goes whole onto the next page.
					if (y + table.height > bottom && y > top + 0.5) {
						newPage();
					}
				}
				final left = column * (width + table.columnGap);
				// List & Label takes a chart as 0.53 pt shorter than its height, measured
				// from the panel it draws and from where the next table starts.
				final height = table.height - Units.toScm(0.53);
				pages[pages.length - 1].push(new Placed([], height, NO_SPACE, {table: table, rows: recorded.rows, left: left, width: width}).at(y));
				rowHeight = Math.max(rowHeight, height);
				column++;
				if (columns == 1) {
					endRow();
				}
				continue;
			}
			endRow();
			if (table.kind != "List") {
				Trace.log("not drawn yet:", '${table.kind} table ${table.id}', 0);
				continue;
			}
			final rows = [for (row in recorded.rows) measureLines(project, container, table.body, data.variables, row)];
			// List & Label holds a table's header back until its first data line prints, so a
			// container's table whose rows print nothing prints nothing at all, footer
			// included. Table objects wait together: once one prints a line, all have begun.
			final printed = Lambda.find(rows, lines -> lines.length > 0);
			if (container.tableObject ? !started : printed == null) {
				continue;
			}
			final firstRow = printed == null ? [] : printed;
			final first = recorded.rows.length > 0 ? recorded.rows[0] : null;
			final last = recorded.rows.length > 0 ? recorded.rows[recorded.rows.length - 1] : null;
			final header = measureLines(project, container, table.header, data.variables, first);
			// Footer lines close the table on every page it runs onto, as the header opens it.
			final footer = measureLines(project, container, table.footer, data.variables, last);
			final headerHeight = sum(header);
			final footerHeight = sum(footer);

			final columns = table.columns > 1 ? table.columns : 0;
			if (columns != listColumns) {
				endColumns();
			}
			function put(lines:Array<Placed>) {
				for (line in lines) {
					pages[pages.length - 1].push(line.at(y, listColumn * listOffset));
					y += line.height;
				}
				listBottom = Math.max(listBottom, y);
			}
			// The top of the page, or of the column the table is in.
			function atTop() {
				return y <= (listColumns > 0 ? listTop : top) + 0.5;
			}

			if (table.wrapBefore && y > top + 0.5) {
				newPage();
			}
			if (listColumns > 0 && table.columnBreakBefore && !atTop()) {
				nextColumn();
			}
			// Every column starts level with the first, above the space the first table keeps.
			if (columns > 0 && listColumns == 0) {
				listColumns = columns;
				listColumn = 0;
				listTop = y;
				listBottom = y;
				listOffset = (container.common.rect.width - table.columnGap * (columns - 1)) / columns + table.columnGap;
			}
			// The space above a table is kept only below something: not at the top of a page or
			// of a column after the first.
			if (y > top + 0.5 && !(listColumn > 0 && atTop())) {
				y += table.distanceTop;
			}
			// The header goes with the first row, so it is never left alone at a column's foot.
			if (y + headerHeight + sum(firstRow) + footerHeight > bottom && !atTop()) {
				nextColumn();
			}
			put(header);
			// Where this column's rows begin: a row too tall for one goes in one by itself.
			var rowsTop = y;
			for (lines in rows) {
				if (y + sum(lines) + footerHeight > bottom && y > rowsTop + 0.5) {
					put(footer);
					nextColumn();
					put(header);
					rowsTop = y;
				}
				put(lines);
			}
			put(footer);
		}
		return pages;
	}

	static final NO_SPACE:Frame = {left: 0, top: 0, right: 0, bottom: 0};

	static function matchTable(container:Container, used:Array<Bool>, id:String):Null<Table> {
		for (i in 0...container.tables.length) {
			if (!used[i] && container.tables[i].id == id) {
				used[i] = true;
				return container.tables[i];
			}
		}
		return null;
	}

	static function sum(lines:Array<Placed>):Float {
		var h = 0.0;
		for (l in lines) {
			h += l.height;
		}
		return h;
	}

	/** The lines of a table section whose condition holds for a row, measured. **/
	function measureLines(project:Project, container:Container, lines:Array<TableLine>, variables:Named, row:Null<Named>):Array<Placed> {
		final scope = new RenderScope(variables);
		scope.row = row;
		final out = [];
		for (line in lines) {
			if (line.cells.length == 0 || !truth(line.condition, scope)) {
				continue;
			}
			final cells = [];
			var height = 0.0;
			var printed = false;
			for (cell in line.cells) {
				final visible = truth(cell.condition, scope);
				final font = resolve([cell.font, line.font, container.font, project.defaultFont], scope);
				final text = visible ? optimize(textOf(cell.text, scope), cell.spaceOptimization) : "";
				final width = cell.widthFormula != "" ? number(cell.widthFormula, scope) * project.unit : cell.width;
				final inner = width - cell.padding.left - cell.padding.right;
				final wrapped = wrap(text, font, Units.pt(inner), cell.wrap);
				final picture = visible && cell.picture != null ? pictureOf(project, cell.picture.source, scope) : null;
				final background = visible && cell.background != null ? pictureOf(project, cell.background.source, scope) : null;
				printed = printed || text != "" || picture != null;
				// A picture cell is as tall as its picture's space, whether or not there is a
				// picture to put in it; a fixed height overrides either.
				var content = cell.picture != null ? cell.picture.height : Units.toScm(wrapped.length * Metrics.pitch(font.size));
				final fixed = cell.fixedHeightFormula != "" ? number(cell.fixedHeightFormula, scope) * project.unit : cell.fixedHeight;
				if (fixed > 0) {
					content = fixed;
				}
				height = Math.max(height, cell.padding.top + cell.padding.bottom + content);
				cells.push({
					cell: cell,
					width: width,
					font: font,
					lines: wrapped,
					fill: visible && truth(cell.fill, scope) ? color(cell.fillColor, scope) : -1,
					frame: drawnSides(cell.frame, scope),
					picture: picture,
					background: background
				});
			}
			// A line with nothing in any cell is not printed.
			if (printed) {
				out.push(new Placed(cells, line.reserved.top + height + line.reserved.bottom, line.reserved));
			}
		}
		return out;
	}

	// DRAWING ---------------------------------------------------------------------

	function drawLine(page:PdfPage, project:Project, container:Container, placed:Placed) {
		var x = container.common.rect.left + placed.x + placed.reserved.left;
		final top = placed.y + placed.reserved.top;
		final height = placed.height - placed.reserved.top - placed.reserved.bottom;
		for (c in placed.cells) {
			final cell = c.cell;
			if (c.fill >= 0) {
				page.fillRect(Units.pt(x), Units.pt(top), Units.pt(c.width), Units.pt(height), c.fill);
			}
			if (c.background != null) {
				placePicture(page, c.background, Units.pt(x), Units.pt(top), Units.pt(c.width), Units.pt(height), cell.background.isotropic,
					cell.background.alignment);
			}
			drawFrame(page, c.frame, Units.pt(x), Units.pt(top), Units.pt(x + c.width), Units.pt(top + height));
			final left = Units.pt(x + cell.padding.left);
			final right = Units.pt(x + c.width - cell.padding.right);
			final inside = Units.pt(height - cell.padding.top - cell.padding.bottom);
			if (c.picture != null) {
				placePicture(page, c.picture, left, Units.pt(top + cell.padding.top), right - left, inside, cell.picture.isotropic, cell.picture.alignment);
			}
			// Text a taller cell beside it leaves room around goes to its top, middle or foot.
			final spare = inside - c.lines.length * Metrics.pitch(c.font.size);
			final shift = spare <= 0 ? 0.0 : (cell.valign == 1 ? spare / 2 : (cell.valign == 2 ? spare : 0.0));
			var baseline = Units.pt(top + cell.padding.top) + shift + Metrics.cellAscent(c.font.size);
			for (text in c.lines) {
				drawString(page, c.font, alignX(cell.align, left, right, c.font, text), baseline, text);
				baseline += Metrics.pitch(c.font.size);
			}
			x += c.width;
		}
	}

	/**
		A text object's paragraphs, line by line from its top. Its frame is drawn round the
		lines it printed, down to the last one's descent, as List & Label drew the one framed
		text object in the reports measured; with nothing printed, round the whole object.
	**/
	function drawText(page:PdfPage, project:Project, o:TextObject, scope:RenderScope) {
		final r = rectOf(project, o.common, scope);
		final left = Units.pt(r.left);
		final right = Units.pt(r.left + r.width);
		final bottom = Units.pt(r.top + r.height);
		var printed = -1.0;
		final sides = drawnSides(o.frame, scope);
		function frame() {
			drawFrame(page, sides, left, Units.pt(r.top), right, printed < 0 ? bottom : Math.min(printed, bottom));
		}
		var y = Units.pt(r.top);
		for (p in o.paragraphs) {
			if (!truth(p.condition, scope)) {
				continue;
			}
			// An empty paragraph takes no line, with or without space optimization.
			final text = optimize(textOf(p.text, scope), p.spaceOptimization);
			if (text == "") {
				continue;
			}
			final font = resolve([p.font, project.defaultFont], scope);
			for (line in wrap(text, font, right - left, p.wrap)) {
				final pitch = Metrics.pitch(font.size);
				final ascent = Metrics.textAscent(font.size) - (p.align == 0 ? 0 : Metrics.ALIGNED_RAISE);
				// A line whose baseline would fall below the object's foot is not printed,
				// unless it is the first: a label's 18 pt name in a 20 pt box still is.
				if (printed >= 0 && y + Metrics.textAscent(font.size) > bottom) {
					frame();
					return;
				}
				drawString(page, font, alignX(p.align, left, right, font, line), y + ascent, line);
				printed = y + Metrics.textAscent(font.size) + Math.abs(font.font.descent) / font.font.unitsPerEm * font.size;
				y += pitch;
			}
		}
		frame();
	}

	/**
		An object's rectangle on this page: the layout's numbers, with any it gives as a
		formula worked out in the layout's unit.
	**/
	function rectOf(project:Project, c:Common, scope:RenderScope):Rect {
		if (!c.placed.keys().hasNext()) {
			return c.rect;
		}
		function at(key:String, fallback:Float):Float {
			final f = c.placed.get(key);
			return f == null ? fallback : number(f, scope) * project.unit;
		}
		return {
			left: at("left", c.rect.left),
			top: at("top", c.rect.top),
			width: at("width", c.rect.width),
			height: at("height", c.rect.height)
		};
	}

	/** A line object: across or down the middle of its rectangle, or corner to corner. **/
	function drawLineObject(page:PdfPage, project:Project, o:LineObject, scope:RenderScope) {
		final r = rectOf(project, o.common, scope);
		final x1 = Units.pt(r.left);
		final y1 = Units.pt(r.top);
		final x2 = Units.pt(r.left + r.width);
		final y2 = Units.pt(r.top + r.height);
		final w = Units.pt(o.width);
		final c = color(o.color, scope);
		switch o.direction {
			case 0: page.line(x1, y1, x2, y2, w, c);
			case 1: page.line(x1, y2, x2, y1, w, c);
			case 3: page.line((x1 + x2) / 2, y1, (x1 + x2) / 2, y2, w, c);
			default: page.line(x1, (y1 + y2) / 2, x2, (y1 + y2) / 2, w, c);
		}
	}

	function drawRectangle(page:PdfPage, project:Project, o:RectangleObject, scope:RenderScope) {
		final r = rectOf(project, o.common, scope);
		final x = Units.pt(r.left);
		final y = Units.pt(r.top);
		final w = Units.pt(r.width);
		final h = Units.pt(r.height);
		if (truth(o.fill, scope)) {
			page.fillRect(x, y, w, h, color(o.fillColor, scope));
		}
		if (truth(o.frame, scope)) {
			page.strokeRect(x, y, w, h, Units.pt(o.width), color(o.color, scope));
		}
	}

	/**
		A picture in its object's rectangle, fitted and placed as `placePicture` says, or at
		its file's own size for an object so set, which may then reach outside the
		rectangle. A picture that cannot be found or read is left out.
	**/
	function drawPicture(page:PdfPage, project:Project, o:PictureObject, scope:RenderScope) {
		final pic = pictureOf(project, o.source, scope);
		if (pic == null) {
			return;
		}
		final r = rectOf(project, o.common, scope);
		placePicture(page, pic, Units.pt(r.left), Units.pt(r.top), Units.pt(r.width), Units.pt(r.height), o.isotropic, o.alignment,
			o.originalSize);
	}

	/**
		A picture in a rectangle, in points. Not kept in proportion, it is stretched over the
		rectangle. Kept in proportion, it is as large as fits, or its own size when `original`,
		and placed as List & Label places it, measured: alignment 1 tiles it from the top left,
		clipped to the rectangle; 2 to 9 put it at the left top, left bottom, right top, right
		bottom, left middle, right middle, centre top and centre bottom, and a number past 9 is
		taken as 9; anything else centres it.
	**/
	static function placePicture(page:PdfPage, pic:Picture, x:Float, y:Float, w:Float, h:Float, isotropic:Bool, alignment:Int,
			original = false) {
		if (!isotropic && !original) {
			page.picture(x, y, w, h, pic);
			return;
		}
		final s = Math.min(w / pic.width, h / pic.height);
		final dw = original ? pic.pointWidth() : pic.width * s;
		final dh = original ? pic.pointHeight() : pic.height * s;
		if (alignment > 9) {
			alignment = 9;
		}
		if (alignment == 1 && dw > 0 && dh > 0) {
			page.clip(x, y, w, h);
			var ty = y;
			while (ty < y + h) {
				var tx = x;
				while (tx < x + w) {
					page.picture(tx, ty, dw, dh, pic);
					tx += dw;
				}
				ty += dh;
			}
			page.unclip();
			return;
		}
		final across = switch alignment {
			case 2 | 3 | 6: 0.0;
			case 4 | 5 | 7: 1.0;
			default: 0.5;
		}
		final down = switch alignment {
			case 2 | 4 | 8: 0.0;
			case 3 | 5 | 9: 1.0;
			default: 0.5;
		}
		page.picture(x + (w - dw) * across, y + (h - dh) * down, dw, dh, pic);
	}

	/** Pictures read so far, by their file's contents or path, so each is read once. **/
	final pictures = new Map<String, Null<Picture>>();

	/** The key of each picture a layout carries, worked out once however many pages draw it. **/
	final carried = new haxe.ds.ObjectMap<haxe.io.Bytes, String>();

	function pictureOf(project:Project, source:PictureSource, scope:RenderScope):Null<Picture> {
		var bytes:Null<haxe.io.Bytes> = null;
		final key = switch source {
			case PEmbedded(b):
				bytes = b;
				if (!carried.exists(b)) {
					// By contents, so that four objects carrying one label are one picture in the PDF.
					carried.set(b, "embedded:" + haxe.crypto.Md5.make(b).toHex());
				}
				carried.get(b);
			case PFile(path):
				"file:" + filePath(project, path);
			case PVariable(name):
				final path = textOf(name, scope);
				if (StringTools.trim(path) == "") {
					return null;
				}
				"file:" + filePath(project, path);
		}
		if (pictures.exists(key)) {
			return pictures.get(key);
		}
		if (bytes == null) {
			final path = key.substr(5);
			try {
				bytes = sys.io.File.getBytes(path);
			} catch (_:Dynamic) {
				Trace.log("picture not found:", path, 0);
			}
		}
		final pic = bytes == null ? null : Picture.read(bytes);
		if (bytes != null && pic == null) {
			Trace.log("picture not read:", key, 0);
		}
		pictures.set(key, pic);
		return pic;
	}

	/** A file a layout names, from the layout's folder when the name is not a full path. **/
	static function filePath(project:Project, name:String):String {
		final p = StringTools.replace(name, "\\", "/");
		final absolute = StringTools.startsWith(p, "/") || (p.length > 1 && p.charAt(1) == ":");
		return Files.localPath(absolute || project.folder == "" ? name : project.folder + "/" + name);
	}

	/** Text on a baseline, underlined when its font is, by the font's own measure. **/
	static function drawString(page:PdfPage, font:ResolvedFont, x:Float, baseline:Float, text:String) {
		page.text(font.font, font.size, font.color, x, baseline, text);
		if (font.underline && text != "") {
			final em = font.size / font.font.unitsPerEm;
			final y = baseline - font.font.underlinePosition * em;
			page.line(x, y, x + font.font.width(text, font.size), y, font.font.underlineThickness * em, font.color);
		}
	}

	/** The sides of a frame whose line is drawn here, with their widths in points and their colours. **/
	function drawnSides(frame:Array<FrameSide>, scope:RenderScope):Array<DrawnSide> {
		return [
			for (f in frame)
				if (truth(f.line, scope)) {side: f.side, width: Units.pt(f.width), color: color(f.color, scope)}
		];
	}

	/** The drawn sides of a frame around a rectangle, in points; width 0 is a hairline. **/
	static function drawFrame(page:PdfPage, sides:Array<DrawnSide>, x1:Float, y1:Float, x2:Float, y2:Float) {
		// All four sides alike are one rectangle, as List & Label draws them.
		if (sides.length == 4 && Lambda.foreach(sides, f -> f.width == sides[0].width && f.color == sides[0].color)) {
			page.strokeRect(x1, y1, x2 - x1, y2 - y1, sides[0].width, sides[0].color);
			return;
		}
		for (f in sides) {
			switch f.side {
				case "Left": page.line(x1, y1, x1, y2, f.width, f.color);
				case "Top": page.line(x1, y1, x2, y1, f.width, f.color);
				case "Right": page.line(x2, y1, x2, y2, f.width, f.color);
				default: page.line(x1, y2, x2, y2, f.width, f.color);
			}
		}
	}

	/** Space optimization: the spaces a value was padded with are not printed. **/
	static function optimize(text:String, on:Bool):String {
		return on ? StringTools.trim(text) : text;
	}

	static function alignX(align:Int, left:Float, right:Float, font:ResolvedFont, text:String):Float {
		return switch align {
			case 1: (left + right - font.font.width(text, font.size)) / 2;
			case 2: right - font.font.width(text, font.size);
			default: left;
		}
	}

	/** Text broken into lines: at its own line breaks, and at spaces to fit a width. **/
	static function wrap(text:String, font:ResolvedFont, width:Float, wrapWords:Bool):Array<String> {
		final out = [];
		for (para in text.split("\n")) {
			if (!wrapWords || font.font.width(para, font.size) <= width) {
				out.push(para);
				continue;
			}
			final words = para.split(" ");
			var line = "";
			for (w in words) {
				final candidate = line == "" ? w : line + " " + w;
				if (line != "" && font.font.width(candidate, font.size) > width) {
					out.push(line);
					line = w;
				} else {
					line = candidate;
				}
			}
			out.push(line);
		}
		return out;
	}

	// VALUES ----------------------------------------------------------------------

	function formula(source:String):Formula {
		var f = formulas.get(source);
		if (f == null) {
			f = Formula.parse(source);
			formulas.set(source, f);
		}
		return f;
	}

	function evaluate(source:String, scope:RenderScope):Null<Value> {
		try {
			return formula(source).evaluate(scope);
		} catch (e:FormulaError) {
			Trace.log("formula not read:", source + " (" + e.message + ")", 0);
			return null;
		}
	}

	function truth(source:String, scope:RenderScope):Bool {
		final v = evaluate(source, scope);
		return v == null ? true : v.truth();
	}

	function textOf(source:String, scope:RenderScope):String {
		if (source == "") {
			return "";
		}
		final v = evaluate(source, scope);
		return v == null ? "" : StringTools.replace(v.text(), "\r\n", "\n");
	}

	function number(source:String, scope:RenderScope):Float {
		final v = evaluate(source, scope);
		return v == null ? 0 : v.number();
	}

	function color(source:String, scope:RenderScope):Int {
		final v = evaluate(source, scope);
		return v == null ? 0 : Colors.toRgb(Std.int(v.number()));
	}

	/** The first value each field has along a chain of fonts, innermost first. **/
	function resolve(chain:Array<FontSpec>, scope:RenderScope):ResolvedFont {
		var face:Null<String> = null;
		var size:Null<String> = null;
		var bold:Null<String> = null;
		var italic:Null<String> = null;
		var underline:Null<String> = null;
		var colour:Null<String> = null;
		for (f in chain) {
			if (face == null) face = f.face;
			if (size == null) size = f.size;
			if (bold == null) bold = f.bold;
			if (italic == null) italic = f.italic;
			if (underline == null) underline = f.underline;
			if (colour == null) colour = f.color;
		}
		final faceName = face == null ? "" : textOf(face, scope);
		final points = size == null ? 0.0 : number(size, scope);
		return {
			font: fonts.find(faceName == "" ? "Arial" : faceName, bold != null && truth(bold, scope), italic != null && truth(italic, scope)),
			size: points > 0 ? points : 10,
			color: colour == null ? 0 : color(colour, scope),
			underline: underline != null && truth(underline, scope)
		};
	}
}

/**
	List & Label's line spacing, measured from its PDF output for Trebuchet MS, the face
	every shipped layout uses: 11.361 pt between 9 pt lines and 14.956 pt between 12.02 pt
	lines, with the first baseline 0.954 of the size below a table cell's padding and 0.972
	below a text object's top.
**/
class Metrics {
	public static inline function pitch(size:Float):Float {
		return 1.19040 * size + 0.6474;
	}

	public static inline function cellAscent(size:Float):Float {
		return 0.954 * size;
	}

	public static inline function textAscent(size:Float):Float {
		return 0.972 * size;
	}

	/**
		How much higher List & Label sets a centred or right-aligned paragraph of a text
		object than a left-aligned one: 0.81 to 0.91 pt, measured on five objects in four
		layouts at 9 and 12 pt. Table cells do not do this.
	**/
	public static inline final ALIGNED_RAISE = 0.86;
}

typedef ResolvedFont = {
	final font:TrueType;
	final size:Float;
	final color:Int;
	final underline:Bool;
}

typedef MeasuredCell = {
	final cell:Cell;
	/** In SCM, for this row. **/
	final width:Float;
	final font:ResolvedFont;
	final lines:Array<String>;
	final fill:Int;
	final frame:Array<DrawnSide>;
	final picture:Null<Picture>;
	final background:Null<Picture>;
}

/** A frame side as drawn: its width in points and its colour. **/
typedef DrawnSide = {
	final side:String;
	final width:Float;
	final color:Int;
}

/** A chart and the rows it draws, at an offset across its container. **/
typedef PlacedChart = {
	final table:Table;
	final rows:Array<Named>;
	final left:Float;
	final width:Float;
}

/** A table line measured for one row, or a chart, and where it went. **/
class Placed {
	public final cells:Array<MeasuredCell>;
	public final height:Float;
	public final reserved:Frame;
	public final chart:Null<PlacedChart>;
	public var y(default, null) = 0.0;
	/** How far across its container the line starts: past the columns before its own. **/
	public var x(default, null) = 0.0;

	public function new(cells:Array<MeasuredCell>, height:Float, reserved:Frame, ?chart:PlacedChart) {
		this.cells = cells;
		this.height = height;
		this.reserved = reserved;
		this.chart = chart;
	}

	public function at(y:Float, x = 0.0):Placed {
		final p = new Placed(cells, height, reserved, chart);
		p.y = y;
		p.x = x;
		return p;
	}
}

/** A row's fields over the report's variables, and the page being drawn. **/
class RenderScope implements Scope {
	public var row:Null<Named> = null;
	public var page = 1;
	public var totalPages = 1;
	/** The layout's unit and page size, in SCM, for the lengths a formula answers. **/
	public var unit = 25400.0;
	public var pageWidth = 0.0;
	public var pageHeight = 0.0;

	final variables:Named;

	public function new(variables:Named) {
		this.variables = variables;
	}

	public function lookup(name:String):Null<Value> {
		// A PDF page is printable to its edges.
		switch name.toLowerCase() {
			case "ll.device.printablearea.offset.cx" | "ll.device.printablearea.offset.cy":
				return VNumber(0);
			case "ll.device.printablearea.size.cx":
				return VNumber(pageWidth / unit);
			case "ll.device.printablearea.size.cy":
				return VNumber(pageHeight / unit);
		}
		if (row != null) {
			final v = row.lookup(name);
			if (v != null) {
				return v;
			}
		}
		return variables.lookup(name);
	}

	public function call(name:String, args:Array<Value>):Null<Value> {
		return switch name {
			case "page": VNumber(page);
			case "page$": VText(Std.string(page));
			case "totalpages$": VText(Std.string(totalPages));
			case "totalpages": VNumber(totalPages);
			case "lastpage": VBool(page == totalPages);
			case "printpassindex": VNumber(1);
			case "printpasscount": VNumber(1);
			// A length given in SCM, in the layout's unit, as positions are written.
			case "unitfromscm": args.length > 0 ? VNumber(args[0].number() / unit) : null;
			default: null;
		}
	}
}
