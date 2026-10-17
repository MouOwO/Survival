"""Read-only version recheck after a concurrent release; no player data."""
import json
from deploy_driver import remote
CODE=r'''from pathlib import Path
import hashlib,json,sys,urllib.request
a=Path('/opt/goufayu/releases/current').resolve(strict=True)
p=Path('/opt/goufayu/payments/current').resolve(strict=True)
sys.path.insert(0,str(p));from deploy import connection
with connection() as c:
 c.execute('SET TRANSACTION READ ONLY')
 exists=c.execute("SELECT to_regclass('public.archive_leaderboard_identities') IS NOT NULL").fetchone()[0]
 catalog=c.execute('SELECT catalog_hash FROM payments.catalog_state WHERE singleton').fetchone()[0]
 c.rollback()
health={}
for name,port in [('archive',8765),('payment',8766)]:
 with urllib.request.urlopen('http://127.0.0.1:'+str(port)+'/health',timeout=5) as r:health[name]=json.load(r)
m=json.loads((a/'release_manifest.json').read_bytes())
print(json.dumps({'status':'CURRENT_VERSION_READ_ONLY','archive_release':str(a),'bundle':json.loads((a/'addon/server/bundles/current.json').read_bytes())['hash'],
 'manifest_sha256':hashlib.sha256((a/'release_manifest.json').read_bytes()).hexdigest(),'payment_release':str(p),'cash_catalog_hash':catalog,
 'leaderboard_table_exists':exists,'release_metadata':{k:v for k,v in m.items() if k!='files'},
 'public_source_hashes':{n:v for n,v in m['files'].items() if n.startswith('backend/')},'health':health}))
'''
if __name__=='__main__':print(json.dumps(remote('current_recheck',CODE),ensure_ascii=False))
