"""Reject monthly publication before any catalog write on an older database."""
import importlib.util
from pathlib import Path
import sys
import types
import unittest
from unittest import mock

from .csv_catalog import build


class Result:
    def __init__(self, row=None):
        self.row = row

    def fetchone(self):
        return self.row


class Connection:
    def __init__(self, installed):
        self.installed, self.queries = installed, []

    def execute(self, sql, params=()):
        self.queries.append((sql, params))
        if 'to_regprocedure' in sql:
            return Result((self.installed,))
        return Result()


class MonthlySchemaGuardTests(unittest.TestCase):
    def setUp(self):
        source = Path(__file__).with_name('sync_catalog.py')
        deploy = types.ModuleType('deploy')
        deploy.connection, deploy.backup, deploy.GAME = mock.Mock(), mock.Mock(), Path('/fixture')
        json_adapter = types.ModuleType('psycopg.types.json')
        json_adapter.Jsonb = lambda value: value
        self.modules = mock.patch.dict(sys.modules, {'deploy': deploy, 'psycopg.types.json': json_adapter})
        self.modules.start()
        self.addCleanup(self.modules.stop)
        specification = importlib.util.spec_from_file_location('_monthly_sync_guard', source)
        self.sync = importlib.util.module_from_spec(specification)
        original_path = sys.path[:]
        specification.loader.exec_module(self.sync)
        self.addCleanup(lambda: sys.path.__setitem__(slice(None), original_path))
        product = next(p for p in build(source.parents[2])['catalog']['products'] if p['sku'] == 'archive_pass_monthly')
        self.package = {'catalog_hash': 'fixture', 'catalog': {'products': [product], 'categories': []}}

    def test_missing_timed_upgrade_rejects_before_product_or_catalog_writes(self):
        connection = Connection(False)
        with self.assertRaisesRegex(ValueError, 'upgrade_monthly_pass.sql'):
            self.sync.apply(connection, self.package)
        self.assertFalse(any(sql.lstrip().lower().startswith(('insert ', 'update ', 'delete '))
                             for sql, _ in connection.queries))

    def test_upgraded_database_receives_exact_price_and_immutable_duration(self):
        connection = Connection(True)
        self.sync.apply(connection, self.package)
        rows = [params for sql, params in connection.queries if sql.startswith('INSERT INTO payments.products')]
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0][4], 5800)
        self.assertEqual(rows[0][8]['entitlement_days'], {'archive_pass': 30})


if __name__ == '__main__':
    unittest.main()
