"""Exercise the installed editor's real TUI, resizing and UTF-8 file editing."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import pty
import select
import struct
import subprocess
import tempfile
import termios
import time

from test_graphics import Host

p = argparse.ArgumentParser()
p.add_argument('--host', required=True)
p.add_argument('--nvim', required=True)
p.add_argument('--output', required=True)
args = p.parse_args()
with tempfile.TemporaryDirectory(prefix='cudaterm-nvim-') as directory:
    root = Path(directory)
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH',40,120,960,960))
    gpu = Host(args.host,120,40)
    gpu.command(b'D',struct.pack('<2i',8,24))
    env = dict(os.environ,TERM='xterm-256color',COLORTERM='truecolor',
               XDG_STATE_HOME=str(root/'state'),XDG_CACHE_HOME=str(root/'cache'))
    env.pop('DISPLAY',None); env.pop('WAYLAND_DISPLAY',None)
    process = subprocess.Popen([args.nvim,'-n','-i','NONE','--cmd',
        f'autocmd VimEnter * call writefile(["ready"], "{root}/ready")',str(root/'edit.txt')],
        stdin=slave,stdout=slave,stderr=slave,env=env,start_new_session=True)
    os.close(slave)
    reply_bytes = 0
    tail = bytearray()
    def drain():
        global reply_bytes
        if select.select([master],[],[],.02)[0]:
            try: data = os.read(master,65536)
            except OSError: return
            tail.extend(data); del tail[:-4096]
            replies = gpu.feed(data)
            if replies: os.write(master,replies); reply_bytes += len(replies)
    try:
        deadline = time.monotonic()+30
        while not (root/'ready').exists():
            drain()
            if process.poll() is not None or time.monotonic()>deadline:
                raise AssertionError('editor startup failed: '+repr(bytes(tail)))
        for cols,rows in ((80,24),(140,45),(120,40)):
            gpu.command(b'W',struct.pack('<2i',cols,rows))
            fcntl.ioctl(master,termios.TIOCSWINSZ,struct.pack('HHHH',rows,cols,cols*8,rows*24))
            for _ in range(10): drain()
        expected = 'Finix daily use — café 中\n'
        os.write(master,b'i'+expected.rstrip('\n').encode())
        for _ in range(10): drain()
        os.write(master,b'\x1b')
        # A physical Escape followed by ':' is distinct from an Alt-: sequence.
        # Let the editor's escape timeout expire between those key events.
        for _ in range(10): drain()
        os.write(master,b':wq\r')
        deadline = time.monotonic()+20
        while process.poll() is None:
            drain()
            if time.monotonic()>deadline: raise AssertionError('editor save/quit hung: '+repr(bytes(tail)))
        for _ in range(3): drain()
        assert process.returncode == 0, bytes(tail)
        assert (root/'edit.txt').read_text() == expected
        report = dict(status='passed',host=os.path.realpath(args.host),nvim=os.path.realpath(args.nvim),
          reply_bytes=reply_bytes,checks=['installed Neovim TUI startup','three PTY resizes',
          'UTF-8 editing and save','clean quit'],scope='real editor PTY and CUDA parser; no desktop clipboard')
        Path(args.output).write_text(json.dumps(report,indent=2)+'\n')
        print(json.dumps(report))
    finally:
        if process.poll() is None: process.kill()
        process.wait(); os.close(master); gpu.close()
