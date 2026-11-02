import folio.layout.ChartRenderer;
import folio.layout.Model;
import folio.layout.ProjectReader;
import folio.lst.LstParser;
import utest.Assert;

class TestChart extends utest.Test {
	var tables:Array<Table>;

	function setup() {
		final project = ProjectReader.read(LstParser.parse(Fixtures.text("Chart.lst")));
		tables = switch project.objects[0] {
			case OContainer(c): c.tables;
			default: [];
		}
	}

	/** Every chart scale measured from List & Label's PDFs of production reports. **/
	function testTheScaleIsListAndLabels() {
		final measured:Array<Array<Float>> = [
			// lowest, highest value; lowest, highest mark; step
			[-58, 147, -75, 150, 25], [-39, 100, -50, 100, 25], [0, 580, 0, 600, 100],
			[-13.7, 21, -15, 25, 5], [-1.5, 11.8, -2.5, 12.5, 2.5], [0, 9, 0, 9, 1],
			[-0.4, 8, -1, 8, 1], [-17.6, 26.9, -20, 30, 5], [-0.5, 4.3, -1, 5, 1],
			[0, 54.2, 0, 60, 10], [0, 107.7, 0, 120, 20], [0, 1271, 0, 1500, 250],
			[0, 34.8, 0, 35, 5], [0, 7253, 0, 8000, 1000], [0, 1200, 0, 1200, 200],
			[0, 104, 0, 120, 20]
		];
		for (m in measured) {
			final s = ChartRenderer.scale(m[0], m[1]);
			Assert.floatEquals(m[2], s.lo, 1e-9, 'lowest mark for ${m[0]}..${m[1]}');
			Assert.floatEquals(m[3], s.hi, 1e-9, 'highest mark for ${m[0]}..${m[1]}');
			Assert.floatEquals(m[4], s.step, 1e-9, 'step for ${m[0]}..${m[1]}');
		}
	}

	function testAValueMayGroupItsThousands() {
		Assert.equals("1,200", ChartRenderer.grouped("1200"));
		Assert.equals("-1,234,567.50", ChartRenderer.grouped("-1234567.50"));
		Assert.equals("999", ChartRenderer.grouped("999"));
		Assert.equals("-100.5", ChartRenderer.grouped("-100.5"));
	}

	function testAChartOfZerosHasOneMark() {
		final s = ChartRenderer.scale(0, 0);
		Assert.equals(0, s.count);
		Assert.equals(0.0, s.lo);
	}

	function testAOneSeriesChartMayNameItsCategoriesOnTheYAxis() {
		final t = tables[1];
		Assert.equals("Cost", t.id);
		Assert.equals(2, t.columns);
		Assert.equals(991.0, t.columnGap);
		Assert.equals(100000.0, t.height);
		final c = t.chart;
		Assert.notNull(c);
		Assert.equals("Cost.Label", c.category);
		Assert.isFalse(c.categoryUp);
		Assert.isTrue(c.byCategory);
		Assert.isFalse(c.legend);
		Assert.equals(1, c.series.length);
		Assert.equals("Val(Cost.Val1)", c.series[0].value);
		Assert.isTrue(c.series[0].showValues);
		Assert.equals(0, c.series[0].decimals);
		Assert.isTrue(c.series[0].thousands);
		// No formatter on the scale: List & Label's two decimals.
		Assert.equals(2, c.valueDecimals);
		Assert.equals('"$$/Year"', c.valueTitle);
		Assert.equals('"Trebuchet MS"', c.titleFont.face);
		Assert.isTrue(c.backgroundGradient);
		Assert.isTrue(c.frame);
		Assert.isTrue(c.zebra);
	}

	function testTheDesignersSchemeIsItsTenColours() {
		final c = tables[1].chart;
		Assert.equals(10, c.colors.length);
		Assert.equals("RGB(255,51,0)", c.colors[0]);
		Assert.equals("RGB(1,2,3)", c.colors[1]);
		Assert.equals("RGB(102,102,204)", c.colors[9]);
	}

	function testAGroupedChartHasASeriesPerRowItemAndALegend() {
		final c = tables[2].chart;
		Assert.equals(0, tables[2].columns);
		Assert.isFalse(c.byCategory);
		Assert.isTrue(c.legend);
		Assert.isTrue(c.categoryUp);
		Assert.equals('" "', c.categoryTitle);
		Assert.equals(2, c.series.length);
		Assert.equals('"Actual"', c.series[1].label);
		Assert.equals("RGB(0,102,204)", c.series[1].color);
		Assert.equals(45.0, c.series[1].barWidth);
		Assert.isFalse(c.series[0].showValues);
		Assert.isFalse(c.series[0].thousands);
		Assert.equals(0, c.valueDecimals);
		// A title font of Default=True is the chart's font.
		Assert.isNull(c.titleFont.face);
	}

	function testACellOfTheDefaultFrameTakesTheTablesSpacing() {
		final cells = tables[0].body[0].cells;
		Assert.equals(0.0, cells[0].padding.left);
		Assert.equals(991.0, cells[0].padding.right);
		// A cell with a frame of its own keeps its spacing.
		Assert.equals(991.0, cells[1].padding.left);
		Assert.isNull(tables[0].chart);
	}
}
