"""Publish the verified U-coin catalog and switch only the payment service.

Run from a named, hash-checked payment release. Existing account permissions,
receipts, rewards, and the game service are retained. Validation uses synthetic
accounts inside a transaction that is always rolled back.
"""
import hashlib
import json
import os
from pathlib import Path
import secrets
import sys
import time
import urllib.request

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from deploy import BASE, backup, connection, health, run
from payment_backend.sync_catalog import validate, apply
from payment_backend.test_ucoin_database import run_checks


def verify_release(expected):
    if os.geteuid()!=0 or ROOT.parent!=BASE or ROOT.name=='current':
        raise RuntimeError('named_release_action_required')
    current=(BASE/'current').resolve()
    if current!=Path(expected) or current.parent!=BASE:
        raise RuntimeError('payment_release_changed_since_review')
    for name,digest in json.loads((ROOT/'manifest.json').read_text()).items():
        path=ROOT/name
        if Path(name).is_absolute() or '..' in Path(name).parts or path.is_symlink():
            raise RuntimeError('release_manifest_path_invalid')
        if hashlib.sha256(path.read_bytes()).hexdigest()!=digest:
            raise RuntimeError('release_manifest_mismatch')
    return current


def preserved_state(conn):
    # Hash only; never log account data or access tokens.
    queries=("SELECT to_jsonb(o) FROM payments.orders o ORDER BY order_id",
             "SELECT to_jsonb(s) FROM public.player_gameplay_stats s ORDER BY player_id",
             "SELECT to_jsonb(a) FROM public.player_archive_state a ORDER BY account_id",
             "SELECT to_jsonb(e) FROM public.archive_entitlements e ORDER BY account_id,entitlement_id")
    return [hashlib.sha256(json.dumps(conn.execute(query).fetchall(),
                                    sort_keys=True,default=str).encode()).hexdigest() for query in queries]


def check(package):
    with connection() as conn:
        try:
            conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ')
            before=preserved_state(conn)
            apply(conn,package)
            if preserved_state(conn)!=before:
                raise RuntimeError('catalog_update_modified_existing_receipts_or_rewards')
            result=run_checks(conn,package['catalog'])
        finally:conn.rollback()
    return result


def wait_healthy():
    for attempt in range(20):
        try:
            with urllib.request.urlopen('http://127.0.0.1:8766/health',timeout=2) as response:
                if response.status==200:return
        except Exception:
            pass
        time.sleep(.5)
    raise RuntimeError('payment_service_not_ready')


def catalog_snapshot(conn):
    products=conn.execute('SELECT to_jsonb(p) FROM payments.products p ORDER BY sku').fetchall()
    state=conn.execute('SELECT to_jsonb(s) FROM payments.catalog_state s WHERE singleton').fetchone()
    return {'products':[row[0] for row in products], 'state':state[0] if state else None}


def restore_catalog(snapshot, expected_hash, published_skus):
    """Restore this publication only; keep new SKU rows for immutable orders."""
    with connection() as conn:
        conn.execute("SET lock_timeout='5s'")
        conn.execute('SET ROLE goufayu_owner')
        conn.execute("SELECT pg_advisory_xact_lock(hashtext('payments.catalog.publish'))")
        current=conn.execute('SELECT catalog_hash FROM payments.catalog_state WHERE singleton FOR UPDATE').fetchone()
        if not current or current[0]!=expected_hash:
            return False
        old_skus={product['sku'] for product in snapshot['products']}
        for product in snapshot['products']:
            conn.execute('''UPDATE payments.products SET item_id=%s,title=%s,description=%s,amount=%s,
              effects=%s::jsonb,enabled=%s,sort_order=%s,grants=%s::jsonb,category_id=%s,
              product_type=%s,icon=%s,purchase_limit=%s WHERE sku=%s''',
              (product['item_id'],product['title'],product['description'],product['amount'],
               json.dumps(product['effects']),product['enabled'],product['sort_order'],json.dumps(product['grants']),
               product['category_id'],product['product_type'],product['icon'],product['purchase_limit'],product['sku']))
        new_skus=sorted(set(published_skus)-old_skus)
        if new_skus:
            conn.execute('UPDATE payments.products SET enabled=false WHERE sku=ANY(%s)',(new_skus,))
        state=snapshot['state']
        if state:
            conn.execute('''UPDATE payments.catalog_state SET catalog_hash=%s,categories=%s::jsonb,
              updated_at=%s::timestamptz WHERE singleton''',
              (state['catalog_hash'],json.dumps(state['categories']),state['updated_at']))
        else:
            conn.execute('DELETE FROM payments.catalog_state WHERE singleton')
    return True


