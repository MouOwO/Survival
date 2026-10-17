"""Exercise final prices, retained references and repeat-build integrity."""
import copy
from decimal import Decimal
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from .csv_catalog import build,compile_catalog,rows,SOURCES,HALF_PRICE_POLICY
from .commerce_bundles import compile_commerce,csv_text
from . import ucoin_recharge

ROOT=Path(__file__).resolve().parents[2]

class HalfPriceTests(unittest.TestCase):
    def setUp(self):
        self.package=build(ROOT)
        self.reference={name:(ROOT/'data/csv'/name).read_text(encoding='utf-8-sig') for name in SOURCES}

    def test_every_commerce_price_is_half_actual_price_including_old_bundle_sale(self):
        records=rows(self.package['commerce_tables']['commerce_products'])
        self.assertEqual(len(records),129)
        catalog=compile_commerce(self.package['commerce_tables'],self.reference,self.package['tables']['payment_categories'])
        compiled={p['sku']:p for p in catalog['products']}
        memberships=rows(self.package['commerce_tables']['commerce_bundle_members'])
        bundles={p['bundle_sku'] for p in memberships if p['enabled']=='1'}
        self.assertEqual({r['currency'] for r in records},{'u_coin','shop_points','shop_gold'})
        for p in records:
            with self.subTest(sku=p['sku']):
                self.assertEqual(p['price_policy'],HALF_PRICE_POLICY)
                basis=Decimal(p['price_baseline'])
                historical=p['source_current_price'] if p['sku'] in bundles else p['source_original_price'] or p['source_current_price']
                self.assertEqual(basis,Decimal(historical))
                self.assertEqual(Decimal(p['price'])*2,basis)
                self.assertEqual(compiled[p['sku']]['price'],int(p['price']))
        again=compile_commerce(self.package['commerce_tables'],self.reference,self.package['tables']['payment_categories'])
        self.assertEqual(catalog,again,'Compiling final authority prices must never discount again')

    def test_all_eight_cash_prices_and_recharge_are_independent(self):
        records=rows(self.package['tables']['payment_products']);self.assertEqual(len(records),8)
        products={p['sku']:p for p in compile_catalog(self.package['tables'],self.reference)['products']}
        for p in records:
            self.assertEqual(p['price_policy'],HALF_PRICE_POLICY)
            self.assertEqual(Decimal(p['price_yuan'])*2,Decimal(p['price_baseline_yuan']))
            self.assertEqual(products[p['sku']]['amount'],Decimal(p['price_yuan'])*100)
        self.assertEqual(products['archive_pass_monthly']['amount'],1000)
        recharge=ucoin_recharge.product()
        self.assertEqual(recharge['amount'],100)
        self.assertEqual(recharge['grants']['lines'][0]['quantity'],100)
        self.assertEqual(recharge['grants']['pricing'],dict(u_coin_price=100,u_coin_per_yuan=100))
        payment={p['sku']:p for p in self.package['catalog']['products']}
        for p in rows(self.package['commerce_tables']['commerce_products']):
            if p['currency']=='u_coin':
                self.assertEqual(payment[p['sku']]['amount'],int(p['price']))
                self.assertEqual(payment[p['sku']]['u_coin_per_yuan'],100)

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
                for relative,field,basis,count in ((tool.COMMERCE,'price','price_baseline',129),(tool.PAYMENT,'price_yuan','price_baseline_yuan',8)):
                    path=temporary/relative;before=path.read_bytes()
                    tool.update_prices(relative,field,basis,count);once=path.read_bytes()
                    tool.update_prices(relative,field,basis,count)
                    self.assertEqual(before,once);self.assertEqual(once,path.read_bytes())

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
