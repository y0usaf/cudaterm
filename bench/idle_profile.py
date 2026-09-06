"""Private, instrumented idle attribution; never an uninstrumented cost baseline."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

CHILD = '''import json,os,pathlib,sys,time
root=pathlib.Path(sys.argv[1])
os.write(1,b'baseline ready\\r\\n')
time.sleep(.5)
size=os.get_terminal_size()
(root/'ready').write_text(json.dumps({'terminal_pid':os.getppid(),'cols':size.columns,'rows':size.lines}))
deadline=time.monotonic()+30
while not (root/'stop').exists() and time.monotonic()<deadline: time.sleep(.05)
'''


def stop_process(process):
    if process is None or process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)


def snapshot(pid):
    root = Path('/proc') / str(pid)
    threads = []
    for task in sorted((root / 'task').iterdir()):
        fields = (task / 'stat').read_text().rsplit(')', 1)[1].split()
        counts = {}
        for line in (task / 'status').read_text().splitlines():
            key, _, value = line.partition(':')
            if key in ('voluntary_ctxt_switches', 'nonvoluntary_ctxt_switches'):
                counts[key] = int(value)
        threads.append(dict(tid=int(task.name), comm=(task/'comm').read_text().strip(),
                            state=fields[0], utime=int(fields[11]), stime=int(fields[12]),
                            wchan=(task/'wchan').read_text().strip(), **counts))
    fds = {}
    for fd in (root / 'fd').iterdir():
        try:
            fds[fd.name] = os.readlink(fd)
        except FileNotFoundError:
            pass
    return dict(realtime_ns=time.time_ns(), monotonic_ns=time.monotonic_ns(),
                threads=threads, fds=fds)


def main(term, weston, seat):
    with tempfile.TemporaryDirectory(prefix='cudaterm-idle-') as folder:
        root = Path(folder)
        env = dict(os.environ, XDG_RUNTIME_DIR=folder, WAYLAND_DISPLAY='idle-profile',
                   CUDATERM_TRACE=str(root/'frames.csv'))
        env.pop('DISPLAY', None)
        compositor = process = None
        with (root/'weston.log').open('w') as log:
            try:
                compositor = subprocess.Popen([weston, '--backend=headless', '--renderer=gl',
                    '--shell=desktop', '--socket=idle-profile', '--no-config', '--modules='+seat,
                    '--width=960', '--height=640'], env=env, stdout=log, stderr=log)
                deadline = time.monotonic()+15
                while not (root/'idle-profile').exists():
                    if compositor.poll() is not None or time.monotonic()>deadline:
                        raise RuntimeError('private Weston failed to become ready')
                    time.sleep(.01)
                command = [term, '--cols', '80', '--rows', '24', '-e', sys.executable,
                           '-c', CHILD, folder]
                if os.environ.get('IDLE_STRACE'):
                    options = ['-k'] if os.environ.get('IDLE_STACKS') == '1' else []
                    command = ['strace', '--kill-on-exit', '-f', '-tt', '-yy', *options,
                               '-o', os.environ['IDLE_STRACE'], *command]
                process = subprocess.Popen(command, env=env)
                deadline = time.monotonic()+30
                while not ((root/'ready').exists() and (root/'frames.csv').exists()
                           and 'gl_texture_swap' in (root/'frames.csv').read_text()):
                    if process.poll() is not None or time.monotonic()>deadline:
                        raise RuntimeError('terminal child/initial frame readiness failed')
                    time.sleep(.01)
                ready = json.loads((root/'ready').read_text())
                assert (ready['cols'], ready['rows']) == (80, 24), ready
                pid = ready['terminal_pid']
                assert os.path.samefile(Path('/proc')/str(pid)/'exe', term)
                time.sleep(.5)
                samples = [snapshot(pid)]
                deadline = time.monotonic()+3
                while time.monotonic()<deadline:
                    time.sleep(min(.25, max(0, deadline-time.monotonic())))
                    samples.append(snapshot(pid))
                (root/'stop').touch()
                status = process.wait(timeout=10)
                assert status == 0, status
                print(json.dumps(dict(scope='instrumented settled idle; not cost acceptance',
                    command=command, terminal_pid=pid, launcher_pid=process.pid, exit=status,
                    geometry=ready, interval_start_realtime_ns=samples[0]['realtime_ns'],
                    interval_end_realtime_ns=samples[-1]['realtime_ns'],
                    interval_start_monotonic_ns=samples[0]['monotonic_ns'],
                    interval_end_monotonic_ns=samples[-1]['monotonic_ns'], samples=samples,
                    application_trace=(root/'frames.csv').read_text())))
            finally:
                (root/'stop').touch()
                stop_process(process)
                stop_process(compositor)


if __name__ == '__main__':
    main(*sys.argv[1:])
