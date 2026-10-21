"""Permanent point goods share one ownership record across shop/draw/aliases."""
import copy
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
import re
import sys
import threading
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'server'))

from payment_backend.csv_catalog import build, rows, SOURCES
from payment_backend.commerce_bundles import compile_commerce, csv_text
from payment_backend import test_commerce_bundles as bundle_tests
from archive_backend.bundle import Bundle


class PointOfferTests(unittest.TestCase):
    def setUp(self):
        self.package = build(ROOT)
        self.tables = copy.deepcopy(self.package['commerce_tables'])
        self.reference = {name: (ROOT / 'data/csv' / name).read_text('utf-8-sig') for name in SOURCES}

    def compile(self):
        return {p['sku']: p for p in compile_commerce(
            self.tables, self.reference, self.package['tables']['payment_categories'])['products']}

    def test_hundred_pack_is_paused_with_same_rewards_and_fixed_quality_price(self):
        products = self.compile()
        bulk, single = products['video_p089'], products['video_p103']
        self.assertFalse(bulk['enabled'])
        self.assertEqual((bulk['price'], bulk['ownership_quantity']), (8000, 100))
        self.assertEqual(bulk['effects'], {'hero_basic_attack_growth': 10})
        self.assertTrue(single['enabled'])
        self.assertEqual((single['price'], single['ownership_quantity'], single['purchase_limit']), (8000, 1, 0))
        self.assertEqual(single['item_id'], bulk['item_id'])
        self.assertEqual(single['effects'], {})

    def test_future_enabled_point_offers_cannot_reintroduce_unlimited_or_bulk_ownership(self):
        for sku, edits in [('video_p117', {'purchase_limit': '0'}),
                           ('video_p117', {'ownership_quantity': '2'})]:
            with self.subTest(sku=sku, edits=edits):
                original = self.tables['commerce_products']
                records = rows(original)
                next(p for p in records if p['sku'] == sku).update(edits)
                self.tables['commerce_products'] = csv_text(records, list(records[0]))
                with self.assertRaisesRegex(ValueError, 'commerce_unique_points_ownership_invalid'):
                    self.compile()
                self.tables['commerce_products'] = original


