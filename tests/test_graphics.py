"""Independent RGB/RGBA oracle for the real CUDA parser and rasterizer."""
import argparse
import base64
import json
import random
import struct
import subprocess
import zlib


class Host:
    def __init__(self, executable, cols=40, rows=12):
        self.process = subprocess.Popen([executable], stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE)
        self.resize(cols, rows)

    def command(self, action, data=b''):
        self.process.stdin.write(action + struct.pack('<I', len(data)) + data)
        self.process.stdin.flush()
        header = self.process.stdout.read(4)
        if len(header) != 4:
            raise RuntimeError('CUDA host exited before response')
        size, = struct.unpack('<I', header)
        out = self.process.stdout.read(size)
        if len(out) != size:
            raise RuntimeError('truncated CUDA response')
        return out

    def feed(self, data, chunk=65536):
        return b''.join(self.command(b'F', data[i:i+chunk])
                        for i in range(0, len(data), chunk))

    def resize(self, cols, rows):
        self.cols, self.rows = cols, rows
        self.command(b'W', struct.pack('<ii', cols, rows))

    def pixels(self):
        return self.command(b'R')

    def close(self):
        self.process.stdin.close()
        try:
            code = self.process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()
            raise
        if code:
            raise RuntimeError(f'CUDA host exit {code}')


def apc(header, payload=b''):
    return b'\x1b_G' + header.encode() + b';' + payload + b'\x1b\\'


def upload(raw, width, height, channels=4, image_id=7, compressed=True,
           extra='', compressor=None):
    data = (compressor(raw) if compressor else zlib.compress(raw)) if compressed else raw
    return encoded_upload(data, width, height, channels, image_id, compressed, extra)


def encoded_upload(data, width, height, channels, image_id, compressed, extra=''):
    data = base64.b64encode(data)
    out = bytearray()
    for at in range(0, len(data), 4096):
        end = min(at + 4096, len(data))
        header = (f'a=T,t=d,f={channels*8},s={width},v={height},i={image_id},p=1,C=1'
                  + (',o=z' if compressed else '') + extra + ',') if at == 0 else ''
        out.extend(apc(header + f'm={int(end < len(data))}', data[at:end]))
    return bytes(out)


