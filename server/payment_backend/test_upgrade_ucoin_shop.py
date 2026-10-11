"""Exercise publication failure boundaries and guarded catalog recovery offline."""
import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import sys
import types
import unittest
from unittest import mock


class Result:
    def __init__(self, rows=()):
        self.rows = rows

    def fetchone(self):
        return self.rows[0] if self.rows else None

    def fetchall(self):
        return self.rows


class CatalogConnection:
    def __init__(self, database, events=None):
        self.database = database
        self.events = events if events is not None else []
        self.queries = []
        self.committed = False

    def __enter__(self):
        self.before = copy.deepcopy(self.database)
        return self

    def __exit__(self, kind, value, traceback):
        if kind is not None:
            self.database.clear()
            self.database.update(self.before)
            self.events.append('rollback')
        else:
            self.committed = True
            self.events.append('commit')

    def execute(self, sql, values=()):
        self.queries.append((sql, values))
        normalized = ' '.join(sql.lower().split())
        if normalized.startswith('set ') or normalized.startswith('select pg_advisory_xact_lock'):
            return Result()
        if normalized.startswith('select catalog_hash '):
            state = self.database['state']
            return Result([(state['catalog_hash'],)] if state else [])
        if normalized.startswith('update payments.products set item_id='):
            columns = ('item_id', 'title', 'description', 'amount', 'effects', 'enabled',
                       'sort_order', 'grants', 'category_id', 'product_type', 'icon', 'purchase_limit')
            product = dict(zip(columns, values[:-1]))
            for key in ('effects', 'grants'):
                product[key] = json.loads(product[key])
            self.database['products'][values[-1]].update(product)
            return Result()
        if normalized.startswith('update payments.products set enabled=false'):
            for sku in values[0]:
                self.database['products'][sku]['enabled'] = False
            return Result()
        if normalized.startswith('update payments.catalog_state '):
            self.database['state'].update(catalog_hash=values[0], categories=json.loads(values[1]), updated_at=values[2])
            return Result()
        if normalized.startswith('delete from payments.catalog_state '):
            self.database['state'] = None
            return Result()
        raise AssertionError('unexpected fixture SQL: ' + normalized)


