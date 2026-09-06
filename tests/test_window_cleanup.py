"""CPU checks for bounded cleanup of fixture-owned descendants."""
import pathlib
import signal
import subprocess
import sys
import tempfile
import time
import unittest

from window_sync import stop_daemon


class CleanupTests(unittest.TestCase):
    def exercise(self, mode, expected):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            program = """import pathlib,signal,sys,time
root=pathlib.Path(sys.argv[1]); mode=sys.argv[2]
if mode=='kill': signal.signal(signal.SIGTERM,signal.SIG_IGN)
(root/'ready').touch()
while mode!='cooperative' or not (root/'stop').exists(): time.sleep(.01)
"""
            process = subprocess.Popen([sys.executable, '-c', program, directory, mode])
            try:
                deadline = time.monotonic() + 3
                while not (root/'ready').exists():
                    if process.poll() is not None or time.monotonic() > deadline:
                        self.fail('cleanup child failed to become ready')
                    time.sleep(.01)
                (root/'pid').write_text(str(process.pid))
                before = set(pathlib.Path('/proc/self/fd').iterdir())
                stop_daemon(root, 'pid', 'stop')
                self.assertEqual(process.wait(timeout=1), expected)
                self.assertEqual(set(pathlib.Path('/proc/self/fd').iterdir()), before)
                self.assertFalse((root/'pid').exists())
                stop_daemon(root, 'pid', 'stop')  # Repeated cleanup is harmless.
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait(timeout=3)

    def test_cooperative_exit(self):
        self.exercise('cooperative', 0)

    def test_term_fallback(self):
        self.exercise('term', -signal.SIGTERM)

    def test_kill_fallback(self):
        self.exercise('kill', -signal.SIGKILL)


if __name__ == '__main__':
    unittest.main()
