"""Offline quantity-only publisher safety boundaries; no gateway or external DB."""
import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import sys
import tempfile
import types
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]


def load_operator():
    release = types.ModuleType('payment_backend.upgrade_ucoin_shop')
    release.BASE = Path('/opt/goufayu/payments')
    for name in ('connection', 'verify_release', 'health', 'backup', 'prepare_environment',
                 'temporary_link', 'run', 'wait_healthy', 'restore_code', 'restore_catalog', 'write_history'):
        setattr(release, name, mock.Mock())
    deploy = types.ModuleType('deploy')
    deploy.GAME = Path('/opt/goufayu/releases/current')
    package = types.ModuleType('payment_backend')
    package.upgrade_ucoin_shop = release
    spec = importlib.util.spec_from_file_location('_quantity_operator_test', ROOT / 'server/payment_backend/upgrade_order_quantity.py')
    module = importlib.util.module_from_spec(spec)
    path = sys.path[:]
    try:
        with mock.patch.dict(sys.modules, {'payment_backend': package,
             'payment_backend.upgrade_ucoin_shop': release, 'deploy': deploy}):
            spec.loader.exec_module(module)
    finally:
        sys.path[:] = path
    return module, release


class Connection:
    def __init__(self):
        self.queries, self.committed, self.rolled_back = [], False, False

    def __enter__(self):
        return self

    def __exit__(self, kind, *_):
        self.committed = kind is None and not self.rolled_back

    def execute(self, sql):
        self.queries.append(sql)
        return []

    def rollback(self):
        self.rolled_back = True


