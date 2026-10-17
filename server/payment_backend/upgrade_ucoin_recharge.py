"""Reviewed recharge-only release operator; never invoked by the game/API.

Validation rolls back all DDL and synthetic fixtures. Activation is explicit,
backs up first, retains a version-6-compatible reader after a committed upgrade,
and adds only the fixed recharge product without replaying the workspace catalog.
"""
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from payment_backend import ucoin_recharge as recharge

BASELINE='20261016-shop-functional-v2'
BASELINE_MANIFEST_SHA256='59e0dc9130668f13a07794148224cd217a5a18b2436276f16c126165e787b66e'
CANDIDATE='20261017-payment03'
ARCHIVE_RELEASE='20261016-vip-recharge-v1'
ARCHIVE_BUNDLE='ab2db559240bcb08d60bc982152bc869b729496cc2afcb71dabb973149c1f3fb'
REPLACED=frozenset('payment_backend/'+name for name in ('service.py','order_quantity.py','ucoin_catalog.py','sync_catalog.py'))
ADDED=frozenset({'payment_backend/ucoin_recharge.py','payment_backend/upgrade_ucoin_recharge.sql',
    'payment_backend/upgrade_ucoin_recharge.py','payment_backend/test_ucoin_recharge_database.py',
    'recharge_release.json','UCOIN_RECHARGE_RELEASE.md'})
TABLES=(('public.player_gameplay_stats','player_id'),('public.survival_players','account_id'),
    ('payments.orders','order_id'),('public.player_archive_state','account_id'),
    ('public.archive_entitlements','account_id,entitlement_id'),('payments.vip_recharge_credits','order_id'),
    ('payments.products','sku'),('payments.catalog_state','singleton'),('payments.providers','provider'),
    ('public.match_profile_sessions','account_id,match_session_id'),('payments.test_settings','singleton'),
    ('payments.test_accounts','account_id'),('payments.test_resets','account_id,request_id'),
    ('payments.cleared_reward_grants','grant_id'),('payments.vip_recharge_levels','level'))


def canonical(value):
    return json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':'),default=str).encode()


def digest(data):return hashlib.sha256(data).hexdigest()


def _manifest(directory):
    value=json.loads((directory/'manifest.json').read_text(encoding='utf-8'))
    if not isinstance(value,dict) or not value:raise RuntimeError('recharge_manifest_invalid')
    for name,expected in value.items():
        relative=Path(name);target=directory/relative
        if (not isinstance(expected,str) or len(expected)!=64 or relative.is_absolute() or '..' in relative.parts
            or '\\' in name or name=='manifest.json' or directory.resolve() not in target.resolve().parents
            or any(p.is_symlink() for p in [target,*target.parents] if p!=directory.parent)):
            raise RuntimeError('recharge_manifest_path_invalid')
        if digest(target.read_bytes())!=expected:raise RuntimeError('recharge_manifest_mismatch:'+name)
    return value


def verify_scope(old):
    if old.name!=BASELINE or ROOT.name!=CANDIDATE:raise RuntimeError('recharge_baseline_not_reviewed')
    if digest((old/'manifest.json').read_bytes())!=BASELINE_MANIFEST_SHA256:
        raise RuntimeError('recharge_baseline_manifest_changed')
    before,after=_manifest(old),_manifest(ROOT)
    changed={name for name in before if after.get(name)!=before[name]}
    if changed!=REPLACED or set(after)-set(before)!=ADDED or set(before)-set(after):
        raise RuntimeError('recharge_release_scope_changed')
    scope=json.loads((ROOT/'recharge_release.json').read_text(encoding='utf-8'))
    if (scope.get('baseline_release')!=BASELINE or scope.get('baseline_manifest_sha256')!=BASELINE_MANIFEST_SHA256
        or scope.get('product')!=recharge.product() or scope.get('archive_release')!=ARCHIVE_RELEASE
        or scope.get('archive_bundle')!=ARCHIVE_BUNDLE):raise RuntimeError('recharge_product_scope_changed')
    return scope


def verify_archive_baseline(release):
    from deploy import GAME
    archive=GAME.resolve(strict=True)
    if archive.name!=ARCHIVE_RELEASE or json.loads((archive/'addon/server/bundles/current.json').read_bytes()).get('hash')!=ARCHIVE_BUNDLE:
        raise RuntimeError('recharge_archive_changed_since_review')


def verify_database_baseline(conn,expected_functions,expected_database='goufayu_test'):
    if conn.execute('SELECT current_database()').fetchone()[0]!=expected_database:
        raise RuntimeError('recharge_database_scope_changed')
    if not isinstance(expected_functions,dict) or len(expected_functions)!=12:
        raise RuntimeError('recharge_database_review_missing')
    for signature in ('payments.recharge_wallet_balance(text)','payments.receipt_quantity_pre_recharge(jsonb)',
        'payments.catalog_pre_recharge(text,text)','payments.deliver_pre_recharge(text,text,integer,text,text)',
        'payments.finish_reset_pre_recharge(text,text,text,text)'):
        if conn.execute('SELECT to_regprocedure(%s)',(signature,)).fetchone()[0] is not None:
            raise RuntimeError('recharge_database_capability_already_present')
    for signature,expected in expected_functions.items():
        definition=conn.execute('SELECT pg_get_functiondef(to_regprocedure(%s))',(signature,)).fetchone()[0]
        if definition is None or digest(definition.encode())!=expected:
            raise RuntimeError('recharge_database_function_changed:'+signature)


