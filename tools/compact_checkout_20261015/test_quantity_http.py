"""HTTP quantity/immutable display contract tests; fake gateways, no external requests."""
import copy,hashlib,hmac,json,sys,unittest
from datetime import datetime,timezone,timedelta
from pathlib import Path
from unittest.mock import Mock
ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'server'),str(ROOT/'output/video_shop_20261015/deps')]
from payment_backend.service import Payments
from payment_backend.wechat import PaymentError,APPID,MCHID
from payment_backend.alipay import Alipay
from payment_backend.test_payments import paid

IDENTITY={'account_id':'123','match_session_id':'quantity_local_test'}
ORDER='WX'+'a'*30

def frozen_order():
 return dict(order_id=ORDER,account_id=hmac.new(b'p'*32,b'123',hashlib.sha256).hexdigest(),sku='quantity_fixture',amount=600,currency='CNY',provider='wechat',appid=APPID,mchid=MCHID,state='created',code_url=None,
  expires_at=(datetime.now(timezone.utc)+timedelta(minutes=30)).isoformat(),
  reward=dict(version=5,quantity=5,unit_amount_fen=120,unit_pricing=dict(u_coin_price=1200,u_coin_per_yuan=1000,original_u_coin_price=1500),
   title='数量测试',effects=dict(initial_wood=50),grants=dict(items={'special_lottery_ticket':5},lines=[dict(kind='item',id='special_lottery_ticket',label='特殊抽奖券',quantity=5)],pricing=dict(u_coin_price=6000,u_coin_per_yuan=1000,original_u_coin_price=7500))))

class StubDB:
 def __init__(self):self.row=frozen_order();self.calls=[];self.warning=None;self.deliveries=0;self.catalog=[]
 def call(self,name,*args):
  self.calls.append((name,args))
  if name=='catalog':return dict(ok=True,products=copy.deepcopy(self.catalog))
  if name in ('create_order','create_order_channel','create_order_quantity'):
   result=copy.deepcopy(self.row)
   if self.warning:result['warning']=self.warning
   return result
  if name=='update_gateway':
   if args[1]!='checked':self.row['state']=args[1]
   if args[2]:self.row['code_url']=args[2]
  if name=='deliver':
   if self.row['state']!='delivered':self.deliveries+=1
   self.row['state']='delivered'
  return copy.deepcopy(self.row)

