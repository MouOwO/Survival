"""Exercise final prices, retained references and repeat-build integrity."""
import copy
from decimal import Decimal
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
from .csv_catalog import build,compile_catalog,rows,SOURCES,HALF_PRICE_POLICY,MONTHLY_FIXED_PRICE_POLICY,FIXED_QUALITY_SHOP_POINTS_POLICY,fixed_points_price,FIXED_TICKET_PRICE_POLICY,TICKET_PRICES
from .commerce_bundles import compile_commerce,csv_text
from . import ucoin_recharge

ROOT=Path(__file__).resolve().parents[2]

class HalfPriceTests(unittest.TestCase):
    def setUp(self):
        self.package=build(ROOT)
        self.reference={name:(ROOT/'data/csv'/name).read_text(encoding='utf-8-sig') for name in SOURCES}

    def test_fixed_point_prices_and_unchanged_cash_half_prices(self):
        records=rows(self.package['commerce_tables']['commerce_products'])
        self.assertEqual(len(records),130)
        catalog=compile_commerce(self.package['commerce_tables'],self.reference,self.package['tables']['payment_categories'])
        compiled={p['sku']:p for p in catalog['products']}
        memberships=rows(self.package['commerce_tables']['commerce_bundle_members'])
        bundles={p['bundle_sku'] for p in memberships if p['enabled']=='1'}
        self.assertEqual({r['currency'] for r in records},{'u_coin','shop_points','shop_gold'})
        for p in records:
            with self.subTest(sku=p['sku']):
                if p['currency']=='shop_points':
                    self.assertEqual(p['price_policy'],FIXED_QUALITY_SHOP_POINTS_POLICY)
                    self.assertEqual(int(p['price']),fixed_points_price(p))
                else:
                    self.assertEqual(p['price_policy'],HALF_PRICE_POLICY)
                    self.assertEqual(Decimal(p['price'])*2,Decimal(p['price_baseline']))
                basis=Decimal(p['price_baseline'])
                historical=p['source_current_price'] if p['sku'] in bundles else p['source_original_price'] or p['source_current_price']
                self.assertEqual(basis,Decimal(historical))
                self.assertEqual(compiled[p['sku']]['price'],int(p['price']))
        again=compile_commerce(self.package['commerce_tables'],self.reference,self.package['tables']['payment_categories'])
        self.assertEqual(catalog,again,'Compiling final authority prices must never discount again')

    def test_seven_cash_discounts_fixed_monthly_price_and_recharge_are_independent(self):
        records=rows(self.package['tables']['payment_products']);self.assertEqual(len(records),9)
        products={p['sku']:p for p in compile_catalog(self.package['tables'],self.reference)['products']}
        for p in records:
            if p['sku']=='archive_pass_monthly':
                self.assertEqual(p['price_policy'],MONTHLY_FIXED_PRICE_POLICY)
                self.assertEqual(Decimal(p['price_yuan']),58)
                self.assertEqual(Decimal(p['price_baseline_yuan']),20)
            elif p['sku'] in TICKET_PRICES:
                self.assertEqual(p['price_policy'],FIXED_TICKET_PRICE_POLICY)
                self.assertEqual(Decimal(p['price_yuan'])*100,TICKET_PRICES[p['sku']])
                self.assertEqual(p['price_yuan'],p['price_baseline_yuan'])
            else:
                self.assertEqual(p['price_policy'],HALF_PRICE_POLICY)
                self.assertEqual(Decimal(p['price_yuan'])*2,Decimal(p['price_baseline_yuan']))
            self.assertEqual(products[p['sku']]['amount'],Decimal(p['price_yuan'])*100)
        self.assertEqual(products['archive_pass_monthly']['amount'],5800)
        recharge=ucoin_recharge.product()
        self.assertEqual(recharge['amount'],100)
        self.assertEqual(recharge['grants']['lines'][0]['quantity'],100)
        self.assertEqual(recharge['grants']['pricing'],dict(u_coin_price=100,u_coin_per_yuan=100))
        payment={p['sku']:p for p in self.package['catalog']['products']}
        for p in rows(self.package['commerce_tables']['commerce_products']):
            if p['currency']=='u_coin':
                self.assertEqual(payment[p['sku']]['amount'],int(p['price']))
                self.assertEqual(payment[p['sku']]['u_coin_per_yuan'],100)

    def test_monthly_fixed_price_cannot_regress_discount_or_fabricate_its_baseline(self):
        for mutation in ('old_half','missing_policy','fake_baseline','wrong_price','other_sku'):
            with self.subTest(mutation=mutation):
                tables=copy.deepcopy(self.package['tables']);records=rows(tables['payment_products'])
                monthly=next(p for p in records if p['sku']=='archive_pass_monthly')
                if mutation=='old_half':monthly.update(price_policy=HALF_PRICE_POLICY,price_yuan='10.00')
                elif mutation=='missing_policy':monthly['price_policy']=''
                elif mutation=='fake_baseline':monthly['price_baseline_yuan']='116.00'
                elif mutation=='wrong_price':monthly['price_yuan']='29.00'
                else:records[0].update(price_policy=MONTHLY_FIXED_PRICE_POLICY,price_yuan='58.00',price_baseline_yuan='20.00')
                tables['payment_products']=csv_text(records,list(records[0]))
                with self.assertRaisesRegex(ValueError,'catalog_monthly_fixed_price_invalid'):
                    compile_catalog(tables,self.reference)

    def test_policy_cannot_be_missing_unknown_or_quartered(self):
        for mutation in ('missing','unknown','quarter','source_drift'):
            with self.subTest(mutation=mutation):
                tables=copy.deepcopy(self.package['commerce_tables']);records=rows(tables['commerce_products']);p=records[0]
                if mutation=='missing':p['price_baseline']=''
                elif mutation=='unknown':p['price_policy']='half_again'
                elif mutation=='quarter':p['price']=str(int(p['price'])//2)
                else:p['price_baseline']=str(int(p['price_baseline'])*2);p['price']=str(int(p['price'])*2)
                tables['commerce_products']=csv_text(records,list(records[0]))
                with self.assertRaisesRegex(ValueError,'catalog_(half_price_mismatch|price_policy_invalid)'):
                    compile_commerce(tables,self.reference,self.package['tables']['payment_categories'])

    def test_one_time_csv_migration_is_idempotent_and_preserves_evidence(self):
        spec=importlib.util.spec_from_file_location('half_price_tool',ROOT/'tools/shop_pricing_half_20261017/catalog_prices.py')
        tool=importlib.util.module_from_spec(spec);spec.loader.exec_module(tool)
        with tempfile.TemporaryDirectory() as directory:
            temporary=Path(directory)
            for relative in (tool.COMMERCE,tool.PAYMENT):
                path=temporary/relative;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes((ROOT/relative).read_bytes())
            with patch.object(tool,'ROOT',temporary),patch.object(tool,'OUT',temporary/'audit'):
                for relative,field,basis,count in ((tool.COMMERCE,'price','price_baseline',130),(tool.PAYMENT,'price_yuan','price_baseline_yuan',9)):
                    path=temporary/relative;before=path.read_bytes()
                    with self.assertRaisesRegex(AssertionError,'invalid_existing_policy'):
                        tool.update_prices(relative,field,basis,count)
                    self.assertEqual(path.read_bytes(),before,'The archived migration cannot overwrite newer fixed prices')

    def test_half_price_tool_reapply_promotes_only_monthly_to_fixed_price_once(self):
        spec=importlib.util.spec_from_file_location('half_price_tool',ROOT/'tools/shop_pricing_half_20261017/catalog_prices.py')
        tool=importlib.util.module_from_spec(spec);spec.loader.exec_module(tool)
        self.assertEqual(tool.MONTHLY_FIXED_POLICY,MONTHLY_FIXED_PRICE_POLICY)
        with tempfile.TemporaryDirectory() as directory:
            temporary=Path(directory);path=temporary/tool.PAYMENT;path.parent.mkdir(parents=True,exist_ok=True)
            current=(ROOT/tool.PAYMENT).read_bytes()
            # This archived migration accepts only its original eight offers.
            # Keep a historical fixture rather than reapplying it to new tickets.
            fixture=rows(current.decode('utf-8-sig'))
            fixture=[p for p in fixture if p['sku']!='lottery_ticket_single']
            ticket=next(p for p in fixture if p['sku']=='special_lottery_ticket_single')
            ticket.update(price_yuan='25.00',price_policy=HALF_PRICE_POLICY,price_baseline_yuan='50.00')
            current=csv_text(fixture,list(fixture[0])).encode('utf-8')
            old=current.replace(b'single,58.00,0,1,80,',b'single,10.00,0,1,80,')
            old=old.replace('58元开通'.encode(),'10元开通'.encode()).replace(MONTHLY_FIXED_PRICE_POLICY.encode(),HALF_PRICE_POLICY.encode())
            self.assertNotEqual(old,current);path.write_bytes(old)
            with patch.object(tool,'ROOT',temporary),patch.object(tool,'OUT',temporary/'audit'):
                changes=tool.update_prices(tool.PAYMENT,'price_yuan','price_baseline_yuan',8)
                self.assertEqual(path.read_bytes(),current)
                self.assertEqual(sum(p['price_policy']==tool.MONTHLY_FIXED_POLICY for p in changes),1)
                tool.update_prices(tool.PAYMENT,'price_yuan','price_baseline_yuan',8)
                self.assertEqual(path.read_bytes(),current)

    def test_daily_price_regeneration_uses_fixed_authority_price_and_is_idempotent(self):
        spec=importlib.util.spec_from_file_location('half_price_tool',ROOT/'tools/shop_pricing_half_20261017/catalog_prices.py')
        tool=importlib.util.module_from_spec(spec);spec.loader.exec_module(tool)
        builder_spec=importlib.util.spec_from_file_location('build_configs',ROOT/'tools/build_configs.py')
        builder=importlib.util.module_from_spec(builder_spec);builder_spec.loader.exec_module(builder)
        rule='data/csv/存档系统/archive_daily_rules.csv'
        generated='scripts/vscripts/config/generated/archive_daily_rules.lua'
        with tempfile.TemporaryDirectory() as directory:
            temporary=Path(directory)
            for relative in (tool.PAYMENT,rule,generated):
                path=temporary/relative;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes((ROOT/relative).read_bytes())
            expected=(temporary/rule).read_bytes()
            (temporary/rule).write_bytes(expected.replace('58元'.encode(),'10元'.encode()))
            with patch.object(tool,'ROOT',temporary),patch.object(tool,'OUT',temporary/'audit'),patch.dict(sys.modules,{'build_configs':builder}):
                tool.monthly_rule();self.assertEqual((temporary/rule).read_bytes(),expected)
                self.assertEqual((temporary/generated).read_text('utf-8'),(ROOT/generated).read_text('utf-8'))
                tool.monthly_rule();self.assertEqual((temporary/rule).read_bytes(),expected)
                self.assertEqual((temporary/generated).read_text('utf-8'),(ROOT/generated).read_text('utf-8'))

    def test_bundle_previews_match_final_authority_and_preserve_original_reference(self):
        data=json.loads((ROOT/'data/ui/video_shop_bundles_20261015.json').read_bytes())
        products={p['sku']:p for p in rows(self.package['commerce_tables']['commerce_products'])}
        self.assertEqual(len(data['products']),15)
        for p in data['products']:
            source=products[p['sku']]
            self.assertEqual(p['price'],int(source['price']))
            self.assertEqual(p['amount_fen'],p['u_coin_price'])
            self.assertEqual(p['u_coin_per_yuan'],100)
            self.assertEqual(p['original_price'],int(source['source_original_price']))

if __name__=='__main__':unittest.main()
