from contextlib import ExitStack, nullcontext, redirect_stdout
import io
import json
from pathlib import Path
import socket
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

import hammer_backend_bridge as bridge


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.worker = bridge.Bridge(key=self.root / 'private-key')
        self.game = {'status': 'authentication_required', 'session': 'session-A',
                     'players': 1, 'authenticated': 0, 'loaded': 0}
        for obj, name, value in ((bridge, 'inspect_game', self.game),
                                 (bridge.tunnel, 'connect', {'ok': True}),
                                 (bridge.auth, 'inject', {'ok': True}),
                                 (bridge.time, 'monotonic', 100)):
            mocker = patch.object(obj, name, return_value=value)
            setattr(self, name, mocker.start())
            self.addCleanup(mocker.stop)
        lock = patch.object(bridge.tunnel, 'state_lock', side_effect=lambda _: nullcontext())
        lock.start()
        self.addCleanup(lock.stop)

    def test_waiting_or_other_map_does_not_open_tunnel_or_read_credentials(self):
        for state in ('waiting_for_workshop', 'waiting_for_map', 'waiting_for_party'):
            self.inspect_game.return_value = {'status': state}
            self.assertEqual(self.worker.step(), {'ok': True, 'status': state})
        self.connect.assert_not_called()
        self.inject.assert_not_called()

    def test_new_game_injects_once_and_preserves_loaded_profiles_on_followup(self):
        self.assertEqual(self.worker.step()['status'], 'authentication_applied')
        self.game.update(status='configured', authenticated=1, loaded=1)
        self.assertEqual(self.worker.step(), {'ok': True, 'status': 'connected',
            'players': 1, 'authenticated_players': 1, 'loaded_profiles': 1})
        self.inject.assert_called_once()
        self.connect.assert_called_once()

    def test_new_map_session_and_lost_token_each_trigger_fresh_injection(self):
        self.worker.step()
        self.game.update(status='configured', session='session-B')
        self.worker.step()
        self.game['status'] = 'authentication_required'
        self.worker.step()
        self.assertEqual(self.inject.call_count, 3)

    def test_restart_with_existing_token_still_verifies_current_env_once(self):
        self.game['status'] = 'configured'
        self.worker.step()
        self.inject.assert_called_once()

    def test_tunnel_recovery_is_periodic_and_does_not_reset_loaded_game(self):
        self.worker.step()
        self.game['status'] = 'configured'
        self.monotonic.return_value = 121
        self.worker.step()
        self.assertEqual(self.connect.call_count, 2)
        self.inject.assert_called_once()

    def test_unknown_listener_and_backend_failure_never_inject(self):
        self.connect.side_effect = bridge.tunnel.TunnelError('local_port_8765_in_use')
        self.assertEqual(bridge.safe_step(self.worker)['error'], 'local_port_8765_in_use')
        self.inject.assert_not_called()
        self.connect.side_effect = None
        self.connect.return_value = {'ok': False}
        self.assertEqual(bridge.safe_step(self.worker)['status'], 'retrying')
        self.inject.assert_not_called()

    def test_failed_injection_is_not_cached_and_is_retried(self):
        self.inject.side_effect = bridge.auth.AuthError('tools_server_confirmation_missing')
        self.assertFalse(bridge.safe_step(self.worker)['ok'])
        self.assertIsNone(self.worker.session)
        self.inject.side_effect = None
        self.assertEqual(self.worker.step()['status'], 'authentication_applied')

    def test_unexpected_error_text_is_never_exposed(self):
        self.inject.side_effect = subprocess.TimeoutExpired('secret-command-content', 10)
        result = bridge.safe_step(self.worker)
        self.assertNotIn('secret', json.dumps(result))
        self.assertEqual(result['error'], 'local_bridge_operation_failed')


