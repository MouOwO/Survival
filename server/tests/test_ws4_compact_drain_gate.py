"""Actual gate/controller helpers with simulated OS edges; no SSH or firewall."""
from pathlib import Path
import ast
import contextlib
import hashlib
import importlib.util
import json
import signal
import subprocess
import sys
import tempfile
import types
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[2]
def load(name, relative):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
gate_module = load('reviewed_ws4_drain', 'tools/ws4_compact_receipt_20261106/drain_gate.py')
deploy = load('reviewed_ws4_deploy', 'tools/ws4_compact_receipt_20261106/deploy.py')


class GateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.executable = self.root / 'iptables'
        self.executable.write_bytes(b'fixed tool')
        self.gate = gate_module.NewConnectionGate(str(self.executable.resolve()),
            gate_module.digest(b'fixed tool'), {'source': 'a' * 40, 'parent': 'b' * 64}, self.root / 'intent.json')
        self.present = False
        self.actions = []
        self.insert_timeout = self.delete_timeout = False
        def execute(action):
            self.actions.append(action)
            if action == '-C':
                return 0 if self.present else 1
            if action == '-I':
                self.present = True
                if self.insert_timeout:
                    raise subprocess.TimeoutExpired('iptables', 4)
                return 0
            if action == '-D':
                self.present = False
                if self.delete_timeout:
                    raise subprocess.TimeoutExpired('iptables', 4)
                return 0
            raise AssertionError(action)
        self.gate.execute = execute
        self.run = patch.object(gate_module.subprocess, 'run', return_value=types.SimpleNamespace(returncode=0, stdout=b''))
        self.run.start()
        self.addCleanup(self.run.stop)

    def test_insert_timeout_after_kernel_success_still_removes_exact_rule(self):
        self.insert_timeout = True
        with self.assertRaises(subprocess.TimeoutExpired):
            self.gate.install()
        self.assertTrue(self.present)
        self.assertTrue(self.gate.reconcile_remove()['absent'])
        self.assertFalse(self.present)
        self.assertEqual(self.actions, ['-C', '-I', '-C', '-D', '-C'])

    def test_delete_timeout_after_kernel_success_is_reconciled(self):
        self.gate.install()
        self.delete_timeout = True
        self.assertTrue(self.gate.reconcile_remove()['absent'])

    def test_delete_failure_is_never_reported_as_absent(self):
        self.gate.install()
        original = self.gate.execute
        self.gate.execute = lambda action: 1 if action == '-D' else original(action)
        with self.assertRaisesRegex(gate_module.DrainError, 'exact_gate_cleanup_failed'):
            self.gate.reconcile_remove()
        self.assertTrue(self.present)

    def test_existing_other_owned_gate_prevents_install(self):
        with patch.object(gate_module.subprocess, 'run', return_value=types.SimpleNamespace(returncode=0, stdout=b'-A OUTPUT --comment ws4-compact-older')):
            with self.assertRaisesRegex(gate_module.DrainError, 'previous_ws4_gate_requires_recovery'):
                self.gate.install()
        self.assertNotIn('-I', self.actions)

    def test_modified_intent_never_authorizes_rule_removal(self):
        self.gate.install()
        self.gate.record.write_text('{}')
        with self.assertRaisesRegex(gate_module.DrainError, 'gate_intent_changed'):
            self.gate.reconcile_remove()
        self.assertNotIn('-D', self.actions)

    def test_missing_gate_mid_drain_rejects(self):
        self.gate.install()
        self.present = False
        with self.assertRaisesRegex(gate_module.DrainError, 'gate_missing'):
            gate_module.wait_for_drain(self.gate, {})

    def test_rule_only_blocks_ipv4_loopback_new_unmarked_18765(self):
        self.assertEqual(self.gate.rule[:10], ['OUTPUT', '-o', 'lo', '-d', '127.0.0.1/32', '-p', 'tcp', '--dport', '18765', '-m'])
        self.assertIn('NEW', self.gate.rule)
        self.assertIn('!', self.gate.rule)
        self.assertNotIn('FLUSH', self.gate.rule)