class OperatorTests(unittest.TestCase):
    def setUp(self):
        self.op, self.release = load_operator()
        self.old = Path('/opt/goufayu/payments/20261015-payment01')
        self.conn = Connection()
        self.release.connection.return_value = self.conn
        self.release.verify_release.return_value = self.old
        self.release.health.return_value = 'same_game_pid'
        self.op.preserved_state = mock.Mock(return_value={'orders': 'unchanged'})
        self.op.catalog_identity = mock.Mock(return_value=self.op.CATALOG_HASH)
        self.op.verify_scope = mock.Mock(return_value={})
        self.op.run_checks = mock.Mock(return_value={'quantity': 'pass'})
        self.op.retain_compatible_reader = mock.Mock(return_value=True)
        self.op.operator_lock = contextlib.nullcontext
        link = mock.Mock()
        link.is_symlink.return_value = False
        self.release.temporary_link.return_value = link
        self.op.cleanup_link = mock.Mock()

    def main(self, action):
        # The final symlink identity check is tested separately with real links.
        with contextlib.redirect_stdout(io.StringIO()), mock.patch.object(self.op.os, 'replace') as switch, \
             mock.patch.object(Path, 'resolve', return_value=self.op.ROOT):
            self.op.main(action, str(self.old))
            return switch

    def test_validate_rolls_back_without_backup_env_links_or_restart(self):
        switch = self.main('validate')
        self.assertTrue(self.conn.rolled_back)
        self.assertFalse(self.conn.committed)
        self.release.backup.assert_not_called()
        self.release.prepare_environment.assert_not_called()
        self.release.temporary_link.assert_not_called()
        self.release.run.assert_not_called()
        switch.assert_not_called()
        self.assertIn('SAVEPOINT quantity_fixture_rollback', self.conn.queries)
        self.assertIn('ROLLBACK TO SAVEPOINT quantity_fixture_rollback', self.conn.queries)

    def test_fixture_failure_rolls_back_fixture_and_migration(self):
        self.op.run_checks.side_effect = RuntimeError('fixture_failed')
        with self.assertRaisesRegex(RuntimeError, 'fixture_failed'):
            self.op.check_database()
        self.assertTrue(self.conn.rolled_back)
        self.assertFalse(self.conn.committed)
        self.assertIn('ROLLBACK TO SAVEPOINT quantity_fixture_rollback', self.conn.queries)

    def test_migration_failure_always_rolls_back(self):
        self.op.migrate = mock.Mock(side_effect=RuntimeError('ddl_failed'))
        with self.assertRaisesRegex(RuntimeError, 'ddl_failed'):
            self.op.check_database()
        self.assertTrue(self.conn.rolled_back)
        self.op.run_checks.assert_not_called()

    def test_migration_row_mutation_blocks_validation(self):
        self.op.preserved_state.side_effect = [{'orders': 'before'}, {'orders': 'after'}]
        with self.assertRaisesRegex(RuntimeError, 'migration_modified_existing_state'):
            self.op.check_database()
        self.assertTrue(self.conn.rolled_back)
        self.op.run_checks.assert_not_called()

    def test_postfixture_hash_mutation_blocks_validation(self):
        self.op.preserved_state.side_effect = ['unchanged', 'unchanged', 'mutated']
        with self.assertRaisesRegex(RuntimeError, 'fixtures_modified_existing_state'):
            self.op.check_database()
        self.assertTrue(self.conn.rolled_back)

    def test_catalog_mismatch_blocks_before_migration(self):
        self.op.catalog_identity.side_effect = RuntimeError('quantity_catalog_changed_since_review')
        self.op.migrate = mock.Mock()
        with self.assertRaisesRegex(RuntimeError, 'catalog_changed'):
            self.op.check_database()
        self.op.migrate.assert_not_called()
        self.assertTrue(self.conn.rolled_back)

    def test_scope_failure_prevents_database_or_backup(self):
        self.op.verify_scope.side_effect = RuntimeError('scope_changed')
        with self.assertRaisesRegex(RuntimeError, 'scope_changed'):
            self.main('activate')
        self.release.connection.assert_not_called()
        self.release.backup.assert_not_called()

    def test_backup_failure_keeps_code_and_database_unmodified(self):
        self.op.check_database = mock.Mock(return_value={})
        self.release.backup.side_effect = RuntimeError('backup_failed')
        with self.assertRaisesRegex(RuntimeError, 'backup_failed'):
            self.main('activate')
        self.release.connection.assert_not_called()
        self.release.prepare_environment.assert_not_called()
        self.release.temporary_link.assert_not_called()
        self.release.run.assert_not_called()

    def test_environment_failure_happens_before_db_commit(self):
        self.op.check_database = mock.Mock(return_value={})
        self.release.prepare_environment.side_effect = RuntimeError('env_failed')
        with self.assertRaisesRegex(RuntimeError, 'env_failed'):
            self.main('activate')
        self.release.connection.assert_not_called()
        self.release.run.assert_not_called()

    def test_release_change_precommit_aborts_without_reader_rollback(self):
        self.op.check_database = mock.Mock(return_value={})
        self.release.verify_release.side_effect = [self.old, self.old, self.old, RuntimeError('current_changed')]
        with self.assertRaisesRegex(RuntimeError, 'current_changed'):
            self.main('activate')
        self.assertFalse(self.conn.committed)
        self.release.run.assert_not_called()
        self.op.retain_compatible_reader.assert_not_called()

    def test_success_commits_only_quantity_migration_and_payment_restart(self):
        self.op.check_database = mock.Mock(return_value={})
        self.main('activate')
        self.assertTrue(self.conn.committed)
        self.assertIn('SET TRANSACTION ISOLATION LEVEL READ COMMITTED', self.conn.queries)
        self.release.backup.assert_called_once()
        self.release.run.assert_called_once_with(['systemctl', 'restart', 'goufayu-payment.service'])
        self.release.wait_healthy.assert_called_once()
        self.assertIn('LOCK TABLE ' + ','.join(self.op.CORE_TABLES) + ' IN EXCLUSIVE MODE', self.conn.queries)
        self.assertTrue(any(' IN SHARE MODE' in query for query in self.conn.queries))
        self.assertTrue(any('CREATE OR REPLACE FUNCTION payments.receipt_quantity' in query for query in self.conn.queries))
        for name in ('restore_code', 'restore_catalog', 'write_history'):
            getattr(self.release, name).assert_not_called()

    def test_postcommit_failure_retains_v5_reader_without_sql_catalog_rollback(self):
        self.op.check_database = mock.Mock(return_value={})
        self.release.run.side_effect = RuntimeError('restart_failed')
        with self.assertRaisesRegex(RuntimeError, 'restart_failed'):
            self.main('activate')
        self.assertTrue(self.conn.committed)
        self.op.retain_compatible_reader.assert_called_once_with(self.old)
        self.release.restore_code.assert_not_called()
        self.release.restore_catalog.assert_not_called()

    def test_postcommit_current_change_requires_recovery_no_blind_replace(self):
        self.op.check_database = mock.Mock(return_value={})
        self.release.verify_release.side_effect = [self.old] * 4 + [RuntimeError('thirdparty_current')]
        self.op.retain_compatible_reader.return_value = False
        with self.assertRaisesRegex(RuntimeError, 'recovery_incomplete'):
            self.main('activate')
        self.assertTrue(self.conn.committed)
        self.release.run.assert_not_called()
        self.op.retain_compatible_reader.assert_called_once_with(self.old)

    def test_game_service_change_is_failure_not_silent_success(self):
        self.op.check_database = mock.Mock(return_value={})
        self.release.health.side_effect = ['original_pid', 'other_pid']
        with self.assertRaisesRegex(RuntimeError, 'game_api_changed'):
            self.main('activate')
        self.op.retain_compatible_reader.assert_called_once()

    def test_invalid_action_does_not_open_connection(self):
        with self.assertRaisesRegex(RuntimeError, 'action_required'):
            self.main('unknown')
        self.release.connection.assert_not_called()