def pixel_at(pixels, stride, x, y):
    at = (y * stride + x) * 4
    return tuple(pixels[at:at+4])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--host', required=True)
    args = parser.parse_args()
    host = Host(args.host)
    count = 0
    try:
        host.feed(b'\x1b[?25l')
        rng = random.Random(4729)
        for channels in (3, 4):
            for kind in ('raw', 'stored', 'fixed', 'dynamic'):
                for chunk in (1, 7, 65536):
                    width, height = 37, 19
                    raw = bytes(rng.randrange(256) for _ in range(width*height*channels))
                    def compressor(data):
                        c = zlib.compressobj(0 if kind == 'stored' else 6,
                                             strategy=zlib.Z_FIXED if kind == 'fixed' else zlib.Z_DEFAULT_STRATEGY)
                        return c.compress(data) + c.flush()
                    host.feed(b'\x1b[H' + apc('a=d,d=A,q=2'))
                    reply = host.feed(upload(raw, width, height, channels, compressed=kind != 'raw',
                                             compressor=compressor), chunk)
                    assert reply == b'\x1b_Gi=7,p=1;OK\x1b\\', (kind, chunk, reply)
                    pixels = host.pixels()
                    for y in range(height):
                        for x in range(width):
                            at = (y*width+x)*channels
                            a = raw[at+3] if channels == 4 else 255
                            expected = tuple((v*a+127)//255 for v in raw[at:at+3]) + (255,)
                            assert pixel_at(pixels, host.cols*8, x, y) == expected, (kind, chunk, x, y)
                    count += 1
        # Highly compressed dynamic trees and overlapping LZ77 backreferences.
        raw = bytes((240, 90, 20, 255))*256*96
        host.feed(b'\x1b[H' + apc('a=d,d=A,q=2'))
        host.feed(upload(raw, 256, 96))
        assert pixel_at(host.pixels(), host.cols*8, 255, 95) == (240,90,20,255)
        count += 1
        # Ekko's native crop, intra-cell offsets, and placement updates.
        raw = bytes(v for y in range(9) for x in range(13) for v in (x*10, y*20, 80, 255))
        host.feed(apc('a=d,d=A,q=2') + b'\x1b[3;4H')
        host.feed(upload(raw, 13, 9, extra=',x=2,y=3,w=5,h=4,X=3,Y=2'))
        pixels = host.pixels()
        assert pixel_at(pixels, host.cols*8, 27, 34) == (20,60,80,255)
        assert pixel_at(pixels, host.cols*8, 31, 37) == (60,120,80,255)
        assert pixel_at(pixels, host.cols*8, 32, 37) == (0,0,0,255)
        host.feed(b'\x1b[5;6H' + apc('a=p,i=7,p=1,C=1,q=2,x=1,y=1,w=2,h=2'))
        assert pixel_at(host.pixels(), host.cols*8, 40, 64) == (10,20,80,255)
        host.feed(apc('a=d,d=i,i=7,q=2'))
        assert pixel_at(host.pixels(), host.cols*8, 40, 64) == (0,0,0,255)
        host.feed(apc('a=p,i=7,p=1,C=1,q=2'))
        assert pixel_at(host.pixels(), host.cols*8, 40, 64) == (0,0,80,255)
        count += 1
        # Truncated/corrupt compression, dimensions and canonical base64 fail
        # without replacing a previously valid image or painting partial data.
        for data in (b'bad', zlib.compress(raw)[:-1], zlib.compress(raw)[:-4]+b'\0'*4):
            reply = host.feed(encoded_upload(data, 13, 9, 4, 7, True))
            assert b'EINVAL' in reply, reply
            assert pixel_at(host.pixels(), host.cols*8, 40, 64) == (0,0,80,255)
        for command in (apc('a=T,f=32,s=1,v=1,i=8', b'AB=='),
                        apc('a=T,f=32,s=4294967295,v=8192,i=8', b'AAAA'),
                        apc('a=T,f=100,s=1,v=1,i=8', b'AAAA'),
                        apc('a=T,f=32,s=1,v=1,i=8,m=1', b'AA==')):
            assert b'EINVAL' in host.feed(command)
        count += 1
        host.feed(apc('a=d,d=I,i=7,q=2'))
        assert b'EINVAL' in host.feed(apc('a=p,i=7,p=1,C=1'))
        # Graphics transfers never retain host image copies or unused staging;
        # alternate-screen redraws must not allocate primary scrollback.
        host.feed(b'\x1bc\x1b[?1049h\x1b[?25l')
        host.feed(b'hello\r\n'*12000)
        memory = json.loads(host.command(b'A'))
        assert memory['history_capacity'] == 128, memory
        raw = bytes((20,40,60,255))*256*128
        for _ in range(5): host.feed(upload(raw,256,128))
        memory = json.loads(host.command(b'A'))
        assert memory['image_bytes'] == len(raw) and memory['transfer_bytes'] == 0, memory
        host.feed(b'\x1b[?1049l'+b'line\r\n'*500)
        assert json.loads(host.command(b'S'))['history'] > 400
        assert json.loads(host.command(b'A'))['image_bytes'] == 0
        host.feed(b'\x1bc')
        memory = json.loads(host.command(b'A'))
        assert memory['history_capacity'] == 128 and memory['image_bytes'] == 0, memory
        # Clear-screen removes images; ordinary line erase preserves them.
        host.feed(b'\x1b[?25l'+upload(bytes((20,40,60,255))*4,2,2))
        host.feed(b'\x1b[2K')
        assert pixel_at(host.pixels(),host.cols*8,0,0) == (20,40,60,255)
        host.feed(b'\x1b[2J')
        assert json.loads(host.command(b'A'))['image_bytes'] == 0
        count += 1
        # Default cursor movement scrolls the newly placed image and reserves
        # history by decoded height, even when its compressed payload is tiny.
        host.feed(b'\x1bc\x1b[?25l')
        raw = bytes((70,100,130,255))*2*8192
        host.feed(upload(raw,2,8192).replace(b',C=1', b''))
        state = json.loads(host.command(b'S'))
        assert state['history'] == 512-host.rows and state['row'] == host.rows-1, state
        assert json.loads(host.command(b'A'))['history_capacity'] >= state['history']
        pixels = host.pixels()
        assert pixel_at(pixels,host.cols*8,0,0) == (70,100,130,255)
        assert pixel_at(pixels,host.cols*8,0,host.rows*16-1) == (70,100,130,255)
        count += 1
        # A presentation barrier must not replay the last upload's allocation
        # ownership metadata and free an image that the GPU still references.
        host.feed(b'\x1bc\x1b[?25l')
        for index in range(12):
            color = (20+index,40+index,60+index,255)
            host.feed(b'\x1b[?2026h'+upload(bytes(color)*256*128,256,128)+b'\x1b[?2026l')
            assert pixel_at(host.pixels(),host.cols*8,0,0) == color
            assert json.loads(host.command(b'A'))['image_bytes'] == 256*128*4
        count += 1
        # Sliding-window wrap, stored-to-Huffman transitions, short overlapping
        # matches, and long-distance copies under different feed boundaries.
        rng = random.Random(91)
        seed = rng.randbytes(32000)
        streams = [rng.randbytes(256*128*4), (seed*5)[:256*128*4],
                   bytes(v for x in rng.randbytes(256*128) for v in (x,x,x,255))]
        for raw in streams:
            raw = bytearray(raw); raw[3::4] = b'\xff'*(len(raw)//4); raw = bytes(raw)
            for chunk in (257,65536):
                compressor = zlib.compressobj()
                data = compressor.compress(raw[:40000])+compressor.flush(zlib.Z_SYNC_FLUSH)
                data += compressor.compress(raw[40000:])+compressor.flush()
                reply = host.feed(encoded_upload(data,256,128,4,7,True),chunk)
                assert b'OK' in reply,reply
                pixels = host.pixels()
                for y in range(128):
                    assert pixels[y*host.cols*8*4:(y*host.cols*8+256)*4] == raw[y*256*4:(y+1)*256*4]
                count += 1
        # Resize must preserve a primary image anchored on an otherwise blank
        # row.  The planner must retain the blank anchor cell while reflowing;
        # dropping trimmed blanks would make this image unreachable.
        host.feed(b'\x1bc\x1b[?25l\x1b[4;5H')
        primary_color = (181, 37, 229, 255)
        primary_raw = bytes(primary_color) * 4
        host.feed(upload(primary_raw, 2, 2, image_id=21))
        assert pixel_at(host.pixels(), host.cols*8, 32, 48) == primary_color
        retained = json.loads(host.command(b'A'))
        assert retained['image_bytes'] == len(primary_raw), retained
        host.resize(60, 12)
        assert pixel_at(host.pixels(), host.cols*8, 32, 48) == primary_color
        assert json.loads(host.command(b'A'))['image_bytes'] == len(primary_raw)
        host.resize(20, 12)
        assert pixel_at(host.pixels(), host.cols*8, 32, 48) == primary_color
        assert json.loads(host.command(b'A'))['image_bytes'] == len(primary_raw)
        host.feed(apc('a=d,d=I,i=21,q=2'))
        assert json.loads(host.command(b'A'))['image_bytes'] == 0

        # Alternate-screen images are not part of primary reflow.  A geometry
        # resize must retain their physical cell anchor and allocation.
        host.feed(b'\x1b[?1049h\x1b[2;3H')
        alternate_color = (29, 207, 113, 255)
        alternate_raw = bytes(alternate_color) * 4
        host.feed(upload(alternate_raw, 2, 2, image_id=22))
        assert pixel_at(host.pixels(), host.cols*8, 16, 16) == alternate_color
        host.resize(30, 8)
        assert pixel_at(host.pixels(), host.cols*8, 16, 16) == alternate_color
        assert json.loads(host.command(b'A'))['image_bytes'] == len(alternate_raw)
        host.feed(apc('a=d,d=I,i=22,q=2') + b'\x1b[?1049l')
        assert json.loads(host.command(b'A'))['image_bytes'] == 0
        count += 2
        print(json.dumps({'graphics_cases': count, 'status': 'passed',
                          'scope': 'real CUDA parser/decode/raster, no desktop'}))
    finally:
        host.close()


if __name__ == '__main__':
    main()
