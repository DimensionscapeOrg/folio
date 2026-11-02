import folio.image.Picture;
import folio.layout.Model;
import folio.layout.ProjectReader;
import folio.lst.LstParser;
import folio.pdf.PdfDocument;
import haxe.io.Bytes;
import utest.Assert;

/** Pictures read from their files, carried in a layout, and written into a PDF. **/
class TestPictures extends utest.Test {
	static function read(name:String):Picture {
		return Picture.read(sys.io.File.getBytes(Fixtures.path('pictures/$name')));
	}

	static function bytes(b:Null<Bytes>):Array<Int> {
		return b == null ? null : [for (i in 0...b.length) b.get(i)];
	}

	static final SIX = [255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 255, 0, 0, 0, 128, 128, 128];

	function testAPngKeepsItsTransparencyApart() {
		final p = read("rgba.png");
		Assert.equals(2, p.width);
		Assert.equals(2, p.height);
		Assert.equals(3, p.components);
		Assert.same([255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 255], bytes(p.samples));
		Assert.same([255, 128, 0, 255], bytes(p.alpha));
	}

	function testAPalettePngOfFourBitsTakesItsColoursAndTransparency() {
		final p = read("palette.png");
		Assert.same([0, 0, 0, 255, 0, 0, 255, 255, 255], bytes(p.samples));
		Assert.same([0, 255, 255], bytes(p.alpha));
	}

	function testASixteenBitGreyPngKeepsItsHighBytes() {
		final p = read("grey16.png");
		Assert.equals(1, p.components);
		Assert.same([0x12, 0xFF], bytes(p.samples));
		Assert.isNull(p.alpha);
	}

	function testAnInterlacedPngComesTogether() {
		final p = read("interlaced.png");
		Assert.equals(9, p.width);
		var wrong = 0;
		for (y in 0...9) {
			for (x in 0...9) {
				final at = (y * 9 + x) * 3;
				if (p.samples.get(at) != x * 20 || p.samples.get(at + 1) != y * 20 || p.samples.get(at + 2) != 7) {
					wrong++;
				}
			}
		}
		Assert.equals(0, wrong);
	}

	function testBitmapsReadTopRowFirstHoweverTheyAreStored() {
		Assert.same(SIX, bytes(read("rgb24.bmp").samples));
		Assert.same(SIX, bytes(read("topdown.bmp").samples));
		Assert.same(SIX, bytes(read("pal8.bmp").samples));
	}

	function testAJpegIsKeptAsItIs() {
		final p = read("rgb.jpg");
		Assert.notNull(p.jpeg);
		Assert.equals(4, p.width);
		Assert.equals(3, p.height);
		Assert.equals(3, p.components);
		Assert.isFalse(p.inverted);
		final cmyk = read("cmyk.jpg");
		Assert.equals(4, cmyk.components);
		// Adobe writes CMYK JPEGs inverted, and says so in its marker.
		Assert.isTrue(cmyk.inverted);
	}

	function testTiffsReadByEachCompression() {
		Assert.same(SIX, bytes(read("rgb-lzw.tif").samples));
		Assert.same(SIX, bytes(read("palette.tif").samples));
		// Big-endian, deflated, each sample stored as its difference from the one before.
		Assert.same(SIX, bytes(read("motorola.tif").samples));
		final grey = read("grey-packbits.tif");
		Assert.equals(1, grey.components);
		Assert.same([76, 150, 29, 255, 0, 128], bytes(grey.samples));
	}

	function testATiffsTransparencyIsLaidOverBlackAsListAndLabelDrawsIt() {
		final p = read("rgba.tif");
		Assert.same([255, 0, 0, 0, 128, 0, 0, 0, 0, 255, 255, 255], bytes(p.samples));
		Assert.isNull(p.alpha);
	}

	function testGifsReadInterlacedOrNot() {
		Assert.same(SIX, bytes(read("rgb.gif").samples));
		Assert.same(SIX, bytes(read("interlaced.gif").samples));
	}

	function testAGifsTransparentColourPrintsAsListAndLabelPrintsIt() {
		final p = read("transparent.gif");
		Assert.same(SIX, bytes(p.samples));
		Assert.isNull(p.alpha);
	}

	function testAPictureKnowsTheResolutionItsFileStates() {
		Assert.equals(300.0, read("rgb-300.jpg").dpiX);
		Assert.equals(150.0, read("rgb-lzw.tif").dpiY);
		// 2835 pixels a metre.
		Assert.floatEquals(72.009, read("topdown.bmp").dpiX);
		// A GIF states none; List & Label takes it at 75.
		Assert.equals(75.0, read("rgb.gif").dpiX);
		// None stated: two pixels at the screen's 96 an inch.
		Assert.equals(0.0, read("grey16.png").dpiX);
		Assert.equals(1.5, read("grey16.png").pointWidth());
	}

	function testAFileFolioDoesNotReadIsNoPicture() {
		// An enhanced metafile's header.
		final emf = Bytes.alloc(88);
		emf.fill(0, 88, 0);
		emf.set(0, 1);
		emf.blit(40, Bytes.ofString(" EMF"), 0, 4);
		Assert.isNull(Picture.read(emf));
	}

	function testALayoutCarriesAPictureAsItsFileDeflated() {
		final project = ProjectReader.read(LstParser.parse(Fixtures.text("Drawing.lst")));
		final carried = [for (o in project.objects) switch o {
			case OPicture(p) if (p.common.identifier == "Carried"): p;
			default: null;
		}].filter(p -> p != null)[0];
		switch carried.source {
			case PEmbedded(b):
				Assert.equals(sys.io.File.getBytes(Fixtures.path("pictures/rgba.png")).toHex(), b.toHex());
			default:
				Assert.fail("not carried in the layout");
		}
	}

	function testAPictureOnSeveralPagesIsStoredOnce() {
		final doc = new PdfDocument();
		final p = read("rgba.png");
		doc.addPage(100, 100).picture(0, 0, 10, 10, p);
		doc.addPage(100, 100).picture(5, 5, 20, 20, p);
		final pdf = doc.toBytes();
		// The picture and its soft mask, once each.
		Assert.equals(2, count(pdf, "/Subtype /Image"));
		Assert.equals(1, count(pdf, "/SMask"));
	}

	/** How often some ASCII appears in a file, which may hold any bytes besides. **/
	static function count(b:Bytes, s:String):Int {
		var n = 0;
		for (i in 0...b.length - s.length + 1) {
			var j = 0;
			while (j < s.length && b.get(i + j) == StringTools.fastCodeAt(s, j)) {
				j++;
			}
			if (j == s.length) {
				n++;
			}
		}
		return n;
	}
}
