"""Recharge quote boundaries; no gateway or database connection."""
from copy import deepcopy
from unittest import TestCase
from unittest.mock import Mock
from . import ucoin_recharge as recharge
from .order_quantity import quantity, snapshot_units
from .service import Payments, ucoin_quote
from .test_payments import FakeDB, order
from .wechat import PaymentError


def recharge_order(count=1):
    result=order();p=recharge.product();grants=deepcopy(p['grants'])
    grants['lines'][0]['quantity']*=count;grants['pricing']['u_coin_price']*=count
    result.update(sku=p['sku'],amount=100*count)
    result['reward']=dict(item_id=p['item_id'],quantity=count,version=6,unit_amount_fen=100,
        product_type='recharge',recharge_u_coin_per_unit=100,purchase_limit=0,effects={},
        unit_pricing=deepcopy(p['grants']['pricing']),grants=grants,title=p['title'])
    return result


class RechargeTests(TestCase):
    def setUp(self):
        self.db=FakeDB();self.wx=Mock()
        self.app=Payments(dict(allowed_accounts=['123'],pepper='p'*32,checkout_key='c'*32),self.db,self.wx)
        self.identity=dict(account_id='123',match_session_id='session_test')

    def test_one_and_maximum_snapshot_and_public_amounts(self):
        for count in (1,2,100,101,999999):
            with self.subTest(count=count):
                stored=recharge_order(count);before=deepcopy(stored)
                self.assertEqual(snapshot_units(stored),(count,100))
                result=self.app.public(stored)
                self.assertEqual(result['amount_fen'],count*100)
                self.assertEqual(result['recharge_u_coin_total'],count*100)
                self.assertEqual(result['product_type'],'recharge')
                self.assertEqual(result['recharge_u_coin_per_unit'],100)
                self.assertEqual(result['max_quantity'],999999)
                self.assertEqual(result['reward_lines'],[dict(kind='wallet',id='u_coin',quantity=count*100,label='U币')])
                self.assertEqual(stored,before)

    def test_only_recharge_accepts_large_request_and_order_amount(self):
        self.assertEqual(quantity(999999,sku=recharge.SKU),999999)
        for invalid in (0,-1,1000000,True,1.5,'1',None):
            with self.subTest(invalid=invalid),self.assertRaises(PaymentError):quantity(invalid,sku=recharge.SKU)
        with self.assertRaises(PaymentError):quantity(101,sku='video_p001')
        with self.assertRaises(PaymentError):ucoin_quote(99999900)
        self.assertEqual(ucoin_quote(99999900,recharge=True)['u_coin_price'],99999900)
        forged=recharge_order(101);forged['sku']='video_p001'
        with self.assertRaises(PaymentError):self.app.public(forged)

    def test_recharge_snapshots_cannot_forge_reward_or_price(self):
        for path,value in [(('amount',),99),(('reward','version'),5),(('reward','product_type'),'single'),
            (('reward','recharge_u_coin_per_unit'),1000),(('reward','grants','recharge_u_coin_per_unit'),1000),
            (('reward','grants','lines',0,'quantity'),1000),(('reward','unit_amount_fen'),1),
            (('reward','effects'),{'initial_wood':1}),(('reward','quantity'),True)]:
            with self.subTest(path=path),self.assertRaises(PaymentError):
                value_order=recharge_order();target=value_order
                for key in path[:-1]:target=target[key]
                target[path[-1]]=value;self.app.public(value_order)

    def test_catalog_preserves_large_maximum_only_for_fixed_sku(self):
        p=recharge.product();row=dict(sku=p['sku'],product_type=p['product_type'],amount_fen=p['amount'],
            recharge_u_coin_per_unit=100,max_quantity=999999,enabled=True)
        self.db.call=lambda name,*args:dict(ok=True,products=[row])
        result=self.app.game('catalog',self.identity)['products'][0]
        self.assertEqual(result['max_quantity'],999999)
        self.assertEqual(result['recharge_u_coin_per_unit'],100)
        row['sku']='video_p001'
        with self.assertRaises(PaymentError):self.app.game('catalog',self.identity)

    def test_client_cannot_supply_reward_price_or_wallet(self):
        for extra in ({'amount_fen':1},{'recharge_u_coin_per_unit':1000},{'balances':{'u_coin':999}},
                      {'product_type':'recharge'}):
            with self.subTest(extra=extra),self.assertRaises(PaymentError):
                self.app.game('create',dict(self.identity,sku=recharge.SKU,quantity=1,**extra))
        self.wx.create.assert_not_called()

    def test_web_checkout_review_message_covers_wallet_and_profile_review(self):
        from .service import JS,PAGE
        self.assertIn('已收到付款，奖励暂未到账，请保留订单号联系处理，请勿重复付款。',JS)
        self.assertNotIn('但账号已拥有该奖励',JS)
        self.assertIn('请适度娱乐，理性消费',PAGE)

    def test_formal_catalog_adds_fixed_recharge_independent_of_item_discount(self):
        from pathlib import Path
        from .csv_catalog import build
        products=build(Path(__file__).resolve().parents[2])['catalog']['products']
        self.assertEqual([p for p in products if p.get('product_type')=='recharge'],[recharge.product()])
        ticket=next(p for p in products if p['sku']=='video_p001')
        self.assertEqual((ticket['amount'],ticket['u_coin_price'],ticket['u_coin_per_yuan']),(600,600,100))
