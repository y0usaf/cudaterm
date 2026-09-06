"""Run the real Ekko daemon/client over a PTY backed by Cudaterm's CUDA engine."""
import argparse
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import pty
import select
import struct
import subprocess
import sys
import tempfile
import termios
import time

from test_graphics import Host, pixel_at


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--host', required=True)
    parser.add_argument('--ekko-source', required=True)
    parser.add_argument('--ekko', required=True)
    args = parser.parse_args()
    fixture = Path(args.ekko_source) / 'tests/runtime.py'
    spec = importlib.util.spec_from_file_location('ekko_runtime_fixture', fixture)
    runtime = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runtime)
    oracle = runtime.Host()
    gpu = Host(args.host, 120, 40)
    captures = 0
    clients = []
    master = None
    with tempfile.TemporaryDirectory(prefix='cudaterm-ekko-') as directory:
        root = Path(directory)
        env = dict(os.environ, XDG_RUNTIME_DIR=directory, TERM='xterm-256color', COLORTERM='truecolor')

        def control(action):
            return subprocess.check_output([args.ekko, action, 'cuda-test'], env=env, timeout=5)

        def start(command):
            nonlocal master
            master, slave = pty.openpty()
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 40, 120, 960, 640))
            process = subprocess.Popen([args.ekko, *command], stdin=slave, stdout=slave,
                                       stderr=slave, env=env, start_new_session=True)
            os.close(slave)
            clients.append(process)
            return process

        def capture():
            nonlocal captures
            if json.loads(gpu.command(b'S'))['sync'] or oracle.pending:
                return
            pixels = gpu.pixels()
            for color, x, y, width, height in oracle.images.values():
                for px, py in ((x,y), (x+width-1,y), (x,y+height-1),
                               (x+width-1,y+height-1), (x+width//2,y+height//2)):
                    actual = pixel_at(pixels, 960, px, py)
                    assert actual == color, (px, py, actual, color)
            captures += 1

        def pump(seconds):
            end = time.monotonic() + seconds
            while time.monotonic() < end:
                if select.select([master], [], [], .02)[0]:
                    try:
                        data = os.read(master, 65536)
                    except OSError:
                        return
                    if not data:
                        return
                    replies = gpu.feed(data)
                    oracle.feed(data)
                    if replies:
                        os.write(master, replies)
                    capture()

        def until(predicate, seconds=5):
            end = time.monotonic() + seconds
            while time.monotonic() < end:
                pump(.05)
                if predicate(): return
            raise AssertionError('Ekko condition timed out: ' + repr(bytes(oracle.output[-500:])))

        def received(color):
            path = root / f'{color}.input'
            return path.read_bytes() if path.exists() else b''

        try:
            process = start(['run', '--session', 'cuda-test', sys.executable, str(fixture),
                             '--child', directory, 'red', ':::', sys.executable, str(fixture),
                             '--child', directory, 'blue'])
            until(lambda: len(oracle.images) == 2 and not oracle.pending)
            capture()
            assert process.poll() is None
            os.write(master, b'LEFT\x022RIGHT')
            until(lambda: b'LEFT' in received('red') and b'RIGHT' in received('blue'))
            mouse = gpu.command(b'M', struct.pack('<7i', 0, 2, 61, 0, 0, 489, 39))
            assert mouse == b'\x1b[<0;490;40M', mouse
            os.write(master, mouse)
            until(lambda: b'\x1b[<0;10;24M' in received('blue'))
            os.write(master, b'\x1b[200~\x02q\x1b[201~')
            pump(.15)
            assert json.loads(control('status'))['attached']
            os.write(master, b'\x021DELETE')
            until(lambda: len(oracle.images) == 1)
            assert next(iter(oracle.images.values()))[0] == (0,0,255,255)
            process.kill(); process.wait(timeout=3)
            os.close(master); master = None
            time.sleep(.15)
            before = json.loads(control('status'))
            assert not before['attached']
            # A new viewer reconstructs the scene; reuse the CUDA terminal to
            # exercise clearing previous alternate-screen images on re-entry.
            oracle = runtime.Host()
            start(['attach', 'cuda-test'])
            until(lambda: len(oracle.images) == 1)
            os.write(master, b'\x022PAUSE')
            pump(.3)
            uploads = oracle.uploads
            os.write(master, b'\x02z')
            until(lambda: json.loads(control('status'))['panes'][1]['cols'] == 120)
            pump(.2)
            os.write(master, b'\x02z\x02s')
            until(lambda: oracle.images and next(iter(oracle.images.values()))[1] == 0)
            capture()
            assert oracle.uploads == uploads, 'layout reuploaded image'
            assert oracle.placements > 0
            control('stop')
            pump(.2)
            for process in clients: process.wait(timeout=3)
            assert not json.loads(gpu.command(b'S'))['sync']
            print(json.dumps({'status': 'passed', 'cuda_pixel_checks': captures,
                              'checks': ['real Ekko PTYs', 'compressed image pixels', 'two-pane clipping',
                                         'keyboard routing', 'GPU pixel mouse', 'paste', 'scoped deletion',
                                         'client death/reattach', 'zoom/swap', 'placement reuse', 'shutdown'],
                              'scope': 'headless CUDA engine, no desktop presentation'}))
        finally:
            subprocess.run([args.ekko, 'stop', 'cuda-test'], env=env,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
            for process in clients:
                if process.poll() is None: process.kill()
                process.wait()
            if master is not None: os.close(master)
            gpu.close()


if __name__ == '__main__':
    main()
