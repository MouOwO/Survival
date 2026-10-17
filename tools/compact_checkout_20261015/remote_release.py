from pathlib import Path
import subprocess,sys,json,hashlib
ROOT=Path.cwd()
REPORTS=ROOT/'output/compact_checkout_20261015/remote'
REPORTS.mkdir(parents=True,exist_ok=True)
opts=['-T','-F','none','-o','BatchMode=yes','-o','StrictHostKeyChecking=yes','-o','UserKnownHostsFile=tools/deploy/goufayu_test_known_hosts','-o','IdentitiesOnly=yes','-o','ConnectTimeout=10','-i',str(Path.home()/'.ssh/goufayu_ecs_ed25519_v2')]
meta=json.loads((ROOT/'output/compact_checkout_20261015/quantity_release_manifest.json').read_text(encoding='utf8'))
TAR_HASH=meta['tar_sha256']; MANIFEST_HASH=meta['manifest_sha256']
BASELINE_HASH=meta['baseline_manifest_sha256']
OLD='/opt/goufayu/payments/20261015-payment01'
NEW='/opt/goufayu/payments/20261015-payment02'
TRANSFER='/tmp/goufayu-quantity-20261015-'+TAR_HASH[:12]
def remote(code,name):
    r=subprocess.run(['ssh.exe',*opts,'root@47.110.238.248',OLD+'/.venv/bin/python -B -'],input=code.encode('utf8'),stdout=subprocess.PIPE,stderr=subprocess.PIPE,cwd=ROOT,timeout=180,creationflags=subprocess.CREATE_NO_WINDOW)
    (REPORTS/(name+'.log')).write_bytes(r.stdout+r.stderr)
    print(r.stdout.decode('utf8',errors='replace'))
    if r.returncode:
        print(r.stderr.decode('utf8',errors='replace')[:2500]);raise SystemExit(r.returncode)
    return r
common=f"""
from pathlib import Path
import hashlib,json,sys,os,subprocess,urllib.request
OLD=Path({OLD!r}); NEW=Path({NEW!r}); TRANSFER=Path({TRANSFER!r})
assert Path('/opt/goufayu/payments/current').resolve()==OLD
assert hashlib.sha256((OLD/'manifest.json').read_bytes()).hexdigest()=={BASELINE_HASH!r}
assert Path('/opt/goufayu/releases/current').resolve().name=='20261015-video-bundles-v1'
assert json.loads(Path('/opt/goufayu/releases/current/addon/server/bundles/current.json').read_text())['hash']=={meta['archive_hash']!r}
"""
def run(mode):
    if mode=='preflight':
        remote(common+"""
health={}
for name,port in [('archive',8765),('payments',8766)]:
 with urllib.request.urlopen('http://127.0.0.1:'+str(port)+'/health',timeout=10) as r:
  health[name]=r.status==200 and json.load(r)['ok'] is True
assert all(health.values())
assert not NEW.exists()
if TRANSFER.exists():
 assert TRANSFER.is_dir() and not TRANSFER.is_symlink()
else:
 TRANSFER.mkdir(mode=0o700)
os.chmod(TRANSFER,0o700)
print(json.dumps({'preflight':'PASS','baseline':OLD.name,'new_directory_absent':True,'archive_unchanged':True,'health':health,'transfer':str(TRANSFER)}))
""",'preflight')
    elif mode=='upload':
        local=Path(meta['tar'])
        assert hashlib.sha256(local.read_bytes()).hexdigest()==TAR_HASH
        r=subprocess.run(['scp.exe',*opts[1:],str(local),'root@47.110.238.248:'+TRANSFER+'/20261015-payment02.tar.gz'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,cwd=ROOT,timeout=120,creationflags=subprocess.CREATE_NO_WINDOW)
        (REPORTS/'upload.log').write_bytes(r.stdout+r.stderr)
        if r.returncode:print(r.stderr.decode('utf8',errors='replace'));raise SystemExit(r.returncode)
        print('QUANTITY_UPLOAD_PASS '+TAR_HASH)
    elif mode=='stage':
        remote(common+f"""
import tarfile
tar=TRANSFER/'20261015-payment02.tar.gz'
assert hashlib.sha256(tar.read_bytes()).hexdigest()=={TAR_HASH!r}
assert not NEW.exists()
with tarfile.open(tar,'r:gz') as archive:
 members=archive.getmembers()
 for m in members:
  p=Path(m.name)
  assert not p.is_absolute() and '..' not in p.parts and p.parts[0]==NEW.name
  assert m.isdir() or m.isfile()
 archive.extractall(NEW.parent)
assert hashlib.sha256((NEW/'manifest.json').read_bytes()).hexdigest()=={MANIFEST_HASH!r}
sys.path.insert(0,str(NEW))
from payment_backend.upgrade_order_quantity import verify_scope
verify_scope(OLD)
print(json.dumps({{'staged':'PASS','release':NEW.name,'tar_sha256':{TAR_HASH!r},'manifest_sha256':{MANIFEST_HASH!r},'file_count':len(json.loads((NEW/'manifest.json').read_text())),'current_unchanged':True}}))
""",'stage')
    elif mode=='verify':
        remote(Path(__file__).with_name('remote_verify.py').read_text(encoding='utf-8-sig'),'verify')
    elif mode in ('validate','activate'):
        remote(common+f"""
os.chdir(NEW)
r=subprocess.run([str(OLD/'.venv/bin/python'),'-B','-m','payment_backend.upgrade_order_quantity',{mode!r},str(OLD)])
sys.exit(r.returncode)
""",mode)
    else:raise SystemExit('invalid mode')
if __name__=='__main__':run(sys.argv[1])
