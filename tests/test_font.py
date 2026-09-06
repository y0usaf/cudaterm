import struct
import tempfile
import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parents[1] / "tools"))
from build_font import build


HEADER = 16


def glyph(encoding, width, height, yoff, rows, dwidth=None):
    dwidth = width if dwidth is None else dwidth
    return "\n".join(["STARTCHAR x", f"ENCODING {encoding}",
        f"DWIDTH {dwidth} 0", f"BBX {width} {height} 0 {yoff}",
        "BITMAP", *rows, "ENDCHAR"])


class FontTest(unittest.TestCase):
    def run_bdf(self, body):
        text = "STARTFONT 2.1\nFONTBOUNDINGBOX 16 16 0 -2\nFONT_ASCENT 14\n" + body + "\n"
        with tempfile.TemporaryDirectory() as d:
            src, dst = Path(d) / "x.bdf", Path(d) / "x.bin"
            src.write_text(text)
            build(src, dst)
            return dst.read_bytes()

    def test_baseline_and_widths(self):
        data = self.run_bdf(glyph(65, 8, 2, 0, ["80", "40"]) + "\n" +
                            glyph(0x4E00, 16, 2, -2, ["8001", "4002"]))
        self.assertEqual(data[:8], b"CTFONT02")
        self.assertEqual(struct.unpack_from("<I", data, 8)[0], 65536)
        self.assertEqual(struct.unpack_from("<I", data, 12)[0], 0)
        rows = struct.unpack_from("<%dH" % (65536 * 16), data, HEADER)
        self.assertEqual(rows[65 * 16 + 12:65 * 16 + 14], (0x8000, 0x4000))
        self.assertEqual(rows[0x4E00 * 16 + 14:0x4E00 * 16 + 16], (0x8001, 0x4002))
        widths = data[HEADER + 65536 * 16 * 2:]
        self.assertEqual(widths[65], 8)
        self.assertEqual(widths[0x4E00], 16)
        self.assertEqual(widths[66], 0)

    def run_upper(self, body):
        bdf = "STARTFONT 2.1\nFONTBOUNDINGBOX 8 16 0 -2\nFONT_ASCENT 14\n"
        with tempfile.TemporaryDirectory() as d:
            src = Path(d) / "x.bdf"
            upper = Path(d) / "upper.hex"
            dst = Path(d) / "x.bin"
            src.write_text(bdf + glyph(65, 8, 1, 0, ["80"]) + "\n")
            upper.write_text(body)
            build(src, dst, upper)
            return dst.read_bytes()

    def test_supplementary_glyphs_and_sparse_pages(self):
        narrow = "80" + "00" * 15
        wide = "8001" + "0000" * 15
        data = self.run_upper(
            "000020:" + "00" * 16 + "\n"
            "010000:" + narrow + "\n"
            "020123:" + wide + "\n"
            "0E0001:" + narrow + "\n")
        count, pages = struct.unpack_from("<II", data, 8)
        self.assertEqual((count, pages), (65539, 3))
        rows_end = HEADER + count * 16 * 2
        widths_start = rows_end
        widths_end = widths_start + count
        upper_rows = HEADER + 65536 * 16 * 2
        self.assertEqual(data[upper_rows:upper_rows + 32],
                         struct.pack("<16H", *([0x8000] + [0] * 15)))
        self.assertEqual(data[upper_rows + 32:upper_rows + 34],
                         struct.pack("<H", 0x8001))
        self.assertEqual(data[widths_start + 65536], 8)
        page_table = widths_end
        self.assertEqual(struct.unpack_from("<I", data, page_table + 0x100 * 4)[0], 0)
        self.assertEqual(struct.unpack_from("<I", data, page_table + 0x201 * 4)[0], 1)
        self.assertEqual(struct.unpack_from("<I", data, page_table + 0xE00 * 4)[0], 2)
        pages_base = page_table + 0x1100 * 4
        self.assertEqual(struct.unpack_from("<I", data, pages_base + 0x00 * 4)[0], 65536)
        self.assertEqual(struct.unpack_from("<I", data, pages_base + 256 * 4 + 0x23 * 4)[0], 65537)

    def test_upper_validation(self):
        for cp in ("-1", "00D800"):
            with self.subTest(cp=cp), self.assertRaises(ValueError):
                self.run_upper(cp + ":" + "00" * 16 + "\n")
        with self.assertRaises(ValueError):
            self.run_upper("010000:" + "0 " * 16 + "\n")
        with self.assertRaises(ValueError):
            self.run_upper("010000:" + "00" * 15 + "\n")
        with self.assertRaises(ValueError):
            self.run_upper("010000:" + "00" * 16 + "\n010000:" + "00" * 16 + "\n")
        with self.assertRaises(ValueError):
            self.run_upper("110000:" + "00" * 16 + "\n")

    def test_duplicate_and_bad_width_rejected(self):
        with self.assertRaises(ValueError):
            self.run_bdf(glyph(65, 8, 1, 0, ["80"]) + "\n" + glyph(65, 8, 1, 0, ["80"]))
        with self.assertRaises(ValueError):
            self.run_bdf(glyph(65, 7, 1, 0, ["7f"]))


if __name__ == "__main__":
    unittest.main()