class PointPurchaseTests(unittest.TestCase):
    setUpClass = classmethod(bundle_tests.LuaBundleTests.setUpClass.__func__)

    def setUp(self):
        self.bundle = copy.deepcopy(self.base_bundle)
        self.db = self.Database(self.bundle)
        self.app = self.App(self.db)
        self.service = self.Service(self.app, self.bundle,
            os.environ.get('LUA_EXECUTABLE', 'C:/Program Files/lua/bin/lua5.1.exe'))
        self.profile = self.db.profile(self.app._database_account_id('100'))
        self.profile['save']['archive']['commerce'] = {'balances': {'shop_points': 100000}}
        self.seq = 0

    def command(self, sku, token):
        return dict(account_id='100', config_hash=self.bundle.hash,
            command=dict(id='unique_points:' + token, kind='commerce_purchase', sku=sku, request_id=token))

    def purchase(self, sku='video_p103', token='unique_first_0001'):
        return self.service.command(self.command(sku, token))

    def snapshot(self):
        self.seq += 1
        return self.service.command(dict(account_id='100', config_hash=self.bundle.hash,
            command=dict(id='unique_snapshot:' + str(self.seq), kind='commerce_catalog')))

    def test_ember_stacks_and_same_receipt_replays_without_debit_or_effects(self):
        before = copy.deepcopy(self.profile['save']['gameplay_stats'])
        self.assertTrue(self.purchase()['ok'])
        save = self.profile['save']
        self.assertEqual(save['content_inventory']['lottery_ember_of_legacy'], 1)
        self.assertEqual(save['archive']['commerce']['balances']['shop_points'], 92000)
        self.assertAlmostEqual(save['gameplay_stats']['hero_basic_attack_growth'], before['hero_basic_attack_growth'])
        lua = self.LuaRuntime(unpack_returned_tuples=True)
        lua.globals().INPUT = json.dumps(dict(configs=self.bundle.configs, save=save))
        lua.execute('package.path = ' + json.dumps(self.bundle.directory.as_posix() + '/?.lua'))
        lua.execute('''
            local input=require('core/json_decoder').decode(INPUT)
            for name,config in pairs(input.configs) do
                package.loaded['config/generated/'..name]={rows=config.rows}
            end
            OUTPUT=require('core/json_encoder').encode(
                require('systems/commerce_effects').project(input.save,input.save.gameplay_stats))
        ''')
        self.assertEqual(json.loads(lua.globals().OUTPUT), {'hero_basic_attack_growth': .1},
                      'Per-copy attack growth is derived, never repeatedly persisted')
        after = copy.deepcopy(self.profile)
        self.assertTrue(self.purchase()['ok'])
        self.assertEqual(self.profile, after)
        self.assertTrue(self.purchase(token='unique_second_0002')['ok'])
        self.assertEqual(self.profile['save']['content_inventory']['lottery_ember_of_legacy'], 2)
        self.assertEqual(self.profile['save']['archive']['commerce']['balances']['shop_points'], 84000)

    def test_paused_bulk_offer_never_debits_or_grants_and_is_absent_from_catalog(self):
        before = copy.deepcopy(self.profile)
        self.assertEqual(self.purchase('video_p089')['error'], 'product_unavailable')
        self.assertEqual(self.profile, before)
        self.assertNotIn('video_p089', {p['sku'] for p in self.snapshot()['products']})

    def test_legacy_ember_count_is_preserved_and_can_be_rebought(self):
        self.profile['save']['content_inventory'] = {'lottery_ember_of_legacy': 101, 'daily_growth_gem': 9}
        before = copy.deepcopy(self.profile)
        offer = next(p for p in self.snapshot()['products'] if p['sku'] == 'video_p103')
        self.assertEqual(offer['owned'], 101)
        self.assertEqual(offer['disabled_reason'], '')
        self.assertEqual(self.profile, before, 'Reading does not rewrite history')
        self.assertTrue(self.purchase()['ok'])
        self.assertEqual(self.profile['save']['content_inventory']['lottery_ember_of_legacy'], 102)
        self.assertEqual(self.profile['save']['gameplay_stats'], before['save']['gameplay_stats'])

    def test_alias_ownership_blocks_direct_and_bundle_items_even_with_stale_unlimited_limits(self):
        # Exercise every formal permanent point identity through the real
        # transaction path; an old unlimited offer must still share ownership.
        products = self.bundle.tables['commerce_catalog']
        product = products['video_p103']
        points = [r for r in self.bundle.configs['lottery_item_definitions']['rows']
                  if r.get('enabled') and r['item_type'] == '积分道具' and r['item_id']!='lottery_ember_of_legacy']
        self.assertEqual(len(points), 96)
        for item in points:
            with self.subTest(item=item['item_id']):
                product.update(item_id=item['item_id'], purchase_limit=0)
                self.profile['save']['content_inventory'] = {item['item_id']: 1}
                before = copy.deepcopy(self.profile)
                result = self.purchase(token='unique_item_' + item['item_id'])
                self.assertEqual(result['error'], 'already_owned')
                self.assertEqual(self.profile, before)
        product.update(item_id='lottery_nature_crystal', purchase_limit=0)
        self.profile['save']['content_inventory'] = {'lottery_flame_crystal': 3}
        before = copy.deepcopy(self.profile)
        self.assertEqual(self.purchase(token='unique_alias_direct')['error'], 'already_owned')
        self.assertEqual(self.profile, before)
        product.update(item_id='commerce_unique_bundle', purchase_limit=0)
        product['grants']['items'] = {'lottery_nature_crystal': 1}
        product['grants']['item_limits'] = {'lottery_nature_crystal': 100000000}
        self.assertEqual(self.purchase(token='unique_alias_bundle')['error'], 'component_already_owned')
        self.assertEqual(self.profile, before)

    def test_concurrent_ember_offers_both_commit_once_and_preserve_inventory(self):
        other = copy.deepcopy(self.bundle.tables['commerce_catalog']['video_p103'])
        other['sku'] = 'unique_second_offer'
        self.bundle.configs['commerce_catalog']['rows'].append(other)
        self.bundle.tables['commerce_catalog'][other['sku']] = other
        barrier = threading.Barrier(2)
        original_settle = self.service.settle
        initial_lock = threading.Lock()
        initial_calls = set()

        def contend(profile, command, has_pass):
            result = original_settle(profile, command, has_pass)
            if command['kind'] == 'commerce_purchase':
                with initial_lock:
                    first = command['id'] not in initial_calls
                    initial_calls.add(command['id'])
                if first:
                    barrier.wait(timeout=10)
            return result

        self.service.settle = contend
        with ThreadPoolExecutor(max_workers=2) as executor:
            futures = [executor.submit(self.purchase, sku, 'unique_concurrent_' + str(index))
                       for index, sku in enumerate(('video_p103', other['sku']))]
            results = [future.result(timeout=20) for future in futures]
        self.assertEqual(sum(r['ok'] is True for r in results), 2)
        self.assertEqual(self.profile['save']['content_inventory']['lottery_ember_of_legacy'], 2)
        self.assertEqual(self.profile['save']['archive']['commerce']['balances']['shop_points'], 84000)

    def historical_bundle(self):
        data = json.loads((self.bundle.directory / 'bundle.json').read_bytes())
        products = {p['sku']: p for p in data['configs']['commerce_catalog']['rows']}
        products['video_p089']['enabled'] = True
        products['video_p103'].update(price=58, purchase_limit=0)
        source = data['sources']['systems/commerce_settlement.lua']
        source, changes = re.subn(
            r"    -- Every route shares the lottery's permanent identity\..*?(?=    if p.purchase_limit)",
            '', source, flags=re.S)
        self.assertEqual(changes, 1)
        source = source.replace("        local owned=owned_points(inventory,id)\n"
            "        if owned~=nil and (owned>0 or n~=1) then return 'component_already_owned' end\n", '')
        data['sources']['systems/commerce_settlement.lua'] = source
        raw = json.dumps(data, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()
        digest = hashlib.sha256(raw).hexdigest()
        directory = self.bundle.directory.parent / digest
        directory.mkdir(exist_ok=True)
        for name, content in data['sources'].items():
            path = directory / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding='utf-8', newline='\n')
        (directory / 'bundle.json').write_bytes(raw)
        return Bundle(directory)

    def resume_historical(self, old, sku, token):
        account = self.app._database_account_id('100')
        request = self.command(sku, token)['command']
        identity = 'commerce:' + token
        prepared = self.db.rpc('archive_prepare', dict(p_account=account, p_id=identity,
            p_command=request, p_fingerprint=token, p_hash=old.hash))
        return self.service.finish_prepared(account, identity, prepared)

    def test_unfinished_changed_prices_require_confirmation_and_completed_receipts_stay_immutable(self):
        old = self.historical_bundle()
        old_service = self.Service(self.app, old, 'local-lupa')
        self.assertTrue(old_service.settle(self.profile,
            self.command('video_p089', 'historical_preview_0001')['command'], False)['ok'],
            'The recorded reducer deliberately permits the historical 100-pack')
        before = copy.deepcopy(self.profile)
        self.assertEqual(self.resume_historical(old, 'video_p089', 'historical_bulk_0001')['error'],
                         'product_unavailable')
        self.assertEqual(self.profile, before)
        self.assertEqual(self.resume_historical(old, 'video_p103', 'historical_one_0001')['error'],'commerce_price_changed')
        self.assertEqual(self.profile,before,'An unfinished old price never silently debits the higher amount')
        token='historical_completed_0002';account=self.app._database_account_id('100');identity='commerce:'+token
        prepared=self.db.rpc('archive_prepare',dict(p_account=account,p_id=identity,
            p_command=self.command('video_p103',token)['command'],p_fingerprint=token,p_hash=old.hash))
        self.assertTrue(old_service.finish_prepared(account,identity,prepared)['ok'])
        self.assertEqual(self.profile['save']['archive']['commerce']['balances']['shop_points'],99942)
        self.assertEqual(self.profile['save']['content_inventory']['lottery_ember_of_legacy'],1)
        settled=copy.deepcopy(self.profile)
        self.assertTrue(self.resume_historical(old,'video_p103',token)['ok'])
        self.assertEqual(self.profile, settled, 'Completed historical receipts remain immutable and replayable')


if __name__ == '__main__':
    unittest.main(verbosity=2)
