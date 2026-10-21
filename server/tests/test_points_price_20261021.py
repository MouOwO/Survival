"""Fixed shop-point prices and a closed Starjoy exchange use the real Lua worker."""
import copy
import json
from pathlib import Path
import sys
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'server'))
sys.path.insert(0,str(Path(__file__).resolve().parent))
import test_archive_backend as base
from archive_backend.commerce_catalog import build_catalog
from payment_backend.csv_catalog import (rows,validate_price_policy,
    FIXED_QUALITY_SHOP_POINTS_POLICY as POLICY,QUALITY_SHOP_POINTS_PRICES as PRICES)


class PointPriceTests(unittest.TestCase):
    setUpClass=classmethod(base.ArchiveTests.setUpClass.__func__)
    setUp=base.ArchiveTests.setUp
    command=base.ArchiveTests.command
    send=base.ArchiveTests.send

    def test_all_86_point_goods_follow_quality_and_preserve_nonpricing_evidence(self):
        products=rows((ROOT/'data/csv/商城兑换系统/commerce_products.csv').read_text(encoding='utf-8-sig'))
        before_path=ROOT/'tmp/points_price_20261021/backend_before/data/csv/商城兑换系统/commerce_products.csv'
        # Source evidence is also checked against the committed authority below;
        # the task's immutable baseline adds a precise no-unrelated-change audit.
        before={p['sku']:p for p in rows(before_path.read_text(encoding='utf-8-sig'))} if before_path.exists() else {}
        compiled=self.bundle.tables['commerce_catalog']
        lottery={r['item_id']:r for r in self.bundle.configs['lottery_item_definitions']['rows']}
        registry=json.loads((ROOT/'data/ui/item_resources.json').read_text(encoding='utf-8-sig'))['items']
        resources={key:item for item in registry for key in [item['id'],*item.get('aliases',[])]}
        point_goods=[p for p in products if p['currency']=='shop_points']
        self.assertEqual(len(point_goods),86)
        for p in products:
            with self.subTest(sku=p['sku']):
                if p['currency']=='shop_points':
                    self.assertEqual(p['product_type'],'single')
                    self.assertEqual(p['price_policy'],POLICY)
                    self.assertEqual(int(p['price']),PRICES[p['point_quality']])
                    self.assertEqual(compiled[p['sku']]['price'],PRICES[p['point_quality']])
                    self.assertEqual(compiled[p['sku']]['price_policy'],POLICY)
                    self.assertNotIn('original_price',compiled[p['sku']])
                    resource=next((resources[key] for key in (p['ownership_id'],p['sku'],p['source_id']) if key in resources),{})
                    quality=lottery.get(p['ownership_id'],{}).get('quality') or resource.get('quality')
                    if p['sku'] in ('video_p147','video_p151'):quality='ur'
                    self.assertEqual(p['point_quality'],quality.lower(),'Pricing quality must match the authoritative item or its shared alias resource')
                if p['sku'] in before:
                    allowed={'price','price_policy'} if p['currency']=='shop_points' else set()
                    for field,value in before[p['sku']].items():
                        if field not in allowed:self.assertEqual(p[field],value,field)
        for sku in ('video_p147','video_p151','video_p103','video_p089'):
            self.assertEqual(compiled[sku]['price'],8000)
        self.assertFalse(compiled['video_p089']['enabled'])
        self.assertEqual(compiled['video_p089']['ownership_quantity'],100)

    def test_each_quality_charges_only_actual_shop_points_at_new_price(self):
        for quality,price in PRICES.items():
            with self.subTest(quality=quality):
                self.setUp()
                product=next(p for p in self.bundle.tables['commerce_catalog'].values()
                    if p.get('point_quality')==quality and p['enabled'] and not p['effects'].get('starjoy_points'))
                self.profile['save']['archive']['commerce']={'balances':{'shop_points':price,'u_coin':123}}
                self.profile['save']['gameplay_stats'].update(starjoy_points=9000,starjoy_points_earned=12000)
                result=self.send('commerce_purchase',sku=product['sku'],request_id='fixedprice_'+quality)
                self.assertTrue(result['ok'],result)
                self.assertEqual(self.profile['save']['archive']['commerce']['balances'],{'shop_points':0,'u_coin':123})
                self.assertEqual(self.profile['save']['gameplay_stats']['starjoy_points'],9000)
                self.assertEqual(self.profile['save']['gameplay_stats']['starjoy_points_earned'],12000)
                self.assertEqual(self.profile['save']['content_inventory'][product['item_id']],1)

    def test_old_balance_cannot_buy_new_price_and_legacy_disabled_pack_stays_paused(self):
        self.profile['save']['archive']['commerce']={'balances':{'shop_points':94}}
        product=next(p for p in self.bundle.tables['commerce_catalog'].values() if p.get('point_quality')=='n' and p['enabled'])
        before=copy.deepcopy(self.profile['save'])
        self.assertEqual(self.send('commerce_purchase',sku=product['sku'],request_id='old_price_94')['error'],'commerce_balance_insufficient')
        self.assertEqual(self.profile['save'],before)
        self.profile['save']['archive']['commerce']['balances']['shop_points']=8000
        before=copy.deepcopy(self.profile['save'])
        self.assertEqual(self.send('commerce_purchase',sku='video_p089',request_id='disabled_100')['error'],'product_unavailable')
        self.assertEqual(self.profile['save'],before)

    def test_starjoy_exchange_is_closed_before_any_grant_or_reconciliation(self):
        self.profile['save']['gameplay_stats'].update(starjoy_points=999999,starjoy_points_earned=999999)
        self.profile['save']['content_inventory']={'lottery_attribute_crystal':8}
        before=copy.deepcopy(self.profile['save'])
        result=self.send('lottery_exchange',pool_id='map',item_id='lottery_attribute_crystal',request_id='closed_exchange')
        self.assertFalse(result['ok']);self.assertEqual(result['error'],'starjoy_exchange_disabled')
        self.assertEqual(self.profile['save'],before)
        self.assertTrue(all(not row['exchange_enabled'] and row['exchange_points']==0
            for row in self.bundle.configs['lottery_item_definitions']['rows']))

    def test_snapshot_shows_lifetime_starjoy_without_rewriting_historical_balance(self):
        self.profile['save']['gameplay_stats'].update(starjoy_points=12,starjoy_points_earned=456)
        before=copy.deepcopy(self.profile['save'])
        result=self.service.settle(self.profile,{'id':'points:preview','kind':'lottery_snapshot'},False)
        self.assertTrue(all(s['starjoy_points']==456 for s in result['snapshots']))
        self.assertEqual(self.profile['save'],before)

    def test_fixed_policy_rejects_other_currencies_bundles_wrong_quality_and_half_prices(self):
        record={'sku':'test_fixed','product_type':'single','currency':'shop_points',
                'point_quality':'n','price_policy':POLICY,'price_baseline':'188'}
        self.assertTrue(validate_price_policy(record,200,'price_baseline'))
        for changes,value,field,scale in (({'currency':'u_coin'},200,'price_baseline',1),
                ({'currency':'shop_gold'},200,'price_baseline',1),
                ({'product_type':'bundle'},200,'price_baseline',1),
                ({'point_quality':'unknown'},200,'price_baseline',1),({},100,'price_baseline',1),
                ({},200,'price_baseline_yuan',100)):
            with self.subTest(changes=changes,value=value):
                with self.assertRaisesRegex(ValueError,'catalog_fixed_quality_points_price_invalid'):
                    validate_price_policy(dict(record,**changes),value,field,scale=scale)
        catalog=build_catalog(ROOT)
        self.assertEqual(catalog,build_catalog(ROOT),'Rebuilding cannot halve the fixed price again')


if __name__=='__main__':unittest.main()
