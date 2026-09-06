"""Alternate old/new headless hosts to reduce drift on a shared desktop GPU."""
import argparse
import json
from pathlib import Path
import random
import statistics
import sys
import time
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tests'))
from test_graphics import Host, encoded_upload

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--reference', required=True)
parser.add_argument('--host', required=True)
parser.add_argument('--output', required=True)
args = parser.parse_args()
paths = [args.reference, args.host]
hosts = []
report = {'binaries': [str(Path(p).resolve()) for p in paths],
          'scope': 'synthetic CUDA images; shared desktop GPU; alternating host order; '
                   '12 samples per host, first two excluded from medians; Python transport included',
          'cases': {}}
try:
    for path in paths:
        hosts.append(Host(path, 318, 89))
        hosts[-1].feed(b'\x1b[?1049h\x1b[?25l')
    width, height = 1274, 1368
    for name in ('solid', 'grayscale_noise'):
        raw = (bytes((20, 40, 60, 255)) * width * height if name == 'solid' else
               bytes(v for x in random.Random(17).randbytes(width * height) for v in (x, x, x, 255)))
        stream = encoded_upload(zlib.compress(raw), width, height, 4, 7, True)
        cut = stream.rfind(b'\x1b_G')
        samples = [[], []]
        for iteration in range(12):
            for index in ((0, 1) if iteration % 2 == 0 else (1, 0)):
                host = hosts[index]
                start = time.monotonic()
                host.feed(stream[:cut])
                decode = time.monotonic()
                host.feed(stream[cut:])
                end = time.monotonic()
                pixels = host.pixels()
                for x, y in ((0, 0), (width // 2, height // 2), (width - 1, height - 1)):
                    src = (y * width + x) * 4
                    dst = (y * 318 * 8 + x) * 4
                    assert pixels[dst:dst + 4] == raw[src:src + 4]
                samples[index].append({'chunks_ms': (decode - start) * 1000,
                                       'decode_ms': (end - decode) * 1000,
                                       'total_ms': (end - start) * 1000})
        report['cases'][name] = {
            'samples': samples,
            'medians': [{key: statistics.median(s[key] for s in rows[2:])
                         for key in rows[0]} for rows in samples],
            'memory': [json.loads(host.command(b'A')) for host in hosts]}
        Path(args.output).write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({key: value['medians'] for key, value in report['cases'].items()}))
finally:
    for host in hosts:
        host.close()
