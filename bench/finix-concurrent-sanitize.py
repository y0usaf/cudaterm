"""Instrumented decoder/input correctness; intentionally no latency threshold."""
import json
from pathlib import Path
import random
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tests'))
from test_graphics import Host, upload
h=Host(sys.argv[1],40,24)
try:
    h.feed(b'\x1b[?1049h\x1b[?25l\x1b[?1000;1006h')
    h.command(b'H')
    raw=bytes(v for x in random.Random(18).randbytes(256*256) for v in (x,x,x,255))
    assert b'OK' in h.feed(upload(raw,256,256))
    pixels=h.pixels()
    for y in range(256):
        assert pixels[y*320*4:(y*320+256)*4]==raw[y*256*4:(y+1)*256*4]
    report=json.loads(h.command(b'P'))
    assert report['ended']==1 and report['calls']>0 and report['mouse_bytes']>0
    print(json.dumps(report))
finally: h.close()
