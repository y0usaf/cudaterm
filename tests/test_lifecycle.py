"""Bounded private-host lifecycle and allocation-retention evidence."""
import argparse
import hashlib
import json
import os
import pathlib
import threading
import time

from test_graphics import Host, pixel_at, upload, apc


class TimedHost(Host):
    """Start the deadline before the constructor's first blocking request."""
    def __init__(self, *args):
        self.watchdog = None
        try:
            super().__init__(*args)
        except BaseException:
            if self.watchdog:
                self.watchdog.cancel()
            if hasattr(self, 'process'):
                self.process.kill()
                self.process.wait(timeout=10)
            raise

    def command(self, *args):
        if self.watchdog is None:
            self.watchdog = threading.Timer(180, self.process.kill)
            self.watchdog.daemon = True
            self.watchdog.start()
        return super().command(*args)

    def close(self):
        try:
            super().close()
        finally:
            if self.watchdog:
                self.watchdog.cancel()


def proc_memory(pid):
    values = {}
    for line in pathlib.Path(f'/proc/{pid}/smaps_rollup').read_text().splitlines():
        key, value = line.split(':', 1)
        if key == 'Rss':
            values['rss_kib'] = int(value.split()[0])
        elif key == 'Pss':
            values['pss_kib'] = int(value.split()[0])
        elif key in ('Private_Clean', 'Private_Dirty'):
            values['private_kib'] = values.get('private_kib', 0) + int(value.split()[0])
    return values


def memory_stage(host, samples, name):
    value = proc_memory(host.process.pid)
    value['stage'] = name
    value['pid'] = host.process.pid
    value['monotonic'] = time.monotonic()
    value['engine'] = allocation(host)
    samples.append(value)
    return value


def state(host):
    return json.loads(host.command(b'S'))


def allocation(host):
    return json.loads(host.command(b'A'))


def check(condition, message):
    if not condition:
        raise AssertionError(message)


