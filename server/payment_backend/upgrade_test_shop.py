"""Validate with rollback, then deploy an explicitly enabled test shop. Never reset a real account here."""
import csv
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import sys
import time
import urllib.request

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from deploy import connection, backup, write, run, health, GAME, CONFIG, BASE
from payment_backend.catalog import definitions
from payment_backend.test_shop_database import run_checks


def inputs():
    bundle_root=GAME/'addon/server/bundles'
    digest=json.loads((bundle_root/'current.json').read_text())['hash']
    bundle=json.loads((bundle_root/digest/'bundle.json').read_text())['configs']
    rules=[]
    with (GAME/'addon/data/csv/玩家档案系统/player_gameplay_stats.csv').open(encoding='utf-8-sig') as stream:
        for row in csv.DictReader(stream):
            if row['field_id'].startswith('#') or row['enabled'] not in ('1','true'):continue
            rules.append((row['field_id'],float(row['default_value']),float(row['min_value']),
                float(row['max_value']) if row['max_value'] else None))
    return definitions(bundle),rules


def migrate(conn, products, rules):
    from psycopg.types.json import Jsonb
    conn.execute('SET ROLE goufayu_owner')
    if conn.execute("SELECT to_regclass('payments.products') IS NOT NULL").fetchone()[0]:
        raise RuntimeError('shop_upgrade_already_applied')
    conn.execute((ROOT/'payment_backend/upgrade_test_shop.sql').read_text())
    for row in rules:
        conn.execute('INSERT INTO payments.stat_rules(field_id,default_value,minimum,maximum) VALUES(%s,%s,%s,%s)',row)
    for index,p in enumerate(products):
        conn.execute('INSERT INTO payments.products(sku,item_id,title,description,amount,effects,enabled,sort_order) VALUES(%s,%s,%s,%s,%s,%s,true,%s)',
            (p['sku'],p['item_id'],p['title'],p['description'],p['amount'],Jsonb(p['effects']),index))
    # Version 1 had exactly these fixed Monkey King effects. Keep the old amount,
    # merchant identity, transaction and grant timestamps; only add reward metadata.
    legacy=products[0]
    conn.execute("UPDATE payments.orders SET reward=reward||%s::jsonb,applied_effects=CASE WHEN state='delivered' THEN %s::jsonb ELSE '{}'::jsonb END WHERE sku='monkey_test_010_v1'",
        (Jsonb({'title':legacy['title'],'description':legacy['description'],'effects':legacy['effects']}),Jsonb(legacy['effects'])))
    source=conn.execute("SELECT pg_get_functiondef('public.fishing_profile_json(text)'::regprocedure)").fetchone()[0]
    # Keep immutable reward receipts and retry tombstones, but exclude cleared
    # grants from the account's derived fishing inventory after refreshdata.
    source,count=re.subn(r'\bfrom\s+(?:public\.)?reward_grants\b',
        'FROM (SELECT rg.* FROM public.reward_grants rg WHERE NOT EXISTS '
        '(SELECT 1 FROM payments.cleared_reward_grants cleared WHERE cleared.grant_id=rg.grant_id)) visible_grants',
        source,flags=re.I)
    if count!=1:raise RuntimeError('fishing_profile_layout_changed')
    conn.execute(source)


def main(action, account=None):
    if os.geteuid()!=0 or ROOT.parent!=BASE or ROOT.name=='current':raise RuntimeError('named_release_root_required')
    if action=='activate':
        for name,digest in json.loads((ROOT/'manifest.json').read_text()).items():
            if Path(name).is_absolute() or '..' in Path(name).parts or hashlib.sha256((ROOT/name).read_bytes()).hexdigest()!=digest:
                raise RuntimeError('release_manifest_mismatch')
    products,rules=inputs(); defaults={k:int(v) if float(v).is_integer() else v for k,v,_,_ in rules}
    with connection() as conn:
        try:
            migrate(conn,products,rules)
            report=run_checks(conn,defaults)
        finally:conn.rollback()
    print(json.dumps({'validation':report}),flush=True)
    if action=='validate':return
    if action!='activate' or not account or not re.fullmatch(r'[1-9][0-9]{0,9}',account):raise RuntimeError('explicit_test_account_required')
    config=json.loads((CONFIG/'config.json').read_text())
    if account not in config['allowed_accounts']:raise RuntimeError('account_not_previously_authorized')
    hashed=hmac.new(config['pepper'].encode(),account.encode(),hashlib.sha256).hexdigest()
    before=health(); backup()
    run(['systemctl','stop','goufayu-payment.service'])
    previous=(BASE/'current').resolve()
    try:
        with connection() as conn:
            migrate(conn,products,rules)
            conn.execute('INSERT INTO payments.test_accounts(account_id,enabled) VALUES(%s,true)',(hashed,))
            conn.execute('UPDATE payments.test_settings SET enabled=true')
        config['test_reset_enabled']=True
        info=(CONFIG/'config.json').stat()
        write(CONFIG/'config.json',json.dumps(config)+'\n',0o640,info.st_gid)
        conf=Path('/etc/nginx/nginx.conf'); old=conf.read_text()
        new=old.replace('(catalog|create|status|wechat/notify)', '(catalog|create|status|reset|wechat/notify)')
        if new==old:raise RuntimeError('expected_payment_routes_missing')
        write(CONFIG/'nginx.before-test-shop.conf',old)
        write(conf,new,0o644)
        try:run(['nginx','-t'])
        except Exception:write(conf,old,0o644);raise
        if not (ROOT/'.venv').exists():(ROOT/'.venv').symlink_to(previous/'.venv',target_is_directory=True)
        link=BASE/'current.next';link.symlink_to(ROOT);os.replace(link,BASE/'current')
        run(['systemctl','start','goufayu-payment.service'])
        for _ in range(20):
            try:
                with urllib.request.urlopen('http://127.0.0.1:8766/health',timeout=2) as response:assert response.status==200
                break
            except Exception:time.sleep(.5)
        else:raise RuntimeError('payment_service_not_ready')
        run(['systemctl','reload','nginx'])
        state_path=Path('/etc/goufayu-payment-https/state.json')
        state=json.loads(state_path.read_text());state['config_sha256']=hashlib.sha256(conf.read_bytes()).hexdigest()
        write(state_path,json.dumps(state)+'\n')
        print(json.dumps({'activated':ROOT.name,'products':5,'amount_fen':5000,'reset_test_account':account,
            'game_api_unchanged':health()==before,'real_accounts_reset':0,'orders_created':0}),flush=True)
    except Exception:
        # Additive schema remains for diagnosis. Do not restore a database over
        # live receipts or silently run an incompatible old service.
        print(json.dumps({'activation_failed':True,'previous_release':str(previous)}),flush=True)
        raise


if __name__=='__main__':main(*sys.argv[1:])
