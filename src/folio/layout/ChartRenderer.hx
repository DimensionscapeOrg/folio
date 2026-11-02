package folio.layout;

import folio.formula.Functions;
import folio.layout.Model;
import folio.layout.Renderer;
import folio.ll.Named;
import folio.pdf.PdfPage;

/**
	Draws a chart table: a bar chart in a panel, with its title, the value scale up the
	left, the categories along the bottom and, for several series, a legend.

	List & Label does not document how it lays a chart out. The distances here were
	measured from its PDFs of 21 production charts, and each is named where it is used.
	Lengths are in points.
**/
class ChartRenderer {
	final r:Renderer;

	public function new(renderer:Renderer) {
		r = renderer;
	}

	public function draw(page:PdfPage, project:Project, container:Container, placed:Placed, variables:Named) {
		final c = placed.chart.table.chart;
		final rows = placed.chart.rows;
		final scope = new RenderScope(variables);
		final font = r.resolve([container.font, project.defaultFont], scope);

		final x = Units.pt(container.common.rect.left + placed.chart.left);
		final y = Units.pt(placed.y) + PANEL_TOP;
		final w = Units.pt(placed.chart.width);
		final h = Units.pt(placed.height);

		// The panel.
		if (c.backgroundGradient) {
			page.gradient(x, y, w, h, true, [{at: 0, color: r.color(c.background, scope)}, {at: 1, color: r.color(c.background2, scope)}]);
		} else {
			page.fillRect(x, y, w, h, r.color(c.background, scope));
		}
		if (c.frame) {
			page.strokeRect(x, y, w, h, 0, 0);
		}

		// The title, centred, with the plot two of its lines and a margin below the top.
		final titleFont = r.resolve([c.titleFont, container.font, project.defaultFont], scope);
		final title = r.textOf(c.title, scope);
		final titlePitch = Metrics.pitch(titleFont.size);
		page.text(titleFont.font, titleFont.size, titleFont.color, x + (w - titleFont.font.width(title, titleFont.size)) / 2, y + TITLE_BASELINE * titlePitch, title);
		final plotTop = y + PLOT_TOP + 2 * titlePitch;

		// What each row gives: a category name and a value per series. Rows of the same
		// category are added together, and a value that is not a number counts as 0.
		final names = [];
		final values:Array<Array<Float>> = [];
		for (row in rows) {
			scope.row = row;
			final name = r.textOf(c.category, scope);
			var i = names.indexOf(name);
			if (i < 0) {
				i = names.push(name) - 1;
				values.push([for (_ in c.series) 0.0]);
			}
			for (k in 0...c.series.length) {
				final v = r.number(c.series[k].value, scope);
				if (Math.isFinite(v)) {
					values[i][k] += v;
				}
			}
		}
		scope.row = null;

		// The legend, one entry per series, centred at the foot of the panel.
		var foot = y + h;
		if (c.legend) {
			final labels = [for (s in c.series) r.textOf(s.label, scope)];
			var lw = LEGEND_PAD_LEFT + LEGEND_PAD_RIGHT;
			for (i in 0...labels.length) {
				lw += LEGEND_SWATCH + LEGEND_SWATCH_GAP + font.font.width(labels[i], font.size) + (i > 0 ? LEGEND_ENTRY_GAP : 0);
			}
			final top = y + h - LEGEND_BOTTOM - LEGEND_HEIGHT;
			var lx = x + (w - lw) / 2;
			page.fillRect(lx, top, lw, LEGEND_HEIGHT, 0xFFFFFF);
			page.strokeRect(lx, top, lw, LEGEND_HEIGHT, 0, 0);
			lx += LEGEND_PAD_LEFT;
			for (i in 0...labels.length) {
				final colour = r.color(c.series[i].color, scope);
				page.fillRect(lx, top + (LEGEND_HEIGHT - LEGEND_SWATCH) / 2, LEGEND_SWATCH, LEGEND_SWATCH, colour);
				lx += LEGEND_SWATCH + LEGEND_SWATCH_GAP;
				page.text(font.font, font.size, font.color, lx, top + LEGEND_BASELINE, labels[i]);
				lx += font.font.width(labels[i], font.size) + LEGEND_ENTRY_GAP;
			}
			foot = top;
		}

		// The plot's foot leaves room for the category names, and the category title.
		var plotBottom:Float;
		if (c.categoryUp) {
			// The longest name's ink, from where it starts to its advance's end.
			var longest = 0.0;
			for (n in names) {
				longest = Math.max(longest, font.font.width(n, font.size) - font.font.ink(n, font.size).left);
			}
			plotBottom = foot - EDGE - longest - CATEGORY_GAP;
			if (r.textOf(c.categoryTitle, scope) != "") {
				plotBottom -= Metrics.pitch(font.size) + CATEGORY_TITLE_EXTRA;
			}
		} else {
			plotBottom = foot - CATEGORY_ROW;
		}

		// The value scale, which always takes in zero, where bars stand, and the plot's
		// left edge, right of the widest value on it. The layouts' FormulaMin and
		// FormulaMax of True mean automatic: a chart of zeros still shows only 0.
		var lo = 0.0;
		var hi = 0.0;
		for (v in values) {
			for (n in v) {
				lo = Math.min(lo, n);
				hi = Math.max(hi, n);
			}
		}
		final s = scale(lo, hi);
		final ticks = [for (i in 0...s.count + 1) s.lo + i * s.step];
		final tickText = [for (t in ticks) Functions.fixed(t, c.valueDecimals)];
		var widest = 0.0;
		for (t in tickText) {
			widest = Math.max(widest, font.font.width(t, font.size));
		}
		// The value title runs up the left; the plot keeps clear of its ink.
		final valueTitle = r.textOf(c.valueTitle, scope);
		final ink = font.font.ink(valueTitle, font.size);
		final plotLeft = x + PLOT_LEFT + ink.above + ink.below + widest;
		final plotRight = x + w - PLOT_RIGHT;
		final plotW = plotRight - plotLeft;
		final plotH = plotBottom - plotTop;
		function at(v:Float):Float {
			return plotBottom - (v - s.lo) / (s.hi - s.lo) * plotH;
		}

		final middle = (Math.abs(font.font.ascent) - Math.abs(font.font.descent)) / font.font.unitsPerEm / 2 * font.size;
		final lineBox = (Math.abs(font.font.ascent) + Math.abs(font.font.descent)) / font.font.unitsPerEm * font.size;

		// Bands, grid lines, tick marks and the frame.
		if (c.zebra) {
			var i = 0;
			while (i < s.count) {
				page.fillRect(plotLeft, at(ticks[i + 1]), plotW, at(ticks[i]) - at(ticks[i + 1]), r.color(c.zebraColor, scope));
				i += 2;
			}
		}
		final frameColour = r.color(c.plotFrameColor, scope);
		for (i in 0...ticks.length) {
			final ty = at(ticks[i]);
			page.line(plotLeft, ty, plotRight, ty, 0, 0);
			page.line(plotLeft - TICK, ty, plotLeft, ty, TICK_WIDTH, frameColour);
			page.text(font.font, font.size, font.color, plotLeft - TICK_LABEL_GAP - font.font.width(tickText[i], font.size), ty + middle, tickText[i]);
		}
		page.strokeRect(plotLeft, plotTop, plotW, plotH, FRAME_WIDTH, frameColour);

		// The value title, centred up the left, its ink clear of the values beside it.
		if (valueTitle != "") {
			final length = font.font.width(valueTitle, font.size);
			final start = (plotTop + plotBottom + length) / 2;
			var near = 0.0;
			for (i in 0...ticks.length) {
				final ty = at(ticks[i]);
				if (ty + lineBox / 2 > start - length && ty - lineBox / 2 < start) {
					near = Math.max(near, font.font.width(tickText[i], font.size));
				}
			}
			final right = plotLeft - TICK_LABEL_GAP - near - VALUE_TITLE_GAP;
			page.textUp(font.font, font.size, font.color, right - ink.below, start, valueTitle);
		}

		// Bars, their values above them, and the category names below.
		final n = names.length;
		if (n == 0) {
			return;
		}
		final columnW = plotW / n;
		for (i in 0...n + 1) {
			page.line(plotLeft + i * columnW, plotBottom, plotLeft + i * columnW, plotBottom + TICK, TICK_WIDTH, frameColour);
		}
		final slots = c.byCategory ? 1 : c.series.length + 1;
		final slot = c.byCategory ? columnW : columnW / slots;
		final zero = at(Math.max(s.lo, Math.min(s.hi, 0)));
		for (i in 0...n) {
			final columnLeft = plotLeft + i * columnW;
			for (k in 0...c.series.length) {
				final series = c.series[k];
				final centre = c.byCategory ? columnLeft + columnW / 2 : columnLeft + (k + 1) * slot;
				final bw = slot * series.barWidth / 100;
				final v = values[i][k];
				final top = Math.min(at(v), zero);
				final bottom = Math.max(at(v), zero);
				final colour = c.byCategory ? categoryColour(c, i, scope) : r.color(series.color, scope);
				if (bottom - top > 0.01) {
					page.gradient(centre - bw / 2, top, bw, bottom - top, false, lit(colour));
				}
				if (series.showValues) {
					final label = series.thousands ? grouped(Functions.fixed(v, series.decimals)) : Functions.fixed(v, series.decimals);
					final baseline = Math.max(top - VALUE_ABOVE, plotTop + VALUE_TOP_MIN);
					page.text(font.font, font.size, font.color, centre - font.font.width(label, font.size) / 2, baseline, label);
				}
			}
			final centre = columnLeft + columnW / 2;
			final name = names[i];
			if (c.categoryUp) {
				// Its ink, not its line, is centred under the bar.
				final nameInk = font.font.ink(name, font.size);
				page.textUp(font.font, font.size, font.color, centre + (nameInk.above - nameInk.below) / 2, plotBottom + CATEGORY_GAP + font.font.width(name, font.size), name);
			} else {
				page.text(font.font, font.size, font.color, centre - font.font.width(name, font.size) / 2, plotBottom + CATEGORY_BASELINE, name);
			}
		}
	}

