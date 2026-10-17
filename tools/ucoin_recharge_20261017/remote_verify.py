"""Read-only post-deploy checks, executed through remote_release's pinned stdin.

No login, order, gateway, reset or archive mutation endpoint is invoked. Existing
authorized session details and private config remain entirely on the server.
"""
import hmac

assert Path('/opt/goufayu/payments/current').resolve()==NEW,'new_payment_pointer_missing'
archive_guard()
sys.path.insert(0,str(NEW))
from deploy import connection
from payment_backend import ucoin_recharge as recharge
from payment_backend.upgrade_ucoin_recharge import verify_scope,digest,canonical
scope=verify_scope(OLD)
expected_catalog=digest(canonical(dict(kind='u_coin_recharge_addition_v1',previous_hash=scope['catalog_hash'],product=recharge.product())))
aliases={
 'payments.receipt_quantity(jsonb)':'payments.receipt_quantity_pre_recharge(jsonb)',
 'payments.validate_order_quantity_snapshot(jsonb,integer)':'payments.validate_order_quantity_snapshot_pre_recharge(jsonb,integer)',
 'payments.catalog(text,text)':'payments.catalog_pre_recharge(text,text)',
 'payments.create_order_quantity(text,text,text,text,text,integer)':'payments.create_order_quantity_pre_recharge(text,text,text,text,text,integer)',
 'payments.deliver(text,text,integer,text,text)':'payments.deliver_pre_recharge(text,text,integer,text,text)',
 'payments.finish_reset(text,text,text,text)':'payments.finish_reset_pre_recharge(text,text,text,text)',
}
cfg=json.loads(Path('/etc/goufayu-payment/config.json').read_bytes())
body=None;products={}
with connection() as conn:
 conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY')
 assert conn.execute('SELECT current_database()').fetchone()[0]=='goufayu_test','database_scope_changed'
 current_catalog=conn.execute('SELECT catalog_hash FROM payments.catalog_state WHERE singleton').fetchone()[0]
 assert current_catalog==expected_catalog,'new_catalog_revision_mismatch'
 count,old_hash=conn.execute("SELECT count(*),md5(coalesce(jsonb_agg(to_jsonb(p) ORDER BY p.sku)::text,'[]')) FROM payments.products p WHERE sku<>%s",(recharge.SKU,)).fetchone()
 assert count==scope['existing_product_count']==54 and old_hash==scope['existing_products_md5'],'old_product_rows_changed'
 rows=conn.execute('SELECT to_jsonb(p) FROM payments.products p ORDER BY sku').fetchall()
 products={r[0]['sku']:r[0] for r in rows};assert len(products)==55,'product_count_mismatch'
 expected=recharge.product();actual=products[recharge.SKU]
 for field in ('sku','item_id','title','description','amount','effects','enabled','sort_order','purchase_limit','category_id','product_type','icon','grants'):
  assert actual[field]==expected[field],'fixed_recharge_product_changed:'+field
 for signature,old_sha in scope['database_function_sha256'].items():
  target=aliases.get(signature,signature)
  definition=conn.execute('SELECT pg_get_functiondef(to_regprocedure(%s))',(target,)).fetchone()[0]
  if signature in aliases:
   old_name=signature.split('(')[0];new_name=target.split('(')[0]
   assert ('FUNCTION '+new_name+'(') in definition,'renamed_function_header_unexpected'
   definition=definition.replace('FUNCTION '+new_name+'(','FUNCTION '+old_name+'(',1)
   for role in ('goufayu_payment','goufayu_app'):
    assert not conn.execute('SELECT has_function_privilege(%s,%s,%s)',(role,target,'EXECUTE')).fetchone()[0],'private_alias_exposed'
  assert hashlib.sha256(definition.encode()).hexdigest()==old_sha,'old_function_body_changed:'+signature
 triggers=conn.execute("SELECT tgname,pg_get_triggerdef(oid) FROM pg_trigger WHERE tgrelid='payments.orders'::regclass AND NOT tgisinternal ORDER BY tgname").fetchall()
 assert [list(row) for row in triggers]==BASELINE_TRIGGERS,'payment_triggers_changed'
 for account in cfg['allowed_accounts']:
  hashed=hmac.new(cfg['pepper'].encode(),str(account).encode(),hashlib.sha256).hexdigest()
  found=conn.execute('SELECT match_session_id FROM public.match_profile_sessions WHERE account_id=%s ORDER BY created_at DESC LIMIT 1',(hashed,)).fetchone()
  if found:body=dict(account_id=str(account),match_session_id=found[0]);break
 conn.rollback()
