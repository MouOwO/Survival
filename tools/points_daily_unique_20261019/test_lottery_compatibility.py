"""Exact candidate/online-worker receipt checks; no SSH or durable database."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'output/points_daily_unique_20261019/release_v3'
sys.path.insert(0, str(ROOT / 'server'))
from archive_backend.bundle import Bundle
from archive_backend.unique_points import legacy_lottery_error
from tests.test_archive_backend import Database, App


class IdenticalLotteryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.plan = json.loads((OUT / 'plan.json').read_bytes())
        cls.temp = tempfile.TemporaryDirectory(prefix='daily-identical-lottery-')
        cls.addClassCleanup(cls.temp.cleanup)
        for digest, source in ((cls.plan['bundle'], OUT / 'candidate/addon/server/bundles' / cls.plan['bundle']),
                               (cls.plan['parent_bundle'], OUT / 'baseline/addon/server/bundles' / cls.plan['parent_bundle'])):
            raw = (source / 'bundle.json').read_bytes()
            data = json.loads(raw)
            target = Path(cls.temp.name) / digest
            target.mkdir()
            (target / 'bundle.json').write_bytes(raw)
            for name, text in data['sources'].items():
                path = target / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text, encoding='utf-8', newline='\n')
        cls.bundle = Bundle(Path(cls.temp.name) / cls.plan['bundle'])
        cls.old = Bundle(Path(cls.temp.name) / cls.plan['parent_bundle'])
        spec = importlib.util.spec_from_file_location('archive_backend.reviewed_daily_service', OUT / 'baseline/backend/archive_backend/service.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        cls.Service = module.ArchiveService

    def setUp(self):
        self.db = Database(self.bundle)
        self.app = App(self.db)
        self.service = self.Service(self.app, self.bundle,
            os.environ.get('LUA_EXECUTABLE', 'C:/Program Files/lua/bin/lua5.1.exe'))
        self.account = self.app._database_account_id('100')
        self.profile = self.db.profile(self.account)
        self.profile['save']['archive']['commerce'] = {'balances': {'shop_points': 100000, 'u_coin': 7}}
        self.points = {row['item_id']: row for row in self.bundle.configs['lottery_item_definitions']['rows']
                       if row.get('enabled') is not False and row['item_type'] == '积分道具'}
        self.profile['save']['content_inventory'] = {identity: 1 for identity in self.points}
        self.profile['save']['content_inventory'].update(lottery_ticket=100, unrelated_material=999999)

    def payload(self, kind, token, **values):
        return dict(account_id='100', config_hash=self.old.hash,
            command=dict(id='daily-compatible:' + token, kind=kind, pool_id='map', request_id=token, **values))

    def test_only_the_one_directed_pair_is_allowed_and_every_lottery_rule_is_equal(self):
        self.assertIsNone(legacy_lottery_error(self.bundle.hash, self.old.hash, 'lottery_draw'))
        self.assertIsNone(legacy_lottery_error(self.bundle.hash, self.old.hash, 'lottery_exchange'))
        for current, recorded in ((self.old.hash, self.bundle.hash), (self.bundle.hash, 'a' * 64), ('b' * 64, self.old.hash)):
            self.assertEqual(legacy_lottery_error(current, recorded, 'lottery_draw'), 'lottery_config_refresh_required')
        for name, value in self.old.configs.items():
            if name.startswith('lottery_'):
                self.assertEqual(value, self.bundle.configs[name], name)
        for name, value in json.loads((self.old.directory / 'bundle.json').read_bytes())['sources'].items():
            if 'lottery' in name or name == 'config/content_id_aliases.lua':
                self.assertEqual(value, (self.bundle.directory / name).read_text('utf-8'), name)

    def test_old_pending_draw_uses_recorded_rules_and_lost_reply_never_regrants(self):
        before_stats = copy.deepcopy(self.profile['save']['gameplay_stats'])
        payload = self.payload('lottery_draw', 'trusted_daily_draw', count=10)
        self.db.lose_reply = True
        with self.assertRaises(TimeoutError):
            self.service.command(payload)
        settled = copy.deepcopy(self.profile)
        result = self.service.command(payload)
        self.assertTrue(result['ok'], result)
        self.assertEqual(self.profile, settled)
        response = result['response']
        self.assertEqual(len(response['results']), 10)
        self.assertEqual(self.profile['save']['content_inventory']['lottery_ticket'], 90)
        self.assertTrue(all(self.profile['save']['content_inventory'][identity] == 1 for identity in self.points))
        self.assertEqual(self.profile['save']['gameplay_stats'], before_stats)
        self.assertGreater(self.profile['save']['archive']['commerce']['balances']['shop_points'], 100000)
        self.assertEqual(self.profile['save']['content_inventory']['unrelated_material'], 999999)

    def test_old_pending_exchange_and_its_completed_receipt_keep_unique_ownership(self):
        member_ids = {row['item_id'] for row in self.bundle.configs['lottery_pool_items']['rows']
                      if row['pool_id'] == 'map' and row.get('enabled') is not False}
        item = next(row for identity, row in self.points.items()
                    if identity in member_ids and row.get('exchange_enabled') and row['exchange_points'] > 0
                    and 'starjoy_points' not in row['effect_ids'])
        self.profile['save']['content_inventory'].pop(item['item_id'])
        self.profile['save']['gameplay_stats']['starjoy_points'] = 100000
        payload = self.payload('lottery_exchange', 'trusted_daily_exchange', item_id=item['item_id'])
        result = self.service.command(payload)
        self.assertTrue(result['ok'], result)
        self.assertEqual(self.profile['save']['content_inventory'][item['item_id']], 1)
        self.assertEqual(self.profile['save']['archive']['commerce']['balances']['shop_points'], 100000)
        self.assertEqual(self.profile['save']['gameplay_stats']['starjoy_points'], 100000 - item['exchange_points'])
        settled = copy.deepcopy(self.profile)
        self.assertEqual(self.service.command(payload)['response'], result['response'])
        self.assertEqual(self.profile, settled)
        rejected = self.service.command(self.payload('lottery_exchange', 'trusted_daily_exchange_again', item_id=item['item_id']))
        self.assertEqual(rejected['error'], 'lottery_item_owned')
        self.assertEqual(self.profile, settled)


if __name__ == '__main__':
    unittest.main(verbosity=2)
