"""Manual real-window mouse-report test for X11/Xwayland; requires xdotool."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--terminal', default='./result/bin/cudaterm')
    p.add_argument('--xdotool', default='xdotool')
    args = p.parse_args()
    expected = b'\x1b[<0;1;1M\x1b[<32;3;2M\x1b[<0;3;2m\x1b[<64;3;2M'
    child = r'''
import os, pathlib, sys, time, tty
root = pathlib.Path(sys.argv[1])
tty.setraw(0)
time.sleep(0.5)
os.write(1, b'\x1b[?1002;1006h')
(root / 'ready').touch()
data = bytearray()
while len(data) < int(sys.argv[2]):
    chunk = os.read(0, 4096)
    if not chunk: break
    data.extend(chunk)
(root / 'reports').write_bytes(data)
'''
    with tempfile.TemporaryDirectory(prefix='cudaterm-mouse-') as folder:
        root = Path(folder)
        env = os.environ.copy()
        env.pop('WAYLAND_DISPLAY', None)
        proc = subprocess.Popen([args.terminal, '-e', sys.executable, '-c', child,
                                 folder, str(len(expected))], env=env)
        try:
            deadline = time.monotonic() + 30
            while not (root / 'ready').exists():
                if proc.poll() is not None:
                    raise RuntimeError('terminal exited before fixture readiness')
                if time.monotonic() > deadline:
                    raise TimeoutError('fixture did not become ready')
                time.sleep(0.05)
            windows = subprocess.check_output(
                [args.xdotool, 'search', '--onlyvisible', '--pid', str(proc.pid)],
                text=True, timeout=5).split()
            if len(windows) != 1:
                raise RuntimeError(f'expected one owned window, got {windows}')
            subprocess.run([args.xdotool, 'windowactivate', '--sync', windows[0],
                            'mousemove', '--window', windows[0], '4', '8',
                            'sleep', '0.1', 'mousedown', '1', 'sleep', '0.1',
                            'mousemove', '--window', windows[0], '20', '24',
                            'sleep', '0.1', 'mouseup', '1', 'sleep', '0.1',
                            'click', '4'], check=True, timeout=10)
            status = proc.wait(timeout=10)
            actual = (root / 'reports').read_bytes()
            if status != 0 or actual != expected:
                raise AssertionError(f'mouse reports: status={status}, bytes={actual!r}')
            print(json.dumps({'test': 'window-mouse-reports', 'status': 'passed',
                              'terminal': os.path.realpath(args.terminal),
                              'backend': 'X11/Xwayland',
                              'reports': actual.decode('ascii')}))
        finally:
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait()


if __name__ == '__main__':
    main()
