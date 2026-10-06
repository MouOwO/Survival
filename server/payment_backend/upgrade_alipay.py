"""Validate, back up and activate Alipay without restarting the game backend."""
import hashlib
import json
import os
from pathlib import Path
import pwd
import re
import secrets
import sys
import time
import urllib.request

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from deploy import connection,backup,write,run,health,BASE,CONFIG
from payment_backend.alipay import Alipay
from payment_backend.wechat import PaymentError
from payment_backend.upgrade_test_shop import inputs
from payment_backend.test_alipay_database import run_checks
from payment_backend.test_ticket_database import run_checks as ticket_checks

def saved_state(conn):
    queries=("SELECT to_jsonb(o)-'provider' FROM payments.orders o ORDER BY order_id",
        "SELECT to_jsonb(s) FROM public.player_gameplay_stats s ORDER BY player_id",
        "SELECT to_jsonb(a) FROM public.player_archive_state a ORDER BY account_id",
        "SELECT to_jsonb(e) FROM public.archive_entitlements e ORDER BY account_id,entitlement_id",
        "SELECT to_jsonb(p) FROM payments.products p ORDER BY sku",
        "SELECT to_jsonb(c) FROM payments.catalog_state c")
    return [hashlib.sha256(json.dumps(conn.execute(q).fetchall(),sort_keys=True,default=str).encode()).hexdigest() for q in queries]

def migrate(conn,seller):
    conn.execute('SET ROLE goufayu_owner')
    if conn.execute("SELECT to_regclass('payments.providers') IS NOT NULL").fetchone()[0]:
        rows=conn.execute('SELECT provider,appid,mchid,enabled FROM payments.providers ORDER BY provider').fetchall()
        if rows!=[('alipay','2021007102660118',seller,True),('wechat','wx164e25a570fb636a','1117928493',True)]:
            raise RuntimeError('provider_configuration_mismatch')
    else:
        conn.execute("SELECT set_config('payments.alipay_seller',%s,true)",(seller,))
        conn.execute((ROOT/'payment_backend/upgrade_alipay.sql').read_text())
    conn.execute((ROOT/'payment_backend/upgrade_alipay_qr.sql').read_text())

def nginx_config(original):
    if '# Managed by survival/server/aliyun/deploy/payment_https.py' not in original:raise RuntimeError('unmanaged_nginx_refused')
    # The placeholder contains JSON braces, so match its exact managed block.
    placeholder='''        location = /v1/payments/alipay/notify {
            default_type application/json;
            return 503 '{"status":"payment_not_ready"}';
        }
'''
    value=original.replace(placeholder,'')
    if 'location = /v1/payments/alipay/notify' in value:raise RuntimeError('unexpected_alipay_placeholder')
    value=value.replace('(catalog|create|status|reset|wechat/notify)', '(catalog|create|status|cancel|reset|wechat/notify|alipay/notify)')
    value=value.replace('(?:status|qr)', '(?:status|qr|alipay|return)')
    if 'location = /alipay-redirect.js' not in value:
        value=value.replace('        location / { return 404; }', '''        location = /alipay-redirect.js {
            proxy_pass http://127.0.0.1:8766;
            proxy_set_header Host pay.xiaofengnet.com;
            proxy_read_timeout 10s;
        }
        location / { return 404; }''')
    if 'cancel|reset|wechat/notify|alipay/notify' not in value or 'status|qr|alipay|return' not in value:
        raise RuntimeError('payment_routes_missing')
    return value

def ready():
    for _ in range(20):
        try:
            with urllib.request.urlopen('http://127.0.0.1:8766/health',timeout=2) as response:
                if response.status==200:return
        except Exception:time.sleep(.5)
    raise RuntimeError('payment_service_not_ready')

def main(action,seller):
    if os.geteuid()!=0 or ROOT.parent!=BASE or ROOT.name=='current' or action not in ('validate','activate'):raise ValueError('named_release_required')
    if not re.fullmatch(r'2088[0-9]{12}',seller):raise ValueError('seller_pid_required')
    for name,digest in json.loads((ROOT/'manifest.json').read_text()).items():
        if Path(name).is_absolute() or '..' in Path(name).parts or hashlib.sha256((ROOT/name).read_bytes()).hexdigest()!=digest:
            raise RuntimeError('release_manifest_mismatch')
    gateway=Alipay(CONFIG/'alipay',seller)
    try:gateway.query('CONFIGCHECK'+secrets.token_hex(12))
    except PaymentError as error:
        if error.code!='ACQ.TRADE_NOT_EXIST':raise
    else:raise RuntimeError('unexpected_probe_order')
    _,rules=inputs();defaults={k:int(v) if float(v).is_integer() else v for k,v,_,_ in rules}
    with connection() as conn:
        try:
            conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ')
            before=saved_state(conn);migrate(conn,seller);assert saved_state(conn)==before
            report=run_checks(conn,defaults,seller);report['wechat_ticket_regression']=ticket_checks(conn,defaults)
        finally:conn.rollback()
    print(json.dumps({'validation':report,'existing_orders_rewards_catalog_unchanged':True,'production_signed_query_verified':True}),flush=True)
    nginx=Path('/etc/nginx/nginx.conf');old_nginx=nginx.read_text();new_nginx=nginx_config(old_nginx)
    if action=='validate':return
    before_api=health();backup();previous=(BASE/'current').resolve()
    if not (ROOT/'.venv').exists():(ROOT/'.venv').symlink_to(previous/'.venv',target_is_directory=True)
    config_path=CONFIG/'config.json';old_config=config_path.read_text();config=json.loads(old_config)
    config.update(alipay_enabled=True,alipay_seller_id=seller)
    gid=pwd.getpwnam('goufayu-payment').pw_gid
    write(CONFIG/('config.before-'+ROOT.name+'.json'),old_config)
    write(CONFIG/('nginx.before-'+ROOT.name+'.conf'),old_nginx)
    run(['systemctl','stop','goufayu-payment.service'])
    try:
        with connection() as conn:
            conn.execute("SET lock_timeout='5s'")
            conn.execute('LOCK TABLE public.player_gameplay_stats,public.player_archive_state,public.archive_entitlements,payments.orders IN SHARE ROW EXCLUSIVE MODE')
            before=saved_state(conn);migrate(conn,seller);assert saved_state(conn)==before
        write(config_path,json.dumps(config)+'\n',0o640,gid)
        link=BASE/'current.next';link.symlink_to(ROOT);os.replace(link,BASE/'current')
        run(['systemctl','start','goufayu-payment.service']);ready()
        write(nginx,new_nginx,0o644);run(['nginx','-t']);run(['systemctl','reload','nginx'])
    except Exception:
        write(nginx,old_nginx,0o644);run(['nginx','-t']);run(['systemctl','reload','nginx'])
        write(config_path,old_config,0o640,gid)
        link=BASE/'current.rollback';link.symlink_to(previous);os.replace(link,BASE/'current')
        run(['systemctl','restart','goufayu-payment.service']);ready()
        raise
    state_path=Path('/etc/goufayu-payment-https/state.json');state=json.loads(state_path.read_text())
    state.update(phase='payments_ready',config_sha256=hashlib.sha256(nginx.read_bytes()).hexdigest())
    write(state_path,json.dumps(state)+'\n')
    assert health()==before_api,'game_service_unexpected_restart'
    print(json.dumps({'activated':ROOT.name,'wechat':True,'alipay':True,'game_api_unchanged':True,'real_accounts_reset':0}),flush=True)

if __name__=='__main__':main(*sys.argv[1:])
