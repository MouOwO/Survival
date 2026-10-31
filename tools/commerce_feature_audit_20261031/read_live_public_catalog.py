"""Read only WS4 public product configuration, never player/order/auth rows."""
from pathlib import Path
import argparse,hashlib,importlib.util,json

ROOT=Path(__file__).resolve().parents[2]


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    assert not args.output.exists(),'New snapshot required'
    spec=importlib.util.spec_from_file_location('commerce_audit_transport',ROOT/'tools/ws4_catalog_sync_20261031/driver.py')
    driver=importlib.util.module_from_spec(spec);spec.loader.exec_module(driver)
    source=r'''
from pathlib import Path
import hashlib,json,psycopg
with psycopg.connect(host='127.0.0.1',port=15432,dbname='goufayu_ws4',user='postgres',
 password=Path('/etc/goufayu-ws4/admin-password').read_text().strip(),
 options='-c statement_timeout=10000 -c lock_timeout=2000') as conn:
 conn.execute('SET TRANSACTION READ ONLY')
 names=[row[0] for row in conn.execute("SELECT column_name FROM information_schema.columns WHERE table_schema='payments' AND table_name='products'")]
 allowed=['sku','item_id','title','description','effects','enabled','amount','grants','purchase_limit','category_id','product_type','icon']
 assert set(allowed)<=set(names),'public_product_schema_changed'
 rows=conn.execute('SELECT '+','.join(allowed)+' FROM payments.products ORDER BY sku').fetchall()
 products=[dict(zip(allowed,row)) for row in rows]
 catalog=conn.execute('SELECT catalog_hash FROM payments.catalog_state WHERE singleton').fetchone()[0]
 archive=conn.execute("SELECT config_hash,config->'configs'->'commerce_catalog' FROM public.archive_config_sets WHERE config_hash=%s",('d573588b64d2ea6d1431c856d52e0515b5ed471cfdf6af4456ff618d0f568488',)).fetchone()
print(json.dumps(dict(scope='WS4_PUBLIC_PRODUCT_CONFIGURATION_ONLY',read_only=True,
 cash_catalog_hash=catalog,cash_products=products,archive_hash=archive[0],archive_commerce_catalog=archive[1],
 player_or_order_rows_read=False,identity_tokens_read=False),ensure_ascii=False))
'''
    result=driver.remote(source,timeout=50)
    assert result['read_only'] and result['player_or_order_rows_read'] is False and result['identity_tokens_read'] is False
    raw=(json.dumps(result,ensure_ascii=False,indent=2)+'\n').encode()
    args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_bytes(raw)
    print(json.dumps(dict(status='WS4_PUBLIC_PRODUCT_SNAPSHOT_SAVED',cash_products=len(result['cash_products']),
        cash_enabled=sum(row['enabled'] for row in result['cash_products']),sha256=hashlib.sha256(raw).hexdigest())))


if __name__=='__main__':main()
