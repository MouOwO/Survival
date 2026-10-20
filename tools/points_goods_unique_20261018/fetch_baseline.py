"""Read-only pinned release export. No upload, DB writes, service or pointer changes."""
from pathlib import Path
import base64
import contextlib
import difflib
import importlib.util
import io
import json

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'output/points_goods_unique_20261018/release'
spec = importlib.util.spec_from_file_location('points_release_transport', ROOT / 'tools/shop_pricing_half_20261017/remote.py')
transport = importlib.util.module_from_spec(spec)
spec.loader.exec_module(transport)
transport.OUT = OUT / 'remote'

SOURCE = r'''
from pathlib import Path, PurePosixPath
import base64, hashlib, json, sys, urllib.request
archive=Path('/opt/goufayu/releases/current').resolve(strict=True)
payment=Path('/opt/goufayu/payments/current').resolve(strict=True)
assert archive.name=='20261017-monthly-58-v1','archive_baseline_changed'
assert payment.name=='20261018-checkout-gcoin-v1','payment_baseline_changed'
sha=lambda raw:hashlib.sha256(raw).hexdigest()
manifest_raw=(archive/'release_manifest.json').read_bytes()
manifest=json.loads(manifest_raw)
pointer_raw=(archive/'addon/server/bundles/current.json').read_bytes()
pointer=json.loads(pointer_raw)
expected='9d27f6174b24e922d831837ec7a971c3726dc7a95b894c536b191ad5227406fb'
assert pointer['hash']==expected,'archive_bundle_changed'
def public(name,for_export=False):
 p=PurePosixPath(name)
 assert not p.is_absolute() and '..' not in p.parts and '\\' not in name and ':' not in name,'unsafe_manifest_path'
 if for_export:assert not any(word in name.lower() for word in ('.env','.pem','secret','password','private_key','config.json')),'private_release_file_refused'
 source=archive/name
 assert not source.is_symlink(),'release_symlink_refused'
 raw=source.read_bytes()
 assert sha(raw)==manifest['files'][name],'archive_manifest_drift'
 return raw
for name in manifest['files']:public(name)
names=['addon/server/bundles/current.json','addon/server/bundles/'+expected+'/bundle.json',
 'backend/archive_backend/service.py','backend/archive_backend/bundle.py',
 'backend/archive_backend/config_compatibility.py','backend/archive_backend/commerce_catalog.py']
if 'backend/archive_backend/unique_points.py' in manifest['files']:names.append('backend/archive_backend/unique_points.py')
export={name:base64.b64encode(public(name,True)).decode() for name in names}
export['release_manifest.json']=base64.b64encode(manifest_raw).decode()
assert sha(base64.b64decode(export['addon/server/bundles/'+expected+'/bundle.json']))==expected,'bundle_bytes_changed'
sys.path.insert(0,str(payment))
from deploy import connection
functions={}
with connection() as conn:
 conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY')
 assert conn.execute('SELECT current_database()').fetchone()[0]=='goufayu_test','database_scope_changed'
 definition=conn.execute("SELECT pg_get_functiondef('public.archive_sync_config(text,jsonb)'::regprocedure)").fetchone()[0]
 functions['public.archive_sync_config(text,jsonb)']={'definition':definition,'sha256':sha(definition.encode())}
 catalog_hash=conn.execute('SELECT catalog_hash FROM payments.catalog_state WHERE singleton').fetchone()[0]
 configs={row[0]:sha(json.dumps(row[1],ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()) for row in conn.execute('SELECT config_hash,config FROM public.archive_config_sets')}
 conn.rollback()
health={}
for name,port in [('archive',8765),('payments',8766)]:
 with urllib.request.urlopen('http://127.0.0.1:'+str(port)+'/health',timeout=10) as response:
  value=json.load(response);assert response.status==200 and value.get('ok') is True,'unhealthy_service'
  health[name]=True
print(json.dumps(dict(status='READONLY_POINTS_PREFLIGHT_PASS',archive_release=archive.name,payment_release=payment.name,
 archive_bundle=expected,archive_manifest_sha256=sha(manifest_raw),payment_manifest_sha256=sha((payment/'manifest.json').read_bytes()),
 archive_manifest=manifest,functions=functions,export_files=export,catalog_hash=catalog_hash,config_rows=configs,
 health=health,database_writes=0,orders_created=0,gateway_requests=0)))
'''


def main():
    with contextlib.redirect_stdout(io.StringIO()):
        report = transport.execute(SOURCE, 'preflight', timeout=90)
    record = report['records'][0]
    for name, encoded in record['export_files'].items():
        relative = Path(name)
        assert not relative.is_absolute() and '..' not in relative.parts
        target = OUT / 'baseline' / relative
        raw = base64.b64decode(encoded, validate=True)
        if target.exists():
            assert target.read_bytes() == raw, 'immutable_baseline_changed'
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(raw)
    before = (OUT / 'baseline/backend/archive_backend/service.py').read_text('utf-8-sig').splitlines(keepends=True)
    after = (ROOT / 'server/archive_backend/service.py').read_text('utf-8-sig').splitlines(keepends=True)
    (OUT / 'service_vs_local.diff').write_text(''.join(difflib.unified_diff(before, after,
        fromfile='online/backend/archive_backend/service.py', tofile='local/server/archive_backend/service.py')), encoding='utf-8')
    print(json.dumps({key:record[key] for key in ('status','archive_release','payment_release','archive_bundle',
        'archive_manifest_sha256','payment_manifest_sha256','catalog_hash','health','database_writes')}, ensure_ascii=False))


if __name__ == '__main__':
    main()