def verify_catalog_baseline(conn,scope):
    state=conn.execute('SELECT catalog_hash FROM payments.catalog_state WHERE singleton').fetchone()
    products=conn.execute("SELECT count(*),md5(coalesce(jsonb_agg(to_jsonb(p) ORDER BY p.sku)::text,'[]')) FROM payments.products p").fetchone()
    if (state is None or state[0]!=scope['catalog_hash'] or products[0]!=scope['existing_product_count']
        or products[1]!=scope['existing_products_md5']):
        raise RuntimeError('recharge_catalog_changed_since_review')


def preserved_state(conn):
    result={}
    for table,order in TABLES:
        h=hashlib.sha256()
        for row in conn.execute('SELECT to_jsonb(t)::text FROM '+table+' t ORDER BY '+order):
            data=row[0].encode();h.update(len(data).to_bytes(8,'big'));h.update(data)
        result[table]=h.hexdigest()
    return result


def migrate(conn):
    conn.execute('SET ROLE goufayu_owner')
    conn.execute((ROOT/'payment_backend/upgrade_ucoin_recharge.sql').read_text(encoding='utf-8'))


def append_product(conn):
    """Only one new SKU; no old prices/products/categories are updated."""
    from psycopg.types.json import Jsonb
    p=recharge.product()
    prior=conn.execute('SELECT to_jsonb(p) FROM payments.products p WHERE sku=%s FOR UPDATE',(p['sku'],)).fetchone()
    fields=('sku','item_id','title','description','amount','effects','enabled','sort_order','grants','category_id','product_type','icon','purchase_limit')
    if prior:
        if any(prior[0].get(k)!=p[k] for k in fields):raise RuntimeError('recharge_existing_product_conflict')
        return {'added':False,'sku':p['sku']}
    current=conn.execute('SELECT catalog_hash FROM payments.catalog_state WHERE singleton FOR UPDATE').fetchone()
    if not current:raise RuntimeError('recharge_catalog_state_missing')
    new_hash=digest(canonical(dict(kind='u_coin_recharge_addition_v1',previous_hash=current[0],product=p)))
    conn.execute('''INSERT INTO payments.products(sku,item_id,title,description,amount,effects,enabled,sort_order,
     grants,category_id,product_type,icon,purchase_limit) VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)''',
     tuple(Jsonb(p[k]) if k in ('effects','grants') else p[k] for k in fields))
    conn.execute('UPDATE payments.catalog_state SET catalog_hash=%s,updated_at=now() WHERE singleton',(new_hash,))
    return dict(added=True,sku=p['sku'],previous_catalog_hash=current[0],catalog_hash=new_hash)


def verify_addition(conn,before):
    after=preserved_state(conn)
    allowed={'payments.products','payments.catalog_state'}
    if any(before[name]!=after[name] for name in before if name not in allowed):
        raise RuntimeError('recharge_publication_changed_player_or_order_state')
    # Compare all non-recharge rows independently, so a changed old price fails.
    return after


def old_products_hash(conn):
    return digest(canonical([r[0] for r in conn.execute("SELECT to_jsonb(p) FROM payments.products p WHERE sku<>%s ORDER BY sku",(recharge.SKU,))]))


def check_connection(conn,expected_functions=None,expected_database='goufayu_test'):
    from payment_backend.test_ucoin_recharge_database import run_checks
    conn.execute('SET ROLE goufayu_owner');before=preserved_state(conn);old_prices=old_products_hash(conn)
    if expected_functions is not None:verify_database_baseline(conn,expected_functions,expected_database)
    migrate(conn)
    if preserved_state(conn)!=before:raise RuntimeError('recharge_migration_modified_existing_rows')
    conn.execute('SAVEPOINT recharge_synthetic_validation')
    try:checks=run_checks(conn)
    finally:
        conn.execute('ROLLBACK TO SAVEPOINT recharge_synthetic_validation');conn.execute('RELEASE SAVEPOINT recharge_synthetic_validation')
    if preserved_state(conn)!=before:raise RuntimeError('recharge_fixtures_not_fully_rolled_back')
    conn.execute('SAVEPOINT recharge_catalog_validation')
    try:
        added=append_product(conn);verify_addition(conn,before)
        if old_products_hash(conn)!=old_prices:raise RuntimeError('recharge_publication_changed_old_products')
    finally:
        conn.execute('ROLLBACK TO SAVEPOINT recharge_catalog_validation');conn.execute('RELEASE SAVEPOINT recharge_catalog_validation')
    if preserved_state(conn)!=before:raise RuntimeError('recharge_publication_validation_not_rolled_back')
    return dict(checks=checks,existing_state_tables_unchanged=list(before),old_products_unchanged=True,
                new_product=added['sku'],synthetic_validation_rolled_back=True)


