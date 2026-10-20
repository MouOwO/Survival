"""Offline operator safety checks. No SSH, service or database is contacted."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import call, patch

SPEC = importlib.util.spec_from_file_location('archive_caps_operator', Path(__file__).with_name('deploy_remote.py'))
operator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(operator)


class OperatorTests(unittest.TestCase):
    def plan(self):
        migrations = [{'id': 'target/'+name, 'path': 'database/migrations/target/'+name, 'sha256': '3'*64}
                      for name in operator.MIGRATIONS]
        return {'expected': {'release': 'old-release', 'bundle_hash': '1'*64,
                             'ledger': [{'id': 'old_'+str(i), 'sha256': '4'*64} for i in range(26)]},
                'candidate': {'release_id': 'new-release', 'bundle_hash': '2'*64,
                              'migrations': migrations, 'overlay': {row['path']: row['sha256'] for row in migrations}}}

    def test_paths_reject_traversal_absolute_aliases_and_windows_forms(self):
        for name in ('../secret', 'a/../b', '/etc/config', 'C:/private', 'a\\b', './a', 'a//b', ''):
            with self.subTest(name=name), self.assertRaises(operator.Refused):
                operator.relative(name)
        self.assertEqual(str(operator.relative('backend/archive_backend/clear_receipts.py')), 'backend/archive_backend/clear_receipts.py')
        self.assertIn('backend/archive_backend/clear_receipts.py', operator.BACKEND_OVERLAYS)
        self.assertIn('backend/fishing_api/postgres.py', operator.BACKEND_OVERLAYS)

    def test_plan_hash_and_exact_migration_order_are_required(self):
        with tempfile.TemporaryDirectory() as temporary:
            stage = Path(temporary)
            plan = self.plan()
            path = stage/'plan.json'
            path.write_text(json.dumps(plan), encoding='utf-8')
            with self.assertRaisesRegex(operator.Refused, 'plan_digest_changed'):
                operator.Operator(stage, '0'*64)
            self.assertEqual(operator.Operator(stage, operator.file_hash(path)).bundle, '2'*64)
            plan['candidate']['migrations'].reverse()
            path.write_text(json.dumps(plan), encoding='utf-8')
            with self.assertRaisesRegex(operator.Refused, 'migration_sequence_invalid'):
                operator.Operator(stage, operator.file_hash(path))

    def test_sync_change_only_adds_one_exact_branch_and_preserves_all_old_bytes(self):
        original = ("CREATE OR REPLACE FUNCTION public.archive_sync_config(p_hash text, p_config jsonb)\n"
                    " RETURNS jsonb LANGUAGE plpgsql AS $function$\ndeclare v jsonb;\nbegin\n"
                    " if jsonb_typeof(p_config) is distinct from 'object' then raise exception 'bad'; end if;\n"
                    " -- Reviewed daily unique points: exact configuration with backed-up inventory repair.\n"
                    " if p_hash='old-reviewed-hash' then return '{}'::jsonb; end if;\n"
                    " raise exception 'archive_compatibility_invalid';\nend; $function$\n")
        candidate = operator.exact_sync_branch(original, '2'*64, '3'*64)
        marker = ' -- Reviewed daily unique points: exact configuration with backed-up inventory repair.'
        prefix = original[:original.index(marker)]
        added = candidate[len(prefix):candidate.index(marker)]
        self.assertEqual(candidate.replace(added, '', 1), original)
        self.assertIn("if p_hash='"+'2'*64+"'", added)
        self.assertIn("<>'"+'3'*64+"'", added)
        self.assertIn('archive_config_immutable', added)
        self.assertEqual(candidate.count("if p_hash='"+'2'*64+"'"), 1)
        with self.assertRaises(operator.Refused):
            operator.exact_sync_branch(candidate, '2'*64, '3'*64)

    def test_migration_body_requires_a_transaction_wrapper(self):
        self.assertEqual(operator.sql_body('-- task\nBEGIN;\nSELECT 1;\nCOMMIT;\n'), '\nSELECT 1;\n')
        for source in ('SELECT 1;', 'BEGIN; SELECT 1;', 'COMMIT;'):
            with self.assertRaises(operator.Refused):
                operator.sql_body(source)

    def test_prepare_restores_root_umask_after_failure(self):
        instance = object.__new__(operator.Operator)
        with patch.object(operator.os, 'umask', side_effect=[0o077, None]) as masked:
            with patch.object(instance, '_prepare', side_effect=operator.Refused('synthetic_prepare_failure')):
                with self.assertRaisesRegex(operator.Refused, 'synthetic_prepare_failure'):
                    instance.prepare()
        self.assertEqual(masked.call_args_list, [call(0o022), call(0o077)])

    def test_preservation_checks_reject_unrelated_function_or_runtime_privilege_changes(self):
        before = {'tables': ['survival_players'], 'functions': {
            'archive_unique_points_20261019_valid(args)': {'name': 'archive_unique_points_20261019_valid', 'sha256': 'a', 'app': False}}}
        after = copy.deepcopy(before)
        after['tables'].append('fishing_daily_limit_receipts')
        instance = object.__new__(operator.Operator)
        instance.unchanged_schema(before, after)
        after['functions']['archive_unique_points_20261019_valid(args)']['sha256'] = 'changed'
        with self.assertRaisesRegex(operator.Refused, 'unrelated_database_function_changed'):
            instance.unchanged_schema(before, after)
        after = copy.deepcopy(before); after['tables'].append('fishing_daily_limit_receipts')
        after['functions']['archive_unique_points_20261019_valid(args)']['app'] = True
        with self.assertRaisesRegex(operator.Refused, 'existing_rpc_privilege_changed'):
            instance.unchanged_schema(before, after)

    def activation_harness(self, stage, *, fail_after_switch=False):
        calls = []
        state = {'pointer': Path('old-release')}
        payment = {'release': 'payment-unchanged'}

        class Harness(operator.Operator):
            def __init__(self):
                self.stage = stage
                self.plan_hash = 'pinned-plan'
                self.bundle = 'candidate-bundle'
                self.old, self.new = Path('old-release'), Path('new-release')
            def check(self):
                calls.append('check')
            def payment_pin(self):
                return payment
            def manifest(self, root):
                return {'files': {}}
            def validate_legacy_lottery_guard(self):
                calls.append('lottery-proof')
            def systemctl(self, action):
                calls.append(action)
            def service_state(self, service):
                return {'active': 'inactive', 'pid': 0}
            def pointer(self, new=False):
                if state['pointer'] != (self.new if new else self.old):
                    raise operator.Refused('archive_pointer_changed')
            def backup(self):
                calls.append('private-backup')
            def admit(self):
                calls.append('single-owner-transaction')
                if not fail_after_switch:
                    raise operator.Refused('synthetic_ddl_failure')
            def switch(self, target):
                calls.append('switch-'+str(target)); state['pointer'] = target
            def health(self):
                calls.append('health')
                if state['pointer'] == self.new:
                    raise operator.Refused('synthetic_health_failure')
            def save(self, name, value):
                calls.append(value['phase'])
                return value

        (stage/'prepared.json').write_text(json.dumps({'plan_sha256': 'pinned-plan', 'bundle': 'candidate-bundle', 'payment': payment}))
        (stage/'release_manifest.json').write_text('{"files":{}}')
        class Releases:
            def __truediv__(self, name):
                return SimpleNamespace(resolve=lambda strict=True: state['pointer'])
        return Harness(), calls, Releases()

    def test_ddl_failure_restarts_old_code_without_data_rollback(self):
        with tempfile.TemporaryDirectory() as temporary:
            instance, calls, releases = self.activation_harness(Path(temporary))
            with patch.object(operator, 'RELEASES', releases), self.assertRaisesRegex(operator.Refused, 'synthetic_ddl_failure'):
                instance.activate()
        self.assertEqual(calls, ['check', 'lottery-proof', 'stop', 'private-backup', 'single-owner-transaction',
                                 'stop', 'start', 'health', 'OLD_CODE_RESTORED_DDL_PRESERVED'])

    def test_failed_candidate_health_switches_back_once_and_preserves_ddl(self):
        with tempfile.TemporaryDirectory() as temporary:
            instance, calls, releases = self.activation_harness(Path(temporary), fail_after_switch=True)
            with patch.object(operator, 'RELEASES', releases), self.assertRaisesRegex(operator.Refused, 'synthetic_health_failure'):
                instance.activate()
        self.assertEqual(calls, ['check', 'lottery-proof', 'stop', 'private-backup', 'single-owner-transaction',
                                 'switch-new-release', 'start', 'health', 'stop', 'switch-old-release', 'start',
                                 'health', 'OLD_CODE_RESTORED_DDL_PRESERVED'])


if __name__ == '__main__':
    unittest.main()
