"""CPU regressions for the private resource collector's accounting boundaries."""
import pathlib
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / 'bench'))
import private_baseline as baseline


class CollectorTests(unittest.TestCase):
    def gpu(self, entries):
        xml = ('<nvidia_smi_log><driver_version>test</driver_version><gpu id="card0">'
               '<product_name>test GPU</product_name><processes>' + entries +
               '</processes></gpu></nvidia_smi_log>')
        with patch.object(baseline.shutil, 'which', return_value='/mock/nvidia-smi'), \
             patch.object(baseline.subprocess, 'check_output', return_value=xml):
            return baseline.nvidia_sample(123)

    def test_graphics_process_is_observable(self):
        sample = self.gpu('<process_info><pid>123</pid><type>G</type>'
                          '<used_memory>42 MiB</used_memory></process_info>')
        self.assertEqual(sample['memory_bytes'], 42 * 1024 * 1024)
        self.assertIn('<type>G</type>', sample['process_info_xml'])

    def test_missing_or_unavailable_memory_is_unknown(self):
        for entries in ('', '<process_info><pid>123</pid><type>G</type>'
                            '<used_memory>N/A</used_memory></process_info>'):
            self.assertIsNone(self.gpu(entries)['memory_bytes'])

    def test_unrelated_process_is_not_retained(self):
        sample = self.gpu('<process_info><pid>987</pid><process_name>unrelated</process_name>'
                          '<used_memory>42 MiB</used_memory></process_info>')
        self.assertIsNone(sample['memory_bytes'])
        self.assertNotIn('unrelated', str(sample))

    def test_cpu_ticks_are_not_counted_twice(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            process = root / '123'
            process.mkdir()
            (process / 'smaps_rollup').write_text(
                'Rss: 100 kB\nPss: 80 kB\nPrivate_Clean: 20 kB\nPrivate_Dirty: 30 kB\n')
            def stat(user, system):
                fields = ['0'] * 52
                fields[0], fields[11], fields[12] = 'S', str(user), str(system)
                return '123 (name with ) inside) ' + ' '.join(fields)
            (process / 'stat').write_text(stat(7, 3))
            for tid, user, system in ((123, 4, 2), (124, 3, 1)):
                thread = process / 'task' / str(tid)
                thread.mkdir(parents=True)
                (thread / 'stat').write_text(stat(user, system))
                (thread / 'status').write_text(
                    'voluntary_ctxt_switches: 2\nnonvoluntary_ctxt_switches: 1\n')
            def proc_path(path):
                return root / pathlib.Path(path).relative_to('/proc')
            with patch.object(baseline, 'Path', side_effect=proc_path), \
                 patch.object(baseline.os, 'sysconf', return_value=100):
                sample = baseline.proc_sample(123)
            self.assertEqual(sample['cpu_seconds'], .1)
            self.assertEqual(sample['private_bytes'], 50 * 1024)
            self.assertEqual(sample['voluntary_ctxt_switches'], 4)
            self.assertEqual(sample['nonvoluntary_ctxt_switches'], 2)

    def test_controlled_environment_isolated_and_default_preserved(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            source = {'XDG_CONFIG_HOME': '/user/config', 'FONTCONFIG_FILE': '/user/fonts.conf',
                      'FONTCONFIG_PATH': '/user/fontconfig'}
            self.assertEqual(baseline.child_environment(source, root / 'controlled', False), source)
            controlled = baseline.child_environment(source, root / 'controlled', True)
            self.assertEqual(controlled['XDG_CONFIG_HOME'], str(root / 'controlled'))
            self.assertNotIn('FONTCONFIG_FILE', controlled)
            self.assertNotIn('FONTCONFIG_PATH', controlled)
            fontconfig = root / 'fonts.conf'; fontconfig.write_text('<fontconfig/>')
            controlled = baseline.child_environment(source, root / 'controlled', True, fontconfig)
            self.assertEqual(controlled['FONTCONFIG_FILE'], str(fontconfig.resolve()))
            self.assertNotIn('FONTCONFIG_PATH', controlled)

    def test_controlled_terminal_config_and_font_probe_pattern(self):
        self.assertIn('--config', baseline.command('foot', '/foot', 80, 24, '/tmp/x', True))
        self.assertIn('--config', baseline.command('monstar', '/monstar', 80, 24, '/tmp/x', True))
        with patch.object(baseline.shutil, 'which', return_value='/bin/true'), \
             patch.object(baseline.subprocess, 'check_output', return_value='DejaVu Sans Mono\nBook\n/font.ttf\n0\n17\n'), \
             patch.object(baseline, 'sha256', return_value='hash'):
            result = baseline.font_probe('monstar', {})
        self.assertEqual(result['requested_pattern'], 'DejaVu Sans Mono:pixelsize=17')
        self.assertEqual(result['executable_sha256'], 'hash')


if __name__ == '__main__':
    unittest.main()
