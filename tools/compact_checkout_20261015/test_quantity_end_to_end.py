"""Actual HTTP service -> local SQL as payment role -> fake gateway -> SQL reward."""
import copy,hashlib,hmac,json,secrets,sys
from pathlib import Path
from unittest.mock import Mock
ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'server'),str(ROOT/'output/video_shop_20261015/deps')]
import psycopg
from psycopg.types.json import Jsonb
from payment_backend.service import Payments,CALLS
from payment_backend.wechat import PaymentError,APPID,MCHID
DSN='host=127.0.0.1 port=54627 dbname=survival_bundle_test user=postgres'

def connect():
 c=psycopg.connect(DSN,connect_timeout=3)
 assert c.info.host=='127.0.0.1' and c.info.dbname=='survival_bundle_test','disposable local DB only'
 return c
class LocalRPC:
 """Use the real payment SQL permissions without making a NOLOGIN test role LOGIN."""
 def call(self,name,*values):
  assert name in CALLS and len(values)==CALLS[name]
  with connect() as c:
   c.execute('SET LOCAL ROLE goufayu_payment')
   result=c.execute('SELECT payments.'+name+'('+','.join(['%s']*len(values))+')',values).fetchone()[0]
  if isinstance(result,dict) and result.get('error'):raise PaymentError(result['error'],409)
  return result

def run():
 nonce=secrets.token_hex(16);pepper=nonce*2;public='12345678';account=hmac.new(pepper.encode(),public.encode(),hashlib.sha256).hexdigest()
 session='compact_quantity_http_'+nonce;sku='compact_qty_http_'+nonce[:16]
 source=json.loads((ROOT/'output/video_shop_20261015/release/payment_catalog_310_overlay.json').read_bytes())['catalog']['products']
 p=copy.deepcopy(next(p for p in source if p['sku']=='video_p001'));assert p['amount']==120 and p['grants']['items']=={'special_lottery_ticket':1}
 db=LocalRPC();wx=Mock();wx.query.side_effect=PaymentError('ORDER_NOT_EXIST',502);wx.create.return_value='weixin://wxpay/bizpayurl?local-quantity-only'
 app=Payments(dict(allowed_accounts=[public],pepper=pepper,checkout_key=nonce*2),db,wx)
 identity=dict(account_id=public,match_session_id=session);checks={};tx_index=0
 def purchase(q):return app.game('create',dict(identity,sku=sku,quantity=q))
 def saved():
  with connect() as c:return c.execute('SELECT content_inventory FROM public.player_archive_state WHERE account_id=%s',(account,)).fetchone()[0]
 def pay(order):
  nonlocal tx_index
  tx_index+=1
  receipt=dict(out_trade_no=order['order_id'],appid=APPID,mchid=MCHID,trade_state='SUCCESS',trade_type='NATIVE',transaction_id='420000'+str(int(nonce[:20],16))+str(tx_index).zfill(3),amount=dict(total=order['amount_fen'],currency='CNY'))
  app.success(receipt);app.success(receipt)
 try:
  with connect() as c:
   assert c.execute("SELECT to_regprocedure('payments.create_order_quantity(text,text,text,text,text,integer)') IS NOT NULL").fetchone()[0]
   assert not c.execute('SELECT 1 FROM public.survival_players WHERE account_id=%s',(account,)).fetchone()
   defaults=c.execute("SELECT jsonb_object_agg(field_id,default_value) FROM payments.stat_rules").fetchone()[0]
   c.execute('SELECT public.ensure_player_gameplay_stats(%s,%s)',(account,Jsonb(defaults)))
   assert c.execute('SELECT public.match_profile_login(%s,%s,%s,%s)',(account,session,'standard',Jsonb(defaults))).fetchone()[0]['ok']
   c.execute("INSERT INTO public.player_archive_state(account_id,archive,content_inventory) VALUES(%s,'{}','{}')",(account,))
   c.execute("""INSERT INTO payments.products(sku,item_id,title,description,amount,effects,enabled,sort_order,grants,category_id,product_type,icon,purchase_limit)
    VALUES(%s,%s,%s,%s,%s,%s,true,999,%s,%s,%s,%s,%s)""",(sku,p['item_id'],p['title'],p['description'],p['amount'],Jsonb(p['effects']),Jsonb(p['grants']),p['category_id'],p['product_type'],p['icon'],p['purchase_limit']))
  catalog=app.game('catalog',identity);entry=next(p for p in catalog['products'] if p['sku']==sku)
  assert entry['max_quantity']==100 and entry['unit_amount_fen']==120
  five=purchase(5);assert (five['quantity'],five['unit_amount_fen'],five['amount_fen'],five['u_coin_price'])==(5,120,600,6000)
  assert wx.create.call_args.args[0]['amount']==600
  checks['http_quote_and_gateway_total_from_sql']=True
  conflict=purchase(1);assert conflict['warning']=='order_quantity_conflict' and conflict['order_id']==five['order_id'] and conflict['quantity']==5
  assert conflict['qr_matrix']==five['qr_matrix'] and wx.create.call_count==1
  checks['cache_loss_restores_five_and_existing_qr']=True
  again=purchase(5);assert again['order_id']==five['order_id'] and wx.create.call_count==1
  pay(five);inventory=saved();assert inventory['special_lottery_ticket']==5 and inventory[p['item_id']]==5
  checks['real_sql_five_rewards_and_root_units_once']=True
  two=purchase(2);assert two['order_id']!=five['order_id'] and two['amount_fen']==240
  pay(two);inventory=saved();assert inventory['special_lottery_ticket']==7 and inventory[p['item_id']]==7
  checks['new_order_quantity_two_uses_its_own_total_and_grants']=True
  four=purchase(4);assert app.game('cancel',dict(identity,order_id=four['order_id']))['state']=='closed'
  one=purchase(1);assert one['order_id']!=four['order_id'] and one['amount_fen']==120
  checks['cancel_then_new_quantity_is_safe']=True
  with connect() as c:
   assert c.execute('SELECT count(*) FROM payments.vip_recharge_credits WHERE account_id=%s',(account,)).fetchone()[0]==2
  checks['repeated_callbacks_credit_recharge_once_per_paid_order']=True
  return dict(status='PASS',checks=checks,scope='actual_Payments_service_real_local_SQL_as_payment_role_fake_wechat_gateway',connection_adapter='postgres connection SET LOCAL ROLE goufayu_payment; existing test role remains NOLOGIN',external_gateway_requests=0,fixture_cleanup=True)
 finally:
  with connect() as c:
   for table in ('payments.vip_recharge_credits','payments.orders','payments.test_resets','payments.test_accounts','public.match_profile_sessions','public.archive_entitlements','public.player_archive_state'):
    c.execute('DELETE FROM '+table+' WHERE account_id=%s',(account,))
   c.execute('DELETE FROM public.player_gameplay_stats WHERE player_id=%s',(account,));c.execute('DELETE FROM public.survival_players WHERE account_id=%s',(account,))
   c.execute('DELETE FROM payments.products WHERE sku=%s',(sku,))

if __name__=='__main__':
 report=run();folder=ROOT/'output/compact_checkout_20261015';folder.mkdir(parents=True,exist_ok=True)
 (folder/'http_sql_end_to_end_validation.json').write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps(report))
