"""Read-only live verification of the single monthly-pass update."""
from pathlib import Path
import hashlib
import hmac
import json
import sys
import urllib.request

stage=Path(STAGE);plan=json.loads((stage/'plan.json').read_bytes())
payment=Path('/opt/goufayu/payments/current').resolve(strict=True)
archive=Path('/opt/goufayu/releases/current').resolve(strict=True)
assert payment.name==plan['payment_release'] and archive.name==plan['archive_release'],'monthly_release_pointer_mismatch'
for root,filename,key in ((payment,'manifest.json',None),(archive,'release_manifest.json','files')):
    manifest=json.loads((root/filename).read_bytes())
    if key:manifest=manifest[key]
    for name,digest in manifest.items():
        assert hashlib.sha256((root/name).read_bytes()).hexdigest()==digest,'monthly_release_manifest_drift'
sys.path.insert(0,str(payment))
from deploy import connection
from payment_backend.service import Payments
config=json.loads(Path('/etc/goufayu-payment/config.json').read_bytes())
app=Payments.__new__(Payments);app.config=config
body=None;orders_checked=0
with connection() as conn:
    conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY')
    assert conn.execute('SELECT catalog_hash FROM payments.catalog_state WHERE singleton').fetchone()[0]==plan['catalog_hash']
    product=conn.execute("SELECT to_jsonb(p) FROM payments.products p WHERE sku='archive_pass_monthly'").fetchone()[0]
    assert product==plan['monthly_product'],'monthly_row_mismatch'
    assert product['amount']==5800 and product['grants']['entitlement_days']['archive_pass']==30
    for signature,digest in plan['baseline_functions'].items():
        definition=conn.execute('SELECT pg_get_functiondef(to_regprocedure(%s))',(signature,)).fetchone()[0]
        assert hashlib.sha256(definition.encode()).hexdigest()==digest,'unrelated_payment_function_changed'
    saved=conn.execute('SELECT config FROM public.archive_config_sets WHERE config_hash=%s',(plan['bundle'],)).fetchone()[0]
    assert saved['configs']['archive_daily_rules']['rows'][0]['price_text']=='58元'
    for raw, in conn.execute('SELECT to_jsonb(o) FROM payments.orders o ORDER BY created_at DESC LIMIT 200'):
        shown=app.public(raw);assert shown['amount_fen']==raw['amount'];orders_checked+=1
    for account in config['allowed_accounts']:
        digest=hmac.new(config['pepper'].encode(),str(account).encode(),hashlib.sha256).hexdigest()
        row=conn.execute('SELECT match_session_id FROM public.match_profile_sessions WHERE account_id=%s ORDER BY created_at DESC LIMIT 1',(digest,)).fetchone()
        if row:body=dict(account_id=str(account),match_session_id=row[0]);break
    conn.rollback()
assert body,'existing_authorized_session_missing'
request=urllib.request.Request('http://127.0.0.1:8766/v1/payments/catalog',data=json.dumps(body).encode(),method='POST',
    headers={'Content-Type':'application/json','Authorization':'Bearer '+config['game_token']})
with urllib.request.urlopen(request,timeout=20) as response:
    catalog=json.load(response);assert response.status==200 and catalog.get('ok') is True
public=next(p for p in catalog['products'] if p['sku']=='archive_pass_monthly')
assert catalog['catalog_hash']==plan['catalog_hash'] and catalog['u_coin_per_yuan']==100
assert public['amount_fen']==public['unit_amount_fen']==public['u_coin_price']==public['unit_u_coin_price']==5800
assert public['u_coin_per_yuan']==100
health={}
for name,port in (('archive',8765),('payments',8766)):
    with urllib.request.urlopen('http://127.0.0.1:'+str(port)+'/health',timeout=5) as response:
        assert response.status==200 and json.load(response).get('ok') is True;health[name]=True
print(json.dumps(dict(status='DEPLOYMENT_VERIFIED',payment_release=payment.name,archive_release=archive.name,
    bundle=plan['bundle'],catalog_hash=plan['catalog_hash'],monthly_amount_fen=5800,monthly_u_coin_price=5800,
    duration_days=30,historical_orders_readable=orders_checked,health=health,read_only=True,orders_created=0,gateway_requests=0)))
