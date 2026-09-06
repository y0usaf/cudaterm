"""Validate binary screenshot decoding without a graphical session."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    'visible_output', Path(__file__).resolve().parents[1] / 'bench/visible_output.py')
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class CaptureTests(unittest.TestCase):
    def test_pixel_whitespace_is_preserved(self):
        self.assertEqual(probe.ppm(b'P6\n# generated\n2 1\n255\n\n\r \x00\xff\x80'),
                         (2, 1, b'\n\r \x00\xff\x80'))

    def test_rejects_truncated_capture(self):
        with self.assertRaises(ValueError):
            probe.ppm(b'P6\n2 1\n255\n\x00\x00\x00')

    def test_rejects_unsupported_depth(self):
        with self.assertRaises(ValueError):
            probe.ppm(b'P6\n1 1\n65535\n' + bytes(6))


if __name__ == '__main__':
    unittest.main()
