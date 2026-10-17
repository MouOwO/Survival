"""U-coin order/display regression using the real service and fake gateways."""
from copy import deepcopy
from pathlib import Path
import unittest
from unittest.mock import Mock

from .service import Payments, ucoin_quote
from .test_payments import FakeDB, order
from .wechat import PaymentError


class UCoinServiceTests(unittest.TestCase):
    def setUp(self):
        self.db=FakeDB()
        self.wx=Mock()
        self.app=Payments({'allowed_accounts':['123'],'pepper':'p'*32,
                           'checkout_key':'c'*32},self.db,self.wx)
        self.identity={'account_id':'123','match_session_id':'session_test'}

    def test_catalog_quote_uses_database_price_and_preserves_eligibility(self):
        products=[{'sku':'video_p001','amount_fen':120,'enabled':True,'owned':0},
                  {'sku':'video_p004','amount_fen':680,'enabled':False,
                   'owned':1,'disabled_reason':'already_owned'}]
        original=self.db.call
        self.db.call=lambda name,*args: {'ok':True,'products':products} if name=='catalog' else original(name,*args)
        result=self.app.game('catalog',self.identity)
        self.assertEqual(result['u_coin_per_yuan'],100)
        self.assertEqual([p['u_coin_price'] for p in result['products']],[120,680])
        self.assertFalse(result['products'][1]['enabled'])
        self.assertEqual(result['products'][1]['disabled_reason'],'already_owned')
        self.assertNotIn('u_coin_price',products[0], 'display must not mutate DB snapshots')

    def test_order_quote_is_from_immutable_order_not_current_catalog(self):
        stored=order()
        stored.update(sku='video_p001',amount=120)
        stored['reward']['grants']={'pricing':{'u_coin_price':1200,'u_coin_per_yuan':1000}}
        before=deepcopy(stored)
        result=self.app.public(stored)
        self.assertEqual((result['amount_fen'],result['u_coin_price']),(120,1200))
        self.assertEqual(stored,before)
        # A later product price cannot change the order's original cash amount.
        self.db.row['amount']=680
        self.assertEqual(self.app.public(stored)['amount_fen'],120)

    def test_client_ucoin_amount_or_rate_cannot_override_an_order(self):
        for extra in ({'u_coin_price':1},{'u_coin_per_yuan':1},{'amount_fen':1}):
            with self.subTest(extra=extra),self.assertRaises(PaymentError):
                self.app.game('create',{**self.identity,'sku':'video_p001',**extra})
        self.wx.create.assert_not_called()
        self.assertEqual(self.db.deliveries,0)

    def test_discount_bundle_order_accepts_only_immutable_valid_original_price(self):
        stored=order();stored.update(sku='video_bundle_b002',amount=4768)
        stored['reward']['grants']={'pricing':{'u_coin_price':47680,'u_coin_per_yuan':1000,'original_u_coin_price':59600}}
        before=deepcopy(stored);result=self.app.public(stored)
        self.assertEqual((result['amount_fen'],result['u_coin_price'],result['original_u_coin_price']),(4768,47680,59600))
        self.assertEqual(stored,before)
        for original in (True,47679,59600.5,'59600',100000001):
            with self.subTest(original=original),self.assertRaises(PaymentError):
                invalid=deepcopy(stored);invalid['reward']['grants']['pricing']['original_u_coin_price']=original
                self.app.public(invalid)
        for key,value in [('u_coin_price',59600),('u_coin_per_yuan',100),('client_price',1)]:
            with self.subTest(key=key),self.assertRaises(PaymentError):
                invalid=deepcopy(stored);invalid['reward']['grants']['pricing'][key]=value
                self.app.public(invalid)

    def test_all_formal_sellable_bundle_order_details_use_their_full_snapshot(self):
        from .csv_catalog import build
        package=build(Path(__file__).resolve().parents[2]);products=package['catalog']['products']
        bundles=[p for p in products if p['enabled'] and 'original_u_coin_price' in p]
        from .csv_catalog import rows
        expected={p['sku'] for p in rows(package['commerce_tables']['commerce_products'])
                  if p['currency']=='u_coin' and p['product_type']=='bundle' and p['enabled']=='1'}
        self.assertEqual({p['sku'] for p in bundles},expected)
        for product in bundles:
            with self.subTest(sku=product['sku']):
                stored=order();stored.update(sku=product['sku'],amount=product['amount'])
                stored['reward']=deepcopy(product);before=deepcopy(stored)
                result=self.app.public(stored)
                self.assertEqual(result['u_coin_price'],product['u_coin_price'])
                self.assertEqual(result['original_u_coin_price'],product['original_u_coin_price'])
                self.assertEqual(result['reward_lines'],product['grants']['lines'])
                self.assertEqual(result['effects'],product['effects'])
                self.assertEqual(stored,before)

    def test_invalid_pricing_snapshot_fails_and_old_orders_remain_readable(self):
        stored=order()
        self.assertEqual(self.app.public(stored)['u_coin_price'],50000)
        stored['reward']['grants']={'pricing':{'u_coin_price':1,'u_coin_per_yuan':1000}}
        with self.assertRaises(PaymentError) as error:self.app.public(stored)
        self.assertEqual(error.exception.code,'payment_pricing_mismatch')
        for amount in (0,True,1.5,1000001):
            with self.subTest(amount=amount),self.assertRaises(PaymentError):ucoin_quote(amount)


if __name__=='__main__':unittest.main()
