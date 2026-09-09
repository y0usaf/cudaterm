"""Exercise native fonts, padding, live reload and zoom in an owned compositor."""
import argparse
import json
import os
from pathlib import Path
import select
import struct
import subprocess
import sys
import tempfile
import time
import tty
from PIL import Image


def child(folder):
    root = Path(folder)
    tty.setraw(0)
    (root / 'project').mkdir()
    os.chdir(root / 'project')
    content = (
        '\x1b[?25l\x1b[2J\x1b[H'
        '\x1b[1;34mCUDATERM\x1b[0m   /   workspace\r\n\r\n'
        '\x1b[32m❯\x1b[0m git status --short\r\n'
        '  \x1b[32mM\x1b[0m src/renderer.cu\r\n'
        '  \x1b[32mM\x1b[0m src/settings.hpp\r\n\r\n'
        '\x1b[1mReadable type. Precise interaction.\x1b[0m\r\n'
        '\x1b[3mRegular, bold and italic at the actual font size.\x1b[0m\r\n'
        '\x1b[9mOld bitmap zoom\x1b[0m  Native font rasterization\r\n\r\n'
        '\x1b[36mUnicode\x1b[0m   café  λ  中  →  ✓\r\n'
        '\x1b[34mPalette\x1b[0m   '
        + ''.join(f'\x1b[{40+i}m   ' for i in range(8)) + '\x1b[0m\r\n\r\n'
        'https://example.org/cudaterm\r\n'
        '\x1b[2mCtrl +/- zoom   Ctrl Shift , reload   Ctrl Shift F search\x1b[0m\r\n'
        '\x1b[32m❯\x1b[0m '
    )
    os.write(1, content.encode())
    received = bytearray()
    while not (root / 'stop').exists():
        if (root / 'history').exists() and not (root / 'history-ready').exists():
            os.write(1, ('\x1b[3J\x1b[2J\x1b[H' + ''.join(f'history line {i:02d}\r\n' for i in range(80))).encode())
            (root / 'history-ready').touch()
        if (root / 'osc-copy').exists() and not (root / 'osc-copy-ready').exists():
            import base64
            sequence = b'\x1b]52;c;' + base64.b64encode('Ekko clipboard é中\n'.encode()) + b'\x1b\\'
            for offset in range(0, len(sequence), 3):
                os.write(1, sequence[offset:offset+3])
                time.sleep(.005)
            (root / 'osc-copy-ready').touch()
        if (root / 'alternate').exists() and not (root / 'alternate-ready').exists():
            os.write(1, b'\x1b[?1049h')
            (root / 'alternate-ready').touch()
        size = os.get_terminal_size(1)
        (root / 'geometry.tmp').write_text(json.dumps([size.columns, size.lines]))
        (root / 'geometry.tmp').replace(root / 'geometry')
        ready, _, _ = select.select([0], [], [], .01)
        if ready:
            received.extend(os.read(0, 4096))
    (root / 'received').write_bytes(received)


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--terminal', required=True)
    p.add_argument('--weston', required=True)
    p.add_argument('--seat', required=True)
    p.add_argument('--wl-paste', required=True)
    p.add_argument('--output', default='bench/appearance')
    p.add_argument('--pixel-font', action='store_true', help='configured pixel-art outline font')
    args = p.parse_args()
    output = Path(args.output).resolve(); output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='cudaterm-appearance-') as folder:
        root = Path(folder)
        env = dict(os.environ, XDG_RUNTIME_DIR=folder, WAYLAND_DISPLAY='appearance',
                   CUDATERM_TEST_KEYS=str(root / 'keys'), CUDATERM_TRACE=str(root / 'trace.csv'))
        env.pop('DISPLAY', None)
        os.mkfifo(root / 'keys', 0o600)
        config = root / 'config'
        def configure(extra=''):
            config.write_text('font-family=DejaVu Sans Mono\nfont-size=14\nline-height=1.3\n'
                              'padding-x=12\npadding-y=10\ntheme=midnight\n' + extra)
        configure()
        shell = root / 'new-shell'
        shell.write_text('#!/bin/sh\npwd > "'+str(root / 'new-window-cwd')+'"\nwhile [ ! -f "'+str(root / 'new-window-stop')+'" ]; do sleep 0.05; done\n')
        shell.chmod(0o700)
        env['SHELL'] = str(shell)
        terminal = None
        with (output / 'weston.log').open('w') as log, (output / 'terminal.log').open('w') as terminal_log:
            weston = subprocess.Popen([args.weston, '--backend=headless', '--renderer=gl', '--shell=desktop',
                '--socket=appearance', '--no-config', '--debug', '--modules='+args.seat,
                '--width=1500', '--height=1000'], env=env, stdout=log, stderr=log)
            def wait(predicate, label, seconds=20):
                deadline = time.monotonic() + seconds
                while not predicate():
                    if time.monotonic() > deadline or (terminal and terminal.poll() is not None):
                        raise RuntimeError('timed out: '+label+'; see '+str(output / 'terminal.log'))
                    time.sleep(.02)
            try:
                wait(lambda: (root / 'appearance').exists(), 'compositor')
                terminal = subprocess.Popen([args.terminal, '--config', str(config), '--cols', '90', '--rows', '26',
                    '-e', sys.executable, str(Path(__file__).resolve()), '--child', folder],
                    env=env, stdout=terminal_log, stderr=terminal_log)
                def geometry():
                    return json.loads((root / 'geometry').read_text()) if (root / 'geometry').exists() else None
                wait(lambda: geometry() == [90, 26], 'initial grid')
                wait(lambda: (root / 'trace.csv').exists() and 'gl_texture_swap' in (root / 'trace.csv').read_text(), 'first frame')
                time.sleep(.3)
                with (root / 'keys').open('wb', buffering=0) as keys:
                    def chord(key, shift=False):
                        codes = [(29,1)] + ([(42,1)] if shift else []) + [(key,1),(key,0)]
                        codes += ([(42,0)] if shift else []) + [(29,0)]
                        for code, value in codes: keys.write(struct.pack('=II', code, value))
                    def capture(name, delay=.25):
                        time.sleep(delay)
                        for path in root.glob('*.png'): path.unlink()
                        subprocess.run([str(Path(args.weston).with_name('weston-screenshooter'))],
                            cwd=folder, env=env, check=True, capture_output=True, timeout=10)
                        image = Image.open(next(root.glob('*.png'))).convert('RGB').transpose(Image.Transpose.FLIP_TOP_BOTTOM)
                        image.save(output / (name+'.png'))
                        return image
                    initial = capture('midnight')
                    swaps = (root / 'trace.csv').read_text().count(',gl_texture_swap,')
                    time.sleep(.4)
                    assert (root / 'trace.csv').read_text().count(',gl_texture_swap,') == swaps, 'idle redraw loop'
                    background = (22, 27, 38)
                    points = [(x, y) for y in range(initial.height) for x in range(initial.width)
                              if initial.getpixel((x, y)) == background]
                    left, top = min(x for x,y in points), min(y for x,y in points)
                    right, bottom = max(x for x,y in points)+1, max(y for x,y in points)+1
                    terminal_image = initial.crop((left,top,right,bottom))
                    terminal_image.save(output / 'terminal.png')
                    colors = terminal_image.getcolors(terminal_image.width * terminal_image.height)
                    assert len(colors) > (32 if args.pixel_font else 300), 'font coverage lacks expected grayscale levels'
                    # Locate cells through the actual padded framebuffer, then copy
                    # a URI and a rectangle using real compositor pointer events.
                    cw = (right-left-24)//90; ch = (bottom-top-20)//26
                    def event(code,value): keys.write(struct.pack('=II',code,value))
                    def move(col,row):
                        x,y = left+12+col*cw+cw//2, top+10+row*ch+ch//2
                        event(768,(x<<16)|y)
                    def button(code,down): event(769,(code<<1)|down)
                    def clipboard(expected):
                        def matches():
                            result = subprocess.run([args.wl_paste,'--no-newline'],env=env,capture_output=True,timeout=5)
                            return result.returncode == 0 and result.stdout == expected
                        wait(matches, 'clipboard '+repr(expected))
                    move(10,13); event(29,1); button(273,1); button(273,0); event(29,0)
                    clipboard(b'https://example.org/cudaterm')
                    move(4,3); event(29,1); button(272,1); move(6,4); button(272,0); event(29,0)
                    chord(46,True)
                    clipboard(b'src\nsrc')
                    chord(13)
                    wait(lambda: geometry() and geometry()[0] < 90 and geometry()[1] < 26, 'zoom changes PTY')
                    zoom = geometry(); capture('zoom')
                    chord(11)
                    wait(lambda: geometry() == [90,26], 'zoom reset')
                    configure('theme=light\npadding-x=30\n')
                    chord(51, True)
                    wait(lambda: geometry() and geometry()[0] < 90 and geometry()[1] == 26, 'reload padding')
                    reloaded = geometry(); light = capture('light')
                    assert light.tobytes() != initial.tobytes(), 'theme did not change'
                    config.write_text('font-size=broken\n')
                    chord(51, True); time.sleep(.4)
                    assert terminal.poll() is None and geometry() == reloaded, 'invalid reload changed session'
                    rejected = capture('rejected')
                    assert rejected.tobytes() == light.tobytes(), 'invalid reload changed presentation'
                    configure()
                    chord(51, True)
                    wait(lambda: geometry() == [90,26], 'reload recovery')
                    (root / 'history').touch()
                    wait(lambda: (root / 'history-ready').exists(), 'history output')
                    time.sleep(.3)
                    event(42,1); event(102,1); event(102,0); event(42,0)
                    time.sleep(.2)
                    move(0,0); button(272,1)
                    event(768, ((left+12+16*cw)<<16) | (bottom-2))
                    time.sleep(1.2)
                    button(272,0)
                    flashed = capture('copy-flash', .02)
                    assert (255,255,175) in flashed.getdata(), 'selection did not flash on release'
                    restored = capture('copy-restored')
                    assert (255,255,175) not in restored.getdata(), 'copy flash did not expire while idle'
                    chord(46,True)
                    repeated = capture('keyboard-copy-flash', .02)
                    assert (255,255,175) in repeated.getdata(), 'keyboard copy did not flash'
                    time.sleep(.25)
                    copied = subprocess.run([args.wl_paste,'--no-newline'],env=env,capture_output=True,check=True,timeout=5).stdout
                    assert copied.startswith(b'history line 00\n') and copied.count(b'\n') >= 30, copied
                    (root / 'osc-copy').touch()
                    wait(lambda: (root / 'osc-copy-ready').exists(), 'OSC clipboard output')
                    time.sleep(.2)
                    copied = subprocess.run([args.wl_paste,'--no-newline'],env=env,capture_output=True,check=True,timeout=5).stdout
                    assert copied == 'Ekko clipboard é中\n'.encode(), copied
                    (root / 'alternate').touch()
                    wait(lambda: (root / 'alternate-ready').exists(), 'alternate screen')
                    time.sleep(.2)
                    event(42,1)
                    for key in (102,107,104,109): event(key,1); event(key,0)
                    event(42,0)
                    # Only application navigation and ordinary input reach the child.
                    keys.write(struct.pack('=II',45,1)); keys.write(struct.pack('=II',45,0))
                    time.sleep(.2)
                    chord(49, True)  # New shell window inherits the foreground CWD.
                    wait(lambda: (root / 'new-window-cwd').exists(), 'new window')
                    assert (root / 'new-window-cwd').read_text().strip() == str(root / 'project')
                    (root / 'new-window-stop').touch()
                (root / 'stop').touch()
                assert terminal.wait(timeout=10) == 0
                assert (root / 'received').read_bytes() == b'\x1b[1;2H\x1b[1;2F\x1b[5;2~\x1b[6;2~x', (root / 'received').read_bytes()
                (output / 'result.json').write_text(json.dumps({'initial':[90,26], 'zoom':zoom,
                    'reloaded':reloaded, 'native_font_colors':len(colors), 'pixel_font':args.pixel_font, 'exact_input':True,
                    'invalid_reload_preserved_window':True, 'uri_clipboard':True, 'rectangular_clipboard':True,
                    'history_drag_lines':copied.count(b'\n')+1, 'new_window_cwd':True, 'alternate_navigation_passthrough':True, 'idle_redraws':0}, indent=2)+'\n')
                print('PASS: native typography, zoom, config reload/rejection, padding and exact keyboard input')
            finally:
                if (root / 'trace.csv').exists():
                    (output / 'trace.csv').write_bytes((root / 'trace.csv').read_bytes())
                (root / 'new-window-stop').touch()
                if terminal and terminal.poll() is None:
                    terminal.terminate()
                    try: terminal.wait(timeout=5)
                    except subprocess.TimeoutExpired: terminal.kill(); terminal.wait()
                weston.terminate()
                try: weston.wait(timeout=5)
                except subprocess.TimeoutExpired: weston.kill(); weston.wait()

if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--child': child(sys.argv[2])
    else: main()
