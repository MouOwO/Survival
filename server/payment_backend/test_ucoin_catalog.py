"""Verify exact U-coin pricing, complete rewards and operator package validation."""
import copy
import csv
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest import mock

from .csv_catalog import SOURCES, build, canonical, compile_catalog, rows
from .ucoin_catalog import COMMERCE_SOURCES, U_COIN_PER_YUAN, compile_payment_catalog, ucoin_amount_fen
from . import ucoin_recharge

ROOT = Path(__file__).resolve().parents[2]


def replace_rows(text, update):
    records = rows(text)
    update(records)
    output = io.StringIO()
    writer = csv.DictWriter(output, fieldnames=list(records[0]))
    writer.writeheader()
    writer.writerows(records)
    return output.getvalue()


class UcoinCatalogTests(unittest.TestCase):
    def setUp(self):
        self.package = build(ROOT)
        self.tables = copy.deepcopy(self.package['tables'])
        self.commerce_tables = copy.deepcopy(self.package['commerce_tables'])
        self.reference = {name: (ROOT / 'data/csv' / name).read_text(encoding='utf-8-sig') for name in SOURCES}

    def compile(self):
        return compile_payment_catalog(self.tables, self.commerce_tables, self.reference)

    def edit_product(self, product_sku='video_p004', **changes):
        def update(records):
            next(row for row in records if row['sku'] == product_sku).update(changes)
        self.commerce_tables['commerce_products'] = replace_rows(self.commerce_tables['commerce_products'], update)

    def test_exact_rate_and_all_real_ucoin_products(self):
        catalog = self.compile()
        products = {row['sku']: row for row in catalog['products']}
        ucoin = {row['sku']: row for row in rows(self.commerce_tables['commerce_products']) if row['currency'] == 'u_coin'}
        legacy={p['sku'] for p in compile_catalog(self.tables,self.reference)['products']}
        self.assertEqual(set(products),legacy|set(ucoin)|{ucoin_recharge.SKU})
        self.assertTrue(ucoin)
        self.assertEqual(U_COIN_PER_YUAN, 1000)
        self.assertEqual(catalog['u_coin_per_yuan'], 1000)
        self.assertEqual(catalog['exchange_rate'], 1000)
        for sku, source in ucoin.items():
            with self.subTest(sku=sku):
                product = products[sku]
                self.assertEqual(product['amount'], int(source['price']) // 10)
                self.assertIsInstance(product['amount'], int)
                self.assertEqual(product['u_coin_price'], int(source['price']))
                self.assertEqual(product['u_coin_per_yuan'], 1000)
                self.assertEqual(product['exchange_rate'], 1000)
                pricing={'u_coin_price':int(source['price']),'u_coin_per_yuan':1000}
                if source['product_type']=='bundle':pricing['original_u_coin_price']=int(source['source_original_price'])
                self.assertEqual(product['grants']['pricing'],pricing)
        self.assertEqual(products['video_p033']['amount'], 10)
        self.assertEqual(products['video_p029']['amount'], 60)
        self.assertEqual(products['video_p001']['amount'], 120)
        self.assertEqual(products['video_p004']['amount'], 680)
        self.assertEqual(products['video_p012']['amount'], 2980)

    def test_legacy_cash_products_remain_unchanged(self):
        old = compile_catalog(self.tables, self.reference)
        merged = {row['sku']: row for row in self.compile()['products']}
        for product in old['products']:
            self.assertEqual(merged[product['sku']], product)
        cash_count=sum(p['currency']=='u_coin' for p in rows(self.commerce_tables['commerce_products']))
        self.assertEqual(len(merged), len(old['products']) + cash_count + 1)
        self.assertEqual(merged[ucoin_recharge.SKU],ucoin_recharge.product())
        self.assertEqual(merged['special_lottery_ticket_single']['amount'], 5000)
        self.assertFalse(merged['starter_bundle_v4']['enabled'])

    def test_other_wallet_currencies_are_not_cash_products(self):
        merged = {row['sku'] for row in self.compile()['products']}
        for product in rows(self.commerce_tables['commerce_products']):
            if product['currency'] != 'u_coin':
                self.assertNotIn(product['sku'], merged)
        self.commerce_tables['commerce_products'] = replace_rows(
            self.commerce_tables['commerce_products'],
            lambda records: [row.update(currency='shop_points') for row in records if row['currency'] == 'u_coin'])
        self.assertEqual(self.compile()['products'], compile_catalog(self.tables, self.reference)['products']+[ucoin_recharge.product()])

    def test_original_ownership_limits_and_all_rewards_are_preserved(self):
        products = {row['sku']: row for row in self.compile()['products']}
        rewards = rows(self.commerce_tables['commerce_rewards'])
        for source in rows(self.commerce_tables['commerce_products']):
            if source['currency'] != 'u_coin':
                continue
            product = products[source['sku']]
            self.assertEqual(product['item_id'], source['ownership_id'])
            self.assertEqual(product['purchase_limit'], int(source['purchase_limit']))
            if source['product_type']=='bundle':
                expected=[row for row in rows(self.commerce_tables['commerce_bundle_members']) if row['bundle_sku']==source['sku'] and row['enabled']=='1']
                self.assertEqual([(r['kind'],r['id'],r['quantity']) for r in product['grants']['lines']],
                    [(r['member_type'],r['target_id'],int(r['quantity'])) for r in expected])
                self.assertEqual(product['enabled'],source['enabled']=='1')
                if not product['enabled']:
                    self.assertEqual(product['effects'],{})
                    self.assertEqual(product['grants']['items'],{})
                continue
            expected = [row for row in rewards if row['sku'] == source['sku'] and row['enabled'] == '1']
            self.assertEqual(len(product['grants']['lines']), len(expected))
            for reward in expected:
                target, quantity = reward['target_id'], float(reward['amount'])
                if reward['reward_type'] == 'stat':
                    self.assertEqual(product['effects'][target], quantity)
                else:
                    self.assertEqual(product['grants']['items'][target], quantity)
        self.assertEqual(products['video_p001']['purchase_limit'], 0)
        self.assertEqual(products['video_p001']['grants']['items'], {'special_lottery_ticket': 1})

    def test_invalid_prices_never_round_or_compile(self):
        for price in ('0', '-10', '1', '9', '101', '1200.1', 'NaN', 'Infinity', '10000010'):
            with self.subTest(price=price):
                with self.assertRaises(ValueError):
                    ucoin_amount_fen(price)
                self.commerce_tables = copy.deepcopy(self.package['commerce_tables'])
                self.edit_product(price=price, source_current_price=price, source_original_price='')
                with self.assertRaises(ValueError):
                    self.compile()

    def test_reference_price_and_original_price_preference(self):
        self.edit_product(price='6790')
        with self.assertRaisesRegex(ValueError, 'commerce_reference_price_mismatch'):
            self.compile()
        self.edit_product(price='6800', source_current_price='1', source_original_price='6800')
        product = next(row for row in self.compile()['products'] if row['sku'] == 'video_p004')
        self.assertEqual(product['amount'], 680)
        self.edit_product(source_original_price='6900')
        with self.assertRaisesRegex(ValueError, 'commerce_reference_price_mismatch'):
            self.compile()

    def test_unknown_rewards_and_unsupported_ownership_quantity_fail(self):
        def change_reward(records):
            next(row for row in records if row['sku'] == 'video_p004')['target_id'] = 'imaginary_buff'
        self.commerce_tables['commerce_rewards'] = replace_rows(self.commerce_tables['commerce_rewards'], change_reward)
        with self.assertRaises(ValueError):
            self.compile()
        self.commerce_tables = copy.deepcopy(self.package['commerce_tables'])
        self.edit_product(ownership_quantity='2')
        with self.assertRaisesRegex(ValueError, 'ucoin_ownership_quantity_unsupported'):
            self.compile()

    def test_duplicate_sku_and_ownership_marker_fail(self):
        self.edit_product(ownership_id='payment_test_initial_wood_100')
        with self.assertRaises(ValueError):
            self.compile()
        self.commerce_tables = copy.deepcopy(self.package['commerce_tables'])
        self.edit_product(sku='wood_100_test_50_v3')
        def change_sku(records):
            for row in records:
                if row['sku'] == 'video_p004':
                    row['sku'] = 'wood_100_test_50_v3'
        self.commerce_tables['commerce_rewards'] = replace_rows(self.commerce_tables['commerce_rewards'], change_sku)
        with self.assertRaises(ValueError):
            self.compile()


class UcoinPackageTests(unittest.TestCase):
    def setUp(self):
        self.package = build(ROOT)
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        folder = Path(self.temporary.name)
        release, game = folder / 'payment_release', folder / 'game_release'
        hashes = {}
        for name in SOURCES + COMMERCE_SOURCES:
            destination = release / 'reference_csv' / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            raw = (ROOT / 'data/csv' / name).read_bytes().replace(b'\r\n', b'\n')
            destination.write_bytes(raw)
            hashes['data/csv/' + name] = hashlib.sha256(raw).hexdigest()
        bundle_root = game / 'addon/server/bundles'
        (bundle_root / 'test_bundle').mkdir(parents=True)
        (bundle_root / 'current.json').write_text(json.dumps({'hash': 'test_bundle'}), encoding='utf-8')
        self.bundle_path = bundle_root / 'test_bundle/bundle.json'
        self.bundle = {'configs': {'player_gameplay_stats': {'rows': rows(
            self.package_reference(SOURCES[1]))}}, 'csv_hashes': hashes}
        self.bundle_path.write_bytes(canonical(self.bundle))
        # The operator module's real deploy helper is Linux-only. No deployment
        # or database access occurs in these isolated transfer validation tests.
        deploy = types.ModuleType('deploy')
        deploy.connection = mock.Mock(side_effect=AssertionError('database access forbidden'))
        deploy.backup = mock.Mock(side_effect=AssertionError('backup forbidden'))
        deploy.GAME = game
        specification = importlib.util.spec_from_file_location(
            'payment_backend._ucoin_sync_test', ROOT / 'server/payment_backend/sync_catalog.py')
        self.sync = importlib.util.module_from_spec(specification)
        with mock.patch.dict(sys.modules, {'deploy': deploy}):
            specification.loader.exec_module(self.sync)
        self.sync.ROOT = release
        self.path = folder / 'catalog.json'

    def package_reference(self, name):
        return (ROOT / 'data/csv' / name).read_text(encoding='utf-8-sig')

    def validate(self):
        raw = canonical(self.package)
        self.path.write_bytes(raw)
        return self.sync.validate(self.path, hashlib.sha256(raw).hexdigest())

    def test_built_package_recompiles_to_the_same_catalog_and_hash(self):
        self.assertEqual(self.validate(), self.package)
        self.assertEqual(self.package['catalog_hash'], hashlib.sha256(canonical(self.package['catalog'])).hexdigest())
        expected={p['sku'] for p in rows(self.package['commerce_tables']['commerce_products']) if p['currency']=='u_coin'}
        self.assertEqual({p['sku'] for p in self.package['catalog']['products'] if 'u_coin_price' in p},expected)

    def test_transfer_hash_catalog_tampering_and_catalog_hash_are_rejected(self):
        self.path.write_bytes(canonical(self.package))
        with self.assertRaisesRegex(ValueError, 'catalog_transfer_hash_mismatch'):
            self.sync.validate(self.path, '0' * 64)
        product = next(row for row in self.package['catalog']['products'] if row['sku'] == 'video_p004')
        product['amount'] += 1
        with self.assertRaisesRegex(ValueError, 'catalog_recompile_mismatch'):
            self.validate()
        self.package = build(ROOT)
        self.package['catalog_hash'] = '0' * 64
        with self.assertRaisesRegex(ValueError, 'catalog_hash_mismatch'):
            self.validate()

    def test_upload_and_deployed_wallet_sources_must_match(self):
        self.package['commerce_tables']['commerce_products'] = self.package['commerce_tables']['commerce_products'].replace(
            'video_p004,清暑符', 'video_p004,另一个名字')
        with self.assertRaises(ValueError):
            self.validate()
        self.package = build(ROOT)
        self.bundle['csv_hashes']['data/csv/' + COMMERCE_SOURCES[0]] = '0' * 64
        self.bundle_path.write_bytes(canonical(self.bundle))
        with self.assertRaises(ValueError):
            self.validate()


if __name__ == '__main__':
    unittest.main()
