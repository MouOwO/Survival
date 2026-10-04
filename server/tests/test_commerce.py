"""Real Lua reducer through the archive service, including commit/retry behavior."""
import copy
import json
import sys
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'server'))
from tests import test_archive_backend as archive_tests
from archive_backend.service import ArchiveError
from archive_backend.commerce_catalog import build_catalog

class CommerceTests(unittest.TestCase):
    setUpClass = classmethod(archive_tests.ArchiveTests.setUpClass.__func__)
    setUp = archive_tests.ArchiveTests.setUp
    command = archive_tests.ArchiveTests.command
    send = archive_tests.ArchiveTests.send
    def fund(self, **balances):
        self.profile['save']['archive']['commerce']={'balances':balances}

    def purchase(self, sku='video_p004', token='purchase_0001'):
        return self.send('commerce_purchase',sku=sku,request_id=token)

    def test_reviewed_selection_and_original_prices(self):
        catalog=build_catalog(ROOT)
        products={p['sku']:p for p in catalog['products']}
        self.assertEqual(len(products),64)
        self.assertEqual(products['video_p033']['price'],100)
        self.assertEqual(products['video_p029']['price'],600)
        self.assertEqual(products['video_p037']['currency'],'shop_gold')
        self.assertEqual(products['video_p116']['price'],588)
        self.assertNotIn('video_p140',products)
        self.assertEqual(products['video_p135']['effects']['hero_health_bonus_pct'],30)
        self.assertEqual(products['video_p069']['effects']['hero_attack_bonus_pct'],10)
        self.assertNotIn('hero_attack_speed_bonus_pct',products['video_p069']['effects'])

    def test_empty_wallet_catalog_is_read_only(self):
        before=copy.deepcopy(self.profile)
        result=self.send('commerce_catalog')
        self.assertEqual(len(result['products']),64)
        self.assertEqual(result['balances'],dict(u_coin=0,shop_points=0,shop_gold=0))
        self.assertTrue(all(not p['enabled'] for p in result['products']))
        self.assertEqual(self.profile,before)
        self.assertFalse(self.db.ops)

    def test_every_selected_product_grants_its_full_reward_list(self):
        for product in self.bundle.tables['commerce_catalog'].values():
            with self.subTest(sku=product['sku']):
                self.setUp()
                self.fund(u_coin=1000000,shop_points=1000000,shop_gold=1000000)
                before=copy.deepcopy(self.profile)
                self.assertTrue(self.purchase(product['sku'])['ok'])
                for field, amount in product['effects'].items():
                    self.assertAlmostEqual(self.profile['save']['gameplay_stats'][field],before['save']['gameplay_stats'][field]+amount)
                self.assertEqual(self.profile['save']['content_inventory'][product['item_id']],1)
                self.assertEqual(self.profile['save']['archive']['commerce']['balances'][product['currency']],1000000-product['price'])

    def test_insufficient_and_client_tampering(self):
        before=copy.deepcopy(self.profile)
        result=self.purchase()
        self.assertFalse(result['ok'])
        self.assertEqual(result['error'],'commerce_balance_insufficient')
        self.assertEqual(self.profile,before)
        for key,value in [('price',0),('currency','shop_gold'),('amount',100000),('balance',999999)]:
            with self.assertRaises(ArchiveError):
                self.service.command(self.command('commerce_purchase',sku='video_p004',request_id='tamper_0001',**{key:value}))

    def test_debit_rewards_and_limit_are_atomic(self):
        self.fund(u_coin=100000,shop_points=9999,shop_gold=9000)
        before=copy.deepcopy(self.profile)
        result=self.purchase()
        self.assertTrue(result['ok'],result)
        price=self.bundle.tables['commerce_catalog']['video_p004']['price']
        self.assertEqual(self.profile['save']['archive']['commerce']['balances'],dict(u_coin=100000-price,shop_points=9999,shop_gold=9000))
        self.assertEqual(self.profile['save']['gameplay_stats']['initial_wood'],before['save']['gameplay_stats']['initial_wood']+200)
        self.assertEqual(self.profile['save']['gameplay_stats']['starjoy_points'],before['save']['gameplay_stats']['starjoy_points']+68)
        after=copy.deepcopy(self.profile)
        self.assertEqual(self.purchase(token='purchase_0002')['error'],'already_owned')
        self.assertEqual(self.profile,after)

    def test_lost_reply_idempotent_and_token_conflict(self):
        self.fund(u_coin=100000)
        self.db.lose_reply=True
        with self.assertRaises(TimeoutError):self.purchase()
        after=copy.deepcopy(self.profile)
        self.assertTrue(self.purchase()['ok'])
        self.assertEqual(self.profile,after)
        self.assertEqual(self.purchase('video_p011')['error'],'archive_id_conflict')
        self.assertEqual(self.profile,after)

    def test_revision_conflict_keeps_other_rewards(self):
        self.fund(u_coin=100000)
        old=self.profile['save']['gameplay_stats']['initial_wood']
        self.db.conflict=True
        self.assertTrue(self.purchase()['ok'])
        self.assertEqual(self.profile['save']['gameplay_stats']['initial_wood'],old+100+200)

    def test_existing_lottery_ownership_prevents_second_grant(self):
        self.fund(shop_points=100000)
        self.profile['save']['content_inventory']={'lottery_life_spirit':1}
        before=copy.deepcopy(self.profile)
        self.assertEqual(self.purchase('video_p113')['error'],'already_owned')
        self.assertEqual(self.profile,before)

    def test_currencies_do_not_spend_starjoy_or_initial_gold(self):
        self.fund(u_coin=0,shop_points=100000,shop_gold=1000)
        self.profile['save']['gameplay_stats']['starjoy_points']=8000
        self.profile['save']['gameplay_stats']['initial_gold']=500
        self.assertTrue(self.purchase('video_p038')['ok'])
        self.assertEqual(self.profile['save']['archive']['commerce']['balances']['shop_gold'],0)
        self.assertEqual(self.profile['save']['gameplay_stats']['initial_gold'],510)
        self.assertEqual(self.profile['save']['gameplay_stats']['starjoy_points'],8000)
        self.assertTrue(self.purchase('video_p113','points_0001')['ok'])
        self.assertEqual(self.profile['save']['archive']['commerce']['balances']['shop_points'],99412)

    def test_ticket_repeatable_and_stat_overflow_does_not_charge(self):
        self.fund(u_coin=100000)
        self.assertTrue(self.purchase('video_p001','ticket_001')['ok'])
        self.assertTrue(self.purchase('video_p001','ticket_002')['ok'])
        self.assertEqual(self.profile['save']['content_inventory']['special_lottery_ticket'],2)
        self.assertEqual(self.profile['save']['archive']['commerce']['balances']['u_coin'],97600)
        self.profile['save']['gameplay_stats']['gold_mine_efficiency_pct']=10000
        before=copy.deepcopy(self.profile)
        self.assertEqual(self.purchase()['error'],'attribute_limit_reached')
        self.assertEqual(self.profile,before)

if __name__=='__main__':unittest.main()