def temporary_link(prefix, target):
    link=BASE/(prefix+'-'+ROOT.name+'-'+secrets.token_hex(8))
    link.symlink_to(target)
    return link


def restore_code(old):
    current=(BASE/'current').resolve()
    if current not in (ROOT,old):
        return False
    if current==ROOT:
        rollback=temporary_link('ucoin-rollback',old)
        os.replace(rollback,BASE/'current')
    run(['systemctl','restart','goufayu-payment.service'])
    wait_healthy()
    return True


def prepare_environment(old):
    # Never link through "current", which would recurse after activation.
    env=ROOT/'.venv'
    if not env.exists():env.symlink_to(old/'.venv',target_is_directory=True)
    if env.resolve()!=(old/'.venv').resolve():raise RuntimeError('payment_environment_changed')


def write_history(package):
    history=Path('/etc/goufayu-payment/catalog_history')/package['catalog_hash']
    history.mkdir(parents=True,exist_ok=True)
    for name,text in {**package['tables'],**package['commerce_tables']}.items():
        (history/(name+'.csv')).write_text(text,encoding='utf-8')


def main(action,path,digest,expected):
    if action not in ('validate','activate'):raise RuntimeError('operator_action_required')
    old=verify_release(expected)
    package=validate(path,digest)
    report=check(package)
    if action=='validate':
        print(json.dumps({'validated':True,'catalog_hash':package['catalog_hash'],
                          'database':report,'fixture_rolled_back':True}))
        return
    before_api=health()
    backup()
    prepare_environment(old)
    committed=False
    link=None
    try:
        # Complete filesystem preparation before committing the directory.
        write_history(package)
        link=temporary_link('ucoin-next',ROOT)
        with connection() as conn:
            conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ')
            conn.execute("SET lock_timeout='5s'")
            before=preserved_state(conn)
            snapshot=catalog_snapshot(conn)
            apply(conn,package)
            if preserved_state(conn)!=before:
                raise RuntimeError('catalog_update_modified_existing_receipts_or_rewards')
            verify_release(expected)
        committed=True
        # If another operator switched releases after the pre-commit review,
        # use the guarded recovery path instead of replacing their code link.
        verify_release(expected)
        os.replace(link,BASE/'current')
        run(['systemctl','restart','goufayu-payment.service'])
        wait_healthy()
        game_api_unchanged=health()==before_api
    except Exception as error:
        recovery={'activation_failed':True,'catalog_was_committed':committed}
        if committed:
            try:
                recovery['catalog_restored']=restore_catalog(snapshot,package['catalog_hash'],
                    [product['sku'] for product in package['catalog']['products']])
            except Exception:
                recovery['catalog_rollback_failed']=True
            try:
                recovery['code_restored']=restore_code(old)
            except Exception:
                recovery['code_rollback_failed']=True
        print(json.dumps(recovery),flush=True)
        if recovery.get('catalog_rollback_failed') or recovery.get('code_rollback_failed'):
            raise RuntimeError('payment_activation_failed_and_rollback_incomplete') from error
        raise
    finally:
        try:
            if link is not None and link.is_symlink() and link.resolve()==ROOT:
                link.unlink()
        except OSError:
            pass  # A leftover private link must not hide an activation error.
    print(json.dumps({'activated':ROOT.name,'catalog_hash':package['catalog_hash'],
                      'ucoin_products':report['ucoin_skus'],'u_coin_per_yuan':1000,
                      'database':report,'fixture_rolled_back':True,
                      'game_api_unchanged':game_api_unchanged,
                      'existing_orders_and_rewards_preserved':True,
                      'account_permissions_unchanged':True}))


if __name__=='__main__':main(*sys.argv[1:])
