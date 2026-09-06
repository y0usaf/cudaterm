"""Graphics placement and mouse coordinates at non-default cell dimensions."""
import argparse
import struct
from test_graphics import Host, upload

p = argparse.ArgumentParser()
p.add_argument('--host',required=True)
args = p.parse_args()
for width,height in ((8,24),(12,36),(16,32)):
    host = Host(args.host,40,12)
    try:
        host.command(b'D',struct.pack('<2i',width,height))
        assert host.feed(b'\x1b[16t') == f'\x1b[6;{height};{width}t'.encode()
        host.feed(b'\x1b[?25l\x1b[2;2H')
        raw = bytes((23,45,67,255))*13*49
        assert b'OK' in host.feed(upload(raw,13,49))
        pixels = host.pixels()
        stride = 40*width*4
        for y in range(49):
            start = (height+y)*stride + width*4
            assert pixels[start:start+13*4] == raw[y*13*4:(y+1)*13*4]
        assert pixels[(height-1)*stride+width*4:(height-1)*stride+width*4+4] == b'\0\0\0\xff'
        host.feed(b'\x1b[?1000h\x1b[?1016h')
        reply = host.command(b'M',struct.pack('<7i',0,1,1,0,0,width+2,height+3))
        assert reply == f'\x1b[<0;{width+3};{height+4}M'.encode()
    finally: host.close()
print('PASS: image placement, cell-size queries and pixel mouse at three cell sizes')
