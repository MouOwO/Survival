"""Prepare/validate/activate a sealed additive backend release and hashed codes."""
from pathlib import Path
import argparse
import base64
import hashlib
import importlib.util
import io
import json
import sys
import tarfile

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/redemption_codes_20261029/deployment'
sha=lambda raw:hashlib.sha256(raw).hexdigest()
def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path);value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value
transport=module('redemption_server_transport',ROOT/'tools/archive_release_20261029/server_deploy.py')
patcher=module('redemption_source_patch',Path(__file__).with_name('patch_backend.py'))

def build():
    baseline=ROOT/'tmp/redemption_codes_20261029/baseline'
    audit=json.loads((baseline/'audit.json').read_bytes())
    overlay={}
    for name,kind in [('backend/archive_backend/service.py','service'),('backend/fishing_api/postgres.py','rpc')]:
        overlay[name]=patcher.patch((baseline/name).read_bytes(),kind)
    for name in ['redemption_codes.py','redemption_worker.lua','redemption_settlement.lua']:
        overlay['backend/archive_backend/'+name]=(ROOT/'server/archive_backend'/name).read_bytes()
    registry=(ROOT/'output/redemption_codes_20261029/private/server_codes_ready.json').read_bytes()
    plan={'version':1,'parent_release':audit['release'],'parent_manifest_sha256':audit['manifest_sha256'],
          'payment_release':audit['payment_release'],'payment_pid':audit['services']['goufayu-payment.service']['MainPID'],
          'bundle':audit['bundle'],'ledger':audit['ledger'],'functions':audit['functions'],'app_rpcs':audit['app_rpcs'],
          'all_backend_hashes':audit['backend_source_hashes'],'overlay':{k:sha(v)for k,v in overlay.items()}}
    files={'overlay/'+name:raw for name,raw in overlay.items()}
    files.update({'migration.sql':(ROOT/'server/aliyun/database/target/202610290002_redemption_codes.sql').read_bytes(),
                  'codes.json':registry,'database_checks.py':Path(__file__).with_name('database_checks.py').read_bytes(),
                  'remote_operator.py':Path(__file__).with_name('remote_operator.py').read_bytes()})
    plan['payload']={k:sha(v)for k,v in files.items()}
    fingerprint=sha(json.dumps(plan,sort_keys=True,separators=(',',':')).encode())[:12]
    plan['release']='20261029-redemption-'+fingerprint
    plan['stage']='/root/goufayu_upload/redemption-'+fingerprint
    files['plan.json']=(json.dumps(plan,ensure_ascii=False,sort_keys=True,indent=2)+'\n').encode()
    buffer=io.BytesIO()
    with tarfile.open(fileobj=buffer,mode='w:gz')as archive:
        for name,raw in sorted(files.items()):
            entry=tarfile.TarInfo(name);entry.size=len(raw);entry.mode=0o600;entry.mtime=0;archive.addfile(entry,io.BytesIO(raw))
    OUT.mkdir(parents=True,exist_ok=True)
    for name,raw in files.items():
        target=OUT/'candidate'/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(raw)
    (OUT/'payload.tar.gz').write_bytes(buffer.getvalue())
    (OUT/'seal.json').write_text(json.dumps({'stage':plan['stage'],'release':plan['release'],
        'archive_sha256':sha(buffer.getvalue()),'plan_sha256':sha(files['plan.json'])},indent=2))
    return {'ok':True,'release':plan['release'],'codes':len(json.loads(registry)['codes']),'sealed':True}

def source(action):
    seal=json.loads((OUT/'seal.json').read_bytes())
    code='STAGE='+repr(seal['stage'])+'\nMODE='+repr(action)+'\nPLAN_SHA='+repr(seal['plan_sha256'])+'\n'
    if action=='prepare':
        raw=(OUT/'payload.tar.gz').read_bytes()
        if sha(raw)!=seal['archive_sha256']:raise RuntimeError('sealed_payload_changed')
        code+='PAYLOAD='+repr(base64.b64encode(raw).decode())+'\nARCHIVE_SHA='+repr(seal['archive_sha256'])+'\n'
        code+='''from pathlib import Path,PurePosixPath
import base64,hashlib,io,tarfile,os
root=Path(STAGE)
assert root.parent==Path('/root/goufayu_upload') and not root.exists()
raw=base64.b64decode(PAYLOAD,validate=True);assert hashlib.sha256(raw).hexdigest()==ARCHIVE_SHA
root.mkdir(mode=0o700)
with tarfile.open(fileobj=io.BytesIO(raw))as archive:
 for entry in archive.getmembers():
  name=PurePosixPath(entry.name);assert entry.isfile() and not name.is_absolute() and '..' not in name.parts
  target=root/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(archive.extractfile(entry).read());target.chmod(0o600)
'''
    code+='''from pathlib import Path
import hashlib,importlib.util,json,re,traceback
root=Path(STAGE);assert not root.is_symlink() and hashlib.sha256((root/'plan.json').read_bytes()).hexdigest()==PLAN_SHA
spec=importlib.util.spec_from_file_location('redemption_operator',root/'remote_operator.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
try:
 result=m.Operator(root).dispatch(MODE)
 print(json.dumps(result))
except Exception as error:
 (root/(MODE+'_failure_private.txt')).write_text(traceback.format_exc())
 state=getattr(error,'sqlstate',None)
 code=str(error) if isinstance(error,RuntimeError) and re.fullmatch(r'[a-z0-9_]{1,100}',str(error)) else 'redemption_'+MODE+'_failed'
 (root/'last_failure.json').write_text(json.dumps({'ok':False,'error':code,'type':type(error).__name__,'sqlstate':state}))
 raise RuntimeError(code) from None
'''
    return code

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('action',choices=['build','prepare','validate','activate','verify','failure'])
    parser.add_argument('--via-local-proxy',action='store_true')
    args=parser.parse_args();action=args.action
    if args.via_local_proxy:
        original=transport.options
        proxy=Path(__file__).with_name('ssh_proxy.py').resolve().as_posix()
        command='ProxyCommand='+Path(sys.executable).as_posix()+' "'+proxy+'" %h %p'
        transport.options=lambda:[*original(),'-o',command]
    if action=='build':result=build()
    elif action=='failure':
        seal=json.loads((OUT/'seal.json').read_bytes())
        result=transport.remote('import json\nfrom pathlib import Path\nr=json.loads((Path('+repr(seal['stage'])+')/"last_failure.json").read_bytes());r["ok"]=True;print(json.dumps(r))')
    else:
        result=transport.remote(source(action),timeout=300)
        (OUT/(action+'.json')).write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(result,ensure_ascii=False))

if __name__=='__main__':main()