class InspectionTests(unittest.TestCase):
    def test_resident_waits_for_startup_race_with_one_shot_diagnostic(self):
        busy = bridge.tunnel.TunnelError('tunnel_operation_in_progress')
        with patch.object(bridge, '_run_locked', side_effect=[busy, {'ok': True, 'status': 'stopped'}]) as run, \
                patch.object(bridge.time, 'sleep'), patch.object(bridge, 'STOP', Mock(exists=lambda: False)):
            self.assertEqual(bridge.run(Mock())['status'], 'stopped')
            self.assertEqual(run.call_count, 2)
        with patch.object(bridge, '_run_locked', side_effect=busy):
            self.assertEqual(bridge.run(Mock(), once=True)['status'], 'already_running')

    def test_stop_requested_during_startup_is_preserved_before_any_connection(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            stop = root / 'bridge.stop'
            stop.write_text('stop\n')
            with patch.object(bridge, 'OUTPUT', root), patch.object(bridge, 'STOP', stop), \
                    patch.object(bridge, 'STATUS', root / 'bridge_status.json'), \
                    patch.object(bridge.auth, 'ignored'), \
                    patch.object(bridge.tunnel, 'state_lock', return_value=nullcontext()), \
                    patch.object(bridge, 'safe_step') as step:
                result = bridge.run(Mock())
                self.assertEqual(result['status'], 'stopped')
                self.assertTrue(stop.exists())
                step.assert_not_called()

    def test_paused_one_shot_never_inspects_or_injects(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            stop = root / 'bridge.stop'
            stop.write_text('stop\n')
            with patch.object(bridge, 'OUTPUT', root), patch.object(bridge, 'STOP', stop), \
                    patch.object(bridge, 'STATUS', root / 'bridge_status.json'), \
                    patch.object(bridge.auth, 'ignored'), \
                    patch.object(bridge.tunnel, 'state_lock', return_value=nullcontext()), \
                    patch.object(bridge, 'safe_step') as step:
                result = bridge.run(Mock(), once=True)
                self.assertEqual(result['status'], 'stopped')
                self.assertTrue(stop.exists())
                step.assert_not_called()

    def test_unpaused_one_shot_runs_normally_once(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            with patch.object(bridge, 'OUTPUT', root), patch.object(bridge, 'STOP', root / 'bridge.stop'), \
                    patch.object(bridge, 'STATUS', root / 'bridge_status.json'), \
                    patch.object(bridge.auth, 'ignored'), \
                    patch.object(bridge.tunnel, 'state_lock', return_value=nullcontext()), \
                    patch.object(bridge, 'safe_step', return_value={
                        'ok': True, 'status': 'authentication_applied'}) as step:
                result = bridge.run(Mock(), once=True)
                self.assertEqual(result['status'], 'authentication_applied')
                step.assert_called_once()

    def test_probe_uses_existing_strict_guard_and_loaded_survival_modules(self):
        code = bridge.inspection_lua()
        for value in ("IsInToolsMode()", "IsServer()", "'template_map'", 'host_timescale',
                      "package.loaded['systems/player_profile_service']", 'setup.get_session_id()'):
            self.assertIn(value, code)
        self.assertNotIn('LoadKeyValues(', code)
        self.assertNotIn('Convars:SetStr', code)
        self.assertNotIn('load_player', code)

    def test_console_history_is_not_logged_and_session_is_only_returned_as_hash(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(bridge, 'OUTPUT', Path(tmp)), \
                patch.object(bridge.auth, 'ignored'), patch.object(bridge.shutil, 'which', return_value='node'), \
                patch.object(socket, 'create_connection') as raw_probe, \
                patch.object(bridge.subprocess, 'run') as run:
            payload = {'status': 'configured', 'session': 'nonsecret-session-123',
                       'players': 1, 'authenticated': 1, 'loaded': 0}
            run.return_value = Mock(returncode=0, stdout=('unrelated-history-secret\n' +
                bridge.PREFIX + json.dumps(payload) + '\n').encode())
            result = bridge.inspect_game()
            self.assertEqual(result['status'], 'configured')
            self.assertEqual(len(result['session']), 64)
            self.assertNotIn('nonsecret-session-123', json.dumps(result))
            self.assertNotIn('unrelated-history-secret', json.dumps(result))
            self.assertTrue(run.call_args.kwargs['capture_output'])
            raw_probe.assert_not_called()
            self.assertFalse((Path(tmp) / 'bridge_probe.json').exists())
            run.return_value.stdout = b'echo GOUFAYU_HAMMER_STATE:{"status":"configured"}\n'
            self.assertEqual(bridge.inspect_game()['status'], 'waiting_for_map')

    def test_probe_removed_even_after_transport_timeout(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(bridge, 'OUTPUT', Path(tmp)), \
                patch.object(bridge.auth, 'ignored'), patch.object(bridge.shutil, 'which', return_value='node'), \
                patch.object(bridge.subprocess, 'run',
                    side_effect=subprocess.TimeoutExpired('node', 15)):
            with self.assertRaises(subprocess.TimeoutExpired):
                bridge.inspect_game()
            self.assertFalse((Path(tmp) / 'bridge_probe.json').exists())

    def test_refused_console_connection_is_safe_and_removes_probe(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(bridge, 'OUTPUT', Path(tmp)), \
                patch.object(bridge.auth, 'ignored'), patch.object(bridge.shutil, 'which', return_value='node'), \
                patch.object(socket, 'create_connection') as raw_probe, \
                patch.object(bridge.subprocess, 'run', return_value=Mock(returncode=1,
                    stdout=b'unrelated-console-secret', stderr=b'ECONNREFUSED')) as run:
            self.assertEqual(bridge.inspect_game(), {'status': 'waiting_for_workshop'})
            raw_probe.assert_not_called()
            run.assert_called_once()
            self.assertFalse((Path(tmp) / 'bridge_probe.json').exists())


class StopTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        for name, value in (('OUTPUT', self.root), ('STOP', self.root / 'bridge.stop'),
                            ('STATUS', self.root / 'bridge_status.json')):
            self.stack.enter_context(patch.object(bridge, name, value))
        self.ignored = self.stack.enter_context(patch.object(bridge.auth, 'ignored'))
        self.lock = self.stack.enter_context(patch.object(bridge.tunnel, 'state_lock',
                                                         side_effect=lambda _: nullcontext()))
        self.monotonic = self.stack.enter_context(patch.object(bridge.time, 'monotonic', return_value=100))
        self.sleep = self.stack.enter_context(patch.object(bridge.time, 'sleep'))

    def test_no_worker_confirms_stop_and_never_reads_api_or_process_state(self):
        with patch.object(bridge.auth, 'inject') as inject, \
                patch.object(bridge.local_config, 'load') as config, \
                patch.object(bridge.tunnel, 'read_state') as read_state:
            result = bridge.stop()
        self.assertTrue(result['ok'])
        self.assertTrue(result['stop_confirmed'])
        self.assertEqual(result['status'], 'stopped')
        self.assertEqual(bridge.STOP.read_text(encoding='ascii'), 'stop\n')
        self.lock.assert_called_once_with(self.root / 'bridge_instance.json')
        inject.assert_not_called()
        config.assert_not_called()
        read_state.assert_not_called()
        self.sleep.assert_not_called()
        for path in (bridge.STOP, bridge.STATUS, self.root / 'bridge_instance.lock'):
            self.assertIn(unittest.mock.call(path), self.ignored.call_args_list)

    def test_busy_worker_must_release_instance_lock_before_stop_is_confirmed(self):
        attempts = []

        def enter(path):
            self.assertTrue(bridge.STOP.exists(), 'request stop before waiting for worker')
            self.assertFalse(bridge.STATUS.exists(), 'must not publish stopped while worker owns lock')
            attempts.append(path)
            if len(attempts) < 3:
                raise bridge.tunnel.TunnelError('tunnel_operation_in_progress')
            return nullcontext()

        self.lock.side_effect = enter
        result = bridge.stop()
        self.assertTrue(result['stop_confirmed'])
        self.assertEqual(len(attempts), 3)
        self.assertEqual(self.sleep.call_count, 2)
        self.assertEqual(json.loads(bridge.STATUS.read_text())['status'], 'stopped')

    def test_persistent_busy_times_out_without_force_kill_or_false_confirmation(self):
        self.lock.side_effect = bridge.tunnel.TunnelError('tunnel_operation_in_progress')
        self.monotonic.side_effect = [100, 154.9, 155]
        with patch.object(bridge, 'publish') as publish, \
                patch.object(bridge.subprocess, 'run') as process_call:
            with self.assertRaisesRegex(bridge.auth.AuthError, '^bridge_stop_timeout$'):
                bridge.stop()
            publish.assert_not_called()
            process_call.assert_not_called()
        self.assertTrue(bridge.STOP.exists())
        self.assertFalse(bridge.STATUS.exists())
        self.assertEqual(self.lock.call_count, 2)
        self.assertLessEqual(self.sleep.call_args.args[0], 0.25)
        self.assertLessEqual(bridge.STOP_WAIT_SECONDS, 55)

    def test_unexpected_lock_failure_propagates_without_stopped_status(self):
        self.lock.side_effect = bridge.tunnel.TunnelError('fixture_lock_invalid')
        with self.assertRaisesRegex(bridge.tunnel.TunnelError, '^fixture_lock_invalid$'):
            bridge.stop()
        self.assertTrue(bridge.STOP.exists())
        self.assertFalse(bridge.STATUS.exists())
        self.sleep.assert_not_called()

    def test_stop_validates_marker_and_actual_lock_before_any_write(self):
        for rejected in (bridge.STOP, self.root / 'bridge_instance.lock'):
            with self.subTest(path=rejected.name):
                calls = []

                def validate(path):
                    calls.append(path)
                    if path == rejected:
                        raise bridge.auth.AuthError('reparse_path_refused')

                with patch.object(bridge.auth, 'no_reparse', side_effect=validate):
                    with self.assertRaisesRegex(bridge.auth.AuthError, 'reparse_path_refused'):
                        bridge.stop()
                self.assertIn(rejected, calls)
                self.assertFalse(bridge.STOP.exists())
                self.lock.assert_not_called()

    def test_stop_rejects_nonignored_output_before_writing_marker(self):
        self.ignored.side_effect = bridge.auth.AuthError('temporary_auth_file_not_git_ignored')
        with self.assertRaisesRegex(bridge.auth.AuthError, 'temporary_auth_file_not_git_ignored'):
            bridge.stop()
        self.assertFalse(bridge.STOP.exists())
        self.lock.assert_not_called()

    def test_cli_timeout_returns_fixed_error_and_preserves_pending_stop(self):
        with patch('sys.argv', ['hammer_backend_bridge.py', 'stop']), \
                patch.object(bridge, 'stop', side_effect=bridge.auth.AuthError('bridge_stop_timeout')) as stop, \
                redirect_stdout(io.StringIO()) as output:
            result = bridge.main()
        stop.assert_called_once()
        self.assertEqual(result, 1)
        self.assertEqual(json.loads(output.getvalue()), {'ok': False, 'error': 'bridge_stop_timeout'})


if __name__ == '__main__':
    unittest.main()
