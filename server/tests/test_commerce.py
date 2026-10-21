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
from payment_backend.csv_catalog import rows

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
        source=rows((ROOT/'data/csv/商城兑换系统/commerce_products.csv').read_text('utf-8-sig'))
        self.assertEqual(len(products),114+15)
        self.assertEqual(set(products),{row['sku'] for row in source})
        for row in source:
            with self.subTest(sku=row['sku']):
                self.assertEqual(row['price_policy'],'half_current_20261017')
                self.assertEqual(products[row['sku']]['price']*2,int(row['price_baseline']))
        self.assertEqual(sum(p['product_type']=='bundle' for p in products.values()),15)
        self.assertEqual({p['sku'] for p in products.values() if not p['enabled']},{'video_p037','video_p038','video_p089','video_bundle_b005'})
        self.assertEqual(products['video_p037']['effects'],{'initial_wood':50})
        self.assertEqual(products['video_p038']['effects'],{'initial_gold':10})
        self.assertEqual(products['video_p033']['price'],50)
        self.assertEqual(products['video_p029']['price'],300)
        self.assertEqual(products['video_p037']['currency'],'shop_gold')
        self.assertEqual(products['video_p116']['price'],294)
        self.assertEqual(products['video_p140']['item_id'],'lottery_nature_spirit')
        self.assertEqual(products['video_p140']['effects'],{'wood_per_second':1})
        self.assertTrue(products['video_p140']['enabled'])
        self.assertEqual(products['video_p135']['effects']['hero_health_bonus_pct'],30)
        self.assertEqual(products['video_p069']['effects']['hero_attack_bonus_pct'],10)
        self.assertNotIn('hero_attack_speed_bonus_pct',products['video_p069']['effects'])

    def test_empty_wallet_catalog_is_read_only(self):
        before=copy.deepcopy(self.profile)
        result=self.send('commerce_catalog')
        expected={p['sku'] for p in self.bundle.tables['commerce_catalog'].values() if p['enabled']}
        self.assertEqual({p['sku'] for p in result['products']},expected)
        self.assertNotIn('video_p089',expected)
        self.assertEqual(result['balances'],dict(u_coin=0,shop_points=0,shop_gold=0))
        self.assertTrue(all(not p['enabled'] for p in result['products']))
        self.assertEqual(self.profile,before)
        self.assertFalse(self.db.ops)

    def test_every_selected_product_grants_its_full_reward_list(self):
        for product in self.bundle.tables['commerce_catalog'].values():
            with self.subTest(sku=product['sku']):
                self.setUp()
                self.fund(u_coin=1000000,shop_points=1000000,shop_gold=1000000)
                if not product['enabled']:
                    before=copy.deepcopy(self.profile)
                    self.assertEqual(self.purchase(product['sku'])['error'],'shop_gold_not_open' if product['currency']=='shop_gold' else 'product_unavailable')
                    self.assertEqual(self.profile,before)
                    if product['sku']=='video_p089':
                        # Preserve paused historical pack metadata; it cannot
                        # grant a second permanent item under the unique rule.
                        self.assertEqual(product['ownership_quantity'],100)
                        self.assertEqual(product['effects'],{'hero_basic_attack_growth':10})
                    elif product['currency']!='shop_gold':
                        self.assertFalse(product['effects']);self.assertFalse(product['grants']['items'])
                    else:
                        self.assertEqual(product['effects'],{'initial_wood':50} if product['sku']=='video_p037' else {'initial_gold':10})
                    continue
                required=product['grants'].get('required_vip_level',0)
                if required:
                    tier=next(r for r in self.bundle.configs['archive_vip_levels']['rows'] if r['level']==required)
                    self.profile['save']['gameplay_stats']['vip_recharge_total_fen']=tier['required_recharge_fen']
                before=copy.deepcopy(self.profile)
                self.assertTrue(self.purchase(product['sku'])['ok'])
                # Direct gifts of starjoy points also award every newly crossed
                # formal tier in the same purchase transaction. Assert all direct
                # and tier fields, so extra progression is never silently ignored.
                prior=before['save']['gameplay_stats'];actual=self.profile['save']['gameplay_stats']
                expected=dict(product['effects']);tiers=[]
                if expected.get('starjoy_points',0)>0:
                    score=max(prior.get('starjoy_points_earned',0),prior.get('starjoy_points',0))+expected['starjoy_points']
                    tiers=[r for r in self.bundle.configs['archive_starjoy_levels']['rows'] if r.get('enabled') and r['level']>prior.get('starjoy_reward_level',0) and score>=r['required_points']]
                    for tier in tiers:
                        for field,amount in zip(tier['effect_ids'],tier['effect_values']):expected[field]=expected.get(field,0)+float(amount)
                    self.assertEqual(actual['starjoy_points_earned'],score)
                    self.assertEqual(actual['starjoy_reward_level'],max([prior.get('starjoy_reward_level',0)]+[r['level'] for r in tiers]))
                for field, amount in expected.items():
                    self.assertAlmostEqual(actual[field],prior.get(field,0)+amount,field)
                self.assertEqual(self.profile['save']['content_inventory'][product['item_id']],product.get('ownership_quantity',1))
                for item,count in product['grants']['items'].items():
                    self.assertEqual(self.profile['save']['content_inventory'][item],count)
                for claim in product['grants'].get('vip_claims',[]):
                    self.assertTrue(self.profile['save']['archive']['vip_claimed'][claim])
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
        before=copy.deepcopy(self.profile)
        self.assertEqual(self.purchase('video_p038')['error'],'shop_gold_not_open')
        self.assertEqual(self.profile,before,'Closed gold channel must neither debit nor grant')
        self.assertTrue(self.purchase('video_p113','points_0001')['ok'])
        self.assertEqual(self.profile['save']['archive']['commerce']['balances']['shop_points'],99706)
        self.assertEqual(self.profile['save']['archive']['commerce']['balances']['shop_gold'],1000)
        self.assertEqual(self.profile['save']['gameplay_stats']['initial_gold'],500)
        self.assertEqual(self.profile['save']['gameplay_stats']['starjoy_points'],8000)

    def test_ticket_repeatable_and_stat_overflow_does_not_charge(self):
        self.fund(u_coin=100000)
        self.assertTrue(self.purchase('video_p001','ticket_001')['ok'])
        self.assertTrue(self.purchase('video_p001','ticket_002')['ok'])
        self.assertEqual(self.profile['save']['content_inventory']['special_lottery_ticket'],2)
        self.assertEqual(self.profile['save']['archive']['commerce']['balances']['u_coin'],98800)
        self.profile['save']['gameplay_stats']['gold_mine_efficiency_pct']=10000
        before=copy.deepcopy(self.profile)
        self.assertEqual(self.purchase()['error'],'attribute_limit_reached')
        self.assertEqual(self.profile,before)

    def test_ember_stacks_and_the_old_hundred_pack_stays_paused(self):
        self.fund(shop_points=100000)
        before=copy.deepcopy(self.profile)
        self.assertEqual(self.purchase('video_p089','ember_100')['error'],'product_unavailable')
        self.assertEqual(self.profile,before)
        self.assertTrue(self.purchase('video_p103','ember_001')['ok'])
        self.assertEqual(self.profile['save']['content_inventory']['lottery_ember_of_legacy'],1)
        before=copy.deepcopy(self.profile)
        self.assertTrue(self.purchase('video_p103','ember_001')['ok'])
        self.assertEqual(self.profile,before)
        self.assertTrue(self.purchase('video_p103','ember_002')['ok'])
        self.assertEqual(self.profile['save']['content_inventory']['lottery_ember_of_legacy'],2)
        self.assertEqual(self.profile['save']['archive']['commerce']['balances']['shop_points'],99942)
        self.assertAlmostEqual(self.profile['save']['gameplay_stats']['hero_basic_attack_growth'],0,
                               msg='Stackable growth is projected from inventory rather than saved twice')

    def test_conditional_products_do_not_pregrant_collection_bonuses(self):
        for sku in ('video_p023','video_p025'):
            self.assertEqual(self.bundle.tables['commerce_catalog'][sku]['effects'],{'starjoy_points':298})
        self.assertEqual(self.bundle.tables['commerce_catalog']['video_p075']['effects']['starjoy_points'],200)
        self.assertNotIn('technology_cost_refund_pct',self.bundle.tables['commerce_catalog']['video_p018']['effects'])
        self.assertEqual(self.bundle.tables['commerce_catalog']['video_p094']['effects']['hero_attack_attribute_efficiency_pct'],10)

    def test_double_clear_counts_and_idempotency(self):
        self.profile['save']['content_inventory']={'commerce_p005':1}
        command=self.command('clear',difficulty_id='n1',count=1)
        self.assertTrue(self.service.command(command)['ok'])
        self.assertEqual(self.profile['save']['archive']['clear_counts']['n1'],2)
        before=copy.deepcopy(self.profile)
        self.assertTrue(self.service.command(command)['ok'])
        self.assertEqual(self.profile,before)

if __name__=='__main__':unittest.main()
