"""Offline migration previews and guarded maintenance SQL orchestration."""
import copy
import importlib.util
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'server'))
from archive_backend.bundle import Bundle
from archive_backend.unique_points import MAX_INTEGER, catalog, preview

spec = importlib.util.spec_from_file_location('unique_points_maintenance', ROOT/'server/maintenance/reconcile_unique_points.py')
maintenance = importlib.util.module_from_spec(spec)
spec.loader.exec_module(maintenance)


class Result:
    def __init__(self, rows=()): self.rows = rows
    def fetchall(self): return copy.deepcopy(self.rows)
    def fetchone(self): return copy.deepcopy(self.rows[0]) if self.rows else None


class MemoryConnection:
    """Tiny adapter for lock/state/backup guards, not a substitute for PostgreSQL."""
    def __init__(self, state):
        self.state = copy.deepcopy(state)
        self.backups = []
        self.calls = []
    def execute(self, sql, params=()):
        self.calls.append((sql, params))
        if 'FROM public.survival_players p JOIN' in sql:
            accounts = params[0]
            return Result([(a, r['revision'], r['inventory'], r['archive'])
                           for a, r in sorted(self.state.items()) if accounts is None or a in accounts])
        if 'FROM public.player_gameplay_stats' in sql: return Result([(1,)])
        if 'SELECT profile_revision' in sql: return Result([(self.state[params[0]]['revision'],)])
        if 'SELECT content_inventory,archive' in sql:
            row = self.state[params[0]];return Result([(row['inventory'], row['archive'])])
        if 'INSERT INTO public.archive_unique_points_backups' in sql:
            self.backups.append(copy.deepcopy(params));return Result()
        if 'UPDATE public.player_archive_state' in sql:
            inventory, archive, account = params
            self.state[account]['inventory'] = json.loads(inventory)
            self.state[account]['archive'] = json.loads(archive)
            return Result()
        if 'UPDATE public.survival_players' in sql:
            self.state[params[0]]['revision'] += 1;return Result()
        if 'SELECT account_id,after_revision' in sql:
            return Result([(b[1], b[5], json.loads(b[6]), json.loads(b[7]), json.loads(b[8]), json.loads(b[9]))
                           for b in self.backups if b[0] == params[0] and b[2] == params[1] and b not in getattr(self, 'rolled_back', [])])
        if 'SET rolled_back_at' in sql:
            self.rolled_back = [b for b in self.backups if (b[0], b[1]) == params];return Result()
        raise AssertionError(sql)


class UniquePointsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        base = ROOT/'server/bundles'
        cls.bundle = Bundle(base/json.loads((base/'current.json').read_text())['hash'])
        cls.items, cls.aliases = catalog(cls.bundle)

    def fixture(self):
        return {'synthetic-a': {'revision': 3, 'inventory': {
            'lottery_flame_crystal': 3, 'lottery_nature_crystal': 1,
            'lottery_ember_of_legacy': 100, 'daily_growth_gem': 9, 'lottery_ticket': 7,
            'material_synthesis_gem': 77},
            'archive': {'keep': {'value': True}, 'daily_rewards': {'item_counts': {'daily_growth_gem': 9}},
                        'commerce': {'balances': {'u_coin': 12, 'shop_points': 7, 'shop_gold': 33}}}},
            'synthetic-b': {'revision': 9, 'inventory': {'daily_growth_gem': 123}, 'archive': {}}}

    def test_96_unique_rows_exclude_stackable_ember(self):
        self.assertEqual(len(self.items), 96)
        self.assertNotIn('lottery_ember_of_legacy', self.items)
        self.assertNotIn('daily_growth_gem', self.items)
        self.assertNotIn('material_synthesis_gem', self.items)

    def test_preview_compensates_once_and_preserves_every_other_value(self):
        state = self.fixture()['synthetic-a'];before = copy.deepcopy(state)
        plan = preview(state['inventory'], state['archive'], self.items, self.aliases)
        self.assertEqual(state, before, 'A preview cannot mutate its input')
        self.assertEqual(plan['converted_points'], 15)
        self.assertEqual(plan['content_inventory']['lottery_ember_of_legacy'], 100)
        self.assertEqual(plan['content_inventory']['lottery_nature_crystal'], 1)
        self.assertNotIn('lottery_flame_crystal', plan['content_inventory'])
        for key in ('daily_growth_gem', 'material_synthesis_gem', 'lottery_ticket'):
            self.assertEqual(plan['content_inventory'][key], before['inventory'][key])
        self.assertEqual(plan['archive']['daily_rewards'], before['archive']['daily_rewards'])
        self.assertEqual(plan['archive']['commerce']['balances'], {'u_coin': 12, 'shop_points': 22, 'shop_gold': 33})
        second = preview(plan['content_inventory'], plan['archive'], self.items, self.aliases)
        self.assertEqual(second['changed_items'], 0);self.assertEqual(second['converted_points'], 0)
        self.assertEqual(second['content_inventory'], plan['content_inventory'])
        self.assertEqual(second['archive'], plan['archive'])

    def test_invalid_copies_and_wallet_overflow_refuse_without_loss(self):
        for value in (-1, 1.5, True, {}, [], 'oops', MAX_INTEGER+1):
            with self.subTest(value=value):
                inventory = {'lottery_nature_crystal': value};before = copy.deepcopy(inventory)
                with self.assertRaises(ValueError):preview(inventory, {}, self.items, self.aliases)
                self.assertEqual(inventory, before)
        for balance in (-1, True, '5', MAX_INTEGER):
            with self.subTest(balance=balance):
                archive = {'commerce': {'balances': {'shop_points': balance}}};before = copy.deepcopy(archive)
                with self.assertRaises(ValueError):preview({'lottery_nature_crystal': 2}, archive, self.items, self.aliases)
                self.assertEqual(archive, before)

    def test_preview_summary_preserves_ember_and_reports_only_unique_compensation(self):
        conn = MemoryConnection(self.fixture())
        plans, digest = maintenance.plans(conn, self.bundle)
        self.assertEqual(len(digest), 64)
        self.assertEqual(conn.state, self.fixture())
        summary = maintenance.summary(plans)
        self.assertEqual(summary[0], {'id': 'lottery_nature_crystal', 'affected_accounts': 1,
            'previous_copies': 4, 'extra_copies': 3, 'converted_points': 15})
        self.assertNotIn('synthetic-a', json.dumps(summary))

    def test_apply_review_digest_backup_rollback_and_reapply_are_guarded(self):
        conn = MemoryConnection(self.fixture());before = copy.deepcopy(conn.state)
        _, digest = maintenance.plans(conn, self.bundle)
        with self.assertRaisesRegex(ValueError, 'plan_changed'):
            maintenance.apply(conn, self.bundle, '0'*64)
        self.assertEqual(conn.state, before);self.assertFalse(conn.backups)
        applied = maintenance.apply(conn, self.bundle, digest)
        self.assertEqual(applied['changed_accounts'], 1)
        self.assertEqual(conn.state['synthetic-a']['revision'], 4)
        self.assertEqual(conn.state['synthetic-b'], before['synthetic-b'])
        backup = conn.backups[0]
        self.assertEqual(json.loads(backup[6]), before['synthetic-a']['inventory'])
        self.assertEqual(json.loads(backup[8]), before['synthetic-a']['archive'])
        _, digest = maintenance.plans(conn, self.bundle)
        self.assertEqual(maintenance.apply(conn, self.bundle, digest)['changed_accounts'], 0)
        result = maintenance.rollback(conn, applied['run_id'])
        self.assertEqual(result['rolled_back_accounts'], 1)
        self.assertEqual(conn.state['synthetic-a']['inventory'], before['synthetic-a']['inventory'])
        self.assertEqual(conn.state['synthetic-a']['archive'], before['synthetic-a']['archive'])
        self.assertEqual(conn.state['synthetic-a']['revision'], 5, 'Rollback keeps profile revisions monotonic')
        self.assertEqual(maintenance.rollback(conn, applied['run_id'])['rolled_back_accounts'], 0)

    def test_rollback_refuses_to_overwrite_later_account_changes(self):
        conn = MemoryConnection(self.fixture())
        _, digest = maintenance.plans(conn, self.bundle)
        applied = maintenance.apply(conn, self.bundle, digest)
        conn.state['synthetic-a']['archive']['commerce']['balances']['shop_points'] -= 1
        before = copy.deepcopy(conn.state)
        with self.assertRaisesRegex(ValueError, 'rollback_refused'):
            maintenance.rollback(conn, applied['run_id'])
        self.assertEqual(conn.state, before)


if __name__ == '__main__':
    unittest.main()
