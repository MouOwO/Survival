"""One-time v4 upgrade, keeping catalog edits in the separate repeatable sync CLI."""
import hashlib
import json
import os
from pathlib import Path
import sys
import time
import urllib.request
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from deploy import connection,backup,run,health,BASE
from payment_backend.sync_catalog import validate,apply
from payment_backend.upgrade_test_shop import inputs
from payment_backend.test_shop_database import run_checks
from payment_backend.test_bundle_database import run_checks as bundle_checks
from payment_backend.stat_catalog import PRODUCTS

def saved_state(conn):
    queries=("SELECT to_jsonb(o)-'applied_items'-'applied_entitlements' FROM payments.orders o ORDER BY order_id",
             "SELECT to_jsonb(s) FROM public.player_gameplay_stats s ORDER BY player_id",
             "SELECT to_jsonb(a) FROM public.player_archive_state a ORDER BY account_id",
             "SELECT to_jsonb(e) FROM public.archive_entitlements e ORDER BY account_id,entitlement_id")
    return [hashlib.sha256(json.dumps(conn.execute(q).fetchall(),sort_keys=True,default=str).encode()).hexdigest() for q in queries]

def migrate(conn,package):
    conn.execute('SET ROLE goufayu_owner')
    conn.execute((ROOT/'payment_backend/upgrade_csv_shop.sql').read_text())
    apply(conn,package)

def main(action,path,digest):
    if os.geteuid()!=0 or ROOT.parent!=BASE or ROOT.name=='current' or action not in ('validate','activate'):raise ValueError('named_release_required')
    for name,sha in json.loads((ROOT/'manifest.json').read_text()).items():
        if Path(name).is_absolute() or '..' in Path(name).parts or hashlib.sha256((ROOT/name).read_bytes()).hexdigest()!=sha:raise ValueError('release_manifest_mismatch')
    package=validate(path,digest);_,rules=inputs();defaults={k:int(v) if float(v).is_integer() else v for k,v,_,_ in rules}
    with connection() as conn:
        try:
            conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ')
            before=saved_state(conn);migrate(conn,package);assert saved_state(conn)==before
            report=run_checks(conn,defaults,products=PRODUCTS,single_field=True);report.update(bundle_checks(conn))
        finally:conn.rollback()
    print(json.dumps({'validation':report,'existing_rewards_unchanged':True}),flush=True)
    if action=='validate':return
    before_api=health();backup();previous=(BASE/'current').resolve()
    if not (ROOT/'.venv').exists():(ROOT/'.venv').symlink_to(previous/'.venv',target_is_directory=True)
    run(['systemctl','stop','goufayu-payment.service'])
    try:
        with connection() as conn:
            conn.execute("SET lock_timeout='5s'")
            conn.execute('LOCK TABLE public.player_gameplay_stats,public.player_archive_state,public.archive_entitlements,payments.orders IN SHARE ROW EXCLUSIVE MODE')
            before=saved_state(conn);migrate(conn,package);assert saved_state(conn)==before
        link=BASE/'current.next';link.symlink_to(ROOT);os.replace(link,BASE/'current')
    finally:run(['systemctl','start','goufayu-payment.service'])
    for _ in range(20):
        try:
            with urllib.request.urlopen('http://127.0.0.1:8766/health',timeout=2) as r:assert r.status==200
            break
        except Exception:time.sleep(.5)
    else:raise RuntimeError('payment_service_not_ready')
    print(json.dumps({'activated':ROOT.name,'catalog_hash':package['catalog_hash'],'game_api_unchanged':health()==before_api,'real_accounts_reset':0}),flush=True)

if __name__=='__main__':main(*sys.argv[1:])
