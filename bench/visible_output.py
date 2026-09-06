"""Measure PTY-write to compositor-capture observation, not physical scanout.

Requires a visible Wayland session and grim. Captures include process startup,
compositor scheduling, pixel transfer and decoding overhead; results are upper
bounds on when the changed pixels became available to capture.
"""
import argparse
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time

COLORS = [(19, 83, 157), (173, 47, 101)]
CHILD = r'''
import json, os, socket, sys, time
s = socket.socket(socket.AF_UNIX)
s.connect(sys.argv[1])
f = s.makefile('rwb', buffering=0)
time.sleep(1)
f.write((json.dumps(list(os.get_terminal_size()))+'\n').encode())
for line in f:
    request = json.loads(line)
    if request is None: break
    r, g, b = request['color']
    load = b'load output 0123456789\r\n' * request['load_lines']
    marker = f'\x1b[?25l\x1b[48;2;{r};{g};{b}m\x1b[2J\x1b[H'.encode()
    start = time.monotonic_ns()
    data = load + marker
    while data:
        data = data[os.write(1, data):]
    f.write((json.dumps({'start': start, 'geometry': list(os.get_terminal_size())})+'\n').encode())
'''


def ppm(data):
    # grim's binary PPM header; accept comments and arbitrary header whitespace.
    pos = 0
    tokens = []
    while len(tokens) < 4:
        while data[pos:pos+1].isspace():
            pos += 1
        if data[pos:pos+1] == b'#':
            pos = data.index(b'\n', pos) + 1
            continue
        end = pos
        while not data[end:end+1].isspace():
            end += 1
            if end >= len(data):
                raise ValueError('incomplete PPM header')
        tokens.append(data[pos:end])
        pos = end
    if tokens[0] != b'P6' or tokens[3] != b'255':
        raise ValueError(f'unsupported PPM header: {tokens}')
    width, height = map(int, tokens[1:3])
    pixels = data[pos+1:]
    if len(pixels) != width * height * 3:
        raise ValueError('PPM pixel length mismatch')
    return width, height, pixels


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--terminal', required=True)
    p.add_argument('--terminal-arg', action='append', default=[])
    p.add_argument('--grim', default='grim')
    p.add_argument('--region', help='grim region in compositor coordinates, e.g. 40,40 64x16')
    p.add_argument('--samples', type=int, default=10)
    p.add_argument('--load-lines', type=int, default=0)
    args = p.parse_args()
    if args.samples < 1 or args.load_lines < 0:
        p.error('samples must be positive and load-lines nonnegative')
    command = [args.terminal, *args.terminal_arg]
    captures = []

    def capture():
        start = time.monotonic_ns()
        capture_command = [args.grim, '-s', '1', '-t', 'ppm']
        if args.region:
            capture_command += ['-g', args.region]
        raw = subprocess.check_output(capture_command + ['-'], timeout=5)
        width, height, pixels = ppm(raw)
        end = time.monotonic_ns()
        captures.append(end - start)
        return width, height, pixels, end

    with tempfile.TemporaryDirectory(prefix='cudaterm-visible-') as folder:
        path = str(Path(folder) / 'control')
        with socket.socket(socket.AF_UNIX) as server:
            server.bind(path)
            server.listen(1)
            server.settimeout(30)
            proc = subprocess.Popen(command + [sys.executable, '-c', CHILD, path],
                                    stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
            try:
                connection, _ = server.accept()
                with connection:
                    connection.settimeout(10)
                    stream = connection.makefile('rwb', buffering=0)
                    geometry = json.loads(stream.readline())
                    coordinate = None
                    dimensions = None
                    samples = []
                    # Two calibration transitions verify this coordinate belongs
                    # to the fixture; they are excluded from measured samples.
                    for index in range(args.samples + 2):
                        color = COLORS[index % 2]
                        stream.write((json.dumps({'color': color, 'load_lines':
                            args.load_lines if index >= 2 else 0})+'\n').encode())
                        reply = json.loads(stream.readline())
                        if reply['geometry'] != geometry:
                            raise RuntimeError('terminal geometry changed during run')
                        start = reply['start']
                        deadline = time.monotonic() + 10
                        attempts = 0
                        while True:
                            width, height, pixels, end = capture()
                            attempts += 1
                            if dimensions is not None and dimensions != (width, height):
                                raise RuntimeError('capture dimensions changed during run')
                            dimensions = (width, height)
                            if coordinate is None:
                                # A solid run avoids matching a glyph or one noisy pixel.
                                offset = pixels.find(bytes(color) * 64)
                                if offset >= 0 and offset % 3 == 0:
                                    coordinate = offset + 32 * 3
                            if coordinate is not None and pixels[coordinate:coordinate+3] == bytes(color):
                                break
                            if time.monotonic() > deadline:
                                raise TimeoutError('fixture color not observed; window may be obscured')
                        if index >= 2:
                            samples.append({'write_start_ns': start, 'observed_ns': end,
                                            'duration_ns': end-start, 'captures': attempts})
                    stream.write(b'null\n')
                    stream.close()
                status = proc.wait(timeout=10)
                if status:
                    raise RuntimeError(f'terminal exited {status}: {proc.stderr.read().decode()}')
                print(json.dumps({'benchmark': 'pty-write-to-compositor-capture',
                    'terminal': os.path.realpath(args.terminal), 'command': command,
                    'cols': geometry[0], 'rows': geometry[1],
                    'capture_dimensions': dimensions, 'capture_region': args.region,
                    'sample_pixel': [coordinate // 3 % width, coordinate // 3 // width],
                    'load_lines': args.load_lines, 'samples': samples,
                    'capture_duration_ns': captures,
                    'limitations': 'Includes capture overhead; not physical scanout or input latency.'}, indent=2))
            finally:
                if proc.poll() is None:
                    proc.terminate()
                    try:
                        proc.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        proc.kill()
                        proc.wait()
                proc.stderr.close()


if __name__ == '__main__':
    main()
