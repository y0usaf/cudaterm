"""Real terminal-browser -> Ekko -> CUDA pixels, using a private local page."""
import argparse
import base64
import fcntl
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import pty
import re
import select
import struct
import subprocess
import tempfile
import termios
import threading
import time
import zlib

from test_graphics import Host, pixel_at


class Receiver:
    def __init__(self):
        self.buffer = b''
        self.pending = None
        self.images = {}
        self.cursor = (0, 0)
        self.uploads = 0

    def feed(self, data):
        self.buffer += data
        while self.buffer:
            at = self.buffer.find(b'\x1b')
            if at < 0: self.buffer = b''; return
            self.buffer = self.buffer[at:]
            if len(self.buffer) < 2: return
            if self.buffer.startswith(b'\x1b_G'):
                end = self.buffer.find(b'\x1b\\', 3)
                if end < 0: return
                header, _, payload = self.buffer[3:end].partition(b';')
                self.buffer = self.buffer[end+2:]
                fields = dict(part.split(b'=', 1) for part in header.split(b','))
                action = fields.get(b'a')
                if action == b'd':
                    self.images.pop(int(fields[b'i']), None)
                elif action == b'p':
                    image = self.images[int(fields[b'i'])]
                    image[1] = fields; image[2] = self.cursor
                else:
                    if self.pending is None: self.pending = [fields, bytearray()]
                    self.pending[1].extend(payload)
                    if fields.get(b'm', b'0') == b'0':
                        first, encoded = self.pending; self.pending = None
                        raw = zlib.decompress(base64.b64decode(encoded, validate=True))
                        assert len(raw) == int(first[b's'])*int(first[b'v'])*(int(first[b'f'])//8)
                        self.images[int(first[b'i'])] = [raw, first, self.cursor,
                                                        int(first[b's']), int(first[b'f'])//8]
                        self.uploads += 1
            elif self.buffer.startswith(b'\x1b['):
                match = re.match(rb'\x1b\[([\x20-\x3f]*)([\x40-\x7e])', self.buffer)
                if not match: return
                self.buffer = self.buffer[match.end():]
                if match[2] == b'H':
                    rows, cols = (int(v or 1) for v in match[1].split(b';'))
                    self.cursor = (cols-1, rows-1)
            else: self.buffer = self.buffer[2:]

    def check(self, pixels, stride):
        for raw, fields, cursor, width, channels in self.images.values():
            w, h = int(fields[b'w']), int(fields[b'h'])
            sx, sy = int(fields[b'x']), int(fields[b'y'])
            x = cursor[0]*8 + int(fields[b'X'])
            y = cursor[1]*16 + int(fields[b'Y'])
            for dx, dy in ((0,0),(w//2,h//2),(w-1,h-1),(w//3,h//3)):
                at = ((sy+dy)*width + sx+dx)*channels
                expected = tuple(raw[at:at+3]) + (255,)
                if channels == 3 or raw[at+3] == 255:
                    assert pixel_at(pixels, stride, x+dx, y+dy) == expected


def png(path, pixels, width, height):
    def chunk(kind, data):
        return struct.pack('>I', len(data))+kind+data+struct.pack('>I', zlib.crc32(kind+data))
    scan = b''.join(b'\0'+pixels[y*width*4:(y+1)*width*4] for y in range(height))
    Path(path).write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>2I5B',width,height,8,6,0,0,0))+
                           chunk(b'IDAT',zlib.compress(scan))+chunk(b'IEND',b''))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--host', required=True)
    parser.add_argument('--ekko', required=True)
    parser.add_argument('--browser', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    class Page(BaseHTTPRequestHandler):
        def do_GET(self):
            body = b'''<!doctype html><title>CUDA Ekko integration</title>
            <body style="margin:0;background:#1e3c78;color:white;font:32px sans-serif;height:100vh"
              onclick="document.body.style.background='#dc501e'">
              <h1>Cudaterm + Ekko</h1><p>Real browser pixels</p><p>Click anywhere to change color.</p></body>'''
            self.send_response(200); self.send_header('Content-Type','text/html')
            self.send_header('Content-Length',str(len(body))); self.end_headers(); self.wfile.write(body)
        def log_message(self, *_): pass
    server = HTTPServer(('127.0.0.1', 0), Page)
    thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
    gpu = Host(args.host, 120, 40)
    receiver = Receiver()
    with tempfile.TemporaryDirectory(prefix='cudaterm-browser-') as directory:
        root = Path(directory)
        env = dict(os.environ, XDG_RUNTIME_DIR=directory, XDG_DATA_HOME=str(root/'data'),
                   XDG_STATE_HOME=str(root/'state'), TERMINAL_BROWSER_APPDATA=str(root/'profile'),
                   TERMINAL_BROWSER_FRAMES='inline', TERMINAL_BROWSER_GRAPHICS='kitty',
                   TERM='xterm-256color', COLORTERM='truecolor')
        # Chromium uses its supported headless Ozone platform when neither
        # display variable is present. This never opens a desktop window.
        env.pop('DISPLAY',None); env.pop('WAYLAND_DISPLAY',None)
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH',40,120,960,640))
        url = f'http://127.0.0.1:{server.server_port}/'
        process = subprocess.Popen([args.ekko,'run','--session','browser-test',
                                    'bash','--noprofile','--norc','-i',':::',args.browser,'open',url],
                                   stdin=slave,stdout=slave,stderr=slave,env=env,start_new_session=True)
        os.close(slave)
        tail = bytearray()
        captures = 0
        try:
            def wait_color(color, timeout=40):
                nonlocal captures
                end = time.monotonic()+timeout
                while time.monotonic()<end:
                    if select.select([master],[],[],.05)[0]:
                        data = os.read(master,65536)
                        tail.extend(data); del tail[:-4096]
                        replies = gpu.feed(data); receiver.feed(data)
                        if replies: os.write(master,replies)
                        if not json.loads(gpu.command(b'S'))['sync'] and not receiver.pending and receiver.images:
                            pixels = gpu.pixels(); receiver.check(pixels,960); captures += 1
                            if pixels.count(bytes(color)) > 1000: return pixels
                    if process.poll() is not None: break
                raise AssertionError('browser color not rendered; terminal tail '+repr(bytes(tail)))
            pixels = wait_color((30,60,120,255))
            # Mouse events are encoded by Cudaterm, translated by Ekko, and
            # dispatched by the real browser into the local page's handler.
            for action in (0,1):
                mouse = gpu.command(b'M',struct.pack('<7i',0,25,90,0,action,724,408))
                os.write(master,mouse)
            pixels = wait_color((220,80,30,255),10)
            png(args.output+'.png',pixels,960,640)
            status = json.loads(subprocess.check_output([args.ekko,'status','browser-test'],env=env,timeout=5))
            report = dict(status='passed',uploads=receiver.uploads,pixel_checks=captures,
                          checks=['real browser beside shell','compressed frame pixel oracle','GPU mouse to DOM click'],
                          cuda_binary=os.path.realpath(args.host),ekko_binary=os.path.realpath(args.ekko),
                          browser_binary=os.path.realpath(args.browser),ekko_status=status,
                          scope='headless browser and CUDA raster; no desktop display')
            Path(args.output+'.json').write_text(json.dumps(report,indent=2)+'\n')
            print(json.dumps(report))
        finally:
            subprocess.run([args.ekko,'stop','browser-test'],env=env,stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL,timeout=5)
            subprocess.run([args.browser,'shutdown'],env=env,stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL,timeout=10)
            if process.poll() is None: process.kill()
            process.wait(); os.close(master); gpu.close(); server.shutdown(); server.server_close()
            if __import__('sys').exc_info()[0]:
                for log in (root/'state').glob('*/logs/stderr.log'):
                    print(log.read_text()[-4000:])


if __name__ == '__main__': main()
