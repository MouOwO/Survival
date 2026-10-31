"""State-machine and lock checks; no network, accounts or real relay processes."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location("manual_login_repair", Path(__file__).with_name("repair_steam_login.py"))
repair = importlib.util.module_from_spec(spec); spec.loader.exec_module(repair)
HEALTHY = dict(relay_enabled=True, listener_present=True, web_health_ok=True,
               steam_transport_ok=True, invalid_assertion_rejected=True)
DEAD = dict(HEALTHY, listener_present=False, steam_transport_ok=False, invalid_assertion_rejected=False)


class RepairTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.receipt = Path(self.temp.name) / 'relay.json'
        self.identity = dict(pid=12345, created=2345, executable='ssh.exe', command_sha256='f' * 64)
        self.relay = SimpleNamespace(RECEIPT=self.receipt,
            process_identity=Mock(return_value=self.identity), stop=Mock(), start=Mock())

    def receipt_exists(self):
        self.receipt.write_text(json.dumps(self.identity), 'utf8')

    def test_healthy_repeated_run_never_restarts(self):
        self.receipt_exists(); probe = Mock(return_value=HEALTHY)
        for _ in range(2):
            result = repair.recover(self.relay, probe, repair=True)
            self.assertTrue(result['ok']); self.assertFalse(result['relay_restarted'])
        self.assertEqual(probe.call_count, 2)
        self.relay.stop.assert_not_called(); self.relay.start.assert_not_called()

    def test_default_check_is_read_only(self):
        result = repair.recover(self.relay, Mock(return_value=DEAD))
        self.assertEqual(result['status'], 'RELAY_REPAIR_REQUIRED')
        self.relay.stop.assert_not_called(); self.relay.start.assert_not_called()

    def test_confirmed_stale_receipt_uses_existing_safe_stop_then_start_once(self):
        self.receipt_exists(); self.relay.process_identity.side_effect = RuntimeError('relay_process_not_found')
        actions = []; self.relay.stop.side_effect = lambda: actions.append('stop')
        self.relay.start.side_effect = lambda: actions.append('start')
        probe = Mock(side_effect=[DEAD, HEALTHY])
        result = repair.recover(self.relay, probe, repair=True)
        self.assertEqual(actions, ['stop', 'start']); self.assertEqual(probe.call_count, 2)
        self.assertEqual(result['status'], 'RELAY_RESTORED'); self.assertTrue(result['ok'])

    def test_missing_receipt_never_stops_any_process(self):
        result = repair.recover(self.relay, Mock(side_effect=[DEAD, HEALTHY]), repair=True)
        self.assertTrue(result['ok']); self.relay.stop.assert_not_called(); self.relay.start.assert_called_once()

    def test_live_verified_relay_can_be_restarted_if_official_probe_failed(self):
        self.receipt_exists()
        result = repair.recover(self.relay, Mock(side_effect=[DEAD, HEALTHY]), repair=True)
        self.assertTrue(result['ok']); self.relay.stop.assert_called_once(); self.relay.start.assert_called_once()

    def test_access_failure_or_reused_pid_never_reaches_network_or_stop(self):
        self.receipt_exists()
        for error in ('relay_process_access_failed', 'relay_process_is_not_owned_forward'):
            self.relay.process_identity.side_effect = RuntimeError(error); probe = Mock()
            with self.assertRaisesRegex(RuntimeError, error): repair.recover(self.relay, probe, repair=True)
            probe.assert_not_called()
        self.relay.process_identity.side_effect = None
        self.relay.process_identity.return_value = dict(self.identity, created=999)
        with self.assertRaisesRegex(RuntimeError, 'identity_changed'):
            repair.recover(self.relay, Mock(), repair=True)
        self.relay.stop.assert_not_called(); self.relay.start.assert_not_called()

    def test_foreign_cloud_listener_is_not_replaced(self):
        result = repair.recover(self.relay, Mock(return_value=dict(DEAD, listener_present=True)), repair=True)
        self.assertEqual(result['status'], 'REMOTE_LISTENER_NOT_OWNED')
        self.relay.stop.assert_not_called(); self.relay.start.assert_not_called()

    def test_disabled_or_unhealthy_cloud_never_changes_configuration(self):
        for change, status in [({'relay_enabled': False}, 'CLOUD_RELAY_DISABLED'),
                               ({'web_health_ok': False}, 'CLOUD_AUTH_UNHEALTHY')]:
            result = repair.recover(self.relay, Mock(return_value=dict(DEAD, **change)), repair=True)
            self.assertEqual(result['status'], status)
        self.relay.stop.assert_not_called(); self.relay.start.assert_not_called()

    def test_failed_repair_has_two_probes_and_one_start_no_retry_loop(self):
        probe = Mock(return_value=DEAD)
        result = repair.recover(self.relay, probe, repair=True)
        self.assertFalse(result['ok']); self.assertEqual(result['status'], 'STEAM_TRANSPORT_UNAVAILABLE')
        self.assertEqual(probe.call_count, 2); self.relay.start.assert_called_once()

    def test_invalid_receipt_is_retained(self):
        self.receipt.write_text('{bad json', 'utf8'); raw = self.receipt.read_bytes()
        with self.assertRaises(ValueError): repair.recover(self.relay, Mock(), repair=True)
        self.assertEqual(self.receipt.read_bytes(), raw); self.relay.stop.assert_not_called()

    @unittest.skipUnless(os.name == 'nt', 'Windows file lock')
    def test_duplicate_click_is_blocked_and_lock_file_can_be_reused(self):
        path = Path(self.temp.name) / 'repair.lock'
        with repair.exclusive_repair(path):
            with self.assertRaisesRegex(RuntimeError, 'repair_already_running'):
                with repair.exclusive_repair(path): self.fail('second lock acquired')
        with repair.exclusive_repair(path): self.assertTrue(path.exists())

    def test_remote_probe_outputs_only_fixed_safe_fields(self):
        remote = Mock(return_value=json.dumps(dict(HEALTHY, private='SECRET')))
        self.relay.transport = lambda: SimpleNamespace(remote=remote)
        with self.assertRaisesRegex(RuntimeError, 'remote_check_invalid'): repair.remote_probe(self.relay)


if __name__ == '__main__': unittest.main()
