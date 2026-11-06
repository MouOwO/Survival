"""Exercise actual deploy helper bodies without SSH, systemctl or transactions."""
from pathlib import Path, PurePosixPath
import ast
import hashlib
import importlib.util
import json
import os
import re
import shutil
import tempfile
import unittest
from unittest.mock import Mock, patch


TOOL = Path(__file__).resolve().parents[2] / 'tools/ws4_compact_receipt_20261106/deploy.py'
spec = importlib.util.spec_from_file_location('compact_deploy_test_subject', TOOL)
deploy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deploy)


class DeploymentSafety(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.old, self.new = self.root / 'releases/parent', self.root / 'releases/candidate'
        self.old.mkdir(parents=True)
        self.new.mkdir()
        self.records = self.root / 'deployment_records/candidate'
        self.records.mkdir(parents=True)
        self.unit = self.root / 'service.unit'
        self.original_unit = ('[Service]\nWorkingDirectory=' + str(self.old / 'backend') + '\nExecStart=python -B -m api\n').encode()
        self.target_unit = self.original_unit.replace(str(self.old / 'backend').encode(), str(self.new / 'backend').encode())
        self.unit.write_bytes(self.target_unit)
        self.sha = lambda raw: hashlib.sha256(raw).hexdigest()
        parent_files = {'backend/archive_backend/service.py': b'parent\n', 'backend/extra.py': b'extra\n', 'addon/entry.lua': b'parent asset\n'}
        self.original = {}
        for name, raw in parent_files.items():
            target = self.old / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(raw)
            self.original[name] = self.sha(raw)
        self.pins = {'backend/archive_backend/service.py': self.sha(b'candidate\n'),
                     'backend/archive_backend/command_timing.py': self.sha(b'timing\n'),
                     'backend/archive_backend/lottery_receipt_snapshot.py': self.sha(b'compact\n')}
        env = dict(Path=Path, PurePosixPath=PurePosixPath, json=json, re=re, os=os, sha=self.sha,
                   old=self.old, new=self.new, unit=self.unit, records=self.records,
                   control_root=self.records.parent, SOURCE='a' * 40, OPERATOR='b' * 40,
                   SOURCE_PINS={'immutable': 'c' * 64}, pins=self.pins,
                   expected_manifest_digest='d' * 64, UNIT_SHA=self.sha(self.original_unit),
                   RECIPE='compact-receipt-v1', manifest={'files': self.original, 'release': 'parent'},
                   method_binding={'exact_parent': True})
        tree = ast.parse(deploy.REMOTE)
        selected = ast.Module(body=[node for node in tree.body if isinstance(node, ast.FunctionDef)], type_ignores=[])
        exec(compile(selected, str(TOOL) + ':REMOTE_HELPERS', 'exec'), env)
        self.env = env
        env['PARENT_INVENTORY_SHA'] = self.sha(env['canonical'](self.original))
        (self.records / 'unit.original').write_bytes(self.original_unit)
        (self.records / 'prepared_binding.json').write_bytes(env['canonical'](env['control_binding'](self.original)))
        self.commands = []
        env['command'] = lambda args: self.commands.append(args) or ''
        env['observed'] = lambda: (self.new, {'pid': 0, 'active_state': 'inactive'})
        env['active'] = lambda: (self.old, 77)
        env['start_parent'] = Mock()
        env['health'] = Mock()
        env['keep_services'] = Mock()
        # Retain exact replace_unit precondition while avoiding Unix-only chown.
        def replace_unit(expected, target):
            env['need'](self.sha(self.unit.read_bytes()) == expected, 'ws4_unit_changed')
            self.unit.write_bytes(target)
        env['replace_unit'] = replace_unit

    def candidate(self):
        for path in self.old.rglob('*'):
            if path.is_file():
                target = self.new / path.relative_to(self.old)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, target)
        for name, raw in [('service.py', b'candidate\n'), ('command_timing.py', b'timing\n'), ('lottery_receipt_snapshot.py', b'compact\n')]:
            (self.new / 'backend/archive_backend' / name).write_bytes(raw)
        (self.new / 'release_manifest.json').write_bytes(self.env['canonical'](self.env['candidate_manifest'](self.original)))
        # Test directory walking on disk; fake only the venv link when Windows
        # has no CreateSymbolicLink privilege. No candidate byte verification is mocked.
        (self.old / '.venv').mkdir(exist_ok=True)
        (self.new / '.venv').mkdir(exist_ok=True)
        real_is_symlink, real_resolve = Path.is_symlink, Path.resolve
        venv, parent_venv = self.new / '.venv', self.old / '.venv'
        symlink = patch.object(Path, 'is_symlink', lambda path: True if path == venv else real_is_symlink(path))
        resolve = patch.object(Path, 'resolve', lambda path, *a, **k: real_resolve(parent_venv, *a, **k) if path == venv else real_resolve(path, *a, **k))
        symlink.start(); resolve.start()
        self.addCleanup(symlink.stop); self.addCleanup(resolve.stop)

    def recover(self, pid=0, current=None, active_state='failed'):
        return self.env['rollback_parent'](self.original, current or self.new,
                                          {'pid': pid, 'active_state': active_state}, self.unit.read_bytes())

    def assert_rejected(self, function, reason, *args):
        with self.assertRaisesRegex(RuntimeError, reason):
            function(*args)

    def test_pid_zero_missing_candidate_directory_recovers_exact_parent(self):
        self.new.rmdir()
        result = self.recover()
        self.assertTrue(result['ok'])
        self.assertTrue(result['candidate_files_not_required'])
        self.assertEqual(self.unit.read_bytes(), self.original_unit)
        self.assertEqual(self.commands, [['systemctl', 'stop', 'goufayu-ws4.service']])
        self.env['start_parent'].assert_called_once_with()

    def test_pid_zero_corrupt_candidate_manifest_recovers(self):
        (self.new / 'release_manifest.json').write_text('{corrupt')
        self.assertTrue(self.recover()['ok'])

    def test_pid_zero_parent_unit_can_be_started(self):
        self.unit.write_bytes(self.original_unit)
        self.env['observed'] = lambda: (self.old, {'pid': 0})
        self.assertTrue(self.recover(current=self.old)['ok'])

    def test_unit_replaced_before_daemon_reload_can_recover_when_stopped(self):
        self.env['observed'] = lambda: (self.old, {'pid': 0})
        self.assertTrue(self.recover(current=self.old)['ok'])
        self.assertEqual(self.unit.read_bytes(), self.original_unit)

    def test_unrelated_unit_rejected_before_any_service_action(self):
        self.unit.write_bytes(self.target_unit + b'Environment=UNRELATED=1\n')
        self.assert_rejected(self.recover, 'rollback_unrelated_unit_rejected')
        self.assertEqual(self.commands, [])

    def test_parent_manifest_file_drift_rejected(self):
        (self.old / 'addon/entry.lua').write_bytes(b'changed')
        self.assert_rejected(self.env['parent_inventory'], 'release_file_hash_changed')

    def test_unmanifested_parent_python_drift_bound_to_audit(self):
        (self.old / 'backend/new.py').write_bytes(b'new')
        current = self.env['parent_inventory']()
        self.assert_rejected(self.env['validate_parent_inventory'], 'audited_parent_inventory_changed', current)

    def test_bad_independent_backup_rejected_without_candidate_dependency(self):
        (self.records / 'unit.original').write_bytes(b'bad')
        self.assert_rejected(self.recover, 'original_unit_backup_changed')
        self.assertEqual(self.commands, [])

    def test_live_candidate_never_stopped_without_reviewed_gate(self):
        self.assert_rejected(lambda: self.recover(pid=88), 'live_rollback_requires_reviewed_connection_drain_gate')
        self.assertEqual(self.commands, [])

    def test_automatic_restart_job_never_assumed_drained(self):
        self.assert_rejected(lambda: self.recover(active_state='activating'), 'rollback_restart_job_requires_drain_review')
        self.assertEqual(self.commands, [])

    def test_healthy_but_deactivating_parent_never_reported_active(self):
        self.unit.write_bytes(self.original_unit)
        self.assert_rejected(lambda: self.recover(pid=77,current=self.old,active_state='deactivating'),
                             'parent_service_transition_requires_recovery')
        self.env['health'].assert_not_called()
        self.assertEqual(self.commands, [])

    def test_parent_start_failure_reports_restored_unit_and_no_success(self):
        self.env['start_parent'].side_effect = RuntimeError('sensitive internal diagnostic')
        result = self.recover()
        self.assertFalse(result['ok'])
        self.assertEqual(result['status'], 'PARENT_UNIT_RESTORED_START_OR_HEALTH_FAILED')
        self.assertEqual(self.unit.read_bytes(), self.original_unit)
        self.assertNotIn('sensitive', json.dumps(result))

    def test_receipt_failure_preserves_explicit_recovered_state(self):
        self.env['save'] = Mock(side_effect=OSError('private path'))
        result = self.env['record_recovery'](self.recover())
        self.assertFalse(result['ok'])
        self.assertFalse(result['receipt_persisted'])
        self.assertEqual(result['status'], 'OWN_WS4_COMPACT_RECEIPT_ROLLED_BACK')
        self.assertEqual(self.unit.read_bytes(), self.original_unit)

    def test_postcheck_failure_never_reports_unqualified_success(self):
        self.env['keep_services'].side_effect = RuntimeError('pid changed')
        result = self.env['record_recovery'](self.recover())
        self.assertFalse(result['ok'])
        self.assertFalse(result['retained_services_unchanged'])
        self.assertTrue(result['receipt_persisted'])

    def test_exact_candidate_passes(self):
        self.candidate()
        self.assertEqual(self.env['validate_candidate'](self.original)['files'], {**self.original, **self.pins})

    def test_nonpayload_and_self_reported_hash_modified_together_rejected(self):
        self.candidate()
        (self.new / 'backend/extra.py').write_bytes(b'changed')
        doc = json.loads((self.new / 'release_manifest.json').read_bytes())
        doc['files']['backend/extra.py'] = self.sha(b'changed')
        (self.new / 'release_manifest.json').write_bytes(self.env['canonical'](doc))
        self.assert_rejected(self.env['validate_candidate'], 'exact_candidate_manifest_changed', self.original)

    def test_removed_manifest_entry_rejected(self):
        self.candidate()
        doc = json.loads((self.new / 'release_manifest.json').read_bytes())
        del doc['files']['backend/extra.py']
        (self.new / 'release_manifest.json').write_bytes(self.env['canonical'](doc))
        self.assert_rejected(self.env['validate_candidate'], 'exact_candidate_manifest_changed', self.original)

    def test_additional_runtime_file_rejected(self):
        self.candidate()
        (self.new / 'backend/untracked.py').write_bytes(b'untracked')
        self.assert_rejected(self.env['validate_candidate'], 'candidate_runtime_file_set_changed', self.original)

    def test_missing_venv_rejected(self):
        self.assert_rejected(self.env['validate_candidate'], 'candidate_venv_lineage_changed', self.original)

    def probe(self):
        value = dict(ok=True, status='ACTUAL_WS4_PREPARED_COMPACT_RECEIPT_PARITY_PASS',
                     binding=self.env['control_binding'](self.original), rpc_calls=0, database_writes=0,
                     real_player_data_used=False, samples=[dict(equal=True, **{key: {'real_rpc_calls': 0} for key in ('parent', 'legacy', 'compact')}) for _ in range(3)])
        (self.records / 'probe.json').write_text(json.dumps(value))
        return value

    def test_probe_full_binding_valid(self):
        self.probe()
        self.assertTrue(self.env['validate_probe'](self.original)['ok'])

    def test_probe_operator_or_manifest_binding_drift_rejected(self):
        value = self.probe()
        value['binding']['prepared_manifest_sha256'] = '0' * 64
        (self.records / 'probe.json').write_text(json.dumps(value))
        self.assert_rejected(self.env['validate_probe'], 'probe_binding_changed', self.original)

    def test_live_stop_requires_gate_before_any_service_action(self):
        self.assert_rejected(lambda: self.env['stop_drained'](None, self.new, {'pid': 88}),
                             'live_rollback_requires_reviewed_connection_drain_gate')
        self.assertEqual(self.commands, [])


if __name__ == '__main__':
    unittest.main()
