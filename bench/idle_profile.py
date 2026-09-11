"""Private, instrumented idle attribution; never an uninstrumented cost baseline."""
import json
import hashlib
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


def _identity(path):
    result = {'path': path}
    try:
        data = Path(path).read_bytes()
    except (FileNotFoundError, PermissionError):
        result['sha256'] = None
    else:
        result['sha256'] = hashlib.sha256(data).hexdigest()
    return result


def _mapping_kind(path):
    if path == '[heap]':
        return 'heap'
    if not path or path.startswith('[') or path.startswith('/SYSV'):
        return 'unnamed anonymous'
    if path.startswith('/dev/nvidia') or path.startswith('/dev/dri/'):
        return 'driverdevice'
    if path.startswith('/'):
        return 'file/library'
    return 'unknown ownership'


def pss_maps(pid, output):
    """Capture one bounded, raw smaps read and an ownership summary."""
    proc = Path('/proc') / str(pid)
    smaps_path, rollup_path = proc / 'smaps', proc / 'smaps_rollup'
    read_start = time.time_ns()
    monotonic_start = time.monotonic_ns()
    raw_smaps = smaps_path.read_bytes()
    raw_rollup = rollup_path.read_bytes()
    read_end = time.time_ns()
    monotonic_end = time.monotonic_ns()
    text = raw_smaps.decode('utf-8', errors='replace')
    fields = []
    current = None
    for line in text.splitlines():
        if line and line[0] not in ' \t' and '-' in line.split()[0]:
            parts = line.split(maxsplit=5)
            current = {'address': parts[0], 'perms': parts[1],
                       'offset': parts[2], 'dev': parts[3], 'inode': parts[4],
                       'path': parts[5] if len(parts) == 6 else '',
                       'Size': 0, 'Rss': 0, 'Pss': 0, 'Shared_Clean': 0,
                       'Shared_Dirty': 0, 'Private_Clean': 0, 'Private_Dirty': 0}
            fields.append(current)
        elif current is not None and ':' in line:
            key, _, value = line.partition(':')
            value = value.strip()
            if key in ('Size', 'Rss', 'Pss', 'Shared_Clean', 'Shared_Dirty',
                       'Private_Clean', 'Private_Dirty') and value.endswith('kB'):
                current[key] = int(value[:-2].strip()) * 1024
    totals = {}
    for mapping in fields:
        kind = _mapping_kind(mapping['path'])
        mapping['kind'] = kind
        row = totals.setdefault(kind, {'mappings': 0, 'size_bytes': 0, 'pss_bytes': 0,
                                       'rss_bytes': 0, 'private_bytes': 0,
                                       'shared_bytes': 0})
        row['mappings'] += 1
        row['size_bytes'] += mapping['Size']
        row['rss_bytes'] += mapping['Rss']
        row['pss_bytes'] += mapping['Pss']
        row['shared_bytes'] += mapping['Shared_Clean'] + mapping['Shared_Dirty']
        row['private_bytes'] += mapping['Private_Clean'] + mapping['Private_Dirty']
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    stem = output.with_suffix('')
    raw_smaps_path = stem.with_suffix('.smaps')
    raw_rollup_path = stem.with_suffix('.smaps_rollup')
    raw_smaps_path.write_bytes(raw_smaps)
    raw_rollup_path.write_bytes(raw_rollup)
    result = {
        'pid': pid, 'read_start_realtime_ns': read_start, 'read_end_realtime_ns': read_end,
        'read_start_monotonic_ns': monotonic_start, 'read_end_monotonic_ns': monotonic_end,
        'raw_smaps_path': str(raw_smaps_path), 'raw_smaps_bytes': len(raw_smaps),
        'raw_smaps_rollup_path': str(raw_rollup_path), 'raw_smaps_rollup_bytes': len(raw_rollup),
        'executable': _identity(os.path.realpath(proc / 'exe')),
        'libc': [], 'libcuda': [], 'mapping_count': len(fields), 'categories': totals,
        'largest_private_mappings': sorted(fields,
            key=lambda item: item['Private_Clean'] + item['Private_Dirty'], reverse=True)[:20],
    }
    seen = {'libc': set(), 'libcuda': set()}
    for mapping in fields:
        path = mapping['path']
        if 'libc.so' in path and path not in seen['libc']:
            result['libc'].append(_identity(path))
            seen['libc'].add(path)
        if 'libcuda' in path and path not in seen['libcuda']:
            result['libcuda'].append(_identity(path))
            seen['libcuda'].add(path)
    rollup = {}
    for line in raw_rollup.decode('utf-8', errors='replace').splitlines():
        key, sep, value = line.partition(':')
        if sep and value.strip().endswith('kB'):
            rollup[key] = int(value.split()[0]) * 1024
    result['rollup_bytes'] = rollup
    result['interpretation'] = ('Mapping sums are diagnostic ownership buckets; Pss is rounded per mapping '
                                'and smaps/smaps_rollup are separate non-atomic reads.')
    output.write_text(json.dumps(result, indent=2) + '\n')
    return result


def main(term, weston, seat):
    with tempfile.TemporaryDirectory(prefix='cudaterm-idle-') as folder:
        root = Path(folder)
        env = dict(os.environ, XDG_RUNTIME_DIR=folder, WAYLAND_DISPLAY='idle-profile',
                   CUDATERM_TRACE=str(root/'frames.csv'))
        env.pop('DISPLAY', None)
        compositor = process = None
        with (root/'weston.log').open('w') as log:
            try:
                compositor_env = dict(env)
                compositor_env.pop('MALLOC_TRIM_THRESHOLD_', None)
                compositor = subprocess.Popen([weston, '--backend=headless', '--renderer=gl',
                    '--shell=desktop', '--socket=idle-profile', '--no-config', '--modules='+seat,
                    '--width=960', '--height=640'], env=compositor_env, stdout=log, stderr=log)
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
                launch_start_ns = time.monotonic_ns()
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
                maps = None
                if os.environ.get('IDLE_PSS_MAPS_OUT'):
                    maps = pss_maps(pid, os.environ['IDLE_PSS_MAPS_OUT'])
                samples = [snapshot(pid)]
                deadline = time.monotonic()+3
                while time.monotonic()<deadline:
                    time.sleep(min(.25, max(0, deadline-time.monotonic())))
                    samples.append(snapshot(pid))
                (root/'stop').touch()
                status = process.wait(timeout=10)
                assert status == 0, status
                result = dict(scope='instrumented settled idle; not cost acceptance',
                    command=command, terminal_pid=pid, launcher_pid=process.pid, exit=status,
                    launch_start_monotonic_ns=launch_start_ns,
                    geometry=ready, interval_start_realtime_ns=samples[0]['realtime_ns'],
                    interval_end_realtime_ns=samples[-1]['realtime_ns'],
                    interval_start_monotonic_ns=samples[0]['monotonic_ns'],
                    interval_end_monotonic_ns=samples[-1]['monotonic_ns'], samples=samples,
                    application_trace=(root/'frames.csv').read_text())
                if maps is not None:
                    result['pss_maps'] = maps
                print(json.dumps(result))
            finally:
                (root/'stop').touch()
                stop_process(process)
                stop_process(compositor)


if __name__ == '__main__':
    main(*sys.argv[1:])
