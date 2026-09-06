"""Headless CUDA input latency while a real compressed image is decoding."""
import argparse
import json
from pathlib import Path
import random
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tests'))
from test_graphics import Host, upload

p = argparse.ArgumentParser()
p.add_argument('--host', required=True)
p.add_argument('--output', required=True)
args = p.parse_args()
host = Host(args.host, 160, 90)
try:
    host.feed(b'\x1b[?1049h\x1b[?25l\x1b[?1000h\x1b[?1006h')
    host.command(b'H')
    raw = bytes(v for x in random.Random(17).randbytes(1024 * 1024) for v in (x, x, x, 255))
    stream = upload(raw, 1024, 1024)
    start = time.monotonic()
    assert b'OK' in host.feed(stream)
    elapsed = (time.monotonic() - start) * 1000
    report = json.loads(host.command(b'P'))
    report.update(binary=str(Path(args.host).resolve()), upload_ms=elapsed,
                  scope='GPU snapshot and mouse reports during CUDA decode; no desktop input injection')
    pixels = host.pixels()
    for y in range(1024):
        assert pixels[y * 1280 * 4:(y * 1280 + 1024) * 4] == raw[y * 1024 * 4:(y + 1) * 1024 * 4]
    Path(args.output).write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))
    assert report['calls'] >= 3 and report['ended'] == 1 and report['mouse_bytes'] >= 27
    assert report['maximum_ms'] < 50, 'input blocked behind image decoding'
finally:
    host.close()