class UpgradeTests(unittest.TestCase):
    def setUp(self):
        source = Path(__file__).with_name('upgrade_ucoin_shop.py')
        deploy = types.ModuleType('deploy')
        deploy.BASE = Path('/opt/goufayu/payments')
        for name in ('backup', 'connection', 'health', 'run'):
            setattr(deploy, name, mock.Mock())
        sync = types.ModuleType('payment_backend.sync_catalog')
        sync.validate, sync.apply = mock.Mock(), mock.Mock()
        fixture = types.ModuleType('payment_backend.test_ucoin_database')
        fixture.run_checks = mock.Mock()
        specification = importlib.util.spec_from_file_location('payment_backend._ucoin_upgrade_test', source)
        self.upgrade = importlib.util.module_from_spec(specification)
        with mock.patch.dict(sys.modules, {'deploy': deploy, 'payment_backend.sync_catalog': sync,
                                          'payment_backend.test_ucoin_database': fixture}):
            specification.loader.exec_module(self.upgrade)
        self.old_product = {
            'sku': 'old_cash', 'item_id': 'old_marker', 'title': 'old', 'description': 'old',
            'amount': 5000, 'effects': {'initial_wood': 100}, 'enabled': True, 'sort_order': 1,
            'grants': {'items': {}, 'lines': []}, 'category_id': 'technology',
            'product_type': 'single', 'icon': 'custom_game/item.png', 'purchase_limit': 1,
        }
        self.old_state = {'singleton': True, 'catalog_hash': 'old_hash', 'categories': [{'id': 'old'}],
                          'updated_at': '2026-10-11T00:00:00+00:00'}
        self.snapshot = {'products': [copy.deepcopy(self.old_product)], 'state': copy.deepcopy(self.old_state)}

    def published_database(self, catalog_hash='new_hash'):
        changed = copy.deepcopy(self.old_product)
        changed.update(amount=777, title='new', enabled=False)
        introduced = copy.deepcopy(self.old_product)
        introduced.update(sku='video_p004', item_id='commerce_p004', amount=680)
        return {'products': {'old_cash': changed, 'video_p004': introduced},
                'state': {'singleton': True, 'catalog_hash': catalog_hash, 'categories': [{'id': 'new'}],
                          'updated_at': '2026-10-11T01:00:00+00:00'}}

    def test_catalog_recovery_restores_existing_products_and_retains_new_skus(self):
        database = self.published_database()
        connection = CatalogConnection(database)
        self.upgrade.connection.return_value = connection
        self.assertTrue(self.upgrade.restore_catalog(self.snapshot, 'new_hash', ['old_cash', 'video_p004']))
        self.assertEqual(database['products']['old_cash'], self.old_product)
        self.assertFalse(database['products']['video_p004']['enabled'])
        self.assertEqual(database['products']['video_p004']['amount'], 680)
        self.assertEqual(database['state'], self.old_state)
        self.assertTrue(connection.committed)
        self.assertFalse(any('payments.orders' in sql or 'player_' in sql for sql, _ in connection.queries))

    def test_catalog_recovery_never_overwrites_a_newer_publication(self):
        database = self.published_database('someone_elses_hash')
        before = copy.deepcopy(database)
        connection = CatalogConnection(database)
        self.upgrade.connection.return_value = connection
        self.assertFalse(self.upgrade.restore_catalog(self.snapshot, 'new_hash', ['old_cash', 'video_p004']))
        self.assertEqual(database, before)
        self.assertFalse(any(sql.lstrip().lower().startswith(('update ', 'delete ')) for sql, _ in connection.queries))

    def activation_mocks(self):
        upgrade = self.upgrade
        upgrade.ROOT = Path('/opt/goufayu/payments/new-release')
        old = Path('/opt/goufayu/payments/old-release')
        package = {'catalog_hash': 'new_hash', 'catalog': {'products': [self.old_product, {'sku': 'video_p004'}]},
                   'tables': {}, 'commerce_tables': {}}
        events = []
        database = {'products': {'old_cash': copy.deepcopy(self.old_product)}, 'state': copy.deepcopy(self.old_state)}
        connection = CatalogConnection(database, events)
        upgrade.verify_release = mock.Mock(return_value=old)
        upgrade.validate.return_value = package
        upgrade.check = mock.Mock(return_value={'ucoin_skus': 24})
        upgrade.health.return_value = 'game_api_pid'
        upgrade.prepare_environment = mock.Mock()
        upgrade.write_history = mock.Mock(side_effect=lambda _: events.append('history'))
        link = mock.Mock()
        link.is_symlink.return_value = False
        upgrade.temporary_link = mock.Mock(side_effect=lambda *_: events.append('link') or link)
        upgrade.connection.return_value = connection
        upgrade.preserved_state = mock.Mock(return_value=['unchanged'])
        upgrade.catalog_snapshot = mock.Mock(return_value=self.snapshot)
        def publish(*_):
            events.append('apply')
            database.clear()
            database.update(self.published_database())
        upgrade.apply.side_effect = publish
        upgrade.wait_healthy = mock.Mock()
        upgrade.restore_catalog = mock.Mock(return_value=True)
        upgrade.restore_code = mock.Mock(return_value=True)
        return old, connection, events

    def activate(self, old):
        with contextlib.redirect_stdout(io.StringIO()), mock.patch.object(self.upgrade.os, 'replace'):
            self.upgrade.main('activate', 'package.json', 'digest', str(old))

    def test_history_failure_happens_before_any_catalog_publication(self):
        old, connection, _ = self.activation_mocks()
        self.upgrade.write_history.side_effect = OSError('history failed')
        with self.assertRaisesRegex(OSError, 'history failed'):
            self.activate(old)
        self.upgrade.apply.assert_not_called()
        self.upgrade.connection.assert_not_called()
        self.upgrade.restore_catalog.assert_not_called()
        self.assertFalse(connection.committed)

    def test_release_change_before_commit_rolls_back_and_never_switches_code(self):
        old, connection, events = self.activation_mocks()
        self.upgrade.verify_release.side_effect = [old, RuntimeError('release changed')]
        with self.assertRaisesRegex(RuntimeError, 'release changed'):
            self.activate(old)
        self.assertFalse(connection.committed)
        self.assertEqual(connection.database['state'], self.old_state)
        self.assertIn('rollback', events)
        self.upgrade.run.assert_not_called()
        self.upgrade.restore_catalog.assert_not_called()

    def test_service_failure_recovers_catalog_and_code_after_commit(self):
        old, connection, events = self.activation_mocks()
        self.upgrade.run.side_effect = RuntimeError('restart failed')
        with self.assertRaisesRegex(RuntimeError, 'restart failed'):
            self.activate(old)
        self.assertTrue(connection.committed)
        self.assertLess(events.index('history'), events.index('commit'))
        self.assertLess(events.index('link'), events.index('commit'))
        self.assertEqual(connection.queries[0][0], 'SET TRANSACTION ISOLATION LEVEL REPEATABLE READ')
        self.upgrade.restore_catalog.assert_called_once_with(self.snapshot, 'new_hash', ['old_cash', 'video_p004'])
        self.upgrade.restore_code.assert_called_once_with(old)
        self.assertEqual(self.upgrade.verify_release.call_count, 3)

    def test_code_recovery_keeps_another_releases_current_link(self):
        base = mock.MagicMock()
        base.__truediv__.return_value.resolve.return_value = Path('/opt/goufayu/payments/another-release')
        self.upgrade.BASE = base
        self.assertFalse(self.upgrade.restore_code(Path('/opt/goufayu/payments/old-release')))
        self.upgrade.run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
