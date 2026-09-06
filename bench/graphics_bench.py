"""Headless graphics stage timings; all production decoding stays in CUDA."""
import argparse
import json
from pathlib import Path
import random
import sys
import time
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tests'))
from test_graphics import Host, encoded_upload


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--host', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--repeats', type=int, default=4)
    args = parser.parse_args()
    width, height = 1274, 1368
    levels = random.Random(17).randbytes(width*height)
    cases = {'solid': bytes((20,40,60,255))*width*height,
             'grayscale_noise': bytes(v for x in levels for v in (x,x,x,255))}
    host = Host(args.host,318,89)
    report = {'binary':str(Path(args.host).resolve()), 'width':width,'height':height,
              'scope':'synthetic images, headless CUDA; shared desktop GPU; Python transport overhead included',
              'cases':{}}
    try:
        host.feed(b'\x1b[?1049h\x1b[?25l')
        for name,raw in cases.items():
            compressed = zlib.compress(raw)
            stream = encoded_upload(compressed,width,height,4,7,True)
            cut = stream.rfind(b'\x1b_G')
            samples = []
            for _ in range(args.repeats):
                t = time.monotonic(); host.feed(stream[:cut]); u = time.monotonic()
                host.feed(stream[cut:]); v = time.monotonic(); pixels = host.pixels(); r = time.monotonic()
                # Three nontrivial pixels, including the final image row.
                for x,y in ((0,0),(width//2,height//2),(width-1,height-1)):
                    src=(y*width+x)*4; dst=(y*318*8+x)*4
                    assert pixels[dst:dst+4] == raw[src:src+4]
                samples.append({'chunks_ms':(u-t)*1000,'final_decode_commit_ms':(v-u)*1000,
                                'raster_and_host_copy_ms':(r-v)*1000})
            report['cases'][name] = {'raw_bytes':len(raw),'compressed_bytes':len(compressed),
                                    'pty_bytes':len(stream),'samples':samples,
                                    'memory':json.loads(host.command(b'A'))}
            Path(args.output).write_text(json.dumps(report,indent=2)+'\n')
        print(json.dumps(report))
    finally:
        host.close()


if __name__ == '__main__': main()
