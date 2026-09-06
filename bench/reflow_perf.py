#!/usr/bin/env python3
"""Headless resize request timing and sampled retained-resource evidence."""
import argparse
import hashlib
import json
import pathlib
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / 'tests'))
from test_lifecycle import TimedHost, proc_memory


def main(a):
    unit = b'X' if a.soft_unit == 'ascii' else '中'.encode()
    seed = (b''.join(f'line-{i:04d}\r\n'.encode() for i in range(a.lines))
            if a.lines else unit * (a.soft_bytes // len(unit)))
    report = {
        'status': 'running', 'command': sys.argv,
        'host': str(pathlib.Path(a.host).resolve()),
        'host_sha256': hashlib.sha256(pathlib.Path(a.host).read_bytes()).hexdigest(),
        'lines': a.lines, 'soft_bytes': a.soft_bytes, 'soft_unit': a.soft_unit,
        'seed_bytes': len(seed), 'seed_sha256': hashlib.sha256(seed).hexdigest(),
        'cycles': a.cycles, 'widths': [40, 318, 80], 'rows': 24, 'samples': [],
        'scope': 'Engine-host W request RTT includes IPC and CUDA resize, not presentation latency. Old clipping is not functionally equivalent to reflow.',
        'sampled_peak_note': 'Stage samples are not instantaneous peaks.',
    }
    output = pathlib.Path(a.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    h = None
    try:
        h = TimedHost(a.host, 80, 24)
        report['pid'] = h.process.pid
        h.feed(seed)
        for cycle in range(a.cycles):
            for cols in (40, 318, 80):
                start = time.perf_counter_ns()
                h.resize(cols, 24)
                end = time.perf_counter_ns()
                report['samples'].append({
                    'cycle': cycle, 'cols': cols, 'resize_ns': end - start,
                    'memory': proc_memory(h.process.pid),
                    'allocation': json.loads(h.command(b'A')),
                    'state': json.loads(h.command(b'S')),
                })
                output.write_text(json.dumps(report, indent=2) + '\n')
        report['status'] = 'passed'
    except Exception as error:
        report['status'] = 'failed'
        report['error'] = repr(error)
        raise
    finally:
        output.write_text(json.dumps(report, indent=2) + '\n')
        if h is not None:
            h.close()


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--host', required=True)
    p.add_argument('--output', required=True)
    p.add_argument('--lines', type=int, default=5000)
    p.add_argument('--soft-bytes', type=int, default=0)
    p.add_argument('--cycles', type=int, default=5)
    p.add_argument('--soft-unit', choices=['ascii', 'wide'], default='ascii')
    a = p.parse_args()
    if not 0 <= a.lines <= 10000 or not 0 <= a.soft_bytes <= 1048576 or not 1 <= a.cycles <= 100:
        p.error('lines must be 0..10000, soft-bytes 0..1048576, cycles 1..100')
    if a.lines and a.soft_bytes:
        p.error('choose hard lines or a soft byte stream')
    main(a)
