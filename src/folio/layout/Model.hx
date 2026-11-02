package folio.layout;

/**
	A List & Label layout as folio draws it. Lengths are in the layout's own unit, SCM
	(a thousandth of a millimetre), as the file writes them; `Units.pt` turns them into
	points. Anything that decides per page or per row (conditions, texts, fill colours) is
	kept as formula text and evaluated when the page is drawn.
**/
class Units {
	public static inline function pt(scm:Float):Float {
		return scm * 72 / 25400;
	}

	public static inline function toScm(pt:Float):Float {
		return pt * 25400 / 72;
	}
}

typedef Rect = {
	final left:Float;
	final top:Float;
	final width:Float;
	final height:Float;
}

/**
	A font as far as a section says; null fields are inherited. Each is a formula, since a
	layout can make a row bold, or red, by its values: `Cond(Label == "Total", True, False)`.
**/
typedef FontSpec = {
	final ?face:String;
	final ?size:String;
	final ?bold:String;
	final ?italic:String;
	final ?underline:String;
	final ?color:String;
}

typedef Project = {
	final pageWidth:Float;
	final pageHeight:Float;
	final defaultFont:FontSpec;
	final layers:Map<Int, String>;
	final objects:Array<LayoutObject>;
	/**
		The length a formula's number stands for, in SCM: an inch (25,400) when the layout
		is set to inches, as every shipped one is, or a millimetre (1,000).
	**/
	final unit:Float;
	/** The layout's own folder, which relative file names start from. **/
	final folder:String;
}

enum LayoutObject {
	OText(o:TextObject);
	OContainer(o:Container);
	OLine(o:LineObject);
	ORectangle(o:RectangleObject);
	OPicture(o:PictureObject);
	/** An object folio does not draw yet, by kind, so the trace can name it. **/
	OOther(kind:String, common:Common);
}

typedef Common = {
	final identifier:String;
	final rect:Rect;
	/**
		Any of `left`, `top`, `width` and `height` the layout gives as a formula, in the
		layout's unit, which takes the place of that number in `rect`.
	**/
	final placed:Map<String, String>;
	final layer:Int;
	final condition:String;
}

typedef TextObject = {
	final common:Common;
	final paragraphs:Array<Paragraph>;
	final bottomAligned:Bool;
	final frame:Array<FrameSide>;
}

/** A straight line across its object's rectangle. **/
typedef LineObject = {
	final common:Common;
	/**
		2 runs across through the middle of the rectangle, 3 down through its middle,
		0 from the top left corner to the bottom right and 1 from the bottom left to the top right.
	**/
	final direction:Int;
	/** Width 0 is a hairline. **/
	final width:Float;
	final color:String;
}

typedef RectangleObject = {
	final common:Common;
	/** Formulas: whether the outline is drawn, and whether the inside is filled. **/
	final frame:String;
	final fill:String;
	final width:Float;
	final color:String;
	final fillColor:String;
}

/** A picture fitted into its object's rectangle. **/
typedef PictureObject = {
	final common:Common;
	final source:PictureSource;
	/** Keep the picture's proportions rather than stretch it to fill the rectangle. **/
	final isotropic:Bool;
	/**
		Where an isotropic picture sits in the space it leaves: 0 centred, 1 tiled from the
		top left, 2 left top, 3 left bottom, 4 right top, 5 right bottom, 6 left middle,
		7 right middle, 8 centre top, 9 centre bottom; past 9 as 9.
	**/
	final alignment:Int;
	/** Draw the picture at the size its file states, placed by `alignment`, rather than fitted. **/
	final originalSize:Bool;
}

enum PictureSource {
	/** The picture's file, carried in the layout. **/
	PEmbedded(bytes:haxe.io.Bytes);
	/** A file named by the layout, relative to the layout's own folder when not absolute. **/
	PFile(path:String);
	/** A file named by the value of a variable or field. **/
	PVariable(name:String);
}

/** A side of an object's frame that may be drawn. Width 0 is a hairline. **/
typedef FrameSide = {
	/** Left, Top, Right or Bottom. **/
	final side:String;
	/** A formula; the side is drawn when it is true, as a row's values can decide. **/
	final line:String;
	final width:Float;
	final color:String;
}

