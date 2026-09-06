"""Measure a fresh terminal parent's Linux CPU/RSS and NVIDIA compute allocation."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time


def process_sample(pid):
    stat = Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()
    memory = {}
    for line in Path(f'/proc/{pid}/smaps_rollup').read_text().splitlines():
        key, sep, value = line.partition(':')
        if sep and value.strip().endswith('kB'):
            memory[key] = int(value.split()[0]) * 1024
    return {'cpu_seconds': (int(stat[11]) + int(stat[12])) / os.sysconf('SC_CLK_TCK'),
            'rss_bytes': memory['Rss'], 'pss_bytes': memory['Pss'],
            'private_bytes': memory['Private_Clean'] + memory['Private_Dirty']}


def gpu_memory(pid):
    command = shutil.which('nvidia-smi')
    if not command:
        return None
    rows = subprocess.check_output([command, '--query-compute-apps=pid,used_memory',
                                    '--format=csv,noheader,nounits'], text=True,
                                   timeout=10).splitlines()
    for row in rows:
        fields = [part.strip() for part in row.split(',')]
        if fields[0] == str(pid):
            return int(fields[1]) * 1024 * 1024
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--terminal', required=True)
    parser.add_argument('--terminal-arg', action='append', default=[])
    parser.add_argument('--seconds', type=float, default=3)
    parser.add_argument('--repeat', type=int, default=3)
    args = parser.parse_args()
    if not 0 < args.seconds <= 60 or args.repeat < 1:
        parser.error('seconds must be in (0,60], repeat must be positive')
    samples = []
    child = r'''
import json, os, pathlib, sys, time
root = pathlib.Path(sys.argv[1])
time.sleep(0.5)
os.write(1, b'cudaterm idle resource measurement\r\n')
cols, rows = os.get_terminal_size()
(root / 'ready').write_text(json.dumps({'cols': cols, 'rows': rows}))
while not (root / 'stop').exists(): time.sleep(0.1)
'''
    command = [args.terminal, *args.terminal_arg]
    for _ in range(args.repeat):
        with tempfile.TemporaryDirectory(prefix='cudaterm-idle-') as folder:
            root = Path(folder)
            proc = subprocess.Popen([*command, sys.executable, '-c', child, folder])
            try:
                deadline = time.monotonic() + 30
                while not (root / 'ready').exists():
                    if proc.poll() is not None:
                        raise RuntimeError('terminal exited before readiness')
                    if time.monotonic() > deadline:
                        raise TimeoutError('terminal did not become ready')
                    time.sleep(0.05)
                time.sleep(1)  # Exclude initialization and initial presentation.
                geometry = json.loads((root / 'ready').read_text())
                before = process_sample(proc.pid)
                begin = time.monotonic()
                time.sleep(args.seconds)
                after = process_sample(proc.pid)
                elapsed = time.monotonic() - begin
                cpu = after['cpu_seconds'] - before['cpu_seconds']
                samples.append({'geometry': geometry, 'elapsed_seconds': elapsed,
                                'cpu_seconds': cpu, 'cpu_percent_one_core': 100 * cpu / elapsed,
                                'rss_bytes': after['rss_bytes'],
                                'pss_bytes': after['pss_bytes'],
                                'private_bytes': after['private_bytes'],
                                'nvidia_compute_memory_bytes': gpu_memory(proc.pid)})
                (root / 'stop').touch()
                if proc.wait(timeout=10) != 0:
                    raise RuntimeError('terminal exited unsuccessfully')
            finally:
                if proc.poll() is None:
                    proc.terminate()
                    try: proc.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        proc.kill()
                        proc.wait()
    print(json.dumps({'benchmark': 'terminal-idle-parent-resources', 'command': command,
                      'terminal_resolved': os.path.realpath(shutil.which(args.terminal) or args.terminal),
                      'samples': samples,
                      'scope': 'Terminal parent CPU and RSS only; NVIDIA compute-process memory when reported. '
                               'Excludes compositor, descendants, and GPU utilization. Null GPU memory is unavailable, not zero.'}, indent=2))


if __name__ == '__main__':
    main()
