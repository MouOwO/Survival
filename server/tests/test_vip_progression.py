"""Synthetic accounts, real published bundle and native Lua settlement worker.

No network, payment orders, production database or real player saves are used.
"""
from __future__ import annotations

import copy
import json
import os
from pathlib import Path
import shutil
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'server'))
from archive_backend.bundle import Bundle
from archive_backend.service import ArchiveService, install as install_service
from archive_backend.vip_progression import VipProgression, install
from tests.test_archive_backend import App as BaseApp, Database as BaseDatabase


class Database(BaseDatabase):
    """Keep the existing CAS/receipt fixture; add only public identity binding."""
    def __init__(self, bundle):
        super().__init__(bundle)
        self.calls = []

    def rpc(self, name, payload):
        self.calls.append((name, copy.deepcopy(payload)))
        if name == 'archive_bind_leaderboard_identity':
            return {'ok': True}
        return super().rpc(name, payload)


class App(BaseApp):
    def _public_response(self, value, database_account, public_account):
        value = super()._public_response(value, database_account, public_account)
        # Production fishing responses can be a bare profile as well as the
        # command envelope covered by the existing fixture's public projector.
        if isinstance(value, dict) and value.get('account_id') == database_account:
            value['account_id'] = public_account
        return value


class VipProgressionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lua = (os.environ.get('LUA_EXECUTABLE') or shutil.which('lua5.1')
                   or shutil.which('lua'))
        windows_lua = Path('C:/Program Files/lua/bin/lua5.1.exe')
        if not cls.lua and windows_lua.is_file():
            cls.lua = str(windows_lua)
        if not cls.lua:
            raise RuntimeError('LUA_EXECUTABLE must point to native Lua 5.1')
        cls.current_bytes = (ROOT / 'server/bundles/current.json').read_bytes()
        current = json.loads(cls.current_bytes)
        cls.bundle = Bundle(ROOT / 'server/bundles' / current['hash'])
        cls.levels = sorted(cls.bundle.tables['archive_vip_levels'].values(),
                            key=lambda row: row['level'])
        cls.rewards = sorted((r for r in cls.bundle.tables['archive_vip_rewards'].values()
                              if r['enabled'] and r['group_id'] == 'privileges'),
                             key=lambda row: row['level'])

    def setUp(self):
        self.database = Database(self.bundle)
        self.app = App(self.database)
        self.service = ArchiveService(self.app, self.bundle, self.lua)
        self.serial = 0

    def profile(self, account='100', total=0):
        profile = self.database.profile(self.app._database_account_id(account))
        profile['save']['gameplay_stats']['vip_recharge_total_fen'] = total
        return profile

    def load(self, account='100'):
        return self.service.profile({'account_id': account})

    def command(self, kind, account='100', **fields):
        self.serial += 1
        return self.service.command({'account_id': account,
            'config_hash': self.bundle.hash,
            'command': {'id': 'viptest:manual:' + str(self.serial),
                        'kind': kind, **fields}})

    def assert_claims(self, profile, level):
        claims = profile['save']['archive'].get('vip_claimed', {})
        self.assertEqual({key for key, value in claims.items() if value is True},
                         {r['reward_id'] for r in self.rewards if r['level'] <= level})

    def assert_effects(self, profile, level):
        expected = {}
        for row in self.rewards:
            if row['level'] <= level:
                for field, value in zip(row['effect_ids'], row['effect_values']):
                    expected[field] = expected.get(field, 0) + float(value)
        for field, amount in expected.items():
            default = self.bundle.tables['player_gameplay_stats'][field]['default_value']
            self.assertAlmostEqual(profile['save']['gameplay_stats'][field], default + amount,
                                   msg=field)

    def test_all_12_recharge_boundaries_use_real_worker(self):
        install(self.service)
        for row in self.levels:
            for offset in (-1, 0, 1):
                account = str(10000 + row['level'] * 10 + offset)
                level = row['level'] - (offset == -1)
                with self.subTest(tier=row['level'], offset_fen=offset):
                    self.profile(account, row['required_recharge_fen'] + offset)
                    loaded = self.load(account)
                    self.assert_claims(loaded, level)
                    self.assert_effects(loaded, level)
                    self.assertEqual(loaded['account_id'], account)

    def test_crossing_many_tiers_grants_all_cumulative_privileges(self):
        source = self.profile(total=self.levels[-1]['required_recharge_fen'])
        install(self.service)
        loaded = self.load()
        self.assert_claims(loaded, 12)
        self.assert_effects(loaded, 12)
        self.assertAlmostEqual(source['save']['gameplay_stats']['hero_damage_attack_growth'], 59.5)
        self.assertEqual(len(self.database.ops), 12)

    def test_wallet_and_grade_cache_never_unlock_recharge_rewards(self):
        source = self.profile(total=0)
        stats = source['save']['gameplay_stats']
        stats.update(vip_level=12, shop_paid_currency=2147483647)
        source['save']['archive']['commerce'] = {'balances': {'u_coin': 100000000}}
        source['entitlements']['vip'] = {'active': True}
        install(self.service)
        self.assert_claims(self.load(), 0)
        self.assertFalse(self.database.ops)
        stats['vip_recharge_total_fen'] = 5000
        stats['shop_paid_currency'] = 0
        source['save']['archive']['commerce']['balances']['u_coin'] = 0
        self.assert_claims(self.load(), 1)

    def test_spending_after_unlock_does_not_downgrade(self):
        source = self.profile(total=10000)
        install(self.service)
        first = self.load()
        self.assert_claims(first, 2)
        source['save']['gameplay_stats']['shop_paid_currency'] = 0
        source['save']['archive']['commerce'] = {'balances': {'u_coin': 0}}
        before = copy.deepcopy(source)
        self.assertEqual(self.load()['save'], before['save'])
        self.assertEqual(self.service._vip_progression.level(source), 2)

    def test_repeated_open_and_install_are_idempotent(self):
        source = self.profile(total=25000)
        self.assertIs(install(self.service), self.service)
        handler = self.service.profile
        self.assertIs(install(self.service), self.service)
        self.assertIs(self.service.profile, handler)
        self.load()
        before = copy.deepcopy(source)
        operation_ids = set(self.database.ops)
        self.load()
        self.load()
        self.assertEqual(source, before)
        self.assertEqual(set(self.database.ops), operation_ids)
        self.assertTrue(all(key[1].startswith('vip:auto:' + self.bundle.hash + ':')
                            for key in operation_ids))

    def test_old_manual_claim_and_new_request_do_not_double_apply(self):
        source = self.profile(total=10000)
        self.assertTrue(self.command('vip_claim', reward_id='vip_privilege_01')['ok'])
        install(self.service)
        self.load()
        before = copy.deepcopy(source['save']['gameplay_stats'])
        for _ in range(2):
            self.assertTrue(self.command('vip_claim', reward_id='vip_privilege_01')['ok'])
        self.assertEqual(source['save']['gameplay_stats'], before)
        self.assert_effects(source, 2)

    def test_lost_commit_reply_then_reload_grants_exactly_once(self):
        source = self.profile(total=10000)
        install(self.service)
        self.database.lose_reply = True
        with self.assertRaises(TimeoutError):
            self.load()
        self.assert_claims(source, 1)
        self.assert_claims(self.load(), 2)
        self.assert_effects(source, 2)
        self.assertEqual(len(self.database.ops), 2)

    def test_compare_and_swap_conflict_preserves_other_writer(self):
        source = self.profile(total=10000)
        wood = source['save']['gameplay_stats']['initial_wood']
        install(self.service)
        self.database.conflict = True
        self.assert_claims(self.load(), 2)
        self.assert_effects(source, 2)
        self.assertEqual(source['save']['gameplay_stats']['initial_wood'], wood + 100)

    def test_recharge_never_auto_buys_package_or_medal(self):
        source = self.profile(total=1250000)
        source['save']['gameplay_stats']['shop_paid_currency'] = 999999
        source['save']['archive']['commerce'] = {'balances': {'u_coin': 999999}}
        install(self.service)
        loaded = self.load()
        self.assert_claims(loaded, 12)
        self.assertEqual(source['save']['gameplay_stats']['shop_paid_currency'], 999999)
        self.assertEqual(source['save']['archive']['commerce']['balances']['u_coin'], 999999)
        self.assertFalse(source['save'].get('content_inventory'))
        self.assertEqual(source['save']['gameplay_stats']['tower_critical_chance_pct'], 0)

    def test_legacy_inventory_marker_prevents_second_grant(self):
        source = self.profile(total=5000)
        source['save']['content_inventory'] = {'vip_privilege_01': 1}
        source['save']['gameplay_stats']['hero_damage_attack_growth'] = 1
        install(self.service)
        self.load()
        self.assertFalse(self.database.ops)
        self.assertEqual(source['save']['gameplay_stats']['hero_damage_attack_growth'], 1)

    def test_four_accounts_have_independent_levels_rewards_and_receipts(self):
        install(self.service)
        for account, level in [('100', 0), ('200', 1), ('300', 6), ('400', 12)]:
            total = self.levels[level - 1]['required_recharge_fen'] if level else 0
            self.profile(account, total)
        for account, level in [('400', 12), ('200', 1), ('100', 0), ('300', 6)]:
            loaded = self.load(account)
            self.assert_claims(loaded, level)
            self.assert_effects(loaded, level)
            count = sum(a == self.app._database_account_id(account) for a, _ in self.database.ops)
            self.assertEqual(count, level)

    def test_marketplace_catalog_opens_after_verified_threshold(self):
        source = self.profile(total=4999)
        source['save']['archive']['commerce'] = {'balances': {'u_coin': 1000000}}
        install(self.service)
        first = self.command('commerce_catalog')
        first = {row['sku']: row for row in first['products']}
        self.assertEqual(first['video_bundle_vip_01']['disabled_reason'], 'vip_level_insufficient')
        source['save']['gameplay_stats']['vip_recharge_total_fen'] = 5000
        opened = self.command('commerce_catalog')
        opened = {row['sku']: row for row in opened['products']}
        self.assertTrue(opened['video_bundle_vip_01']['enabled'])
        self.assertEqual(opened['video_bundle_vip_02']['disabled_reason'], 'vip_level_insufficient')
        self.assert_claims(source, 1)

    def test_actual_marketplace_purchase_gifts_medal_once(self):
        source = self.profile(total=10000)
        source['save']['archive']['commerce'] = {'balances': {'u_coin': 1000000}}
        install(self.service)
        self.load()
        before = source['save']['gameplay_stats']['hero_attribute_bonus_pct']
        purchase = self.command('commerce_purchase', sku='video_bundle_vip_02', request_id='vip_buy_0001')
        self.assertTrue(purchase['ok'], purchase)
        claimed = source['save']['archive']['vip_claimed']
        self.assertTrue(claimed['vip_package_02'])
        self.assertTrue(claimed['vip_medal_02'])
        self.assertEqual(source['save']['gameplay_stats']['hero_attribute_bonus_pct'], before + 1.2)
        after = copy.deepcopy(source)
        duplicate = self.command('commerce_purchase', sku='video_bundle_vip_02', request_id='vip_buy_0002')
        self.assertEqual(duplicate['error'], 'already_owned')
        self.assertEqual(source, after)

    def test_invalid_or_foreign_profile_never_causes_rewards(self):
        progression = VipProgression(self.service)
        for value in (-1, True, '5000', 5000.5, float('inf'), None, 9007199254740992):
            source = self.profile(total=value)
            self.assertEqual(progression.level(source), 0)
        with self.assertRaises(ValueError):
            progression.reconcile('200', self.profile('100', 5000))
        self.assertFalse(self.database.ops)

    def test_full_production_install_path_keeps_other_hooks(self):
        source = self.profile(total=10000)
        self.service = install_service(self.app, ROOT, self.lua)
        self.assertIsNotNone(self.service._endless_leaderboard)
        self.assertIsNotNone(self.service._vip_progression)
        loaded = self.load()
        self.assert_claims(loaded, 2)
        self.assert_effects(source, 2)
        self.assertTrue(any(name == 'archive_sync_config' for name, _ in self.database.calls))
        self.assertTrue(any(name == 'archive_bind_leaderboard_identity' for name, _ in self.database.calls))
        self.assertEqual((ROOT / 'server/bundles/current.json').read_bytes(), self.current_bytes)


if __name__ == '__main__':
    unittest.main(verbosity=2)
