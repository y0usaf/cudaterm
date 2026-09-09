import tempfile
import unittest
from pathlib import Path
import sys
import unicodedata

sys.path.insert(0, str(Path(__file__).parents[1] / "tools"))
from build_widths import build


class WidthTest(unittest.TestCase):
    def run_build(self, combining="0301:-8\n"):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            c, w, o, v = root / "c", root / "w", root / "o", root / "v"
            c.write_text(combining)
            build(c, w, o, v)
            return w.read_bytes(), o.read_bytes(), v.read_text().strip()

    def test_scalar_widths_and_offset(self):
        widths, offsets, version = self.run_build()
        self.assertEqual(widths[ord("é")], 1)
        self.assertEqual(widths[0x4E00], 2)
        self.assertEqual(widths[0x0301], 0)
        self.assertEqual(widths[0x1F600], 2)
        self.assertEqual(widths[0x200D], 0)
        self.assertEqual(widths[0x00AD], 1)
        self.assertEqual(offsets[0x0301], 0xF8)  # int8(-8)
        self.assertEqual(version, unicodedata.unidata_version)

    def test_supplementary_combining(self):
        widths, offsets, _ = self.run_build("1D185:-8\n")
        self.assertEqual(widths[0x1D185], 0)
        self.assertEqual(len(offsets), 0x110000)
        self.assertEqual(offsets[0x1D185], 0xF8)

    def test_malformed_entries_rejected(self):
        for value in ("bad\n", "110000:-1\n", "0301:-129\n", "0301:1\n0301:2\n"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.run_build(value)


if __name__ == "__main__":
    unittest.main()
