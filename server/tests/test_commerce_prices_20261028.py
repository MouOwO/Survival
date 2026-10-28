"""Approved ticket prices and stackable point exchanges use real settlement."""
import copy
import sys
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'server'))
sys.path.insert(0,str(Path(__file__).resolve().parent))
import test_archive_backend as base
from payment_backend.csv_catalog import build,compile_catalog,rows,SOURCES
from payment_backend.commerce_bundles import csv_text


class CommercePriceTests(unittest.TestCase):
    setUpClass=classmethod(base.ArchiveTests.setUpClass.__func__)
    setUp=base.ArchiveTests.setUp
    command=base.ArchiveTests.command
    send=base.ArchiveTests.send

    def test_two_60_point_items_grant_one_copy_without_static_effect_duplication(self):
        for sku,item in (('video_p103','lottery_ember_of_legacy'),
                         ('points_welfare_zongzi','welfare_zongzi')):
            with self.subTest(sku=sku):
                self.setUp()
                self.profile['save']['archive']['commerce']={'balances':{'shop_points':120,'u_coin':777}}
                before=copy.deepcopy(self.profile['save']['gameplay_stats'])
                product=self.bundle.tables['commerce_catalog'][sku]
                self.assertEqual(product['effects'],{})
                result=self.send('commerce_purchase',sku=sku,request_id='repeatable_one')
                self.assertTrue(result['ok'],result)
                result=self.send('commerce_purchase',sku=sku,request_id='repeatable_two')
                self.assertTrue(result['ok'],result)
                self.assertEqual(self.profile['save']['content_inventory'][item],2)
                self.assertEqual(self.profile['save']['archive']['commerce']['balances'],{'shop_points':0,'u_coin':777})
                self.assertEqual(self.profile['save']['gameplay_stats'],before)

    def test_zongzi_inventory_cap_rejects_purchase_without_spending_points(self):
        self.profile['save']['content_inventory']={'welfare_zongzi':150}
        self.profile['save']['archive']['commerce']={'balances':{'shop_points':60}}
        before=copy.deepcopy(self.profile['save'])
        result=self.send('commerce_purchase',sku='points_welfare_zongzi',request_id='zongzi_full')
        self.assertFalse(result['ok'],result)
        self.assertEqual(self.profile['save'],before)

    def test_cash_tickets_have_exact_price_and_single_reward_and_reject_price_drift(self):
        package=build(ROOT)
        reference={name:(ROOT/'data/csv'/name).read_text('utf-8-sig') for name in SOURCES}
        catalog={p['sku']:p for p in package['catalog']['products']}
        for sku,item,fen in (('lottery_ticket_single','lottery_ticket',300),
                             ('special_lottery_ticket_single','special_lottery_ticket',600)):
            with self.subTest(sku=sku):
                p=catalog[sku]
                self.assertEqual(p['amount'],fen)
                self.assertEqual(p['grants']['items'],{item:1})
                self.assertEqual(p['purchase_limit'],0)
                tables=copy.deepcopy(package['tables'])
                products=rows(tables['payment_products'])
                next(p for p in products if p['sku']==sku)['price_yuan']='25.00'
                tables['payment_products']=csv_text(products,list(products[0]))
                with self.assertRaisesRegex(ValueError,'catalog_fixed_ticket_price_invalid'):
                    compile_catalog(tables,reference)


if __name__=='__main__':unittest.main()
