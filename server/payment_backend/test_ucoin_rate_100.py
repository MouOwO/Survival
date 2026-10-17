"""Current 100-U quotes and immutable historical receipts; no network or database."""
from copy import deepcopy
from unittest import TestCase
from unittest.mock import Mock

from .service import Payments, ucoin_quote
from .ucoin_catalog import ucoin_amount_fen
from .ucoin_pricing import U_COIN_PER_YUAN
from . import ucoin_recharge as recharge
from .test_payments import FakeDB, order
from .test_ucoin_recharge import recharge_order
from .wechat import PaymentError


def normal_order(rate=100, count=3, original=True):
    result=order();unit=50;factor=rate//100
    pricing=dict(u_coin_price=unit*factor,u_coin_per_yuan=rate)
    if original:pricing['original_u_coin_price']=unit*2*factor
    total=deepcopy(pricing)
    total['u_coin_price']*=count
    if original:total['original_u_coin_price']*=count
    result.update(sku='rate_fixture',amount=unit*count)
    result['reward']=dict(version=5,quantity=count,unit_amount_fen=unit,
        unit_pricing=pricing,grants={'pricing':total},effects={},title='fixture')
    return result


class Rate100Tests(TestCase):
    def setUp(self):
        self.db=FakeDB();self.gateway=Mock()
        self.app=Payments(dict(allowed_accounts=['123'],pepper='p'*32,checkout_key='c'*32),self.db,self.gateway)

    def test_current_rate_and_exact_fen_conversion(self):
        self.assertEqual(U_COIN_PER_YUAN,100)
        for coins in (1,5,50,100,1200,1000000):
            self.assertEqual(ucoin_amount_fen(coins),coins)
            self.assertEqual(ucoin_quote(coins),dict(u_coin_price=coins,u_coin_per_yuan=100))
        for invalid in (0,-1,'0.5','NaN','Infinity',1000001):
            with self.subTest(invalid=invalid),self.assertRaises(ValueError):ucoin_amount_fen(invalid)

    def test_new_catalog_uses_100_and_preserves_db_rows(self):
        product=dict(sku='rate_fixture',amount_fen=50,unit_amount_fen=50,unit_u_coin_price=50,
            enabled=True,max_quantity=100)
        before=deepcopy(product)
        self.db.call=lambda *_:dict(ok=True,products=[product])
        result=self.app.game('catalog',dict(account_id='123',match_session_id='session_test'))
        self.assertEqual(result['u_coin_per_yuan'],100)
        self.assertEqual(result['products'][0]['u_coin_price'],50)
        self.assertEqual(product,before)

    def test_stale_1000_catalog_cannot_silently_become_a_new_quote(self):
        self.db.call=lambda *_:dict(ok=True,products=[dict(sku='rate_fixture',amount_fen=50,
            unit_u_coin_price=500,max_quantity=1)])
        with self.assertRaises(PaymentError):
            self.app.game('catalog',dict(account_id='123',match_session_id='session_test'))

    def test_old_and_new_quantity_orders_keep_their_snapshot_rate(self):
        for rate in (100,1000):
            with self.subTest(rate=rate):
                stored=normal_order(rate);before=deepcopy(stored);shown=self.app.public(stored)
                self.assertEqual((shown['amount_fen'],shown['unit_amount_fen']),(150,50))
                self.assertEqual((shown['u_coin_price'],shown['unit_u_coin_price']),(150*rate//100,50*rate//100))
                self.assertEqual(shown['u_coin_per_yuan'],rate)
                self.assertEqual(shown['original_u_coin_price'],300*rate//100)
                self.assertEqual(stored,before)

    def test_legacy_receipt_without_pricing_keeps_historical_quote(self):
        stored=order();before=deepcopy(stored);shown=self.app.public(stored)
        self.assertEqual(shown['u_coin_per_yuan'],1000)
        self.assertEqual(shown['u_coin_price'],stored['amount']*10)
        self.assertEqual(stored,before)

    def test_unknown_missing_or_mixed_quantity_rates_are_rejected(self):
        for value in (1,10,101,True,'100',100.0,None):
            with self.subTest(value=value),self.assertRaises(PaymentError):
                stored=normal_order();stored['reward']['grants']['pricing']['u_coin_per_yuan']=value
                self.app.public(stored)
        for field in ('u_coin_price','u_coin_per_yuan','original_u_coin_price'):
            with self.subTest(field=field),self.assertRaises(PaymentError):
                stored=normal_order();stored['reward']['unit_pricing'][field]*=10
                self.app.public(stored)

    def test_forged_quantity_quote_without_original_price_is_rejected(self):
        stored=normal_order(original=False)
        stored['reward']['unit_pricing']['u_coin_per_yuan']=1000
        with self.assertRaises(PaymentError):self.app.public(stored)

    def test_both_recharge_snapshot_rates_credit_same_100_per_yuan(self):
        for rate in (100,1000):
            for count in (1,3,999999):
                with self.subTest(rate=rate,count=count):
                    stored=recharge_order(count)
                    stored['reward']['unit_pricing']=dict(u_coin_price=rate,u_coin_per_yuan=rate)
                    stored['reward']['grants']['pricing']=dict(u_coin_price=rate*count,u_coin_per_yuan=rate)
                    before=deepcopy(stored);shown=self.app.public(stored)
                    self.assertEqual(shown['amount_fen'],100*count)
                    self.assertEqual(shown['recharge_u_coin_total'],100*count)
                    self.assertEqual(shown['u_coin_price'],rate*count)
                    self.assertEqual(stored,before)

    def test_recharge_mixed_pricing_or_forged_wallet_reward_is_rejected(self):
        for field,value in (('u_coin_price',1000),('u_coin_per_yuan',1000)):
            with self.subTest(field=field),self.assertRaises(PaymentError):
                stored=recharge_order();stored['reward']['grants']['pricing'][field]=value
                self.app.public(stored)
        for rate in (100,1000):
            with self.subTest(rate=rate),self.assertRaises(PaymentError):
                stored=recharge_order()
                stored['reward']['unit_pricing']=dict(u_coin_price=rate,u_coin_per_yuan=rate)
                stored['reward']['grants']['pricing']=dict(u_coin_price=rate,u_coin_per_yuan=rate)
                stored['reward']['grants']['lines'][0]['quantity']=1000
                self.app.public(stored)

    def test_fixed_recharge_new_price_and_wallet_grant_are_both_100(self):
        product=recharge.product()
        self.assertEqual(product['amount'],100)
        self.assertEqual(product['grants']['pricing'],dict(u_coin_price=100,u_coin_per_yuan=100))
        self.assertEqual(product['grants']['lines'][0]['quantity'],100)
        self.gateway.create.assert_not_called()
