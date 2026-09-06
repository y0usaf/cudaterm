"""Presentation regression: retain old image through slow/coalesced updates."""
import argparse
import os
import signal
import csv
import json
import random
import select
import struct
import tty
from pathlib import Path
import subprocess
import sys
import tempfile
import time

from test_graphics import upload, apc

def stop_daemon(root, pid_name, stop_name):
    pid_file = root/pid_name
    if not pid_file.exists(): return
    pid = int(pid_file.read_text())
    try:
        pidfd = os.pidfd_open(pid)
    except ProcessLookupError:
        pid_file.unlink(missing_ok=True)
        return
    try:
        (root/stop_name).touch()
        poller = select.poll(); poller.register(pidfd, select.POLLIN)
        if not poller.poll(1000):
            try:
                signal.pidfd_send_signal(pidfd, signal.SIGTERM)
            except ProcessLookupError:
                pass
            if not poller.poll(1000):
                try:
                    signal.pidfd_send_signal(pidfd, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                if not poller.poll(1000):
                    raise RuntimeError(f'{pid_name} survived bounded cleanup')
        pid_file.unlink(missing_ok=True)
    finally:
        os.close(pidfd)


def child(directory):
    root = Path(directory)
    def send(data):
        while data:
            data = data[os.write(1, data):]
    def wait(name):
        while not (root/name).exists(): time.sleep(.01)
    def picture(color): return upload(bytes(color)*256*128,256,128)
    start, end = b'\x1b[?2026h', b'\x1b[?2026l'
    delete = apc('a=d,d=A,q=2')
    send(b'\x1b[?25l'+picture((255,0,0,255)))
    (root/'ready').touch(); wait('start')
    send(start+delete)
    for stage in ('red','green'):
        # Keep receiving data beyond the old 150 ms absolute timeout.
        for _ in range(30): send(b'\x1b[0m'); time.sleep(.02)
        (root/(stage+'.ready')).touch(); wait(stage+'.captured')
        if stage == 'red':
            # End one update and begin/delete the next in a single PTY write.
            send(picture((0,255,0,255))+end+start+delete)
    send(picture((0,0,255,255))+end)
    (root/'blue.ready').touch(); wait('stop')


def inherited_child(directory):
    root = Path(directory)
    assert Path.cwd() == root, 'child working directory ignored'
    signal.signal(signal.SIGHUP, signal.SIG_IGN)
    if os.fork() == 0:
        (root/'inherited.pid').write_text(str(os.getpid()))
        deadline = time.monotonic() + 15
        while not (root/'inherited.stop').exists() and time.monotonic() < deadline: time.sleep(.02)
        os._exit(0)
    # More than one input buffer; the terminal must retain the final output
    # and direct child's exit status despite the background PTY owner.
    data = b'x' * (256 * 1024) + b'\r\nFINAL-CHILD-OUTPUT'
    while data: data = data[os.write(1, data):]
    os._exit(23)

def inherited_race_child(directory, tag):
    root = Path(directory)
    stop = root/f'race.stop.{tag}'
    signal.signal(signal.SIGHUP, signal.SIG_IGN)
    if os.fork() == 0:
        (root/f'race.inherited.pid.{tag}').write_text(str(os.getpid()))
        deadline = time.monotonic() + 10
        while not stop.exists() and time.monotonic() < deadline: time.sleep(.01)
        os._exit(0)
    time.sleep(1)
    data = b'z' * (256 * 1024) + b'\r\nRACE-FINAL-OUTPUT-'
    while data: data = data[os.write(1, data):]
    (root/'race.ready').touch()
    os._exit(23)

def quiet_inherited_child(directory):
    root = Path(directory)
    signal.signal(signal.SIGHUP, signal.SIG_IGN)
    if os.fork() == 0:
        (root/'quiet.inherited.pid').write_text(str(os.getpid()))
        deadline = time.monotonic() + 15
        while not (root/'quiet.inherited.stop').exists() and time.monotonic() < deadline: time.sleep(.01)
        os._exit(0)
    (root/'quiet.ready').touch()
    time.sleep(1)
    os._exit(17)

def closed_slave_child(directory):
    root = Path(directory)
    (root/'closed-slave.ready').touch()
    for fd in (0, 1, 2):
        os.close(fd)
    time.sleep(1)
    os._exit(17)

def idle_close_child(directory):
    root = Path(directory)
    (root/'idle-close.ready').touch()
    deadline = time.monotonic() + 15
    while not (root/'idle-close.stop').exists() and time.monotonic() < deadline:
        time.sleep(.01)

def delayed_wake_child(directory):
    root = Path(directory)
    tty.setraw(0)
    (root/'wake.ready').touch()
    time.sleep(1)
    os.write(1, b'WAKE-OUTPUT\r\n\x1b[5n')
    response = bytearray()
    deadline = time.monotonic() + 5
    while len(response) < 4:
        remaining = deadline - time.monotonic()
        if remaining <= 0 or not select.select([0], [], [], remaining)[0]:
            raise RuntimeError('timed out waiting for DSR response')
        response.extend(os.read(0, 4-len(response)))
    (root/'wake.response').write_bytes(response)
    assert bytes(response) == b'\x1b[0n', repr(response)
    deadline = time.monotonic() + 15
    while not (root/'wake.stop').exists() and time.monotonic() < deadline: time.sleep(.01)


def decode_child(directory):
    root = Path(directory)
    tty.setraw(0)
    raw = bytes(v for x in random.Random(41).randbytes(1024 * 2048) for v in (x,x,x,255))
    data = b'\x1b[?1049h\x1b[?25l\x1b[?2026h' + upload(raw,1024,2048) + b'\x1b[?2026l'
    while data: data = data[os.write(1, data):]
    received = os.read(0, 1)
    (root/'decode.received').write_text(json.dumps({'bytes':list(received),'ns':time.monotonic_ns()}))
    while not (root/'decode.stop').exists(): time.sleep(.01)


def clipboard_child(directory, mode):
    root = Path(directory)
    tty.setraw(0)
    if mode == 4:
        # Keep the pixel coordinates below tied to the terminal geometry used
        # by this fixture, rather than silently testing a resized child.
        assert os.get_terminal_size(1).columns == 80
    if mode == 5:
        assert os.get_terminal_size(1).columns == 80
    text = ('A' * 79 + 'é' + '中\r\nAFTER') if mode in (4, 5) else 'COPY é中 é'
    os.write(1, b'\x1b[2J\x1b[H\x1b[?25l\x1b[41m \x1b[0m\r\n' + text.encode() +
             b'\x1b[?1002;1006h\x1b[?2004h')
    (root/'clipboard.ready').touch()
    if mode == 5:
        deadline = time.monotonic() + 10
        while os.get_terminal_size(1).columns != 40 or os.get_terminal_size(1).lines != 32:
            if time.monotonic() > deadline:
                raise RuntimeError('PTY did not receive private compositor resize')
            time.sleep(.01)
        (root/'clipboard.resized').write_text(json.dumps({'cols':40,'rows':32}))
    expected = (('paste é中\n' * 32768) if mode == 1 else
                'é中' if mode == 2 else
                ('A' * 79 + 'é中\nAFTER') if mode in (4, 5) else
                'COPY é中 é').encode()
    framed = b'\x1b[200~' + expected + b'\x1b[201~'
    received = bytearray()
    time.sleep(1.0)  # Deliberately let the PTY input queue fill before POLLOUT.
    while len(received) < len(framed):
        received.extend(os.read(0, min(4096, len(framed) - len(received))))
    (root/'clipboard.received').write_bytes(received)
    assert received == framed, 'clipboard bytes or bracketed-paste framing changed'
    while not (root/'clipboard.stop').exists(): time.sleep(.01)


def main():
    p=argparse.ArgumentParser()
    p.add_argument('--terminal',required=True)
    p.add_argument('--weston',required=True)
    p.add_argument('--seat',required=True)
    p.add_argument('--wl-copy',required=True)
    args=p.parse_args()
    with tempfile.TemporaryDirectory(prefix='cudaterm-sync-') as directory:
        root=Path(directory)
        env=dict(os.environ,XDG_RUNTIME_DIR=directory,WAYLAND_DISPLAY='sync-test')
        os.mkfifo(root/'keys', 0o600)
        env['CUDATERM_TEST_KEYS'] = str(root/'keys')
        env.pop('DISPLAY',None)
        with (root/'weston.log').open('w') as log:
            weston=subprocess.Popen([args.weston,'--backend=headless','--renderer=gl','--shell=desktop',
                '--socket=sync-test','--no-config','--debug','--modules='+args.seat,
                '--width=1200','--height=900'],env=env,stdout=log,stderr=log)
            terminal=None
            def wait(name):
                deadline=time.monotonic()+10
                while not (root/name).exists():
                    if time.monotonic()>deadline: raise RuntimeError('timed out: '+name)
                    time.sleep(.01)
            try:
                wait('sync-test')
                terminal=subprocess.Popen([args.terminal,'--cols','80','--rows','32','-e',sys.executable,
                    str(Path(__file__).resolve()),'--child',directory],env=env)
                wait('ready'); time.sleep(.3); (root/'start').touch()
                from PIL import Image
                for stage,color in [('red',(255,0,0)),('green',(0,255,0)),('blue',(0,0,255))]:
                    wait(stage+'.ready'); time.sleep(.05)
                    for image in root.glob('*.png'): image.unlink()
                    subprocess.run([str(Path(args.weston).with_name('weston-screenshooter'))],
                        env=env,cwd=directory,check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
                    with Image.open(next(root.glob('*.png'))) as image:
                        colors=image.convert('RGB').getcolors(image.width*image.height)
                    count=sum(n for n,c in colors if c==color)
                    assert count>=256*128,(stage,'partial frame presented',count)
                    (root/(stage+'.captured')).touch()
                (root/'stop').touch()
                assert terminal.wait(timeout=5)==0
                print('PASS: slow uploads and coalesced update boundaries retain complete frames')
                dump = root/'exit.dump'
                protocol = root/'protocol.log'
                with protocol.open('w') as trace:
                    terminal=subprocess.Popen([args.terminal,'--cols','80','--rows','32',
                        '--app-id=launcher','--title','Finix launcher',
                        '--working-directory',directory,'--dump',str(dump),'-e',sys.executable,
                        str(Path(__file__).resolve()),'--inherited-child',directory],
                        env=dict(env,WAYLAND_DEBUG='client'),stderr=trace)
                    wait('inherited.pid')
                    assert terminal.wait(timeout=10)==23, 'direct child exit status lost'
                assert 'set_app_id("launcher")' in protocol.read_text()
                assert 'set_title("Finix launcher")' in protocol.read_text()
                assert 'FINAL-CHILD-OUTPUT' in dump.read_text(), 'final child output lost'
                stop_daemon(root, 'inherited.pid', 'inherited.stop')
                print('PASS: inherited PTY closes with final output and direct child status')
                for race in range(3):
                    tag = str(race)
                    for name in (f'race.ready',f'race.inherited.pid.{tag}',f'race.stop.{tag}'):
                        (root/name).unlink(missing_ok=True)
                    dump = root/f'race-{race}.dump'
                    terminal=subprocess.Popen([args.terminal,'--cols','80','--rows','32',
                        '--dump',str(dump),'-e',sys.executable,
                        str(Path(__file__).resolve()),'--inherited-race-child',directory,tag],env=env)
                    wait('race.ready')
                    assert terminal.wait(timeout=5)==23, 'delayed inherited child status lost'
                    assert 'RACE-FINAL-OUTPUT-' in dump.read_text(), 'delayed final output lost'
                    stop_daemon(root, f'race.inherited.pid.{tag}', f'race.stop.{tag}')
                print('PASS: repeated inherited PTY final-byte race preserves output and status')
                for name in ('quiet.ready','quiet.inherited.pid','quiet.inherited.stop'):
                    (root/name).unlink(missing_ok=True)
                terminal=subprocess.Popen([args.terminal,'--cols','80','--rows','32','-e',sys.executable,
                    str(Path(__file__).resolve()),'--quiet-inherited-child',directory],env=env)
                wait('quiet.ready')
                assert terminal.wait(timeout=5)==17, 'quiet EOF with inherited PTY did not preserve direct child status'
                stop_daemon(root, 'quiet.inherited.pid', 'quiet.inherited.stop')
                print('PASS: quiet inherited PTY closes after direct child EOF and preserves status')
                (root/'closed-slave.ready').unlink(missing_ok=True)
                terminal=subprocess.Popen([args.terminal,'--cols','80','--rows','32','-e',sys.executable,
                    str(Path(__file__).resolve()),'--closed-slave-child',directory],env=env)
                wait('closed-slave.ready')
                assert terminal.wait(timeout=3)==17, 'closed-slave EOF did not preserve child status'
                print('PASS: closed-slave EOF exits after child remains alive briefly')
                (root/'idle-close.ready').unlink(missing_ok=True)
                (root/'idle-close.stop').unlink(missing_ok=True)
                idle_trace = root/'idle-close.csv'
                terminal=subprocess.Popen([args.terminal,'--cols','80','--rows','32','-e',sys.executable,
                    str(Path(__file__).resolve()),'--idle-close-child',directory],
                    env=dict(env,CUDATERM_TRACE=str(idle_trace)))
                wait('idle-close.ready')
                frame_deadline=time.monotonic()+5
                while not idle_trace.exists() or 'gl_texture_swap' not in idle_trace.read_text():
                    if terminal.poll() is not None or time.monotonic()>frame_deadline:
                        raise RuntimeError('idle-close initial frame missing')
                    time.sleep(.01)
                time.sleep(.3)
                assert terminal.poll() is None, 'idle child exited before close input'
                deadline=time.monotonic()+3
                with (root/'keys').open('wb', buffering=0) as keys:
                    keys.write(struct.pack('=II',56,1)); keys.write(struct.pack('=II',62,1))
                    keys.write(struct.pack('=II',62,0)); keys.write(struct.pack('=II',56,0))
                while terminal.poll() is None and time.monotonic() < deadline:
                    time.sleep(.01)
                if terminal.poll() is None:
                    (root/'idle-close.stop').touch()
                    terminal.terminate()
                    terminal.wait(timeout=5)
                    raise RuntimeError('Alt-F4 idle close timed out')
                assert terminal.returncode == 0, ('idle close failed', terminal.returncode)
                print('PASS: idle Alt-F4 closes the window within bounded timeout')
                for name in ('wake.ready','wake.response','wake.stop'):
                    (root/name).unlink(missing_ok=True)
                terminal=subprocess.Popen([args.terminal,'--cols','80','--rows','32','-e',sys.executable,
                    str(Path(__file__).resolve()),'--delayed-wake-child',directory],env=env)
                wait('wake.ready')
                wait('wake.response')
                assert (root/'wake.response').read_bytes()==b'\x1b[0n'
                (root/'wake.stop').touch()
                assert terminal.wait(timeout=5)==0
                print('PASS: delayed PTY output wakes event-driven waiter and DSR reply returns')
                timing = root/'decode.csv'
                terminal=subprocess.Popen([args.terminal,'--cols','80','--rows','32','-e',sys.executable,
                    str(Path(__file__).resolve()),'--decode-child',directory],
                    env=dict(env,CUDATERM_TRACE=str(timing)))
                deadline = time.monotonic() + 20
                while not timing.exists() or 'decode_input_pump' not in timing.read_text():
                    if time.monotonic() > deadline: raise RuntimeError('decode input pump never ran')
                    time.sleep(.002)
                injected = time.monotonic_ns()
                with (root/'keys').open('wb', buffering=0) as keys:
                    for key, state in ((29,1),(57,1),(57,0),(29,0)): # Ctrl-Space
                        keys.write(struct.pack('=II',key,state))
                wait('decode.received')
                received = json.loads((root/'decode.received').read_text())
                (root/'decode.stop').touch()
                assert terminal.wait(timeout=10) == 0
                with timing.open() as f:
                    pumps = [row for row in csv.DictReader(f) if row['stage'] == 'decode_input_pump']
                latency = (received['ns'] - injected) / 1e6
                assert received['bytes'] == [0], 'Ctrl-Space did not deliver NUL'
                assert received['ns'] < int(pumps[-1]['end_ns']), 'keyboard waited until decoding finished'
                assert latency < 50, ('keyboard blocked during decode',latency)
                print(f'PASS: Wayland Ctrl-Space reached the PTY during CUDA decode in {latency:.1f} ms')
                for mode in (0, 1, 2, 3, 4, 5):
                    for name in ('clipboard.ready','clipboard.received','clipboard.resized','clipboard.stop'):
                        (root/name).unlink(missing_ok=True)
                    terminal=subprocess.Popen([args.terminal,'--cols','80','--rows','32','-e',sys.executable,
                        str(Path(__file__).resolve()),'--clipboard-child',directory,str(mode)],env=env)
                    wait('clipboard.ready'); time.sleep(.3)
                    with (root/'keys').open('wb', buffering=0) as keys:
                        def event(code, value):
                            keys.write(struct.pack('=II',code,value))
                        def chord(key):
                            for code,value in ((29,1),(42,1),(key,1),(key,0),(42,0),(29,0)):
                                event(code,value)
                        if mode == 1:
                            subprocess.run([args.wl_copy], input=('paste é中\n'*32768).encode(),
                                env=env,check=True,timeout=5)
                        else:
                            if mode == 5:
                                # Weston desktop decorations consume 8 horizontal
                                # and 28 vertical pixels; request the outer size
                                # that yields the pinned 320x512 client content.
                                keys.write(struct.pack('=II', 770, (328 << 16) | 540))
                                wait('clipboard.resized')
                            for png in root.glob('*.png'): png.unlink()
                            subprocess.run([str(Path(args.weston).with_name('weston-screenshooter'))],
                                env=env,cwd=directory,check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
                            with Image.open(next(root.glob('*.png'))) as capture:
                                rgb=capture.convert('RGB')
                                marker=[(x,y) for y in range(rgb.height) for x in range(rgb.width)
                                        if rgb.getpixel((x,y)) == (128,0,0)]
                                assert len(marker)==128, ('selection origin marker',len(marker))
                                x=min(v[0] for v in marker)
                                # Weston GL screenshooter stores its framebuffer bottom-up.
                                y=rgb.height-1-max(v[1] for v in marker)+24
                            event(768,((x+4)<<16)|y); time.sleep(.05)
                            event(42,1)
                            if mode in (2, 3):
                                event(768,((x+52)<<16)|y); time.sleep(.05)
                                for _ in range(mode):
                                    event(769,(272<<1)|1); time.sleep(.04)
                                    event(769,272<<1); time.sleep(.04)
                            elif mode in (4, 5):
                                # The anchor-derived origin and 8-pixel cell
                                # width place the endpoint after AFTER.  In
                                # mode 5 this follows the private compositor
                                # resize to 40 columns (three wrapped rows and
                                # AFTER on the following row).
                                event(769,(272<<1)|1); time.sleep(.05)
                                event(768,(x+36)<<16 | (y+(48 if mode == 5 else 32))); time.sleep(.05)
                                event(769,272<<1)
                            else:
                                event(769,(272<<1)|1); time.sleep(.05)
                                event(768,((x+76)<<16)|y); time.sleep(.05)
                                event(769,272<<1)
                            event(42,0); time.sleep(.05)
                            chord(46); time.sleep(.1) # Ctrl-Shift-C
                        chord(47) # Ctrl-Shift-V
                    wait('clipboard.received')
                    expected=(('paste é中\n'*32768) if mode == 1 else
                              'é中' if mode == 2 else
                              ('A'*79+'é中\nAFTER') if mode in (4, 5) else
                              'COPY é中 é').encode()
                    assert (root/'clipboard.received').read_bytes()==b'\x1b[200~'+expected+b'\x1b[201~', repr((root/'clipboard.received').read_bytes()[:128])
                    (root/'clipboard.stop').touch()
                    assert terminal.wait(timeout=5)==0
                    print('PASS: Wayland ' + ('large external clipboard paste' if mode == 1 else f'Shift-selection mode {mode} clipboard roundtrip') +
                          ' preserves UTF-8 and bracketed-paste framing')
            finally:
                for name in ('stop', 'decode.stop', 'clipboard.stop', 'idle-close.stop', 'wake.stop'):
                    (root/name).touch()
                try:
                    stop_daemon(root, 'inherited.pid', 'inherited.stop')
                    stop_daemon(root, 'quiet.inherited.pid', 'quiet.inherited.stop')
                    for pid_file in root.glob('race.inherited.pid.*'):
                        tag = pid_file.name.rsplit('.', 1)[1]
                        stop_daemon(root, pid_file.name, f'race.stop.{tag}')
                finally:
                    try:
                        if terminal and terminal.poll() is None:
                            terminal.terminate()
                            try: terminal.wait(timeout=5)
                            except subprocess.TimeoutExpired:
                                terminal.kill(); terminal.wait(timeout=5)
                    finally:
                        weston.terminate()
                        try: weston.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            weston.kill(); weston.wait(timeout=5)



if __name__=='__main__':
    if len(sys.argv)>1 and sys.argv[1]=='--child': child(sys.argv[2])
    elif len(sys.argv)>1 and sys.argv[1]=='--inherited-child': inherited_child(sys.argv[2])
    elif len(sys.argv)>1 and sys.argv[1]=='--inherited-race-child': inherited_race_child(sys.argv[2], sys.argv[3])
    elif len(sys.argv)>1 and sys.argv[1]=='--quiet-inherited-child': quiet_inherited_child(sys.argv[2])
    elif len(sys.argv)>1 and sys.argv[1]=='--closed-slave-child': closed_slave_child(sys.argv[2])
    elif len(sys.argv)>1 and sys.argv[1]=='--idle-close-child': idle_close_child(sys.argv[2])
    elif len(sys.argv)>1 and sys.argv[1]=='--delayed-wake-child': delayed_wake_child(sys.argv[2])
    elif len(sys.argv)>1 and sys.argv[1]=='--decode-child': decode_child(sys.argv[2])
    elif len(sys.argv)>1 and sys.argv[1]=='--clipboard-child': clipboard_child(sys.argv[2],int(sys.argv[3]))
    else: main()