typedef Paragraph = {
	final text:String;
	final condition:String;
	final font:FontSpec;
	/** 0 left, 1 centre, 2 right, 3 justified. **/
	final align:Int;
	final wrap:Bool;
	/** Drop the paragraph when its text is empty. **/
	final spaceOptimization:Bool;
}

typedef Container = {
	final common:Common;
	final font:FontSpec;
	final tables:Array<Table>;
	/**
		A table object rather than a report container. Table objects are fed the same rows
		together and start together; a container's tables are filled one after another.
	**/
	final tableObject:Bool;
}

typedef Table = {
	final id:String;
	final kind:String;
	final condition:String;
	final distanceTop:Float;
	/** The table starts on a new page, unless it is already at the top of one. **/
	final wrapBefore:Bool;
	final header:Array<TableLine>;
	final body:Array<TableLine>;
	final footer:Array<TableLine>;
	/**
		How many columns the container's width is split into for this table, and the space
		between them. Consecutive charts of two columns fill the left then the right. A list
		table's rows run down one column and on into the next; consecutive list tables of the
		same columns share them.
	**/
	final columns:Int;
	final columnGap:Float;
	/** The table starts at the top of the next column, unless it is the first in its columns. **/
	final columnBreakBefore:Bool;
	/** A chart's fixed height; list tables are as tall as their rows. **/
	final height:Float;
	final chart:Null<Chart>;
}

/**
	A bar chart. Each row of the table is a category along the bottom; each series gives
	the row a bar, its height a value against the scale up the left.
**/
typedef Chart = {
	final title:String;
	final titleFont:FontSpec;
	final category:String;
	/** Category names run up the page, under their bars. **/
	final categoryUp:Bool;
	/** A title under the category names; space is kept for it even when it is blank. **/
	final categoryTitle:String;
	final series:Array<Series>;
	/** One series, coloured category by category from `colors`, rather than series by series. **/
	final byCategory:Bool;
	final legend:Bool;
	final valueTitle:String;
	final valueDecimals:Int;
	/** Every other band of the scale, from the bottom, is filled with `zebraColor`. **/
	final zebra:Bool;
	final zebraColor:String;
	final background:String;
	final background2:String;
	final backgroundGradient:Bool;
	final frame:Bool;
	final plotFrameColor:String;
	final colors:Array<String>;
}

typedef Series = {
	final value:String;
	final label:String;
	/** Null when the chart colours by category. **/
	final color:Null<String>;
	/** The bar's width as a percentage of the space it has. **/
	final barWidth:Float;
	final showValues:Bool;
	final decimals:Int;
	/** The values over the bars group their thousands, as "1,200". **/
	final thousands:Bool;
}

typedef TableLine = {
	final condition:String;
	final font:FontSpec;
	final cells:Array<Cell>;
	/** Space kept clear around the line: its cells start `reserved.left` in. **/
	final reserved:Frame;
}

typedef Frame = {
	final left:Float;
	final top:Float;
	final right:Float;
	final bottom:Float;
}

typedef Cell = {
	final text:String;
	final condition:String;
	final width:Float;
	/** A width that depends on the row, as a formula in the layout's unit, or empty. **/
	final widthFormula:String;
	final align:Int;
	/** 0 top, 1 middle, 2 foot: where text goes in a cell a taller one beside it makes taller. **/
	final valign:Int;
	final wrap:Bool;
	final font:FontSpec;
	final padding:Frame;
	/** A formula; the cell is filled when it is true. **/
	final fill:String;
	final fillColor:String;
	final spaceOptimization:Bool;
	/** The sides of the cell's frame that may be drawn, along the cell's edges. **/
	final frame:Array<FrameSide>;
	/**
		A height the cell keeps whatever it holds, in SCM, or as a formula in the layout's
		unit when `fixedHeightFormula` is not empty; 0 for none.
	**/
	final fixedHeight:Float;
	final fixedHeightFormula:String;
	/** A cell written `Drawing(name)` holds a picture, as tall as its `height`, and no text. **/
	final picture:Null<CellPicture>;
	/** A picture under the cell's text, over the whole cell. **/
	final background:Null<CellPicture>;
}

typedef CellPicture = {
	final source:PictureSource;
	/** The space a picture cell's picture takes, in SCM; a background takes the cell's. **/
	final height:Float;
	final isotropic:Bool;
	/** As a picture object's `alignment`. **/
	final alignment:Int;
}
