"""Pinned, read-only function/schema compatibility audit; no player values exported."""
from pathlib import Path
import json
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
CODE=r'''
from pathlib import Path
import hashlib,json,sys
pay=Path('/opt/goufayu/payments/current').resolve(strict=True)
archive=Path('/opt/goufayu/releases/current').resolve(strict=True)
assert pay.name=='20261016-shop-functional-v2'
assert hashlib.sha256((pay/'manifest.json').read_bytes()).hexdigest()=='59e0dc9130668f13a07794148224cd217a5a18b2436276f16c126165e787b66e'
assert archive.name=='20261016-vip-recharge-v1'
assert json.loads((archive/'addon/server/bundles/current.json').read_text())['hash']=='ab2db559240bcb08d60bc982152bc869b729496cc2afcb71dabb973149c1f3fb'
manifest=json.loads((pay/'manifest.json').read_bytes())
for name,digest in manifest.items():
 p=Path(name);assert not p.is_absolute() and '..' not in p.parts
 assert not (pay/name).is_symlink() and hashlib.sha256((pay/name).read_bytes()).hexdigest()==digest
sys.path.insert(0,str(pay));from deploy import connection
signatures=['payments.receipt_quantity(jsonb)','payments.validate_order_quantity_snapshot(jsonb,integer)',
 'payments.catalog(text,text)','payments.create_order_quantity(text,text,text,text,text,integer)',
 'payments.deliver(text,text,integer,text,text)','payments.finish_reset(text,text,text,text)',
 'payments.credit_vip_recharge()','payments.product_block(text,text,integer,jsonb,jsonb)',
 'payments.product_block_quantity(text,text,integer,jsonb,jsonb,integer)',
 'payments.max_order_quantity(text,text,integer,jsonb,jsonb,integer)',
 'payments.validate_commerce_bundle(jsonb,jsonb)','payments.apply_effects(text,jsonb,boolean)']
functions={}
with connection() as conn:
 conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY')
 assert conn.execute('SELECT current_database()').fetchone()[0]=='goufayu_test'
 for signature in signatures:
  row=conn.execute('SELECT pg_get_functiondef(oid),pg_get_userbyid(proowner),prosecdef,proacl::text FROM pg_proc WHERE oid=to_regprocedure(%s)',(signature,)).fetchone()
  assert row,'required_function_missing:'+signature
  functions[signature]=dict(definition=row[0],sha256=hashlib.sha256(row[0].encode()).hexdigest(),owner=row[1],security_definer=row[2],acl=row[3])
 constraints=conn.execute("SELECT conname,pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid='payments.orders'::regclass ORDER BY conname").fetchall()
 triggers=conn.execute("SELECT tgname,pg_get_triggerdef(oid) FROM pg_trigger WHERE tgrelid='payments.orders'::regclass AND NOT tgisinternal ORDER BY tgname").fetchall()
 catalog_hash=conn.execute('SELECT catalog_hash FROM payments.catalog_state WHERE singleton').fetchone()[0]
 product_count=conn.execute('SELECT count(*) FROM payments.products').fetchone()[0]
 new_sku_exists=conn.execute("SELECT EXISTS(SELECT 1 FROM payments.products WHERE sku='u_coin_recharge')").fetchone()[0]
 product_hash=conn.execute("SELECT md5(coalesce(jsonb_agg(to_jsonb(p) ORDER BY p.sku)::text,'[]')) FROM payments.products p").fetchone()[0]
 conn.rollback()
print(json.dumps(dict(status='READONLY_SCHEMA_PASS',payment_release=pay.name,archive_release=archive.name,
 manifest_entries_verified=len(manifest),functions=functions,order_constraints=constraints,triggers=triggers,
 catalog_hash=catalog_hash,product_count=product_count,existing_products_md5=product_hash,new_recharge_sku_exists=new_sku_exists,
 private_config_exported=False,player_values_exported=False,database_writes=0,orders_created=0,gateway_requests=0)))
'''


def main():
    options=['-T','-F','none','-o','BatchMode=yes','-o','StrictHostKeyChecking=yes',
        '-o','UserKnownHostsFile=tools/deploy/goufayu_test_known_hosts','-o','IdentitiesOnly=yes',
        '-o','ConnectTimeout=10','-i',str(Path.home()/'.ssh/goufayu_ecs_ed25519_v2')]
    result=subprocess.run(['ssh.exe',*options,'root@47.110.238.248',
        '/opt/goufayu/payments/current/.venv/bin/python -B -'],input=CODE.encode(),capture_output=True,
        cwd=ROOT,timeout=60,creationflags=subprocess.CREATE_NO_WINDOW)
    if result.returncode:
        print(json.dumps(dict(status='READONLY_SCHEMA_FAILED',ssh_exit=result.returncode,private_output_suppressed=True)))
        return result.returncode
    report=json.loads(result.stdout);out=ROOT/'design_refs/ucoin_recharge_20261017/remote'
    out.mkdir(parents=True,exist_ok=True)
    (out/'current_schema.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in report.items() if k not in ('functions','order_constraints','triggers')},ensure_ascii=False))
    return 0


if __name__=='__main__':sys.exit(main())