	/**
		The scale List & Label puts up the side of a bar chart, from the step at or below the
		lowest value to the step at or above the highest: the largest step of 1, 2, 2.5 or 5
		times a power of ten that makes at least 6 of them. That rule gives the scale of each
		of the 16 production charts measured.
	**/
	public static function scale(lo:Float, hi:Float):{lo:Float, hi:Float, step:Float, count:Int} {
		final range = hi - lo;
		if (range <= 0) {
			// Nothing to scale: one mark, at the foot.
			return {lo: lo, hi: lo + 1, step: 1, count: 0};
		}
		// A power of ten at or above the range makes fewer than 6 steps at any multiple.
		var power = Math.pow(10, Math.ceil(Math.log(range) / Math.log(10) + 1e-9));
		while (true) {
			for (m in [5, 2.5, 2, 1]) {
				final step = m * power;
				final first = Math.floor(lo / step + 1e-9);
				final last = Math.ceil(hi / step - 1e-9);
				if (last - first >= 6) {
					return {lo: first * step, hi: last * step, step: step, count: Std.int(last - first)};
				}
			}
			power /= 10;
		}
	}

	/** A formatted number with commas between its thousands, as "-1,234.5". **/
	public static function grouped(s:String):String {
		final sign = StringTools.startsWith(s, "-") ? "-" : "";
		final digits = s.substr(sign.length).split(".");
		var whole = digits[0];
		var out = "";
		while (whole.length > 3) {
			out = "," + whole.substr(whole.length - 3) + out;
			whole = whole.substr(0, whole.length - 3);
		}
		return sign + whole + out + (digits.length > 1 ? "." + digits[1] : "");
	}

