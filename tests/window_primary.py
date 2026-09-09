"""Primary-selection roundtrips in a private, headless Sway compositor."""
import argparse
import json
import os
from pathlib import Path
import select
import subprocess
import sys
import tempfile
import time
import tty


def child(folder):
    root = Path(folder)
    tty.setraw(0)
    os.write(1, '\x1b[?25l\x1b[2J\x1b[Hselect me 界 é\x1b[?2004h'.encode())
    (root / 'ready').touch()
    received = bytearray()
    tracking = False
    keyboard = False
    keyboard_done = False
    while not (root / 'stop').exists():
        if (root / 'mouse').exists() and not tracking:
            os.write(1, b'\x1b[?1000h\x1b[?1006h')
            tracking = True
            (root / 'mouse-ready').touch()
        if (root / 'keyboard').exists() and not keyboard:
            os.write(1, b'\x1b[>1u\x1b[?u')
            keyboard = True
        if (root / 'keyboard-pop').exists() and not keyboard_done:
            os.write(1, b'\x1b[<u\x1b[?u')
            keyboard_done = True
        if select.select([0], [], [], .02)[0]:
            data = os.read(0, 65536)
            if not data:
                break
            received.extend(data)
            (root / 'received').write_bytes(received)


def main(args):
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    processes = []
    with tempfile.TemporaryDirectory(prefix='cudaterm-primary-') as folder:
        root = Path(folder)
        env = dict(os.environ, XDG_RUNTIME_DIR=folder, WLR_BACKENDS='headless',
                   WLR_HEADLESS_OUTPUTS='1', WLR_RENDERER='gles2', XDG_SESSION_TYPE='wayland',
                   CUDATERM_TRACE=str(output / 'trace.csv'))
        render_node = args.render_node
        if not render_node:
            render_node = next(('/dev/dri/' + node.name for node in Path('/sys/class/drm').glob('renderD*')
                                if (node / 'device/vendor').read_text().strip() == '0x10de'), None)
        if render_node:
            env['WLR_RENDER_DRM_DEVICE'] = render_node
        for key in ('DISPLAY', 'WAYLAND_DISPLAY', 'SWAYSOCK'):
            env.pop(key, None)
        config = root / 'sway.conf'
        config.write_text('output HEADLESS-1 mode 1000x700\nseat seat0 fallback true\n'
                          'default_border none\nfocus_follows_mouse no\nxwayland disable\n')
        with (output / 'sway.log').open('w') as sway_log, (output / 'terminal.log').open('w') as terminal_log:
            def wait(predicate, label, seconds=20):
                deadline = time.monotonic() + seconds
                while not predicate():
                    if processes and processes[-1].poll() is not None:
                        raise RuntimeError(f'fixture process exited during {label}; logs in {output}')
                    if time.monotonic() >= deadline:
                        raise RuntimeError(f'timed out: {label}; logs in {output}')
                    time.sleep(.02)

            def run(command, **kwargs):
                return subprocess.run(command, env=env, check=True, capture_output=True,
                                      timeout=10, **kwargs)

            try:
                sway = subprocess.Popen([args.sway, '--unsupported-gpu', '--config', str(config)],
                                        env=env, stdout=sway_log, stderr=sway_log)
                processes.append(sway)
                wait(lambda: list(root.glob('wayland-*')) and list(root.glob('sway-ipc*.sock')), 'private compositor')
                env['WAYLAND_DISPLAY'] = next(p.name for p in root.glob('wayland-*') if not p.name.endswith('.lock'))
                env['SWAYSOCK'] = str(next(root.glob('sway-ipc*.sock')))
                inputs = subprocess.Popen([args.input], env=env, stdin=subprocess.PIPE,
                                          stdout=subprocess.PIPE, stderr=terminal_log,
                                          text=True, bufsize=1)
                processes.append(inputs)
                if not select.select([inputs.stdout], [], [], 5)[0] or inputs.stdout.readline().strip() != 'ready':
                    raise RuntimeError('virtual input initialization failed')

                def event(kind, first, second):
                    inputs.stdin.write(f'{kind} {first} {second}\n')
                    inputs.stdin.flush()
                    if not select.select([inputs.stdout], [], [], 5)[0] or inputs.stdout.readline().strip() != 'ok':
                        raise RuntimeError('virtual input delivery failed')

                def middle():
                    event('b', 274, 1)
                    event('b', 274, 0)
                def press(code, modifiers=()):
                    for modifier in modifiers: event('k', modifier, 1)
                    event('k', code, 1)
                    event('k', code, 0)
                    for modifier in reversed(modifiers): event('k', modifier, 0)
                terminal = subprocess.Popen([args.terminal, '--no-config', '--font-family', 'bitmap',
                    '--padding-x', '0', '--padding-y', '0', '--app-id', 'cudaterm-primary-test',
                    '-e', sys.executable, str(Path(__file__).resolve()), '--child', folder],
                    env=dict(env, **({'WAYLAND_DEBUG': 'client'} if args.ime else {})), stdout=terminal_log, stderr=terminal_log)
                processes.append(terminal)
                wait(lambda: (root / 'ready').exists(), 'terminal child')
                swaymsg = str(Path(args.sway).with_name('swaymsg'))

                def command(text):
                    result = json.loads(run([swaymsg, '-r', text]).stdout)
                    assert all(item['success'] for item in result), result

                wait(lambda: b'cudaterm-primary-test' in run([swaymsg, '-r', '-t', 'get_tree']).stdout,
                     'mapped terminal window')
                command('[app_id="cudaterm-primary-test"] focus')
                time.sleep(.3)
                (output / 'inputs.json').write_bytes(run([swaymsg, '-r', '-t', 'get_inputs']).stdout)
                (output / 'tree.json').write_bytes(run([swaymsg, '-r', '-t', 'get_tree']).stdout)
                event('m', 4, 8)
                event('b', 272, 1)
                event('m', 68, 8)
                event('b', 272, 0)

                def primary_matches(expected):
                    result = subprocess.run([args.wl_paste, '--primary', '--no-newline'],
                                            env=env, capture_output=True, timeout=5)
                    (output / 'primary-last.bin').write_bytes(result.stdout)
                    (output / 'primary-last.stderr').write_bytes(result.stderr)
                    return result.returncode == 0 and result.stdout == expected

                wait(lambda: primary_matches(b'select me'), 'selection ownership')
                event('c', 0, 0)
                time.sleep(.1)
                assert terminal.poll() is None, 'cancelled primary transfer killed terminal'
                wait(lambda: primary_matches(b'select me'), 'selection survives cancelled reader')
                event('m', 60, 8)
                expected = bytearray()

                def received():
                    return (root / 'received').read_bytes() if (root / 'received').exists() else b''

                def external_copy(text, primary):
                    owner = subprocess.Popen([args.wl_copy, '--foreground'] + (['--primary'] if primary else []),
                                             stdin=subprocess.PIPE, env=env, stdout=subprocess.DEVNULL,
                                             stderr=terminal_log)
                    processes.append(owner)
                    owner.stdin.write(text)
                    owner.stdin.close()

                payload = 'external 界 é\n'.encode() * 16384
                external_copy(payload, True)
                wait(lambda: primary_matches(payload), 'external primary owner')
                middle()
                expected.extend(b'\x1b[200~' + payload + b'\x1b[201~')
                wait(lambda: received() == expected, 'bracketed primary paste with backpressure')

                external_copy(b'clipboard only', False)
                time.sleep(.2)
                event('k', 42, 1)
                event('k', 110, 1)
                event('k', 110, 0)
                event('k', 42, 0)
                expected.extend(b'\x1b[200~clipboard only\x1b[201~')
                wait(lambda: received() == expected, 'independent clipboard paste')
                assert primary_matches(payload), 'clipboard ownership replaced primary selection'

                (root / 'mouse').touch()
                wait(lambda: (root / 'mouse-ready').exists(), 'application mouse mode')
                time.sleep(.1)
                middle()
                # The pointer remains at column 8, row 1 (SGR coordinates).
                expected.extend(b'\x1b[<1;8;1M\x1b[<1;8;1m')
                wait(lambda: received() == expected, 'application mouse owns middle click')
                event('k', 42, 1)
                middle()
                event('k', 42, 0)
                expected.extend(b'\x1b[200~' + payload + b'\x1b[201~')
                wait(lambda: received() == expected, 'Shift-middle local override')
                if args.ime:
                    if not args.grim:
                        raise RuntimeError('--ime needs --grim to verify composition rendering')
                    method = subprocess.Popen([args.ime], env=env, stdin=subprocess.PIPE,
                                              stdout=subprocess.PIPE, stderr=terminal_log,
                                              bufsize=0)
                    processes.append(method)
                    method_output = bytearray()

                    def method_response(wanted):
                        deadline = time.monotonic() + 10
                        while time.monotonic() < deadline:
                            while b'\n' in method_output:
                                end = method_output.index(b'\n')
                                line = bytes(method_output[:end]).decode().strip()
                                del method_output[:end + 1]
                                with (output / 'ime-protocol.log').open('a') as log:
                                    log.write(line + '\n')
                                if line == wanted: return
                            if select.select([method.stdout], [], [], .1)[0]:
                                data = os.read(method.stdout.fileno(), 4096)
                                method_output.extend(data)
                                if not data:
                                    raise RuntimeError('input method fixture exited')
                        raise RuntimeError('input method did not respond: ' + wanted)

                    def method_command(command):
                        method.stdin.write((command + '\n').encode())
                        method.stdin.flush()
                        method_response('ok')

                    method_response('active')
                    before_preedit = run([args.grim, '-']).stdout
                    (output / 'ime-before.png').write_bytes(before_preedit)
                    method_command('g')
                    event('k', 48, 1)  # b goes to the input method's keyboard grab.
                    event('k', 48, 0)
                    time.sleep(.15)
                    assert received() == expected, 'IME-grabbed key leaked into PTY'
                    method_command('p 界é')
                    time.sleep(.2)
                    preedit = run([args.grim, '-']).stdout
                    (output / 'ime-preedit.png').write_bytes(preedit)
                    assert preedit != before_preedit, 'IME preedit was not rendered'
                    assert received() == expected, 'uncommitted preedit leaked into PTY'
                    method_command('c 界é')
                    expected.extend('界é'.encode())
                    wait(lambda: received() == expected, 'IME commit exactly once')
                    time.sleep(.2)
                    restored = run([args.grim, '-']).stdout
                    (output / 'ime-restored.png').write_bytes(restored)
                    assert restored == before_preedit, 'IME commit did not clear preedit overlay'
                    method_command('g')  # Return physical shortcuts to Cudaterm.
                    press(33, (29, 42))   # Ctrl-Shift-F opens local search.
                    time.sleep(.15)
                    search_before = run([args.grim, '-']).stdout
                    method_command('p 界')
                    time.sleep(.15)
                    search_preedit = run([args.grim, '-']).stdout
                    assert search_preedit != search_before, 'IME search preedit was not rendered'
                    method_command('c 界')
                    time.sleep(.15)
                    assert received() == expected, 'IME search composition escaped into PTY'
                    press(1)  # Escape closes local search.
                    time.sleep(.15)
                    assert run([args.grim, '-']).stdout == before_preedit, 'closing IME search did not restore screen'
                    method_command('p 界')
                    run([str(Path(args.sway).with_name('swaymsg')), 'workspace', 'number', '2'])
                    # Sway retains text-input focus on an empty workspace.
                    # Focus a real second view to exercise protocol leave.
                    blur_window = subprocess.Popen([args.terminal, '--no-config', '--font-family', 'bitmap',
                        '--app-id', 'cudaterm-ime-blur', '-e', sys.executable, '-c', 'import time; time.sleep(60)'],
                        env=env, stdout=terminal_log, stderr=terminal_log)
                    processes.append(blur_window)
                    method_response('inactive')
                    (output / 'ime-unfocused-tree.json').write_bytes(run([str(Path(args.sway).with_name('swaymsg')), '-t', 'get_tree']).stdout)
                    run([str(Path(args.sway).with_name('swaymsg')), 'workspace', 'number', '1'])
                    def focus_restored():
                        screenshot = run([args.grim, '-']).stdout
                        (output / 'ime-focus-restored.png').write_bytes(screenshot)
                        return screenshot == before_preedit
                    wait(focus_restored, 'IME preedit cleared after focus loss', seconds=5)
                    blur_window.terminate()
                    blur_window.wait(timeout=5)
                    processes.remove(blur_window)
                    method.terminate()
                    method.wait(timeout=5)
                    processes.remove(method)
                    event('k', 48, 1)
                    event('k', 48, 0)
                    expected.extend(b'b')
                    wait(lambda: received() == expected, 'ordinary typing after input method exit')
                if args.keyboard:
                    (root / 'keyboard').touch()
                    expected.extend(b'\x1b[?1u')
                    wait(lambda: received() == expected, 'Kitty keyboard flag negotiation')

                    press(1)              # Escape
                    press(23, (29,))      # Ctrl-I
                    press(15)             # Tab
                    press(30, (29, 42))   # Ctrl-Shift-A
                    press(26, (56,))      # Alt-[
                    press(103)            # Up
                    press(59)             # F1
                    press(30)             # ordinary a, from character callback
                    expected.extend(b'\x1b[27u\x1b[105;5u\t\x1b[97;6u\x1b[91;3u\x1b[A\x1b[P' + b'a')
                    wait(lambda: received() == expected, 'exact Kitty disambiguated input without duplicate characters')
                    (root / 'keyboard-pop').touch()
                    expected.extend(b'\x1b[?0u')
                    wait(lambda: received() == expected, 'Kitty keyboard restore')
                    press(1)
                    press(23, (29,))
                    press(30, (56,))
                    expected.extend(b'\x1b\t\x1ba')
                    wait(lambda: received() == expected, 'legacy keyboard restored after pop')
                (root / 'stop').touch()
                assert terminal.wait(timeout=10) == 0
                (output / 'result.json').write_text(json.dumps({
                    'status': 'passed', 'backend': 'private headless Sway',
                    'terminal': os.path.realpath(args.terminal), 'primary_bytes': len(payload),
                    'selection_owner': True, 'primary_paste': True,
                    'cancelled_reader': True,
                    'clipboard_independent': True, 'mouse_tracking_override': True,
                    'kitty_keyboard': args.keyboard,
                    'ime': bool(args.ime),
                }, indent=2) + '\n')
                print('PASS: primary ownership/paste, cancellation, clipboard independence, mouse override' +
                      (', Kitty keyboard' if args.keyboard else '') + (', IME composition/search/focus' if args.ime else ''))
            finally:
                (root / 'stop').touch()
                if (root / 'received').exists():
                    (output / 'received.bin').write_bytes((root / 'received').read_bytes())
                for process in reversed(processes):
                    if process.poll() is None:
                        process.terminate()
                        try:
                            process.wait(timeout=3)
                        except subprocess.TimeoutExpired:
                            process.kill()
                            process.wait(timeout=3)


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--child':
        child(sys.argv[2])
    else:
        parser = argparse.ArgumentParser(description=__doc__)
        parser.add_argument('--terminal', required=True)
        parser.add_argument('--sway', required=True)
        parser.add_argument('--input', required=True)
        parser.add_argument('--render-node')
        parser.add_argument('--keyboard', action='store_true')
        parser.add_argument('--ime', help='private input-method-v2 fixture binary')
        parser.add_argument('--grim', help='private compositor screenshot client')
        parser.add_argument('--wl-copy', required=True)
        parser.add_argument('--wl-paste', required=True)
        parser.add_argument('--output', default='bench/primary-window')
        main(parser.parse_args())