class QuantityHttpTests(unittest.TestCase):
 def setUp(self):
  self.db=StubDB();self.wx=Mock();self.wx.query.side_effect=PaymentError('ORDER_NOT_EXIST',502)
  self.wx.create.return_value='weixin://wxpay/bizpayurl?quantity-test'
  self.app=Payments(dict(allowed_accounts=['123'],pepper='p'*32,checkout_key='c'*32),self.db,self.wx)
  self.body=dict(IDENTITY,sku='quantity_fixture',quantity=5)
 def test_quantity_sent_to_database_and_gateway_gets_frozen_total(self):
  response=self.app.game('create',self.body)
  create=next(args for name,args in self.db.calls if name=='create_order_quantity')
  self.assertEqual(create[-3:],('quantity_fixture','wechat',5))
  self.assertEqual(self.wx.create.call_args.args[0]['amount'],600)
  self.assertEqual(self.wx.create.call_args.args[0]['reward']['grants']['items'],{'special_lottery_ticket':5})
  self.assertEqual((response['quantity'],response['unit_amount_fen'],response['amount_fen']),(5,120,600))
  self.assertEqual((response['unit_u_coin_price'],response['u_coin_price']),(1200,6000))
  self.assertEqual((response['unit_original_u_coin_price'],response['original_u_coin_price']),(1500,7500))
 def test_invalid_count_is_rejected_before_database_and_gateway(self):
  for n in (0,-1,101,1.5,True,False,None,'5',1e100):
   with self.subTest(n=n),self.assertRaises(PaymentError) as e:self.app.game('create',dict(self.body,quantity=n))
   self.assertEqual(e.exception.code,'quantity_invalid')
  self.assertFalse(self.db.calls);self.wx.create.assert_not_called()
 def test_price_effect_unit_and_identity_overrides_remain_rejected(self):
  for key,value in [('unit_amount_fen',1),('amount_fen',1),('unit_u_coin_price',1),('u_coin_price',1),('effects',{'initial_wood':999}),('reward',{}),('max_quantity',100)]:
   with self.subTest(key=key),self.assertRaises(PaymentError):self.app.game('create',dict(self.body,**{key:value}))
  self.assertFalse(self.db.calls);self.wx.create.assert_not_called()
 def test_pending_quantity_conflict_restores_actual_count_and_original_qr(self):
  self.db.row.update(state='pending',code_url='weixin://wxpay/bizpayurl?existing-five');self.db.warning='order_quantity_conflict';before=copy.deepcopy(self.db.row)
  result=self.app.game('create',dict(self.body,quantity=1))
  self.assertTrue(result['ok']);self.assertEqual(result['warning'],'order_quantity_conflict');self.assertEqual(result['quantity'],5)
  self.assertEqual(result['amount_fen'],600);self.assertIn('qr_matrix',result);self.assertEqual(self.db.row,before)
  self.wx.create.assert_not_called();self.wx.query.assert_not_called()
  status=self.app.game('status',dict(IDENTITY,order_id=ORDER));self.assertEqual(status['quantity'],5)
  self.assertEqual(self.app.game('cancel',dict(IDENTITY,order_id=ORDER))['state'],'closed')
 def test_legacy_missing_quantity_recovers_an_existing_five_unit_order(self):
  self.db.row.update(state='pending',code_url='weixin://wxpay/bizpayurl?existing-five')
  body=dict(self.body);body.pop('quantity')
  result=self.app.game('create',body)
  self.assertEqual((result['warning'],result['quantity'],result['amount_fen']),('order_quantity_conflict',5,600))
  self.assertTrue(any(name=='create_order' for name,_ in self.db.calls));self.wx.create.assert_not_called();self.wx.query.assert_not_called()
 def test_created_quantity_conflict_recovers_read_only_without_gateway_creation(self):
  self.db.warning='order_quantity_conflict';before=copy.deepcopy(self.db.row)
  result=self.app.game('create',dict(self.body,quantity=1))
  self.assertEqual(result['state'],'created');self.assertEqual(result['quantity'],5);self.assertEqual(self.db.row,before)
  self.wx.create.assert_not_called();self.wx.query.assert_not_called()
 def test_provider_conflict_uses_existing_provider_without_new_gateway(self):
  self.app.alipay=Mock();self.db.warning='order_provider_conflict';self.db.row.update(state='pending',code_url='weixin://wxpay/bizpayurl?existing-five')
  result=self.app.game('create',dict(self.body,provider='alipay'))
  self.assertEqual(result['provider'],'wechat');self.assertEqual(result['warning'],'order_provider_conflict')
  self.wx.create.assert_not_called();self.app.alipay.precreate.assert_not_called()
 def test_same_quantity_retry_and_gateway_timeout_preserve_exact_total(self):
  self.wx.create.side_effect=[PaymentError('gateway_unavailable',503),'weixin://wxpay/bizpayurl?quantity-test']
  with self.assertRaises(PaymentError):self.app.game('create',self.body)
  result=self.app.game('create',self.body);again=self.app.game('create',self.body)
  self.assertEqual(result['order_id'],again['order_id']);self.assertEqual(self.wx.create.call_count,2)
  for call in self.wx.create.call_args_list:self.assertEqual((call.args[0]['amount'],call.args[0]['reward']['quantity']),(600,5))
 def test_legacy_requests_and_orders_default_to_one(self):
  row=self.db.row;row['amount']=120;row['reward']['version']=4;row['reward'].pop('quantity');row['reward'].pop('unit_amount_fen');row['reward'].pop('unit_pricing');row['reward']['grants']['pricing']=dict(u_coin_price=1200,u_coin_per_yuan=1000)
  body=dict(self.body);body.pop('quantity');result=self.app.game('create',body)
  self.assertEqual((result['quantity'],result['unit_amount_fen'],result['amount_fen']),(1,120,120))
  self.assertTrue(any(name=='create_order' for name,_ in self.db.calls));self.assertFalse(any(name=='create_order_quantity' for name,_ in self.db.calls))
 def test_corrupt_stored_counts_prices_and_discount_pairs_fail_closed(self):
  original=copy.deepcopy(self.db.row)
  for changes in ({'quantity':0},{'quantity':True},{'quantity':'5'},{'quantity':101},{'unit_amount_fen':119},{'unit_amount_fen':None}):
   row=copy.deepcopy(original);row['reward'].update(changes)
   with self.subTest(changes=changes),self.assertRaises(PaymentError):self.app.public(row)
  row=copy.deepcopy(original);row['reward']['unit_pricing']['original_u_coin_price']=1400
  with self.assertRaises(PaymentError):self.app.public(row)
  row=copy.deepcopy(original);row['reward'].pop('unit_pricing')
  with self.assertRaises(PaymentError):self.app.public(row)
  self.assertEqual(self.db.row,original)
 def test_catalog_limits_are_authoritative_and_old_catalog_defaults_safe(self):
  self.db.catalog=[dict(sku='ticket',enabled=True,amount_fen=120,max_quantity=100,unit_amount_fen=120,unit_u_coin_price=1200),dict(sku='vip',enabled=True,amount_fen=192,max_quantity=1),dict(sku='old',enabled=True,amount_fen=10),dict(sku='owned',enabled=False,amount_fen=10,max_quantity=0)]
  result=self.app.game('catalog',IDENTITY)
  self.assertEqual([p['max_quantity'] for p in result['products']],[100,1,1,0])
  self.assertEqual([p['unit_amount_fen'] for p in result['products']],[120,192,10,10])
  self.assertEqual(self.db.catalog[0]['max_quantity'],100)
 def test_wechat_callback_requires_total_amount_and_remains_idempotent(self):
  transaction=paid();transaction['amount']['total']=120
  with self.assertRaises(PaymentError):self.app.success(transaction)
  self.assertEqual(self.db.deliveries,0)
  transaction['amount']['total']=600;self.app.success(transaction);self.app.success(transaction)
  self.assertEqual(self.db.deliveries,1)
 def test_alipay_validation_requires_total_not_unit(self):
  gateway=object.__new__(Alipay);gateway.app_id='quantity_app';gateway.seller_id='quantity_seller'
  row=copy.deepcopy(self.db.row);row.update(provider='alipay',appid=gateway.app_id,mchid=gateway.seller_id)
  params=dict(app_id=gateway.app_id,seller_id=gateway.seller_id,out_trade_no=ORDER,total_amount='6.00',trade_no='2026101500000000000000000001',trade_status='TRADE_SUCCESS')
  self.assertEqual(gateway.validate(params,row),params['trade_no'])
  params['total_amount']='1.20'
  with self.assertRaises(PaymentError):gateway.validate(params,row)
 def test_conflict_or_status_cannot_read_another_accounts_order(self):
  self.db.row['account_id']='other-account'
  with self.assertRaises(PaymentError):self.app.game('status',dict(IDENTITY,order_id=ORDER))
  self.db.warning='order_quantity_conflict'
  with self.assertRaises(PaymentError):self.app.game('create',self.body)

if __name__=='__main__':
 result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(QuantityHttpTests))
 folder=ROOT/'output/compact_checkout_20261015';folder.mkdir(parents=True,exist_ok=True)
 (folder/'http_quantity_validation.json').write_text(json.dumps(dict(status='PASS' if result.wasSuccessful() else 'FAIL',tests=result.testsRun,errors=len(result.errors),failures=len(result.failures),external_requests=0,scope='actual_http_service_fake_database_and_gateways'),indent=2)+'\n')
 raise SystemExit(not result.wasSuccessful())
