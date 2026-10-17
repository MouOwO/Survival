"""Explicit phase transport for the pinned functional shop publication."""
from pathlib import Path
import argparse,base64,hashlib,importlib.util,json,tarfile
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'design_refs/shop_functional_20261016/release'
STAGE='/tmp/survival-shop-functional-20261016'
spec=importlib.util.spec_from_file_location('transport',ROOT/'tools/shop_catalog_20261016/deploy_driver.py')
transport=importlib.util.module_from_spec(spec);spec.loader.exec_module(transport)
transport.REPORT=ROOT/'design_refs/shop_functional_20261016/deployment'
def sha(b):return hashlib.sha256(b).hexdigest()
def checked():
    plan=json.loads((OUT/'release_plan.json').read_bytes());assert plan['kind']=='functional_commerce'
    assert sha((OUT/'overlay.tar.gz').read_bytes())==plan['tar_sha256']
    with tarfile.open(OUT/'overlay.tar.gz') as tar:
        actual={m.name:sha(tar.extractfile(m).read()) for m in tar.getmembers() if m.isfile()}
    assert actual==plan['files']
    return plan,sha((OUT/'release_plan.json').read_bytes()),sha(Path(__file__).with_name('deploy_remote.py').read_bytes())
def main():
    ap=argparse.ArgumentParser();ap.add_argument('action',choices=['check','upload','backup','prepare','validate','activate','verify']);args=ap.parse_args()
    plan,pin,operator=checked()
    if args.action=='check':print(json.dumps({'status':'LOCAL_ARTIFACTS_VERIFIED','candidate':plan['candidate'],'plan_sha256':pin,'operator_sha256':operator}));return
    if args.action=='upload':
        files={'release_plan.json':OUT/'release_plan.json','overlay.tar.gz':OUT/'overlay.tar.gz','deploy_remote.py':Path(__file__).with_name('deploy_remote.py')}
        entries={n:{'data':base64.b64encode(p.read_bytes()).decode(),'sha256':sha(p.read_bytes())} for n,p in files.items()}
        code='STAGE='+repr(STAGE)+'\nENTRIES='+repr(entries)+'\n'+'''from pathlib import Path
import base64,hashlib,json,os
os.umask(0o077);root=Path(STAGE)
if root.is_symlink():raise RuntimeError('stage_symlink')
root.mkdir(mode=0o700,exist_ok=True)
if root.stat().st_uid!=0 or root.stat().st_mode&0o077:raise RuntimeError('private_root_stage_required')
for name,entry in ENTRIES.items():
 raw=base64.b64decode(entry['data'],validate=True)
 if hashlib.sha256(raw).hexdigest()!=entry['sha256']:raise RuntimeError('upload_digest')
 target=root/name
 if target.is_symlink():raise RuntimeError('upload_symlink')
 if target.exists():
  if target.read_bytes()!=raw:raise RuntimeError('immutable_upload_changed')
 else:
  with target.open('xb') as f:f.write(raw)
  target.chmod(0o600)
print(json.dumps({'status':'UPLOADED_NOT_ACTIVATED','files':{k:v['sha256'] for k,v in ENTRIES.items()}}))
'''
    else:
        code='import runpy,sys\nsys.dont_write_bytecode=True\nsys.argv='+repr(['deploy_remote.py',args.action,'--plan-sha',pin,'--operator-sha',operator])+'\nrunpy.run_path('+repr(STAGE+'/deploy_remote.py')+",run_name='__main__')\n"
    print(json.dumps(transport.remote(args.action,code,timeout=300),ensure_ascii=False))
if __name__=='__main__':main()