class DrainTests(unittest.TestCase):
    def listener(self, protocol='tcp', address='0100007F'):
        return dict(protocol=protocol, address=address, state='0A', inode='1')

    def test_wildcard_and_ipv6_listeners_rejected(self):
        for rows in ([self.listener(address='00000000')], [self.listener('tcp6', '00000000000000000000000001000000')],
                     [self.listener(), self.listener('tcp6', '00000000000000000000000000000000')], []):
            with self.subTest(rows=rows), self.assertRaisesRegex(gate_module.DrainError, 'only_ipv4_loopback'):
                gate_module.validate_listener(rows)

    def test_exact_ipv4_listener_accepted(self):
        self.assertEqual(gate_module.validate_listener([self.listener()]), self.listener())

    def run_samples(self, samples, timeout=.5):
        clock = [0]
        def sleep(seconds): clock[0] += seconds
        gate = Mock()
        with patch.object(gate_module, 'drain_sample', side_effect=samples):
            return gate_module.wait_for_drain(gate, {}, timeout, lambda: clock[0], sleep), gate

    def test_two_idle_samples_required_after_busy_or_disconnected_request(self):
        result, gate = self.run_samples([{'idle': True}, {'idle': False, 'task_count': 2, 'active_namespace_sockets': 0},
                                        {'idle': True}, {'idle': True}])
        self.assertEqual(result['samples'], 4)
        self.assertEqual(gate.verify.call_count, 5)

    def test_busy_request_times_out_without_any_service_control(self):
        with self.assertRaisesRegex(gate_module.DrainError, 'drain_timeout_service_untouched'):
            self.run_samples([{'idle': False}] * 10, timeout=.4)

    def test_changed_process_is_not_treated_as_idle(self):
        with patch.object(gate_module, 'process_identity', side_effect=gate_module.DrainError('process_start_changed')):
            with self.assertRaisesRegex(gate_module.DrainError, 'process_start_changed'):
                gate_module.drain_sample({'pid': 1, 'cwd': '/old', 'start': 2})


