"""Download allowlisted public release sources; no private files or player data."""
from pathlib import Path
import importlib.util

ROOT = Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('vip_audit_transport',Path(__file__).with_name('payment_audit.py'))
mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
mod.OUT=ROOT/'design_refs/vip_recharge_20261016/deployment'
mod.BASELINE_FOLDER='online_baseline'
CODE=r'''
from pathlib import Path
import base64,hashlib,json,sys
sys.dont_write_bytecode=True
archive=Path('/opt/goufayu/releases/current').resolve(strict=True)
payment=Path('/opt/goufayu/payments/current').resolve(strict=True)
assert archive.name=='20261016-shop-functional-v2' and payment.name=='20261016-shop-functional-v2'
manifest=json.loads((archive/'release_manifest.json').read_text())
pointer=json.loads((archive/'addon/server/bundles/current.json').read_text())
digest=pointer['hash'];assert digest=='ab2db559240bcb08d60bc982152bc869b729496cc2afcb71dabb973149c1f3fb'
files={}
names={'release_manifest.json','deploy/manage.py','addon/server/bundles/current.json'}
prefix='addon/server/bundles/'+digest+'/'
for name in manifest['files']:
 if name.startswith('backend/') and name.endswith('.py') or name.startswith(prefix):names.add(name)
for name in sorted(names):
 p=Path(name)
 assert not p.is_absolute() and '..' not in p.parts and p.suffix in ('.py','.json','.lua')
 assert not any(term in name.lower() for term in ['.env','.pem','secret','password','private_key'])
 raw=(archive/name).read_bytes()
 if name in manifest['files']:assert hashlib.sha256(raw).hexdigest()==manifest['files'][name]
 files['archive/'+name]=raw
files['payment/manifest.json']=(payment/'manifest.json').read_bytes()
sys.path.insert(0,str(payment));from deploy import connection
with connection() as c:
 c.execute('SET TRANSACTION READ ONLY')
 row=c.execute("SELECT pg_get_userbyid(proowner),prosecdef,pg_get_functiondef(oid),proacl::text FROM pg_proc WHERE oid='public.archive_endless_leaderboard()'::regprocedure").fetchone()
 privilege=c.execute("SELECT has_table_privilege(%s,'payments.vip_recharge_levels','SELECT')",(row[0],)).fetchone()[0]
 c.rollback()
print(json.dumps({'status':'READONLY_DEPLOYMENT_BASELINE','archive_release':str(archive),'payment_release':str(payment),
 'bundle':digest,'leaderboard_function':{'owner':row[0],'security_definer':row[1],
 'owner_can_select_vip_levels':privilege,'definition':row[2],'acl':row[3]},
 'public_file_count':len(files),'individual_player_rows_read':False,'database_writes':0,
 'public_files':{name:{'sha256':hashlib.sha256(raw).hexdigest(),'base64':base64.b64encode(raw).decode()} for name,raw in files.items()}},ensure_ascii=False))
'''
if __name__=='__main__':mod.remote('online_preflight',CODE)
