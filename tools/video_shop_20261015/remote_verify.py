"""Post-publish read-only checks; never creates a session, order or payment."""
from pathlib import Path
import hashlib,hmac,json,sys,urllib.request
PAY=Path('/opt/goufayu/payments/20261015-payment01');sys.path.insert(0,str(PAY))
from deploy import connection
bundle_hash='dee53fe2e9fb8d1bc97ba6b822a86896e97e94b6bad84501fad5791920c3ca26'
catalog_hash='b56e72aaf6b1cd512ada1f5fe460be98a2f871e7d5dc1b7131701fb4654f4cbe'
assert Path('/opt/goufayu/releases/current').resolve().name=='20261015-video-bundles-v1'
assert Path('/opt/goufayu/payments/current').resolve()==PAY
cfg=json.loads(Path('/etc/goufayu-payment/config.json').read_text())
expected=json.loads(Path('/tmp/goufayu-video-shop-20261015-8c453ceeb046/payment_catalog_310_overlay.json').read_text())['catalog']['products']
expected={p['sku']:p for p in expected if p['sku'].startswith('video_bundle_')}
assert len(expected)==15
with connection() as c:
 c.execute('SET TRANSACTION READ ONLY')
 meta=c.execute('SELECT catalog_hash FROM payments.catalog_state WHERE singleton').fetchone()[0];assert meta==catalog_hash
 rows=c.execute("SELECT sku,amount,enabled,grants FROM payments.products WHERE sku LIKE 'video_bundle_%' ORDER BY sku").fetchall()
 assert len(rows)==15
 products=[]
 for sku,amount,enabled,grants in rows:
  p=expected[sku];assert amount==p['amount'] and enabled==p['enabled'] and grants==p['grants']
  products.append({'sku':sku,'u_coin':amount*10,'yuan':format(amount/100,'.2f'),'enabled':enabled,'required_vip_level':grants.get('required_vip_level',0),'members':len(grants.get('lines',[]))})
 assert sum(p['enabled'] for p in products)==13
 session_body=None
 for account in cfg['allowed_accounts']:
  hashed=hmac.new(cfg['pepper'].encode(),str(account).encode(),hashlib.sha256).hexdigest()
  existing=c.execute('SELECT match_session_id FROM public.match_profile_sessions WHERE account_id=%s LIMIT 1',(hashed,)).fetchone()
  if existing:session_body={'account_id':str(account),'match_session_id':existing[0]};break
 c.rollback()
http={'performed':False,'reason':'no_existing_authorized_test_session','created_session':False}
if session_body:
 request=urllib.request.Request('http://127.0.0.1:8766/v1/payments/catalog',data=json.dumps(session_body).encode(),headers={'Content-Type':'application/json','Authorization':'Bearer '+cfg['game_token']},method='POST')
 with urllib.request.urlopen(request,timeout=15) as response:catalog=json.load(response)
 assert catalog['ok'] and catalog['catalog_hash']==catalog_hash and catalog['u_coin_per_yuan']==1000
 visible={p['sku']:p for p in catalog['products'] if p['sku'].startswith('video_bundle_')}
 assert len(visible)==13
 for sku,p in visible.items():
  wanted=expected[sku];assert p['amount_fen']==wanted['amount'] and p['u_coin_price']==wanted['amount']*10
  assert p['reward_lines']==wanted['grants']['lines'] and (p.get('required_vip_level') or 0)==wanted['grants'].get('required_vip_level',0)
  assert p['original_u_coin_price']==wanted['grants']['pricing']['original_u_coin_price']
 http={'performed':True,'passed':True,'visible_ready_bundles':13,'prices_and_full_contents_match':True,'vip_gate_matches':True,'created_session':False,'used_existing_authorized_test_session':True}
health={}
for name,port in [('archive',8765),('payments',8766)]:
 with urllib.request.urlopen('http://127.0.0.1:'+str(port)+'/health',timeout=5) as response:health[name]=response.status==200 and json.load(response)['ok'] is True
assert all(health.values())
assert json.loads(Path('/opt/goufayu/releases/current/addon/server/bundles/current.json').read_text())['hash']==bundle_hash
print(json.dumps({'status':'PASS','archive_bundle':bundle_hash,'catalog_hash':catalog_hash,'ready':13,'pending_assets':2,'products':products,'live_http_catalog':http,'health':health,'read_only':True,'gateway_requests':0,'orders_created':0,'game_validation':False}))