def lifecycle(host, cycle, samples):
    host.feed(b'\x1b[?25l')
    memory_stage(host, samples, 'before')
    baseline = allocation(host)
    check(baseline['image_bytes'] == 0 and baseline['transfer_bytes'] == 0,
          'baseline retained graphics allocation')

    lines = ''.join(f'cycle-{cycle}-line-{i:04d}\r\n' for i in range(5000)).encode()
    host.feed(lines)
    after_history = allocation(host)
    check(after_history['history_capacity'] == 4096 and state(host)['history'] == 4096,
          'scrollback burst did not fill the bounded history ring')
    memory_stage(host, samples, 'history_burst')

    host.resize(318, 89)
    check((state(host)['cols'], state(host)['rows']) == (318, 89),
          'large resize geometry mismatch')
    memory_stage(host, samples, 'resize_318x89')
    host.resize(40, 12)
    check((state(host)['cols'], state(host)['rows']) == (40, 12),
          'small resize geometry mismatch')
    memory_stage(host, samples, 'resize_40x12')

    channels = 3 if cycle % 4 < 2 else 4
    compressed = cycle % 2 == 1
    raw = bytes(v for i in range(64 * 32)
                for v in (((cycle * 31 + i) & 255), 90, 220)
                + ((255,) if channels == 4 else ()))
    reply = host.feed(b'\x1b[H' + upload(raw, 64, 32, channels=channels,
                                           compressed=compressed))
    check(b'OK' in reply, f'graphics upload failed: {reply!r}')
    alloc = allocation(host)
    check(alloc['image_bytes'] == len(raw) and alloc['transfer_bytes'] == 0,
          f'graphics allocation mismatch: {alloc}')
    pixels = host.pixels()
    for y in range(32):
        for x in range(64):
            offset = (y * 64 + x) * channels
            expected = tuple(raw[offset:offset + 3]) + (raw[offset + 3],) if channels == 4 else tuple(raw[offset:offset + 3]) + (255,)
            check(pixel_at(pixels, host.cols * 8, x, y) == expected,
                  f'uploaded pixel mismatch at {x},{y}')
    memory_stage(host, samples, 'graphics_uploaded')

    host.feed(apc('a=d,d=I,i=7,q=2'))
    alloc = allocation(host)
    check(alloc['image_bytes'] == 0 and alloc['transfer_bytes'] == 0,
          f'graphics allocation retained after delete: {alloc}')
    memory_stage(host, samples, 'graphics_deleted')

    host.feed(b'\x1bc')
    host.resize(80, 24)
    final_state = state(host)
    final_alloc = allocation(host)
    check((final_state['cols'], final_state['rows']) == (80, 24),
          'reset geometry mismatch')
    check(final_state['history'] == 0,
          f'reset retained terminal history: {final_state}')
    check(final_alloc['image_bytes'] == 0 and final_alloc['transfer_bytes'] == 0,
          f'reset retained graphics allocation: {final_alloc}')
    memory_stage(host, samples, 'after')
    return final_alloc


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--host', required=True)
    parser.add_argument('--cycles', type=int, default=30)
    parser.add_argument('--processes', type=int, default=3)
    parser.add_argument('--output', default='bench/lifecycle-final.json')
    args = parser.parse_args()
    if args.cycles < 1 or args.cycles > 1000 or args.processes < 1 or args.processes > 16:
        raise ValueError('--cycles must be 1..1000 and --processes must be 1..16')
    report = {
        'status': 'running',
        'scope': 'private engine-host lifecycle, no desktop compositor',
        'host': os.path.realpath(args.host),
        'host_sha256': hashlib.sha256(pathlib.Path(args.host).read_bytes()).hexdigest(),
        'cycles': [],
        'process_runs': [],
        'processes': args.processes,
        'peak_sampled_note': 'samples occur after lifecycle stages; they are not a true instantaneous peak',
    }
    output = pathlib.Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, sort_keys=True) + '\n')
    try:
        for process_index in range(args.processes):
            process_started = time.monotonic()
            host = TimedHost(args.host, 80, 24)
            process_run = {'process': process_index, 'pid': host.process.pid,
                           'started_monotonic': process_started,
                           'cycles_completed': 0}
            report['process_runs'].append(process_run)
            reset_reference = None
            try:
                for cycle in range(args.cycles):
                    samples = []
                    try:
                        final_alloc = lifecycle(host, cycle, samples)
                        if reset_reference is None:
                            reset_reference = final_alloc
                        else:
                            check(final_alloc['device_bytes'] == reset_reference['device_bytes'],
                                  'device allocation changed after first warmup cycle')
                            check(final_alloc['history_capacity'] == reset_reference['history_capacity'],
                                  'history reservation changed after first warmup cycle')
                        cycle_report = {'process': process_index, 'cycle': cycle,
                                        'samples': samples, 'final_allocation': final_alloc}
                    except Exception as exc:
                        cycle_report = {'process': process_index, 'cycle': cycle,
                                        'samples': samples, 'error': repr(exc)}
                        report['cycles'].append(cycle_report)
                        report['status'] = 'failed'
                        output.write_text(json.dumps(report, sort_keys=True) + '\n')
                        raise
                    report['cycles'].append(cycle_report)
                    process_run['cycles_completed'] = cycle + 1
                    output.write_text(json.dumps(report, sort_keys=True) + '\n')
            finally:
                host.close()
                process_run['ended_monotonic'] = time.monotonic()
                output.write_text(json.dumps(report, sort_keys=True) + '\n')
    except Exception:
        report['status'] = 'failed'
        output.write_text(json.dumps(report, sort_keys=True) + '\n')
        raise
    report['status'] = 'passed'
    output.write_text(json.dumps(report, sort_keys=True) + '\n')
    print(json.dumps(report, sort_keys=True))


if __name__ == '__main__':
    main()