def release_module():
    # These deployment helpers import Linux-only pwd/fcntl and protected account
    # settings. They are loaded only by the explicitly invoked operator CLI.
    from payment_backend import upgrade_ucoin_shop
    return upgrade_ucoin_shop


def check_database(release):
    with release.connection() as conn:
        try:
            conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ');conn.execute("SET lock_timeout='5s'")
            scope=json.loads((ROOT/'recharge_release.json').read_bytes())
            verify_catalog_baseline(conn,scope)
            return check_connection(conn,scope['database_function_sha256'])
        finally:conn.rollback()


@contextmanager
def operator_lock(release):
    import fcntl
    path=release.BASE/'.ucoin_recharge_activation.lock'
    fd=os.open(path,os.O_CREAT|os.O_RDWR|os.O_NOFOLLOW,0o600)
    try:
        fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB);yield
    finally:os.close(fd)


def cleanup_link(link):
    if link is not None and link.is_symlink() and link.resolve()==ROOT:link.unlink()


def activate(release,old,expected,report):
    api_pid=release.health();release.backup();release.prepare_environment(old)
    release.verify_release(expected);scope=verify_scope(old);verify_archive_baseline(release)
    link=None;committed=False;commit_attempted=False;stop_attempted=False;publication=None
    try:
        link=release.temporary_link('recharge-next',ROOT)
        stop_attempted=True
        release.run(['systemctl','stop','goufayu-payment.service'])
        with release.connection() as conn:
            conn.execute("SET lock_timeout='5s'");conn.execute('SET ROLE goufayu_owner')
            conn.execute("SELECT pg_advisory_xact_lock(hashtext('payments.order_quantity.publish'))")
            conn.execute("SELECT pg_advisory_xact_lock(hashtext('payments.catalog.publish'))")
            conn.execute('LOCK TABLE '+','.join(name for name,_ in TABLES)+' IN EXCLUSIVE MODE')
            verify_database_baseline(conn,scope['database_function_sha256'])
            verify_catalog_baseline(conn,scope)
            before=preserved_state(conn);old_prices=old_products_hash(conn);migrate(conn)
            if preserved_state(conn)!=before:raise RuntimeError('recharge_activation_modified_existing_rows')
            publication=append_product(conn);verify_addition(conn,before)
            if old_products_hash(conn)!=old_prices:raise RuntimeError('recharge_activation_changed_old_products')
            release.verify_release(expected);verify_scope(old);verify_archive_baseline(release)
            # The server may commit even if its ACK is lost. From this point
            # recovery must conservatively retain the v6-compatible reader.
            commit_attempted=True
        committed=True
        release.verify_release(expected);verify_scope(old);verify_archive_baseline(release)
        os.replace(link,release.BASE/'current')
        if (release.BASE/'current').resolve()!=ROOT:raise RuntimeError('recharge_reader_changed_before_start')
        release.run(['systemctl','start','goufayu-payment.service']);release.wait_healthy()
        if release.health()!=api_pid:raise RuntimeError('game_api_changed_during_recharge_activation')
    except Exception as error:
        recovered=False
        try:
            current=(release.BASE/'current').resolve()
            if current not in (old,ROOT):raise RuntimeError('recharge_recovery_current_changed')
            if commit_attempted and current!=ROOT:
                recovery=release.temporary_link('recharge-reader-recovery',ROOT)
                try:os.replace(recovery,release.BASE/'current')
                finally:cleanup_link(recovery)
            if stop_attempted:release.run(['systemctl','start','goufayu-payment.service']);release.wait_healthy()
            recovered=True
        finally:
            print(json.dumps(dict(activation_failed=True,recharge_committed=committed,commit_attempted=commit_attempted,compatible_reader_recovered=recovered,
                                  sql_downgraded=False)),flush=True)
        if not recovered:raise RuntimeError('recharge_activation_failed_recovery_incomplete') from error
        raise
    finally:cleanup_link(link)
    return dict(activated=ROOT.name,publication=publication,validation=report,old_products_and_player_state_preserved=True,
                game_api_unchanged=True,gateway_orders_created=0,sql_downgraded=False)


def main(action,expected):
    if action not in ('validate','activate'):raise RuntimeError('operator_action_required')
    release=release_module();old=release.verify_release(expected);verify_scope(old)
    with operator_lock(release):
        verify_archive_baseline(release)
        report=check_database(release);release.verify_release(expected);verify_scope(old)
        result=dict(validated=True,validation=report,gateway_orders_created=0)
        if action=='activate':result=activate(release,old,expected,report)
        print(json.dumps(result,ensure_ascii=False))


if __name__=='__main__':main(*sys.argv[1:])
