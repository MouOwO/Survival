"""Download only public release sources and catalog metadata; no player data.

Uses the existing pinned SSH identity and a read-only database transaction.
Never fetches config files, secrets, keys, account IDs or existing orders.
"""
from pathlib import Path
import base64,hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'design_refs/shop_catalog_20261016/deployment'
CODE=r'''from pathlib import Path
import base64,hashlib,json,sys,urllib.request
archive=Path('/opt/goufayu/releases/current').resolve(strict=True)
payment=Path('/opt/goufayu/payments/current').resolve(strict=True)
digest=json.loads((archive/'addon/server/bundles/current.json').read_text())['hash']
files={}
paths=['release_manifest.json','backend/archive_backend/service.py','backend/archive_backend/bundle.py',
 'backend/archive_backend/config_compatibility.py','deploy/manage.py','addon/server/bundles/current.json',
 'addon/server/bundles/'+digest+'/bundle.json']
for name in paths:files['archive/'+name]=(archive/name).read_bytes()
manifest=json.loads((payment/'manifest.json').read_text())
for name in [*manifest,'manifest.json']:
 p=Path(name)
 if p.is_absolute() or '..' in p.parts or p.suffix not in ('.py','.sql','.txt','.csv','.json','.md'):raise RuntimeError('public_source_path_refused:'+name)
 if any(s in name.lower() for s in ('password','private_key','.env','.pem','.pgpass','config.json')):raise RuntimeError('private_source_refused')
 files['payment/'+name]=(payment/name).read_bytes()
sys.path.insert(0,str(payment));from deploy import connection
with connection() as c:
 c.execute('SET TRANSACTION READ ONLY')
 catalog=c.execute('SELECT catalog_hash FROM payments.catalog_state WHERE singleton').fetchone()[0]
 rules=[r[0] for r in c.execute('SELECT to_jsonb(s) FROM payments.stat_rules s ORDER BY field_id')]
 products=[r[0] for r in c.execute('SELECT to_jsonb(p) FROM payments.products p ORDER BY sort_order,sku')]
 functions={name:c.execute('SELECT pg_get_functiondef(%s::regprocedure)',(name,)).fetchone()[0] for name in ['public.archive_sync_config(text,jsonb)','payments.apply_effects(text,jsonb,boolean)']}
 c.rollback()
health={}
for name,port in [('archive',8765),('payment',8766)]:
 with urllib.request.urlopen('http://127.0.0.1:'+str(port)+'/health',timeout=5) as response:health[name]=json.load(response)
print(json.dumps({'metadata':{'archive_release':str(archive),'payment_release':str(payment),'bundle':digest,'catalog_hash':catalog,'health':health},
 'public_files':{name:{'sha256':hashlib.sha256(raw).hexdigest(),'base64':base64.b64encode(raw).decode('ascii')} for name,raw in files.items()},
 'catalog':products,'stat_rules':rules,'function_definitions':functions},ensure_ascii=False,default=str))
'''
def main():
    OUT.mkdir(parents=True,exist_ok=True)
    opts=['ssh.exe','-T','-F','none','-o','BatchMode=yes','-o','StrictHostKeyChecking=yes','-o','HostKeyAlgorithms=ssh-ed25519',
        '-o','UserKnownHostsFile=tools/deploy/goufayu_test_known_hosts','-o','IdentitiesOnly=yes','-o','ConnectTimeout=10',
        '-i',str(Path.home()/'.ssh/goufayu_ecs_ed25519_v2'),'root@47.110.238.248','/opt/goufayu/payments/current/.venv/bin/python -B -']
    p=subprocess.run(opts,input=CODE.encode('utf-8'),capture_output=True,cwd=ROOT,timeout=180,
                     creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    (OUT/'baseline.stderr.txt').write_bytes(p.stderr)
    if p.returncode:raise RuntimeError('remote_readonly_baseline_failed:'+str(p.returncode))
    data=json.loads(p.stdout);baseline=OUT/'online_baseline';baseline.mkdir(exist_ok=True)
    for name,record in data.pop('public_files').items():
        raw=base64.b64decode(record['base64'],validate=True);assert hashlib.sha256(raw).hexdigest()==record['sha256']
        dest=baseline/name;dest.parent.mkdir(parents=True,exist_ok=True)
        if dest.exists():assert dest.read_bytes()==raw,'online_baseline_changed:'+name
        else:dest.write_bytes(raw)
    (OUT/'preflight.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({**data['metadata'],'cash_products':len(data['catalog']),'cash_enabled':sum(p['enabled'] for p in data['catalog']),
                     'public_sources_saved':True,'player_data_read':False,'gateway_requests':0},ensure_ascii=False))
if __name__=='__main__':main()
