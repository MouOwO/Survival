"""Pure synthetic parser/source tests, not native measurement evidence."""
from pathlib import Path
import importlib.util, subprocess, unittest
from unittest import mock

SPEC = importlib.util.spec_from_file_location('bulk_probe', Path(__file__).with_name('network50_bulk_native_probe_20261103.py'))
m = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(m)


def fixture():
    lines = ['[Client] Build: 10938 (revision 11175759)', '[N50_GB_PROBE] BEGIN event=gb key=d']
    for length in m.EXPECTED:
        # Intentionally different overhead above protobuf size thresholds.
        size = length+(25 if length == 64 else 27)
        lines += ['[N50_GB_PROBE] SEND value_ascii_bytes='+str(length),
                  '[Networking] server @ loopback:1: ('+str(size*8-6)+' bits/'+str(size)+' bytes):',
                  '[Networking] CUserMsg_CustomGameEvent [148]', '[Networking] event_name: "gb"',
                  '[Networking] data: "VBKV\\002\\335\\352\\266\\000\\000\\001d\\000'+'A'*length+'\\000\\013\\013"']
    lines += ['[N50_GB_PROBE] END sends=5 transactions=0', 'ShutdownSource2Logging']
    return ('\r\n'.join(lines)+'\r\n').encode('latin1')


class BulkProbeTests(unittest.TestCase):
    def test_plan_is_pure_and_uses_successful_addon_activate_path(self):
        with mock.patch.object(m.subprocess, 'Popen', side_effect=AssertionError('no launch')), mock.patch.object(m.subprocess, 'run', side_effect=AssertionError('no subprocess')):
            plan = m.plan()
        self.assertEqual(plan['value_lengths'], [64,128,256,512,896])
        self.assertIn('svt_network50_bulk', plan['launch_argv'])
        self.assertNotIn('script_execute', ' '.join(plan['launch_argv']))
        self.assertNotIn('require(', m.SOURCE)
        self.assertIn('function Activate()', m.SOURCE)

    def test_source_compiles_without_running_game(self):
        result = subprocess.run(['C:/Program Files/lua/bin/lua5.1.exe', '-e', 'assert(loadstring(io.read("*a")))'], input=m.SOURCE.encode(), capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_actual_bits_not_fixed_envelope(self):
        result = m.parse_closed_log(fixture())
        self.assertEqual([row['observed_envelope_bytes'] for row in result['samples']], [25,27,27,27,27])
        self.assertEqual(result['max_native_bytes'], 923)
        self.assertTrue(result['all_samples_within_1KiB'])
        self.assertFalse(result['envelope_assumed'])

    def test_closed_complete_ordered_single_key_required(self):
        changes = [(b'ShutdownSource2Logging', b''), (b'event_name: "gb"', b'event_name: "cw"'),
                   (b'A'*896, b'A'*895), (b'\\000\\013\\013"', b'\\000\\001x\\000B\\000\\013\\013"')]
        for old, new in changes:
            with self.subTest(old=old[:32]), self.assertRaises(ValueError):
                m.parse_closed_log(fixture().replace(old, new, 1))

    def test_truncated_duplicate_and_missing_metadata_refused(self):
        raw = fixture()
        for broken in (raw+raw, raw[:500], raw.replace(b'(706 bits/89 bytes):', b'(706 bits/88 bytes):', 1)):
            with self.assertRaises(ValueError):
                m.parse_closed_log(broken)

    def test_existing_client_blocks_prepare_before_any_files(self):
        with mock.patch.object(m.p, 'clients', return_value=[{'pid':1}]), mock.patch.object(m.LAB.__class__, 'mkdir', side_effect=AssertionError('no writes')):
            with self.assertRaisesRegex(ValueError, 'existing_client_preserved'):
                m.prepare()

    def test_retire_refuses_any_running_client_before_io(self):
        with mock.patch.object(m.p, 'clients', return_value=[{'pid':1}]), mock.patch.object(m, 'verify', side_effect=AssertionError('no target IO')):
            with self.assertRaisesRegex(ValueError, 'all_clients_must_exit'):
                m.retire()

    def test_real_public_evidence_is_sanitized_and_matches_closed_measurement(self):
        import json
        evidence = json.loads((m.ROOT/'data/ui/ui_grid_bulk_native_evidence_20261103.json').read_bytes())
        self.assertEqual(evidence['engine_build'], '10938:11198969')
        self.assertEqual([row['native_bytes'] for row in evidence['samples']], [89,155,283,539,923])
        self.assertFalse(evidence['actual_grid_payload_tested'])
        self.assertFalse(evidence['fps_measured'])
        self.assertNotIn('pid', evidence)
        self.assertNotIn('argv', evidence)
        self.assertNotIn('external_lab', evidence)
        self.assertEqual(evidence['source_log_sha256'], 'ce05e75e1373de45e37d10a9232b387d6ac49ad15089f79a9f32c0c54ff9ceac')


if __name__ == '__main__':
    unittest.main()
