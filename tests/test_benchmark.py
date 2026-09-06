"""Exercise the benchmark child against a PTY, without a window system."""
import importlib.util
import json
import os
from pathlib import Path
import pty
import select
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / 'bench/pty_throughput.py'


class BarrierTests(unittest.TestCase):
    def test_parent_rejects_wrong_early_sample_geometry(self):
        spec = importlib.util.spec_from_file_location('pty_throughput', SCRIPT)
        benchmark = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(benchmark)
        args = benchmark.parser().parse_args([
            '--terminal', 'fake-terminal', '--repeat', '1', '--warmup', '0',
            '--iterations', '2', '--timeout', '1', '--settle-seconds', '0',
            '--expected-cols', '318', '--expected-rows', '89'])

        def successful_terminal(command, **kwargs):
            result = Path(command[command.index('--result') + 1])

            def sample(cols, rows):
                geometry = {'cols': cols, 'rows': rows}
                return {'bytes': 10, 'payload_write_ns': 1,
                        'barrier_ns': 2, 'sample_start_ns': 3,
                        'sample_end_ns': 5, 'geometry_before': geometry,
                        'geometry_after': geometry}

            result.write_text(json.dumps({
                'samples': [sample(80, 24), sample(318, 89)],
                'payload_bytes': 10, 'cols': 318, 'rows': 89,
            }))
            return subprocess.CompletedProcess(command, 0, stderr=b'')

        with mock.patch.object(benchmark.subprocess, 'run',
                               side_effect=successful_terminal):
            with self.assertRaisesRegex(RuntimeError, 'geometry'):
                benchmark.run(args)

    def test_child_timeout_is_serialized_and_propagated(self):
        master, slave = pty.openpty()
        try:
            with tempfile.TemporaryDirectory() as tmp:
                result = Path(tmp) / 'result.json'
                child = subprocess.Popen(
                    [sys.executable, str(SCRIPT), '--child', '--iterations', '1',
                     '--payload-bytes', '0', '--timeout', '0.05',
                     '--result', str(result)],
                    stdin=slave, stdout=slave, stderr=subprocess.PIPE)
                _, err = child.communicate(timeout=3)
                self.assertNotEqual(child.returncode, 0)
                diagnostic = json.loads(result.read_text())
                self.assertEqual(diagnostic['error'].split(':', 1)[0],
                                 'TimeoutError')
                self.assertIn('timed out waiting for CSI 6 n response',
                              diagnostic['error'])
                self.assertIn('benchmark failed', err.decode())
        finally:
            os.close(master)
            os.close(slave)

    def test_parent_reports_child_diagnostic_with_terminal_failure(self):
        spec = importlib.util.spec_from_file_location('pty_throughput', SCRIPT)
        benchmark = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(benchmark)
        args = benchmark.parser().parse_args([
            '--terminal', 'fake-terminal', '--repeat', '1', '--warmup', '0',
            '--iterations', '1', '--timeout', '1', '--settle-seconds', '0'])

        def failed_terminal(command, **kwargs):
            result = Path(command[command.index('--result') + 1])
            result.write_text(json.dumps({'error': 'TimeoutError: child stalled'}))
            return subprocess.CompletedProcess(command, 17, stderr=b'GTK warning\n')

        with mock.patch.object(benchmark.subprocess, 'run', side_effect=failed_terminal):
            with self.assertRaisesRegex(
                    RuntimeError,
                    r'terminal exited 17; child: TimeoutError: child stalled; '
                    r'terminal stderr: GTK warning'):
                benchmark.run(args)

    def test_reply_without_newline_completes_each_sample(self):
        pattern = b'0123456789abcdefghijklmnopqrstuvwxyz\r\n'
        cases = [(380, 0, pattern * 10), (380, 7, pattern * 10),
                 (380, 256, pattern * 10), (0, 7, b'')]
        for payload_bytes, write_chunk, expected_payload in cases:
            master, slave = pty.openpty()
            try:
                with tempfile.TemporaryDirectory() as tmp:
                    result = Path(tmp) / 'result.json'
                    child = subprocess.Popen(
                        [sys.executable, str(SCRIPT), '--child', '--iterations', '2',
                         '--payload-bytes', str(payload_bytes),
                         '--write-chunk', str(write_chunk), '--timeout', '2',
                         '--result', str(result)],
                        stdin=slave, stdout=slave, stderr=subprocess.PIPE)
                    try:
                        pending = b''
                        replies = 0
                        queries = 0
                        deadline = time.monotonic() + 5
                        # One launch handshake precedes the two timed iterations.
                        while replies < 3:
                            self.assertLess(time.monotonic(), deadline,
                                            'no cursor query received')
                            if select.select([master], [], [], 0.1)[0]:
                                pending += os.read(master, 4096)
                            while b'\x1b[6n' in pending:
                                queries += 1
                                self.assertLessEqual(queries, 3)
                                payload, pending = pending.split(b'\x1b[6n', 1)
                                self.assertNotIn(b'\r\r\n', payload,
                                                 'PTY output must be raw')
                                if replies:
                                    if payload_bytes:
                                        self.assertEqual(payload, expected_payload)
                                    else:
                                        self.assertEqual(payload, b'')
                                # No newline: a canonical-mode reader would hang here.
                                os.write(master, b'\x1b[2;3R')
                                replies += 1
                        _, err = child.communicate(timeout=3)
                        self.assertEqual(child.returncode, 0, err.decode())
                        self.assertEqual(queries, 3)
                        data = json.loads(result.read_text())
                        self.assertEqual(len(data['samples']), 2)
                        self.assertEqual(data['payload_bytes'], payload_bytes)
                        self.assertGreater(data['init_barrier_ns'], 0)
                        self.assertEqual(len(data['samples'][0]['geometry_before']), 2)
                        self.assertEqual(data['samples'][0]['geometry_before'],
                                         data['samples'][0]['geometry_after'])
                        self.assertTrue(all(s['barrier_ns'] > 0
                                            for s in data['samples']))
                        self.assertTrue(all(s['payload_write_ns'] >= 0
                                            for s in data['samples']))
                        self.assertTrue(all(s['payload_write_ns'] <= s['barrier_ns']
                                            for s in data['samples']))
                        self.assertTrue(all(s['sample_start_ns'] < s['sample_end_ns']
                                            for s in data['samples']))
                        self.assertTrue(all(s['sample_end_ns'] - s['sample_start_ns'] ==
                                            s['barrier_ns']
                                            for s in data['samples']))
                    finally:
                        if child.poll() is None:
                            child.kill()
                            child.communicate()
            finally:
                os.close(master)
                os.close(slave)


if __name__ == '__main__':
    unittest.main()
