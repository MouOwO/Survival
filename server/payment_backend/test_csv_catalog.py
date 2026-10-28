import copy
from pathlib import Path
import unittest
from .csv_catalog import build,compile_catalog,rows,SOURCES
from .commerce_bundles import csv_text

ROOT=Path(__file__).resolve().parents[2]
class CatalogTests(unittest.TestCase):
    def setUp(self):
        self.package=build(ROOT);self.tables=copy.deepcopy(self.package['tables'])
        self.reference={k:(ROOT/'data/csv'/k).read_text(encoding='utf-8-sig') for k in SOURCES}
    def compile(self):return compile_catalog(self.tables,self.reference)
    def test_single_special_ticket_costs_6_yuan_and_is_repeatable(self):
        p=next(p for p in self.compile()['products'] if p['sku']=='special_lottery_ticket_single')
        self.assertTrue(p['enabled']);self.assertEqual(p['amount'],600)
        self.assertEqual(p['purchase_limit'],0);self.assertEqual(p['product_type'],'single')
        self.assertEqual(p['effects'],{});self.assertEqual(p['grants']['entitlements'],[])
        self.assertEqual(p['grants']['items'],{'special_lottery_ticket':1})
        self.assertEqual(len(p['grants']['lines']),1)
    def test_real_csv_bundle_is_complete_and_not_accidentally_listed(self):
        data=self.compile();p=next(p for p in data['products'] if p['sku']=='starter_bundle_v4')
        self.assertFalse(p['enabled']);self.assertEqual(len(p['effects']),5)
        self.assertTrue(all(x==100 for x in p['effects'].values()))
        self.assertEqual(p['grants']['items'],{'special_lottery_ticket':10})
        self.assertEqual(p['grants']['entitlements'],['vip'])
    def test_vip_recharge_counters_cannot_be_sold_as_rewards(self):
        for field in ('vip_level','vip_recharge_total_fen'):
            self.tables=copy.deepcopy(self.package['tables'])
            self.tables['payment_rewards']=self.tables['payment_rewards'].replace('stat,initial_wood','stat,'+field)
            with self.assertRaises(ValueError): self.compile()

    def test_money_is_exact_fen(self):
        # Exercise the general exact-fen compiler contract independently of the
        # authority's separately tested one-time discount policy.
        products=rows(self.tables['payment_products'])
        for product in products:
            if product['sku']!='archive_pass_monthly':
                product['price_policy']='';product['price_baseline_yuan']='';product['price_yuan']='7.77'
        self.tables['payment_products']=csv_text(products,list(products[0]))
        self.assertTrue(all(p['amount']==777 for p in self.compile()['products'] if p['sku']!='archive_pass_monthly'))
        self.tables['payment_products']=self.tables['payment_products'].replace('7.77','7.777')
        with self.assertRaises(ValueError):self.compile()
    def test_monthly_pass_price_duration_and_no_invented_rewards(self):
        p=next(p for p in self.package['catalog']['products'] if p['sku']=='archive_pass_monthly')
        self.assertTrue(p['enabled']);self.assertEqual(p['amount'],5800)
        self.assertEqual(p['purchase_limit'],0)
        self.assertEqual(p['effects'],{});self.assertEqual(p['grants']['items'],{})
        self.assertEqual(p['grants']['entitlements'],['archive_pass'])
        self.assertEqual(p['grants']['entitlement_days'],{'archive_pass':30})
        self.assertEqual(p['grants']['lines'][0]['duration_days'],30)
        legacy=next(p for p in self.compile()['products'] if p['sku']=='starter_bundle_v4')
        self.assertNotIn('entitlement_days',legacy['grants'],'legacy VIP remains permanent')
    def test_monthly_duration_cannot_be_invalid_or_applied_to_other_rewards(self):
        original=self.tables['payment_rewards']
        for old,new in [('签到月卡30天,1,30','签到月卡30天,1,0'),
                        ('签到月卡30天,1,30','签到月卡30天,1,'),
                        ('签到月卡30天,1,30','签到月卡30天,1,1.5'),
                        ('签到月卡30天,1,30','签到月卡30天,1,366'),
                        ('entitlement,archive_pass','entitlement,vip'),
                        ('stat,initial_wood,100,初始木材,1,','stat,initial_wood,100,初始木材,1,30')]:
            with self.subTest(new=new):
                self.tables['payment_rewards']=original.replace(old,new)
                with self.assertRaises(ValueError):self.compile()
    def test_daily_entry_agrees_with_the_authoritative_monthly_product(self):
        rule=rows((ROOT/'data/csv/存档系统/archive_daily_rules.csv').read_text(encoding='utf-8-sig'))[0]
        product=next(p for p in self.package['catalog']['products'] if p['sku']==rule['pass_sku'])
        self.assertEqual(rule['purchase_enabled'],'1')
        self.assertEqual(rule['price_text'],'58元');self.assertEqual(product['amount'],5800)
        self.assertEqual(int(rule['duration_days']),product['grants']['entitlement_days'][rule['pass_entitlement_id']])
    def test_unknown_or_unimplemented_rewards_fail_whole_catalog(self):
        for old,new in [('stat,initial_wood','stat,imaginary_buff'),('entitlement,vip','entitlement,admin'),
                        ('item,special_lottery_ticket','item,unknown_ticket'),('item,special_lottery_ticket,10','item,lottery_monkey_king,1')]:
            with self.subTest(new=new):
                self.tables=copy.deepcopy(self.package['tables'])
                self.tables['payment_rewards']=self.tables['payment_rewards'].replace(old,new)
                with self.assertRaises(ValueError):self.compile()
    def test_duplicate_ids_negative_rewards_and_cross_sku_errors_fail(self):
        for old,new in [('reward_2','reward_1'),('initial_wood,100','initial_wood,-100'),('starter_bundle_v4,stat','not_a_product,stat')]:
            self.tables=copy.deepcopy(self.package['tables']);self.tables['payment_rewards']=self.tables['payment_rewards'].replace(old,new)
            with self.assertRaises(ValueError):self.compile()
    def test_existing_permanent_item_adds_every_configured_effect_once(self):
        self.tables['payment_rewards']=self.tables['payment_rewards'].replace('item,special_lottery_ticket,10','item,lottery_nitride_alloy_wall,1')
        p=next(p for p in self.compile()['products'] if p['sku']=='starter_bundle_v4')
        self.assertEqual(p['effects']['wall_armor'],130)
        self.assertEqual(p['effects']['wall_armor_bonus_pct'],10)
        self.assertEqual(p['effects']['wall_health_per_second'],10)
        self.assertEqual(p['grants']['items'],{'lottery_nitride_alloy_wall':1})

if __name__=='__main__':unittest.main()
