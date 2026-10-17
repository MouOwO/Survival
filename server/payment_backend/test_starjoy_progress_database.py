"""Real PostgreSQL starjoy payment checks. Import never connects; caller must roll back."""
import hashlib,secrets

def run_checks(conn, catalog=None):
 from psycopg.types.json import Jsonb
 assert not conn.autocommit and conn.info.transaction_status.name=='INTRANS'
 nonce=secrets.token_hex(16); session='starjoy_local_'+nonce;checks=[]
 defaults=conn.execute('SELECT jsonb_object_agg(field_id,default_value) FROM payments.stat_rules').fetchone()[0]
 provider=conn.execute("SELECT appid,mchid FROM payments.providers WHERE provider='wechat' AND enabled").fetchone();assert provider
 # With no supplied fixture catalog, clone only the live server-owned formal
 # products inside the rollback transaction; never trust caller reward JSON.
 formal=catalog or {'products':[r[0] for r in conn.execute("SELECT to_jsonb(p) FROM payments.products p WHERE sku IN ('video_p004','video_p011') ORDER BY sku")]}
 actual_skus={}
 for p in formal['products']:
  if p['sku'] not in ('video_p004','video_p011'):continue
  sku='audit_'+p['sku']+'_'+nonce[:12];actual_skus[p['sku']]=sku
  conn.execute("INSERT INTO payments.products(sku,item_id,title,description,amount,effects,enabled,sort_order,grants,category_id,product_type,icon,purchase_limit) VALUES(%s,%s,%s,%s,%s,%s,true,999,%s,%s,%s,%s,%s)",
   (sku,'audit_marker_'+p['sku']+'_'+nonce[:12],p['title'],p['description'],p['amount'],Jsonb(p['effects']),Jsonb(p['grants']),p['category_id'],p['product_type'],p['icon'],p['purchase_limit']))
 assert set(actual_skus)=={'video_p004','video_p011'},'formal_starjoy_products_missing'
 # These nonce products copy the full actual formal snapshot; no real SKU or catalog pointer is changed.
 def digest(s):return hashlib.sha256(('starjoy:'+nonce+':'+s).encode()).hexdigest()
 def call(fn,*args):return conn.execute('SELECT payments.'+fn+'('+','.join(['%s']*len(args))+')',args).fetchone()[0]
 def buyer(label,points=0,earned=1000):
  a=digest(label);conn.execute('SELECT public.ensure_player_gameplay_stats(%s,%s::jsonb)',(a,Jsonb(defaults)))
  assert conn.execute('SELECT public.match_profile_login(%s,%s,%s,%s::jsonb)',(a,session,'standard',Jsonb(defaults))).fetchone()[0]['ok']
  conn.execute("INSERT INTO public.player_archive_state(account_id,archive,content_inventory) VALUES(%s,'{}','{}')",(a,))
  conn.execute('UPDATE public.player_gameplay_stats SET starjoy_points=%s,starjoy_points_earned=%s,starjoy_reward_level=5 WHERE player_id=%s',(points,earned,a));return a
 def state(a):return conn.execute('SELECT starjoy_points,starjoy_points_earned,starjoy_reward_level,initial_wood FROM public.player_gameplay_stats WHERE player_id=%s',(a,)).fetchone()
 # Fails before repair: balance+68, but earned was incorrectly left at1000.
 a=buyer('spent');applied=call('apply_effects',a,Jsonb({'starjoy_points':68}),False)
 assert state(a)[:3]==(68,1068,5),('spent_progress_lost',state(a))
 assert applied=={'starjoy_points':68,'starjoy_points_earned':68};checks.append('spent balance preserves and increases cumulative earned')
 # New receipt records derived deltas; same receipt removal never generates credit.
 call('apply_effects',a,Jsonb(applied),True);assert state(a)[:3]==(0,1000,5);checks.append('exact applied receipt reversal does not double-credit')
 a=buyer('legacy',points=500,earned=0);applied=call('apply_effects',a,Jsonb({'starjoy_points':68}),False)
 assert state(a)[:2]==(568,568);assert applied['starjoy_points_earned']==568
 call('apply_effects',a,Jsonb(applied),True);assert state(a)[:2]==(500,0);checks.append('legacy balance normalization is receipt-aware and reversible')
 a=buyer('explicit');call('apply_effects',a,Jsonb({'starjoy_points':68,'starjoy_points_earned':68}),False)
 assert state(a)[:2]==(68,1068);checks.append('explicit earned delta is never derived twice')
 a=buyer('old_receipt',points=100);call('apply_effects',a,Jsonb({'starjoy_points':68}),True)
 assert state(a)[:2]==(32,1000);checks.append('old receipts without earned remain readable and reversible')
 before=state(a);call('apply_effects',a,Jsonb({'initial_wood':100}),False);assert state(a)[0:3]==before[0:3] and state(a)[3]==before[3]+100;checks.append('non-starjoy effects unchanged')
 a=buyer('two_orders');orders=[]
 for i,sku in enumerate(['video_p004','video_p011']):
  o=call('create_order_quantity',a,session,'WX'+digest('order'+str(i))[:30],actual_skus[sku],'wechat',1);assert 'error' not in o,o
  tx='420000'+str(int(digest('tx'+str(i))[:28],16)).zfill(34)
  delivered=call('deliver',o['order_id'],tx,o['amount'],*provider);assert delivered['state']=='delivered',delivered
  assert delivered['applied_effects']['starjoy_points_earned']==68
  assert delivered['effect_changes']['starjoy_points_earned']['delta']==68
  again=call('deliver',o['order_id'],tx,o['amount'],*provider);assert again['state']=='delivered'
  assert state(a)[:2]==(68*(i+1),1000+68*(i+1));orders.append(o)
 checks.append('two formal product deliveries accumulate and repeated callback grants once')
 # A synthetic repeatable SKU uses the real catalog reward snapshot and quantity scaler.
 sku='audit_starjoy_'+nonce[:16];marker='audit_owned_'+nonce[:16]
 conn.execute("INSERT INTO payments.products(sku,item_id,title,description,amount,effects,enabled,sort_order,purchase_limit,category_id,product_type,icon,grants) SELECT %s,%s,title,description,amount,effects,true,999,0,category_id,product_type,icon,grants FROM payments.products WHERE sku=%s",(sku,marker,actual_skus['video_p004']))
 a=buyer('quantity');o=call('create_order_quantity',a,session,'WX'+digest('quantity_order')[:30],sku,'wechat',5);assert 'error' not in o,o
 tx='420000'+str(int(digest('quantity_tx')[:28],16)).zfill(34);d=call('deliver',o['order_id'],tx,o['amount'],*provider);assert d['state']=='delivered',d
 assert state(a)[:2]==(340,1340);assert d['applied_effects']['starjoy_points_earned']==340
 checks.append('quantity5 price-scaled receipt awards points and earned times5')
 # Existing reset path uses its recorded applied_effects and is itself idempotent.
 conn.execute('UPDATE payments.test_settings SET enabled=true');conn.execute('INSERT INTO payments.test_accounts(account_id,enabled) VALUES(%s,true)',(a,))
 token='starjoy_reset_'+nonce[:16];assert call('begin_reset',a,session,'refreshmoney',token)['ok']
 reset=call('finish_reset',a,session,'refreshmoney',token);assert reset['ok'],reset
 assert state(a)[:2]==(0,1000),state(a)
 again=call('finish_reset',a,session,'refreshmoney',token);assert again['completed'];assert state(a)[:2]==(0,1000)
 late=call('deliver',o['order_id'],tx,o['amount'],*provider);assert late['state']=='delivered';assert state(a)[:2]==(0,1000)
 checks.append('real test reset reverses earned once and late callback cannot regrant')
 # Generic helper remains private; direct client role cannot mint arbitrary fields.
 assert not conn.execute("SELECT has_function_privilege('goufayu_payment','payments.apply_effects(text,jsonb,boolean)','EXECUTE')").fetchone()[0]
 checks.append('payment role has no generic mutation privilege')
 return {'status':'PASS','checks':checks,'cases':len(checks)}
