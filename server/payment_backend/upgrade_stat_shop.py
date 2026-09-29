"""Replace displayed products, retain real receipts/rewards, validate with rollback."""
import hashlib
import json
import os
from pathlib import Path
import sys
import time
import urllib.request

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from deploy import connection, backup, run, health, BASE
from payment_backend.stat_catalog import PRODUCTS, definitions
from payment_backend.upgrade_test_shop import inputs
from payment_backend.test_shop_database import run_checks


def migrate(conn):
    from psycopg.types.json import Jsonb
    conn.execute('SET ROLE goufayu_owner')
    if conn.execute("SELECT 1 FROM information_schema.columns WHERE table_schema='payments' AND table_name='orders' AND column_name='effect_changes'").fetchone():
        raise RuntimeError('stat_shop_upgrade_already_applied')
    conn.execute((ROOT/'payment_backend/upgrade_stat_shop.sql').read_text())
    conn.execute('UPDATE payments.products SET enabled=false')
    for index,p in enumerate(definitions()):
        field=next(iter(p['effects']))
        if not conn.execute('SELECT 1 FROM payments.stat_rules WHERE field_id=%s AND maximum IS NULL',(field,)).fetchone():
            raise RuntimeError('unbounded_gameplay_stat_required:'+field)
        conn.execute('INSERT INTO payments.products(sku,item_id,title,description,amount,effects,enabled,sort_order) VALUES(%s,%s,%s,%s,%s,%s,true,%s)',
                     (p['sku'],p['item_id'],p['title'],p['description'],p['amount'],Jsonb(p['effects']),index))


def real_state(conn):
    # Compare every pre-existing receipt/stat/archive byte-for-byte in one migration.
    queries=("SELECT to_jsonb(o)-'effect_changes' FROM payments.orders o ORDER BY order_id",
             "SELECT to_jsonb(s) FROM public.player_gameplay_stats s ORDER BY player_id",
             "SELECT to_jsonb(a) FROM public.player_archive_state a ORDER BY account_id")
    return [hashlib.sha256(json.dumps(conn.execute(q).fetchall(),sort_keys=True,default=str).encode()).hexdigest() for q in queries]


def main(action):
    if action not in ('validate','activate') or os.geteuid()!=0 or ROOT.parent!=BASE or ROOT.name=='current':
        raise RuntimeError('named_release_action_required')
    for name,digest in json.loads((ROOT/'manifest.json').read_text()).items():
        if Path(name).is_absolute() or '..' in Path(name).parts or hashlib.sha256((ROOT/name).read_bytes()).hexdigest()!=digest:
            raise RuntimeError('release_manifest_mismatch')
    _,rules=inputs(); defaults={k:int(v) if float(v).is_integer() else v for k,v,_,_ in rules}
    with connection() as conn:
        try:
            conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ')
            before=real_state(conn);migrate(conn)
            assert real_state(conn)==before,'migration_modified_existing_rewards'
            report=run_checks(conn,defaults,products=PRODUCTS,single_field=True)
        finally:conn.rollback()
    print(json.dumps({'validation':report,'migration_preserves_existing_rewards':True}),flush=True)
    if action=='validate':return
    before_api=health();backup()
    previous=(BASE/'current').resolve()
    if not (ROOT/'.venv').exists():(ROOT/'.venv').symlink_to(previous/'.venv',target_is_directory=True)
    run(['systemctl','stop','goufayu-payment.service'])
    try:
        with connection() as conn:
            # Prevent unrelated profile writes during the brief preservation check.
            conn.execute('SET lock_timeout=\'5s\'')
            conn.execute('LOCK TABLE public.player_gameplay_stats,public.player_archive_state,payments.orders IN SHARE ROW EXCLUSIVE MODE')
            before=real_state(conn);migrate(conn)
            assert real_state(conn)==before,'migration_modified_existing_rewards'
        link=BASE/'current.next';link.symlink_to(ROOT);os.replace(link,BASE/'current')
    finally:
        run(['systemctl','start','goufayu-payment.service'])
    for _ in range(20):
        try:
            with urllib.request.urlopen('http://127.0.0.1:8766/health',timeout=2) as response:assert response.status==200
            break
        except Exception:time.sleep(.5)
    else:raise RuntimeError('payment_service_not_ready')
    print(json.dumps({'activated':ROOT.name,'products':5,'amount_fen':5000,
                      'game_api_unchanged':health()==before_api,'real_accounts_reset':0,'orders_created':0}),flush=True)


if __name__=='__main__':main(*sys.argv[1:])