	/**
		A category's colour: the chart's colours in turn, paler on the second time round,
		as List & Label tells categories past the tenth apart.
	**/
	function categoryColour(c:Chart, i:Int, scope:RenderScope):Int {
		final base = r.color(c.colors[i % c.colors.length], scope);
		return i < c.colors.length ? base : mix(base, PALER);
	}

	/**
		The light List & Label shines across a bar: the colour blended toward white, most
		near a third of the way across, as sampled from its bars.
	**/
	static function lit(colour:Int):Array<{at:Float, color:Int}> {
		return [for (s in LIGHT) {at: s[0], color: mix(colour, s[1])}];
	}

	static final LIGHT = [
		[0.0, 0.06], [0.1, 0.18], [0.25, 0.305], [0.3, 0.305], [0.4, 0.25],
		[0.5, 0.176], [0.6, 0.133], [0.75, 0.068], [0.9, 0.0], [1.0, 0.0]
	];

	static function mix(colour:Int, white:Float):Int {
		function channel(shift:Int):Int {
			final v = (colour >> shift) & 0xFF;
			return Math.round(v + (255 - v) * white) << shift;
		}
		return channel(16) | channel(8) | channel(0);
	}

	static inline final PALER = 0.5;

	// Measured from List & Label's PDFs, in points.
	/** The panel starts this far below where the chart is placed. **/
	static inline final PANEL_TOP = -0.18;
	/** The title's baseline below the panel's top, in title lines. **/
	static inline final TITLE_BASELINE = 1.28;
	/** The plot's top below the panel's top, besides two title lines. **/
	static inline final PLOT_TOP = 12.75;
	/**
		The plot's left edge right of the panel's, besides the widest value and the height
		of the value title's ink: 15.24 to 15.75 over the 18 charts measured.
	**/
	static inline final PLOT_LEFT = 15.5;
	static inline final PLOT_RIGHT = 8.43;
	/** Space between the panel's foot, or the legend, and what is above it. **/
	static inline final EDGE = 5.55;
	/** Space between the plot and category names that run up the page. **/
	static inline final CATEGORY_GAP = 5.35;
	static inline final CATEGORY_TITLE_EXTRA = 0.25;
	/** Room under the plot for category names written across, and their baseline. **/
	static inline final CATEGORY_ROW = 19.84;
	static inline final CATEGORY_BASELINE = 11.72;
	static inline final TICK = 4.25;
	static inline final TICK_WIDTH = 0.576;
	static inline final TICK_LABEL_GAP = 5.52;
	/** Between the value title's ink and the values beside it. **/
	static inline final VALUE_TITLE_GAP = 3.35;
	static inline final FRAME_WIDTH = 0.288;
	/** A bar's value sits this far above it, and never higher than this below the plot's top. **/
	static inline final VALUE_ABOVE = 3.45;
	static inline final VALUE_TOP_MIN = 6.5;
	static inline final LEGEND_HEIGHT = 22.65;
	static inline final LEGEND_BOTTOM = 2.8;
	static inline final LEGEND_PAD_LEFT = 8.22;
	static inline final LEGEND_PAD_RIGHT = 8.46;
	static inline final LEGEND_SWATCH = 4.6;
	static inline final LEGEND_SWATCH_GAP = 5.48;
	static inline final LEGEND_ENTRY_GAP = 11.15;
	static inline final LEGEND_BASELINE = 14.45;
}
