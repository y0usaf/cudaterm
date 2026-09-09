"""Validate source parsing independently of the generated range search."""
import importlib.util
from pathlib import Path
import re
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('grapheme_properties', ROOT / 'tools/build_grapheme_properties.py')
g = importlib.util.module_from_spec(spec)
spec.loader.exec_module(g)


class Properties(unittest.TestCase):
    def test_bad_sources(self):
        for text in ('-1 ; Extend', '110000 ; Extend', '0302..0300 ; Extend',
                     '0300..0302 ; Extend\n0301 ; Extend',
                     '0302 ; Extend\n0300 ; Extend', '0300 ; Other',
                     '0300 Extend', '0300 ;', 'zzzz ; Extend'):
            with self.subTest(text=text), tempfile.TemporaryDirectory() as d:
                p = Path(d) / 'data.txt'
                p.write_text(text)
                with self.assertRaises(ValueError):
                    g.parse(p, 'Extend')

    def test_source_membership(self):
        for file, prop, count in (('emoji-data-17.0.0.txt', 'Extended_Pictographic', 2848),
                                  ('GraphemeBreakProperty-17.0.0.txt', 'Extend', 2237)):
            p = ROOT / 'data' / file
            # Independent raw set, without the generator's parse/merge/search.
            raw = set()
            for match in re.finditer(r'^([0-9A-F]+)(?:\.\.([0-9A-F]+))?\s*;\s*' + prop + r'\s*(?:#|$)', p.read_text(), re.M):
                a, b = match.groups()
                raw.update(range(int(a, 16), int(b or a, 16) + 1))
            self.assertEqual(len(raw), count)
            merged = g.parse(p, prop)
            self.assertEqual({cp for a, b in merged for cp in range(a, b + 1)}, raw)
            for a, b in merged:
                for cp in (a - 1, a, b, b + 1):
                    self.assertEqual(g.host_contains(merged, cp), cp in raw)


if __name__ == '__main__':
    unittest.main()
