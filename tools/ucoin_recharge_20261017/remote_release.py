"""Reviewed payment03 transport. Run only after root's explicit execute message."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'design_refs/ucoin_recharge_20261017/remote/payment03'
TAR_SHA='cf549d64a8bd70e8ff3a2f72ab9c1f676c7e1cc39388860b4af6d8bb03269d20'
MANIFEST_SHA='9204fc34717fa91ea09277b0c0a71418bb5d779cdc3d16be7caf7e6be5519207'
OLD='/opt/goufayu/payments/20261016-shop-functional-v2'
NEW='/opt/goufayu/payments/20261017-payment03'
TRANSFER='/tmp/goufayu-ucoin-recharge-20261017-payment03-'+TAR_SHA[:12]
OPTIONS=['-T','-F','none','-o','BatchMode=yes','-o','StrictHostKeyChecking=yes',
    '-o','UserKnownHostsFile=tools/deploy/goufayu_test_known_hosts','-o','IdentitiesOnly=yes',
    '-o','ConnectTimeout=10','-i',str(Path.home()/'.ssh/goufayu_ecs_ed25519_v2')]
COMMON=f'''
from pathlib import Path
import hashlib,json,sys,os,urllib.request
OLD=Path({OLD!r});NEW=Path({NEW!r});TRANSFER=Path({TRANSFER!r})
def archive_guard():
 archive=Path('/opt/goufayu/releases/current').resolve(strict=True)
 assert archive.name=='20261016-vip-recharge-v1','archive_release_changed'
 assert json.loads((archive/'addon/server/bundles/current.json').read_bytes())['hash']=='ab2db559240bcb08d60bc982152bc869b729496cc2afcb71dabb973149c1f3fb','archive_bundle_changed'
def baseline():
 assert Path('/opt/goufayu/payments/current').resolve()==OLD,'payment_baseline_changed'
 assert hashlib.sha256((OLD/'manifest.json').read_bytes()).hexdigest()=='59e0dc9130668f13a07794148224cd217a5a18b2436276f16c126165e787b66e','baseline_manifest_changed'
 archive_guard()
def healthy():
 result={{}}
 for name,port in [('archive',8765),('payments',8766)]:
  with urllib.request.urlopen('http://127.0.0.1:'+str(port)+'/health',timeout=10) as response:
   value=json.load(response);assert response.status==200 and value.get('ok') is True,'health_failed:'+name
   result[name]=True
 return result
'''


def remote(code,label,timeout=240):
    safe=COMMON+'\ntry:\n'+''.join(' '+line+'\n' for line in code.splitlines())+'''
except Exception as error:
 import re
 reason=str(error)
 print(json.dumps(dict(status='FAIL',error_type=type(error).__name__,error_code=reason if re.fullmatch(r'[A-Za-z0-9_:.() -]{1,160}',reason) else 'private_details_suppressed')))
 sys.exit(1)
'''
    result=subprocess.run(['ssh.exe',*OPTIONS,'root@47.110.238.248',OLD+'/.venv/bin/python -B -'],
        input=safe.encode(),capture_output=True,cwd=ROOT,timeout=timeout,creationflags=subprocess.CREATE_NO_WINDOW)
    try:records=[json.loads(line) for line in result.stdout.decode('utf-8').splitlines() if line.strip()]
    except Exception:raise RuntimeError('remote_response_invalid_private_output_suppressed')
    OUT.mkdir(parents=True,exist_ok=True)
    report=dict(action=label,ssh_exit=result.returncode,records=records,stderr_suppressed=True)
    (OUT/(label+'.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False))
    if result.returncode:raise SystemExit(result.returncode)
    return report


def main(mode):
    local=ROOT/'output/payment_release/20261017-payment03.tar.gz'
    assert hashlib.sha256(local.read_bytes()).hexdigest()==TAR_SHA,'frozen_payment03_tarball_changed'
    if mode=='preflight':
        return remote('''baseline()
assert not NEW.exists(),'candidate_directory_exists'
health=healthy()
if TRANSFER.exists():assert TRANSFER.is_dir() and not TRANSFER.is_symlink(),'unsafe_transfer_directory'
else:TRANSFER.mkdir(mode=0o700)
os.chmod(TRANSFER,0o700)
print(json.dumps(dict(status='PREFLIGHT_PASS',baseline=OLD.name,archive_unchanged=True,health=health,candidate_absent=True,transfer=str(TRANSFER),orders_created=0)))''','preflight')
    if mode=='upload':
        assert (OUT/'preflight.json').is_file(),'preflight_required'
        result=subprocess.run(['scp.exe',*OPTIONS[1:],str(local),'root@47.110.238.248:'+TRANSFER+'/20261017-payment03.tar.gz'],
            capture_output=True,cwd=ROOT,timeout=120,creationflags=subprocess.CREATE_NO_WINDOW)
        report=dict(status='UPLOAD_PASS' if result.returncode==0 else 'UPLOAD_FAIL',tar_sha256=TAR_SHA,ssh_exit=result.returncode)
        OUT.mkdir(parents=True,exist_ok=True);(OUT/'upload.json').write_text(json.dumps(report,indent=2)+'\n')
        print(json.dumps(report));return result.returncode
    if mode=='stage':
        return remote(f'''baseline()
import tarfile,shutil
archive=TRANSFER/'20261017-payment03.tar.gz'
assert hashlib.sha256(archive.read_bytes()).hexdigest()=={TAR_SHA!r},'uploaded_tarball_mismatch'
assert not NEW.exists(),'candidate_directory_exists'
with tarfile.open(archive,'r:gz') as stream:
 members=stream.getmembers();seen=set()
 for item in members:
  p=Path(item.name)
  assert item.isfile() and not p.is_absolute() and '..' not in p.parts and p.parts[0]==NEW.name,'unsafe_tar_member'
  assert item.name not in seen,'duplicate_tar_member';seen.add(item.name)
 NEW.mkdir(mode=0o755)
 for item in members:
  dest=NEW.parent/item.name;dest.parent.mkdir(parents=True,exist_ok=True)
  with stream.extractfile(item) as source,dest.open('xb') as target:shutil.copyfileobj(source,target)
  dest.chmod(0o644)
assert hashlib.sha256((NEW/'manifest.json').read_bytes()).hexdigest()=={MANIFEST_SHA!r},'candidate_manifest_mismatch'
sys.path.insert(0,str(NEW))
from payment_backend.upgrade_ucoin_recharge import verify_scope,verify_archive_baseline,release_module
scope=verify_scope(OLD);verify_archive_baseline(release_module())
print(json.dumps(dict(status='STAGE_PASS',release=NEW.name,manifest_sha256={MANIFEST_SHA!r},tar_sha256={TAR_SHA!r},baseline=scope['baseline_release'],old_products_pinned=scope['existing_product_count'],orders_created=0)))''','stage')
    if mode in ('validate','activate'):
        assert (OUT/'stage.json').is_file(),'verified_stage_required'
        if mode=='activate':
            prior=json.loads((OUT/'validate.json').read_bytes())
            assert prior['ssh_exit']==0 and any(r.get('validated') is True for r in prior['records']),'successful_validation_required'
        return remote(f'''baseline()
assert hashlib.sha256((NEW/'manifest.json').read_bytes()).hexdigest()=={MANIFEST_SHA!r},'candidate_manifest_mismatch'
os.chdir(NEW);sys.path.insert(0,str(NEW))
from payment_backend.upgrade_ucoin_recharge import main
main({mode!r},str(OLD))''',mode,300)
    if mode=='verify':
        source=Path(__file__).with_name('remote_verify.py').read_text(encoding='utf-8-sig')
        audit=json.loads((ROOT/'design_refs/ucoin_recharge_20261017/remote/current_schema.json').read_bytes())
        activation=json.loads((OUT/'activate.json').read_bytes())
        backup=next(r['local_backup'] for r in activation['records'] if 'local_backup' in r)
        return remote('BASELINE_TRIGGERS='+repr(audit['triggers'])+'\nBACKUP_PATH='+repr(backup)+'\n'+source,'verify',120)
    raise SystemExit('invalid_mode')


if __name__=='__main__':
    value=main(sys.argv[1])
    if isinstance(value,int):sys.exit(value)