class ManifestAndRecoveryTests(unittest.TestCase):
    def setUp(self):
        self.op, self.release = load_operator()
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.old = self.base / '20261015-payment01'
        self.new = self.base / '20261015-payment02'
        shutil.copytree(ROOT / 'output/payment_release/20261015-payment01', self.old)
        shutil.copytree(ROOT / 'output/payment_release/20261015-payment02', self.new)
        self.release.BASE = self.base
        self.op.ROOT = self.new
        self.op.GAME = self.base / 'game'
        pointer = self.op.GAME / 'addon/server/bundles/current.json'
        pointer.parent.mkdir(parents=True)
        pointer.write_text(json.dumps({'hash': self.op.ARCHIVE_HASH}))

    def alter_candidate(self, name, data):
        (self.new / name).write_bytes(data)
        manifest = json.loads((self.new / 'manifest.json').read_text())
        manifest[name] = hashlib.sha256(data).hexdigest()
        (self.new / 'manifest.json').write_text(json.dumps(manifest))

    def link(self, target):
        current = self.base / 'current'
        if current.is_symlink():
            current.unlink()
        current.symlink_to(target, target_is_directory=True)

    def test_exact_baseline_scope_validates(self):
        self.assertEqual(self.op.verify_scope(self.old)['catalog_hash'], self.op.CATALOG_HASH)

    def test_baseline_file_tampering_is_rejected(self):
        (self.old / 'payment_backend/service.py').write_text('tampered')
        with self.assertRaisesRegex(RuntimeError, 'manifest_mismatch'):
            self.op.verify_scope(self.old)

    def test_unrelated_reference_or_old_sql_change_rejected_even_with_new_manifest(self):
        csv = next(name for name in json.loads((self.new/'manifest.json').read_text()) if name.startswith('reference_csv/'))
        for name in ('payment_backend/upgrade_vip_recharge.sql', csv):
            original = (self.new / name).read_bytes()
            self.alter_candidate(name, original + b'\n')
            with self.assertRaisesRegex(RuntimeError, 'scope_changed'):
                self.op.verify_scope(self.old)
            self.alter_candidate(name, original)

    def test_unknown_extra_manifest_file_rejected(self):
        self.alter_candidate('unexpected.py', b'print("unreviewed")')
        with self.assertRaisesRegex(RuntimeError, 'scope_changed'):
            self.op.verify_scope(self.old)

    def test_changed_archive_pointer_rejected(self):
        (self.op.GAME / 'addon/server/bundles/current.json').write_text('{"hash":"other"}')
        with self.assertRaisesRegex(RuntimeError, 'archive_changed'):
            self.op.verify_scope(self.old)

    def test_unsafe_manifest_path_rejected(self):
        manifest = json.loads((self.new / 'manifest.json').read_text())
        manifest['../outside'] = '0' * 64
        (self.new / 'manifest.json').write_text(json.dumps(manifest))
        with self.assertRaisesRegex(RuntimeError, 'manifest_path_invalid'):
            self.op.verify_scope(self.old)

    def test_thirdparty_release_never_overwritten_or_restarted(self):
        third = self.base / 'thirdparty'
        third.mkdir()
        self.link(third)
        self.assertFalse(self.op.retain_compatible_reader(self.old))
        self.assertEqual((self.base / 'current').resolve(), third)
        self.release.temporary_link.assert_not_called()
        self.release.run.assert_not_called()

    def test_recovery_retains_current_candidate_reader(self):
        self.link(self.new)
        self.assertTrue(self.op.retain_compatible_reader(self.old))
        self.release.temporary_link.assert_not_called()
        self.release.run.assert_called_once_with(['systemctl', 'restart', 'goufayu-payment.service'])
        self.assertEqual((self.base / 'current').resolve(), self.new)

    def test_recovery_forwards_reviewed_old_reader(self):
        self.link(self.old)
        link = self.base / 'quantity-private-recovery'
        link.symlink_to(self.new, target_is_directory=True)
        self.release.temporary_link.return_value = link
        # Linux rename atomically replaces directory symlinks. Windows refuses
        # that operation; emulate just rename here while retaining real links.
        def posix_link_replace(source, target):
            target.unlink()
            source.rename(target)
        with mock.patch.object(self.op.os, 'replace', side_effect=posix_link_replace):
            self.assertTrue(self.op.retain_compatible_reader(self.old))
        self.assertEqual((self.base / 'current').resolve(), self.new)
        self.assertFalse(link.exists())

    def test_recovery_stops_if_current_changes_during_link_preparation(self):
        self.link(self.old)
        third = self.base / 'thirdparty'
        third.mkdir()
        link = self.base / 'quantity-private-recovery'
        def prepare(*_):
            link.symlink_to(self.new, target_is_directory=True)
            self.link(third)
            return link
        self.release.temporary_link.side_effect = prepare
        self.assertFalse(self.op.retain_compatible_reader(self.old))
        self.assertEqual((self.base / 'current').resolve(), third)
        self.release.run.assert_not_called()
        self.assertFalse(link.exists())

    def test_recovery_refuses_modified_reader(self):
        self.link(self.old)
        (self.new / 'payment_backend/service.py').write_text('tampered')
        with self.assertRaisesRegex(RuntimeError, 'manifest_mismatch'):
            self.op.retain_compatible_reader(self.old)
        self.assertEqual((self.base / 'current').resolve(), self.old)
        self.release.run.assert_not_called()


if __name__ == '__main__':
    unittest.main(verbosity=2)
