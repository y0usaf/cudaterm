"""Manual X11/Xwayland keyboard-throughput fixture; requires xdotool."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time


CHILD = r'''
import json
import pathlib
import sys
import time
import tty

root = pathlib.Path(sys.argv[1])
count = int(sys.argv[2])
tty.setraw(0)
time.sleep(0.5)
(root / 'ready').touch()
received = bytearray()
while len(received) < count:
    chunk = sys.stdin.buffer.read(min(4096, count - len(received)))
    if not chunk:
        raise RuntimeError('PTY closed before all keyboard bytes arrived')
    received.extend(chunk)
last_read_ns = time.monotonic_ns()
(root / 'received').write_bytes(received)
# Keep the terminal and its input focus owned until the parent has finished
# xdotool, so later key-release events cannot reach another window.
while not (root / 'stop').exists():
    time.sleep(0.005)
start_ns = int((root / 'injection_start_ns').read_text())
(root / 'result.json').write_text(json.dumps({
    'exact_text_pass': bytes(received) == b'a' * count,
    'received_bytes': len(received),
    'expected_bytes': count,
    'child_last_read_ns': last_read_ns,
    'injection_start_to_child_last_read_ns': last_read_ns - start_ns,
}))
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--terminal', default='./result/bin/cudaterm')
    parser.add_argument('--xdotool', default='xdotool')
    parser.add_argument('--count', type=int, default=512)
    args = parser.parse_args()
    if args.count < 1:
        parser.error('--count must be positive')

    with tempfile.TemporaryDirectory(prefix='cudaterm-keyboard-') as folder:
        root = Path(folder)
        env = os.environ.copy()
        env.pop('WAYLAND_DISPLAY', None)
        terminal_command = [args.terminal, '-e', sys.executable, '-c', CHILD,
                            folder, str(args.count)]
        proc = subprocess.Popen(terminal_command, env=env,
                                stdout=subprocess.DEVNULL,
                                stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 30
            while not (root / 'ready').exists():
                if proc.poll() is not None:
                    detail = proc.stderr.read().decode(errors='replace')
                    raise RuntimeError(f'terminal exited before readiness: {detail}')
                if time.monotonic() >= deadline:
                    raise TimeoutError('keyboard fixture did not become ready')
                time.sleep(0.05)

            windows = subprocess.check_output(
                [args.xdotool, 'search', '--onlyvisible', '--pid', str(proc.pid)],
                text=True, timeout=5).split()
            if len(windows) != 1:
                raise RuntimeError(f'expected one owned visible window, got {windows}')
            window = windows[0]
            activate_command = [args.xdotool, 'windowactivate', '--sync', window]
            subprocess.run(activate_command, check=True, timeout=5)

            text = 'a' * args.count
            type_command = [args.xdotool, 'type', '--window', window,
                            '--delay', '0', text]
            injection_start_ns = time.monotonic_ns()
            (root / 'injection_start_ns').write_text(str(injection_start_ns))
            type_started_ns = time.monotonic_ns()
            subprocess.run(type_command, check=True, timeout=30)
            type_duration_ns = time.monotonic_ns() - type_started_ns
            (root / 'stop').touch()

            proc.wait(timeout=30)
            if proc.returncode != 0:
                detail = proc.stderr.read().decode(errors='replace')
                raise RuntimeError(f'terminal exited {proc.returncode}: {detail}')
            result_path = root / 'result.json'
            if not result_path.exists():
                raise RuntimeError('keyboard child did not write a result')
            result = json.loads(result_path.read_text())
            result.update({
                'test': 'window-keyboard-input',
                'status': 'passed' if result['exact_text_pass'] else 'failed',
                'terminal': os.path.realpath(args.terminal),
                'backend': 'X11/Xwayland',
                'count': args.count,
                'window': window,
                'injection_start_ns': injection_start_ns,
                'xdotool_type_duration_ns': type_duration_ns,
                'commands': {
                    'terminal': terminal_command,
                    'activate': activate_command,
                    'type': type_command,
                },
            })
            if not result['exact_text_pass']:
                raise AssertionError(f'keyboard bytes mismatch: {result}')
            print(json.dumps(result))
        finally:
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=5)


if __name__ == '__main__':
    main()
