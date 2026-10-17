"""Fetch only public server sources and schema metadata from the authorized host."""
from pathlib import Path
import argparse,base64,hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'design_refs/endless_leaderboard_20261016/deployment'
CODE=r'''from pathlib import Path
import base64,hashlib,json,sys,urllib.request,subprocess
a=Path('/opt/goufayu/releases/current').resolve(strict=True)
p=Path('/opt/goufayu/payments/current').resolve(strict=True)
manifest=json.loads((a/'release_manifest.json').read_bytes())
files={'release_manifest.json':(a/'release_manifest.json').read_bytes()}
bundle=json.loads((a/'addon/server/bundles/current.json').read_bytes())['hash']
files['addon/server/bundles/'+bundle+'/bundle.json']=(a/'addon/server/bundles'/bundle/'bundle.json').read_bytes()
for name in manifest['files']:
 path=Path(name)
 if name.startswith('backend/') and path.suffix in ('.py','.sql','.txt') or name=='deploy/manage.py' or name=='addon/server/bundles/current.json':
  if path.is_absolute() or '..' in path.parts or any(x in name.lower() for x in ('secret','password','.env','.pgpass','.pem')):raise RuntimeError('source_path_refused')
  raw=(a/path).read_bytes()
  if hashlib.sha256(raw).hexdigest()!=manifest['files'][name]:raise RuntimeError('online_source_changed')
  files[name]=raw
sys.path.insert(0,str(p));from deploy import connection
with connection() as c:
 c.execute('SET TRANSACTION READ ONLY')
 tables=c.execute("SELECT schemaname,tablename FROM pg_tables WHERE schemaname IN ('public','payments') ORDER BY 1,2").fetchall()
 functions={name:c.execute('SELECT pg_get_functiondef(%s::regprocedure)',(name,)).fetchone()[0] for name in ['public.archive_sync_config(text,jsonb)','payments.apply_effects(text,jsonb,boolean)']}
 catalog=c.execute('SELECT catalog_hash FROM payments.catalog_state WHERE singleton').fetchone()[0]
 c.rollback()
nginx=subprocess.run(['nginx','-T'],capture_output=True,check=True).stdout.decode('utf-8','replace')
routes=[line.strip() for line in nginx.splitlines() if 'location' in line or '# configuration file /etc/nginx/' in line]
health={}
for name,port in [('archive',8765),('payment',8766)]:
 with urllib.request.urlopen('http://127.0.0.1:'+str(port)+'/health',timeout=5) as response:health[name]=json.load(response)
print(json.dumps({'metadata':{'archive_release':str(a),'payment_release':str(p),'bundle':json.loads((a/'addon/server/bundles/current.json').read_bytes())['hash'],
 'archive_manifest_sha256':hashlib.sha256((a/'release_manifest.json').read_bytes()).hexdigest(),'payment_manifest_sha256':hashlib.sha256((p/'manifest.json').read_bytes()).hexdigest(),
 'catalog_hash':catalog,'health':health},'tables':tables,'function_definitions':functions,'nginx_locations':routes,
 'public_files':{name:{'sha256':hashlib.sha256(raw).hexdigest(),'base64':base64.b64encode(raw).decode()} for name,raw in files.items()}},ensure_ascii=False))
'''
def main():
    global OUT
    parser=argparse.ArgumentParser();parser.add_argument('--rebase-v2',action='store_true');args=parser.parse_args()
    if args.rebase_v2:OUT=OUT/'rebase_v2'
    OUT.mkdir(parents=True,exist_ok=True)
    opts=['ssh.exe','-T','-F','none','-o','BatchMode=yes','-o','StrictHostKeyChecking=yes','-o','HostKeyAlgorithms=ssh-ed25519',
      '-o','UserKnownHostsFile=tools/deploy/goufayu_test_known_hosts','-o','IdentitiesOnly=yes','-o','ConnectTimeout=10',
      '-i',str(Path.home()/'.ssh/goufayu_ecs_ed25519_v2'),'root@47.110.238.248','/opt/goufayu/payments/current/.venv/bin/python -B -']
    response=subprocess.run(opts,input=CODE.encode('utf-8'),capture_output=True,cwd=ROOT,timeout=120,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    (OUT/'fetch.stderr.txt').write_bytes(response.stderr)
    if response.returncode:raise RuntimeError('readonly_baseline_fetch_failed:'+str(response.returncode))
    data=json.loads(response.stdout);baseline=OUT/'online_baseline'
    records=data.pop('public_files')
    for name,item in records.items():
        raw=base64.b64decode(item['base64'],validate=True);assert hashlib.sha256(raw).hexdigest()==item['sha256']
        dest=baseline/name;dest.parent.mkdir(parents=True,exist_ok=True)
        if dest.exists():assert dest.read_bytes()==raw,'immutable_baseline_changed:'+name
        else:dest.write_bytes(raw)
    (OUT/'preflight.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({**data['metadata'],'public_files_saved':len(records),'business_tables':len(data['tables']),'nginx_locations':data['nginx_locations'],'player_rows_fetched':0},ensure_ascii=False))
if __name__=='__main__':main()