class ControllerTests(unittest.TestCase):
    def setUp(self):
        self.commands = []
        functions = ast.Module(body=[node for node in ast.parse(deploy.REMOTE).body if isinstance(node, ast.FunctionDef)], type_ignores=[])
        self.env = dict(Path=Path, json=json, sha=lambda raw: hashlib.sha256(raw).hexdigest(),
                        gate_api={'process_identity': Mock(return_value={'pid': 9, 'cwd': '/new/backend', 'start': 4}),
                                  'wait_for_drain': Mock(return_value={'drained': True})},
                        command=lambda args: self.commands.append(args))
        exec(compile(functions, 'actual_remote_helpers', 'exec'), self.env)

    def test_failed_drain_never_stops_service(self):
        self.env['gate_api']['wait_for_drain'].side_effect = gate_module.DrainError('busy')
        with self.assertRaisesRegex(gate_module.DrainError, 'busy'):
            self.env['stop_drained'](Mock(), Path('/new'), {'pid': 9})
        self.assertEqual(self.commands, [])

    def test_gate_and_identity_rechecked_before_stop(self):
        order = []
        gate = Mock()
        gate.verify.side_effect = lambda: order.append('gate')
        self.env['gate_api']['process_identity'].side_effect = lambda *args: order.append('identity') or {'pid': 9, 'cwd': '/new/backend', 'start': 4}
        self.env['gate_api']['wait_for_drain'].side_effect = lambda *args: order.append('drain') or {'drained': True}
        states = iter([(Path('/new'), {'pid': 9}), (Path('/new'), {'pid': 0})])
        self.env['observed'] = lambda: next(states)
        self.env['command'] = lambda args: order.append('stop')
        self.env['stop_drained'](gate, Path('/new'), {'pid': 9})
        self.assertEqual(order, ['gate', 'identity', 'drain', 'gate', 'identity', 'stop'])

    def test_cleanup_failure_keeps_watchdog_armed_and_success_false(self):
        gate = Mock()
        gate.reconcile_remove.side_effect = RuntimeError('private diagnostic')
        self.env['finish_watchdog'] = Mock()
        result = self.env['gate_cleanup']({}, gate, {'ok': True})
        self.assertFalse(result['ok'])
        self.assertTrue(result['watchdog_recovery_required'])
        self.env['finish_watchdog'].assert_not_called()
        self.assertNotIn('private diagnostic', json.dumps(result))

    def test_cleanup_disarms_only_after_confirmed_removal(self):
        gate = Mock()
        gate.reconcile_remove.return_value = {'absent': True}
        self.env['finish_watchdog'] = Mock()
        result = self.env['gate_cleanup']({}, gate, {'ok': False})
        self.assertTrue(result['gate_cleanup']['absent'])
        self.env['finish_watchdog'].assert_called_once_with({}, gate)

    def test_verify_failed_candidate_enters_parent_recovery(self):
        self.env.update(new=Path('/new'), old=Path('/old'), unit=Mock(),
                        settled_observed=lambda: (Path('/new'), {'pid': 9,'active_state':'active','sub_state':'running'}),
                        validate_controls=lambda original: ({'bound': True}, (b'old', b'new')),
                        validate_candidate=Mock(side_effect=RuntimeError('bad candidate')),
                        rollback_parent=Mock(return_value={'ok': True, 'restored': 'old'}))
        self.env['unit'].read_bytes.return_value = b'new'
        gate = Mock()
        result = self.env['recover_control']({}, gate)
        self.assertEqual(result, {'ok': True, 'restored': 'old'})
        self.env['rollback_parent'].assert_called_once_with({}, Path('/new'), {'pid': 9,'active_state':'active','sub_state':'running'}, b'new', gate)

    def test_watchdog_preserves_healthy_candidate_but_requires_explicit_verify(self):
        self.env.update(new=Path('/new'), old=Path('/old'), unit=Mock(),
                        settled_observed=lambda: (Path('/new'), {'pid': 9,'active_state':'active','sub_state':'running'}),
                        validate_controls=lambda original: ({'bound': True}, (b'old', b'new')),
                        validate_candidate=Mock(), health=Mock(), rollback_parent=Mock())
        self.env['unit'].read_bytes.return_value = b'new'
        result = self.env['recover_control']({}, Mock())
        self.assertEqual(result['status'], 'INTERRUPTED_CANDIDATE_HEALTHY_REQUIRES_EXPLICIT_VERIFY')
        self.env['rollback_parent'].assert_not_called()


class ActivationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.unit = self.root / 'unit'
        self.unit.write_bytes(b'old')
        self.old, self.new = self.root / 'parent', self.root / 'candidate'
        self.new.mkdir()
        (self.new / 'release_manifest.json').write_bytes(b'manifest')
        self.events = []
        self.pid, self.process_release = 7, self.old
        self.clock = 0
        self.candidate_unhealthy = False
        self.fail_start = False
        self.gate = Mock()
        self.gate.marker = 123
        self.gate.install.side_effect = lambda: self.events.append('install')
        self.gate.verify.side_effect = lambda: self.events.append('verify_gate')
        self.gate.reconcile_remove.side_effect = lambda: self.events.append('remove') or {'absent': True}
        functions = ast.Module(body=[node for node in ast.parse(deploy.REMOTE).body if isinstance(node, ast.FunctionDef)], type_ignores=[])
        fake_signal = types.SimpleNamespace(SIGTERM=15, SIGHUP=1, SIGALRM=14, signal=Mock(return_value='prior'), alarm=Mock())
        self.env = dict(Path=Path, json=json, sha=lambda raw: hashlib.sha256(raw).hexdigest(),
            old=self.old, new=self.new, unit=self.unit, UNIT_SHA=hashlib.sha256(b'old').hexdigest(), pins={'file':'hash'},
            GATE_EXECUTABLE='/iptables', GATE_EXECUTABLE_SHA='a'*64,
            signal=fake_signal, time=types.SimpleNamespace(monotonic=lambda: self.clock, sleep=self.sleep),
            gate_api={'CONTROLLER_SECONDS':60, 'gate_audit': lambda pid: {'executable':'/iptables','executable_sha256':'a'*64}})
        exec(compile(functions, 'actual_activation_helpers', 'exec'), self.env)
        self.env.update(validate_probe=Mock(), validate_candidate=Mock(),
            validate_controls=lambda original: ({'fixed':True},(b'old',b'new')),
            make_gate=lambda original: self.gate, start_watchdog=lambda original: self.events.append('watchdog') or {'ready':True},
            stop_drained=self.stop_drained, observed=lambda: (self.process_release, {'pid':self.pid,'active_state':'active' if self.pid else 'inactive','sub_state':'running' if self.pid else 'dead','job':''}),
            command=self.command, health=self.health, keep_services=lambda: self.events.append('retained'),
            replace_unit=lambda expected,target: self.unit.write_bytes(target),
            finish_watchdog=lambda original,gate: self.events.append('disarm'), recover_control=self.recover)

    def sleep(self, seconds): self.clock += seconds
    def stop_drained(self, gate, release, state):
        self.events.append('drained_stop')
        self.pid = 0
        return {'drained':True}
    def command(self, args):
        self.events.append(args[1])
        if args[1] == 'start':
            if self.fail_start:
                raise RuntimeError('start failure')
            self.pid, self.process_release = 9, self.new
    def health(self):
        self.events.append('health')
        if self.candidate_unhealthy and self.process_release == self.new:
            self.clock += 3
            raise RuntimeError('unhealthy')
    def recover(self, original, gate):
        self.events.append('recover')
        self.unit.write_bytes(b'old')
        self.pid, self.process_release = 7, self.old
        return {'ok':True,'restored':'parent'}
    def activate(self):
        return self.env['activate_candidate']({}, self.old, {'pid':7}, b'old')

    def test_success_arms_before_gate_and_disarms_after_health_and_remove(self):
        result = self.activate()
        self.assertTrue(result['ok'])
        self.assertLess(self.events.index('watchdog'), self.events.index('install'))
        self.assertLess(self.events.index('install'), self.events.index('drained_stop'))
        self.assertLess(self.events.index('health'), self.events.index('remove'))
        self.assertLess(self.events.index('remove'), self.events.index('disarm'))
        self.assertNotIn('recover', self.events)

    def test_drain_failure_keeps_parent_and_removes_gate(self):
        self.env['stop_drained'] = Mock(side_effect=gate_module.DrainError('busy'))
        result = self.activate()
        self.assertFalse(result['ok'])
        self.assertEqual(self.unit.read_bytes(), b'old')
        self.assertNotIn('start', self.events)
        self.assertIn('remove', self.events)

    def test_start_failure_recovers_parent_and_cleans_gate(self):
        self.fail_start = True
        result = self.activate()
        self.assertFalse(result['ok'])
        self.assertTrue(result['recovery']['ok'])
        self.assertLess(self.events.index('recover'), self.events.index('remove'))
        self.assertEqual(self.unit.read_bytes(), b'old')

    def test_unhealthy_candidate_is_bounded_and_recovered(self):
        self.candidate_unhealthy = True
        result = self.activate()
        self.assertFalse(result['ok'])
        self.assertLess(self.clock, 18)
        self.assertTrue(result['recovery']['ok'])
        self.assertIn('remove', self.events)

    def test_parent_recovery_failure_still_cleans_exact_gate_and_reports_failure(self):
        self.fail_start = True
        self.env['recover_control'] = Mock(side_effect=RuntimeError('private details'))
        result = self.activate()
        self.assertFalse(result['ok'])
        self.assertFalse(result['recovery']['ok'])
        self.assertIn('remove', self.events)
        self.assertNotIn('private details', json.dumps(result))

    def test_insert_timeout_after_possible_insertion_enters_cleanup(self):
        self.gate.install.side_effect = subprocess.TimeoutExpired('iptables', 4)
        result = self.activate()
        self.assertFalse(result['ok'])
        self.assertNotIn('drained_stop', self.events)
        self.assertIn('remove', self.events)

    def test_watchdog_start_failure_cannot_install_gate_or_stop_service(self):
        self.env['start_watchdog'] = Mock(side_effect=RuntimeError('not ready'))
        result = self.activate()
        self.assertFalse(result['ok'])
        self.assertNotIn('install', self.events)
        self.assertNotIn('drained_stop', self.events)


class WatchdogTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.context = dict(record=str(self.root), binding={'operation':'fixed'}, gate_executable='/iptables',
            gate_executable_sha256='a'*64, recovery_source='raise RuntimeError("private prologue")')
        self.context['recovery_sha256'] = gate_module.digest(self.context['recovery_source'].encode())

    def test_recovery_prologue_failure_still_reconciles_exact_gate(self):
        gate = Mock()
        gate.reconcile_remove.return_value = {'absent':True}
        with patch.object(gate_module,'NewConnectionGate',return_value=gate), patch.object(gate_module,'cleanup_locks',side_effect=lambda: contextlib.nullcontext()):
            result = gate_module.watchdog_recover(self.context)
        gate.reconcile_remove.assert_called_once_with()
        self.assertFalse(result['recovery_returned'])
        self.assertTrue(result['gate_cleanup']['absent'])
        self.assertNotIn('private prologue', json.dumps(result))

    def test_lock_contention_is_bounded_and_not_false_cleaned(self):
        gate = Mock()
        with patch.object(gate_module,'NewConnectionGate',return_value=gate), patch.object(gate_module,'cleanup_locks',side_effect=gate_module.DrainError('watchdog_cleanup_lock_busy')):
            result = gate_module.watchdog_recover(self.context)
        gate.reconcile_remove.assert_not_called()
        self.assertTrue(result['operator_recovery_required'])
        self.assertFalse(result['gate_cleanup']['absent'])

    def test_changed_recovery_source_never_executes(self):
        self.context['recovery_sha256'] = '0'*64
        gate = Mock()
        gate.reconcile_remove.return_value = {'absent':True}
        with patch.object(gate_module,'NewConnectionGate',return_value=gate), patch.object(gate_module,'cleanup_locks',side_effect=lambda: contextlib.nullcontext()):
            result = gate_module.watchdog_recover(self.context)
        self.assertFalse(result['recovery_returned'])
        gate.reconcile_remove.assert_called_once_with()

    def test_temporary_lock_contention_retries_then_allows_cleanup(self):
        fcntl = types.SimpleNamespace(LOCK_EX=1,LOCK_NB=2,flock=Mock(side_effect=[BlockingIOError(),None,None]))
        files = [Mock(__enter__=Mock(),__exit__=Mock(return_value=False)) for _ in range(2)]
        with patch.dict(sys.modules, {'fcntl':fcntl}), patch.object(gate_module,'open',side_effect=files,create=True), patch.object(gate_module.time,'sleep') as sleep:
            with gate_module.cleanup_locks():
                pass
        self.assertEqual(fcntl.flock.call_count, 3)
        sleep.assert_called_once_with(.1)

    def watchdog(self, process_states, clock_values=None, receipt_write=None):
        context = {**self.context,'controller':{'pid':91,'cwd':'/controller','start':5}}
        fake_signal = types.SimpleNamespace(SIGHUP=1,SIGTERM=15,SIGKILL=9,SIG_IGN=1,signal=Mock())
        with patch.object(gate_module,'signal',fake_signal), patch.object(gate_module,'same_process',side_effect=process_states),\
             patch.object(gate_module,'process_identity',return_value={'pid':92,'cwd':'/watchdog','start':6}),\
             patch.object(gate_module,'watchdog_recover') as recover, patch.object(gate_module.os,'kill') as kill,\
             patch.object(gate_module.time,'sleep'), patch.object(gate_module.time,'monotonic',side_effect=clock_values or [0]),\
             patch.object(gate_module,'durable_new',side_effect=receipt_write):
            gate_module.watchdog_main(context)
        return recover,kill

    def test_dead_controller_recovers_without_signalling_any_process(self):
        recover,kill = self.watchdog([False,False,False])
        recover.assert_called_once()
        kill.assert_not_called()

    def test_controller_deadline_signals_only_bound_controller(self):
        recover,kill = self.watchdog([True,True,False,False,False,False],[0,76])
        kill.assert_called_once_with(91,15)
        recover.assert_called_once()

    def test_trigger_receipt_disk_failure_does_not_skip_recovery(self):
        recover,kill = self.watchdog([False,False,False],receipt_write=[None,OSError('disk full')])
        recover.assert_called_once()
        kill.assert_not_called()


if __name__ == '__main__':
    unittest.main()
