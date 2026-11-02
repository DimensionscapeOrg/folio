import folio.text.Encoding;
import haxe.io.Bytes;
import utest.Assert;

class TestEncoding extends utest.Test {
	function testUtf8IsReadAsUtf8WithoutItsByteOrderMark() {
		final b = Bytes.ofHex("efbbbf41c2b642");
		Assert.equals("A¶B", Encoding.decode(b));
	}

	function testAFileThatIsNotUtf8IsReadAsWindows1252() {
		// 0xB6 is the pilcrow and 0x80 the euro sign; neither starts a UTF-8 sequence.
		Assert.equals("A¶€B", Encoding.decode(Bytes.ofHex("41b68042")));
	}

	function testATruncatedSequenceIsNotUtf8() {
		Assert.isFalse(Encoding.isUtf8(Bytes.ofHex("41e282")));
	}
}