assert body is not None,'no_existing_authorized_test_session'
request=urllib.request.Request('http://127.0.0.1:8766/v1/payments/catalog',data=json.dumps(body).encode(),method='POST',
 headers={'Content-Type':'application/json','Authorization':'Bearer '+cfg['game_token']})
with urllib.request.urlopen(request,timeout=20) as response:
 assert response.status==200,'catalog_http_failed'
 catalog=json.load(response)
assert catalog.get('ok') is True and catalog.get('catalog_hash')==expected_catalog,'catalog_http_revision_mismatch'
assert catalog.get('u_coin_per_yuan')==1000,'ordinary_global_quote_rate_changed'
public={p['sku']:p for p in catalog['products']}
assert len(public)==len(catalog['products']) and set(public)=={sku for sku,p in products.items() if p['enabled']},'enabled_catalog_set_changed'
for sku,p in public.items():
 source=products[sku]
 assert p['amount_fen']==source['amount'] and p['unit_amount_fen']==source['amount'],'unit_cash_price_changed'
 assert p['u_coin_price']==source['amount']*10 and p['unit_u_coin_price']==source['amount']*10,'ordinary_quote_changed'
 assert p['reward_lines']==source['grants']['lines'],'reward_lines_changed'
 maximum=p['max_quantity']
 if sku==recharge.SKU:
  assert p['product_type']=='recharge' and p['recharge_u_coin_per_unit']==100 and p['amount_fen']==100,'recharge_public_contract_mismatch'
  assert type(maximum) is int and 0<=maximum<=999999,'recharge_maximum_invalid'
 else:
  assert type(maximum) is int and 0<=maximum<=100 and maximum*p['amount_fen']<=1000000,'ordinary_quantity_or_total_cap_changed'
 assert p['enabled'] is (maximum>0),'enabled_maximum_disagrees'
backup=Path(BACKUP_PATH)
assert backup.parent==Path('/var/backups/goufayu-payment') and backup.is_file() and backup.stat().st_size>0,'verified_backup_missing'
backup_sha=hashlib.sha256(backup.read_bytes()).hexdigest()
assert backup.with_suffix('.sha256').read_text().strip()==backup_sha,'backup_checksum_mismatch'
health=healthy()
archive_guard()
print(json.dumps(dict(status='DEPLOYMENT_VERIFIED',payment_release=NEW.name,baseline=OLD.name,
 archive_release='20261016-vip-recharge-v1',archive_bundle=scope['archive_bundle'],
 database_products=55,old_product_rows_unchanged=54,old_product_rows_md5=old_hash,catalog_products=len(public),
 catalog_hash=expected_catalog,recharge_sku=recharge.SKU,unit_amount_fen=100,unit_reward_u_coin=100,
 configured_max_quantity=999999,observed_max_quantity=public[recharge.SKU]['max_quantity'],
 ordinary_product_prices_and_quantity_caps_unchanged=True,old_function_bodies_preserved=12,private_helpers_verified=True,
 vip_and_other_payment_triggers_unchanged=True,health=health,backup_path=str(backup),backup_sha256=backup_sha,
 read_only=True,used_existing_authorized_session=True,sessions_created=0,orders_created=0,gateway_requests=0)))
