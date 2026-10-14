"""Offline failure boundaries for the monthly release; no SSH or DB connection."""
import contextlib
import importlib.util
import io
from pathlib import Path
import sys
import types
import unittest
from unittest import mock


class Connection:
    def __init__(self, events):
        self.events, self.queries = events, []
        self.committed, self.rolled_back = False, False

    def __enter__(self):
        return self

    def __exit__(self, kind, value, traceback):
        self.committed = kind is None
        self.events.append('commit' if kind is None else 'abort')

    def execute(self, sql):
        self.queries.append(sql)

    def rollback(self):
        self.rolled_back = True


class MonthlyUpgradeTests(unittest.TestCase):
    def setUp(self):
        release = types.ModuleType('payment_backend.upgrade_ucoin_shop')
        release.BASE = Path('/opt/goufayu/payments')
        for name in ('connection', 'preserved_state', 'verify_release', 'health', 'backup',
                     'prepare_environment', 'write_history', 'temporary_link', 'catalog_snapshot',
                     'run', 'wait_healthy', 'restore_catalog', 'restore_code'):
            setattr(release, name, mock.Mock())
        sync = types.ModuleType('payment_backend.sync_catalog')
        sync.validate, sync.apply = mock.Mock(), mock.Mock()
        fixtures = types.ModuleType('payment_backend.test_monthly_pass_database')
        fixtures.run_checks = mock.Mock()
        source = Path(__file__).with_name('upgrade_monthly_pass.py')
        specification = importlib.util.spec_from_file_location('_monthly_upgrade_test', source)
        self.upgrade = importlib.util.module_from_spec(specification)
        original_path = sys.path[:]
        with mock.patch.dict(sys.modules, {'payment_backend.upgrade_ucoin_shop': release,
                                          'payment_backend.sync_catalog': sync,
                                          'payment_backend.test_monthly_pass_database': fixtures}):
            specification.loader.exec_module(self.upgrade)
        self.addCleanup(lambda: sys.path.__setitem__(slice(None), original_path))
        self.release = release
        self.old = Path('/opt/goufayu/payments/old-release')
        self.package = {'catalog_hash': 'fixture_hash', 'catalog': {'products': [{'sku': 'archive_pass_monthly'}]}}
        self.events = []
        self.conn = Connection(self.events)
        release.connection.return_value = self.conn
        release.preserved_state.return_value = ['unchanged']
        release.verify_release.return_value = self.old
        release.health.return_value = 'unchanged_game_pid'
        release.catalog_snapshot.return_value = {'snapshot': True}
        release.restore_catalog.return_value = True
        release.restore_code.return_value = True
        link = mock.Mock()
        link.is_symlink.return_value = False
        release.temporary_link.return_value = link
        sync.validate.return_value = self.package
        sync.apply.side_effect = lambda *_: self.events.append('publish')
        release.write_history.side_effect = lambda *_: self.events.append('history')
        fixtures.run_checks.return_value = {'duration_days': 30}

    def main(self, action):
        with contextlib.redirect_stdout(io.StringIO()), mock.patch.object(self.upgrade.os, 'replace') as switch:
            self.upgrade.main(action, 'catalog.json', 'digest', str(self.old))
            return switch

    def test_database_fixture_failure_always_rolls_back_upgrade_and_catalog(self):
        self.upgrade.run_checks.side_effect = RuntimeError('fixture failed')
        with self.assertRaisesRegex(RuntimeError, 'fixture failed'):
            self.upgrade.check(self.package)
        self.assertTrue(self.conn.rolled_back)
        self.assertFalse(self.conn.committed)
        self.assertTrue(any('CREATE OR REPLACE FUNCTION payments.deliver' in sql for sql in self.conn.queries))

    def test_validate_never_backs_up_restarts_or_switches_a_release(self):
        switch = self.main('validate')
        self.assertTrue(self.conn.rolled_back)
        self.release.backup.assert_not_called()
        self.release.run.assert_not_called()
        switch.assert_not_called()

    def test_history_failure_happens_before_committing_schema_or_catalog(self):
        self.upgrade.check = mock.Mock(return_value={'duration_days': 30})
        self.release.write_history.side_effect = OSError('history failed')
        with self.assertRaisesRegex(OSError, 'history failed'):
            self.main('activate')
        self.upgrade.apply.assert_not_called()
        self.release.connection.assert_not_called()
        self.release.restore_catalog.assert_not_called()

    def test_release_change_before_commit_aborts_without_restarting(self):
        self.upgrade.check = mock.Mock(return_value={'duration_days': 30})
        self.release.verify_release.side_effect = [self.old, RuntimeError('release changed')]
        with self.assertRaisesRegex(RuntimeError, 'release changed'):
            self.main('activate')
        self.assertFalse(self.conn.committed)
        self.release.run.assert_not_called()
        self.release.restore_catalog.assert_not_called()

    def test_service_failure_after_commit_restores_catalog_and_code(self):
        self.upgrade.check = mock.Mock(return_value={'duration_days': 30})
        self.release.run.side_effect = RuntimeError('restart failed')
        with self.assertRaisesRegex(RuntimeError, 'restart failed'):
            self.main('activate')
        self.assertTrue(self.conn.committed)
        self.release.restore_catalog.assert_called_once_with({'snapshot': True}, 'fixture_hash', ['archive_pass_monthly'])
        self.release.restore_code.assert_called_once_with(self.old)

    def test_success_restarts_only_payment_and_retains_existing_config(self):
        self.upgrade.check = mock.Mock(return_value={'duration_days': 30})
        self.main('activate')
        self.assertTrue(self.conn.committed)
        self.release.backup.assert_called_once()
        self.assertLess(self.events.index('history'), self.events.index('commit'))
        self.release.run.assert_called_once_with(['systemctl', 'restart', 'goufayu-payment.service'])
        self.release.wait_healthy.assert_called_once()
        self.assertTrue(any(sql.startswith('LOCK TABLE') for sql in self.conn.queries))

    def test_changed_game_api_is_a_failed_activation_with_guarded_recovery(self):
        self.upgrade.check = mock.Mock(return_value={'duration_days': 30})
        self.release.health.side_effect = ['original_game_pid', 'changed_game_pid']
        with self.assertRaisesRegex(RuntimeError, 'game_api_changed_during_monthly_activation'):
            self.main('activate')
        self.assertTrue(self.conn.committed)
        self.release.restore_catalog.assert_called_once()
        self.release.restore_code.assert_called_once_with(self.old)
        self.release.run.assert_called_once_with(['systemctl', 'restart', 'goufayu-payment.service'])


if __name__ == '__main__':
    unittest.main()
