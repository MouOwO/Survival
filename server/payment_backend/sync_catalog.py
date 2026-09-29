"""Authenticated operator CLI only; never exposes catalog mutation on the payment HTTP API."""
import hashlib
import json
import os
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from deploy import connection,backup,GAME
from payment_backend.csv_catalog import SOURCES,canonical,compile_catalog,rows

def validate(path,digest):
    raw=Path(path).read_bytes()
    if len(raw)>2_000_000 or hashlib.sha256(raw).hexdigest()!=digest:raise ValueError('catalog_transfer_hash_mismatch')
    package=json.loads(raw)
    reference={name:(ROOT/'reference_csv'/name).read_text(encoding='utf-8-sig') for name in SOURCES}
    # The archive server deploys most definitions inside an immutable bundle,
    # not as individual CSVs. Entitlements are the explicit v4 capability set.
    bundles=GAME/'addon/server/bundles'
    bundle_hash=json.loads((bundles/'current.json').read_text())['hash']
    bundle=json.loads((bundles/bundle_hash/'bundle.json').read_text())
    for name in SOURCES[1:]:
        if Path(name).stem=='player_gameplay_stats':
            # Payment adds to existing values. New-account defaults are owned by
            # the game service and are intentionally not published by shop sync.
            def rules(values):
                return {r['field_id']:(r['storage_type'],str(r.get('enabled','')).lower() in ('true','1'),
                    float(r['min_value']) if r.get('min_value') not in ('',None) else None,
                    float(r['max_value']) if r.get('max_value') not in ('',None) else None) for r in values}
            if rules(rows(reference[name]))!=rules(bundle['configs']['player_gameplay_stats']['rows']):
                raise ValueError('支付与存档服务属性类型或上下限不同: '+name)
            continue
        raw=(ROOT/'reference_csv'/name).read_bytes().replace(b'\r\n',b'\n')
        if hashlib.sha256(raw).hexdigest()!=bundle['csv_hashes'].get('data/csv/'+name):
            raise ValueError('支付与存档服务基础定义不同，请先同步基础配置: '+name)
    for name,text in reference.items():
        if hashlib.sha256(text.encode()).hexdigest()!=package['reference_hashes'].get(name):
            raise ValueError('客户端与服务端基础定义不同，请先同步基础配置: '+name)
    catalog=compile_catalog(package['tables'],reference)
    if canonical(catalog)!=canonical(package['catalog']):raise ValueError('catalog_recompile_mismatch')
    if hashlib.sha256(canonical(catalog)).hexdigest()!=package['catalog_hash']:raise ValueError('catalog_hash_mismatch')
    return package

def apply(conn,package):
    from psycopg.types.json import Jsonb
    catalog=package['catalog'];conn.execute('SET ROLE goufayu_owner')
    conn.execute("SELECT pg_advisory_xact_lock(hashtext('payments.catalog.publish'))")
    conn.execute('UPDATE payments.products SET enabled=false')
    for p in catalog['products']:
        previous=conn.execute('SELECT item_id FROM payments.products WHERE sku=%s',(p['sku'],)).fetchone()
        if previous and previous[0]!=p['item_id']:raise ValueError('已发布商品的持有标记不能更改: '+p['sku'])
        for field in p['effects']:
            if not conn.execute('SELECT 1 FROM payments.stat_rules WHERE field_id=%s',(field,)).fetchone():raise ValueError('stat_not_deployed:'+field)
        conn.execute('''INSERT INTO payments.products(sku,item_id,title,description,amount,effects,enabled,sort_order,
          grants,category_id,product_type,icon,purchase_limit) VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
          ON CONFLICT(sku) DO UPDATE SET title=excluded.title,description=excluded.description,amount=excluded.amount,
          effects=excluded.effects,enabled=excluded.enabled,sort_order=excluded.sort_order,grants=excluded.grants,
          category_id=excluded.category_id,product_type=excluded.product_type,icon=excluded.icon,purchase_limit=excluded.purchase_limit''',
          (p['sku'],p['item_id'],p['title'],p['description'],p['amount'],Jsonb(p['effects']),p['enabled'],p['sort_order'],
           Jsonb(p['grants']),p['category_id'],p['product_type'],p['icon'],p['purchase_limit']))
    conn.execute('''INSERT INTO payments.catalog_state(singleton,catalog_hash,categories) VALUES(true,%s,%s)
       ON CONFLICT(singleton) DO UPDATE SET catalog_hash=excluded.catalog_hash,categories=excluded.categories,updated_at=now()''',
       (package['catalog_hash'],Jsonb(catalog['categories'])))

def main(action,path,digest):
    if os.geteuid()!=0 or action not in ('check','apply'):raise ValueError('operator_action_required')
    package=validate(path,digest)
    # Dry-run all upserts first; no partially published catalog on a late validation error.
    with connection() as conn:
        try:apply(conn,package)
        finally:conn.rollback()
    if action=='apply':
        backup()
        with connection() as conn:apply(conn,package)
        dest=Path('/etc/goufayu-payment/catalog_history')/package['catalog_hash']
        dest.mkdir(parents=True,exist_ok=True)
        for name,text in package['tables'].items():(dest/(name+'.csv')).write_text(text,encoding='utf-8')
    print(json.dumps({'catalog_hash':package['catalog_hash'],'applied':action=='apply',
        'enabled_products':sum(p['enabled'] for p in package['catalog']['products']),
        'orders_changed':0,'players_reset':0}))

if __name__=='__main__':main(*sys.argv[1:])
