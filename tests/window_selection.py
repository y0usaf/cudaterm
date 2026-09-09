"""Manual X11/Xwayland selection integration test; requires a graphical session."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--terminal', default='./result/bin/cudaterm')
    parser.add_argument('--xdotool', default='xdotool')
    parser.add_argument('--mouse', action='store_true', help='Shift selection while application tracking is enabled')
    parser.add_argument('--auto-copy', action='store_true', help='paste after release without pressing Copy')
    parser.add_argument('--rapid', action='store_true', help='send drag events without pacing')
    parser.add_argument('--history', action='store_true', help='copy text after it leaves the live screen')
    parser.add_argument('--curses', action='store_true', help='copy a border drawn by ncurses')
    args = parser.parse_args()
    if args.curses and args.history:
        parser.error('--curses and --history are separate fixtures')
    expected = '┌──┐' if args.curses else 'COPY é中 é'
    child = r'''
import os, pathlib, sys, time, tty
root = pathlib.Path(sys.argv[1])
tty.setraw(0)
time.sleep(0.5)
if sys.argv[2] == 'curses':
    import curses
    curses.initscr()
    curses.noecho()
    window = curses.newwin(3, 4, 0, 0)
    window.border()
    window.refresh()
    tty.setraw(0)
else:
    os.write(1, '\x1b[2J\x1b[H\x1b[?25lCOPY é中 é'.encode())
if sys.argv[2] == 'history':
    os.write(1, ('\r\n' + ''.join('later output\r\n' for _ in range(os.get_terminal_size().lines + 5))).encode())
if sys.argv[3] == 'mouse':
    os.write(1, b'\x1b[?1002;1006h')
(root / 'ready').touch()
result = bytearray()
while True:
    c = os.read(0, 1)
    if c == b'\r': break
    if not c: raise RuntimeError('PTY closed before pasted input')
    result.extend(c)
(root / 'pasted').write_bytes(result)
'''
    with tempfile.TemporaryDirectory(prefix='cudaterm-selection-') as folder:
        root = Path(folder)
        env = os.environ.copy()
        # Exercise Xwayland when the desktop also exposes Wayland.
        env.pop('WAYLAND_DISPLAY', None)
        if args.curses:
            env['NCURSES_NO_UTF8_ACS'] = '0'
        proc = subprocess.Popen([args.terminal, '-e', sys.executable, '-c', child,
                                 folder, 'curses' if args.curses else 'history' if args.history else 'live',
                                 'mouse' if args.mouse else 'local'], env=env)
        try:
            deadline = time.monotonic() + 30
            while not (root / 'ready').exists():
                if proc.poll() is not None:
                    raise RuntimeError('terminal exited before child ready')
                if time.monotonic() > deadline:
                    raise TimeoutError('terminal child did not become ready')
                time.sleep(0.05)
            windows = subprocess.check_output(
                [args.xdotool, 'search', '--onlyvisible', '--pid', str(proc.pid)],
                text=True, timeout=5).split()
            if len(windows) != 1:
                raise RuntimeError(f'expected one owned X11 window, got {windows}')
            window = windows[0]
            def xdo(*commands):
                subprocess.run([args.xdotool, *commands], check=True, timeout=5)
            xdo('windowactivate', '--sync', window)
            if args.history:
                xdo('key', 'shift+Prior')
                time.sleep(0.1)
                xdo('mousemove', '--window', window, '40', '40', 'click', '5', 'click', '4')
                time.sleep(0.1)
            # 8x16 cells: include COPY, accented Latin, both CJK halves, and e+mark.
            drag = ['mousemove', '--window', window, '4', '8']
            if not args.rapid: drag += ['sleep', '0.1']
            if args.mouse: drag += ['keydown', 'Shift_L']
            drag += ['mousedown', '1']
            if not args.rapid: drag += ['sleep', '0.1']
            drag += ['mousemove', '--window', window, '28' if args.curses else '76', '8']
            if not args.rapid: drag += ['sleep', '0.1']
            if args.mouse: drag += ['keyup', 'Shift_L']
            xdo(*drag, 'mouseup', '1')
            time.sleep(0.2)
            if not args.auto_copy:
                xdo('key', 'ctrl+shift+c')
            time.sleep(0.1)
            xdo('key', 'ctrl+shift+v', 'Return')
            status = proc.wait(timeout=10)
            actual = (root / 'pasted').read_text()
            if status != 0 or actual != expected:
                raise AssertionError(f'clipboard roundtrip: status={status}, text={actual!r}')
            print(json.dumps({'test': 'window-selection-clipboard', 'status': 'passed',
                              'terminal': os.path.realpath(args.terminal),
                              'backend': 'X11/Xwayland', 'rapid': args.rapid, 'mouse': args.mouse, 'history': args.history, 'curses': args.curses, 'text': actual}, ensure_ascii=False))
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
