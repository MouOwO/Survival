"""Explicit operator transport for the approved 2026-10-16 points deployment.

No account credentials, database rows or gateway requests are transmitted here.
The existing SSH identity is read by OpenSSH, never by this Python process.
"""
from pathlib import Path
import argparse,base64,hashlib,json,subprocess,sys

ROOT=Path(__file__).resolve().parents[2]
REPORT=ROOT/'design_refs/commerce_points_20261016/deployment'
STAGE='/tmp/survival-commerce-points-20261016-caf4493bb7ad'
REMOTE_PY='/opt/goufayu/payments/current/.venv/bin/python'

def sha(raw):return hashlib.sha256(raw).hexdigest()

def remote(name,source,timeout=240):
    REPORT.mkdir(parents=True,exist_ok=True)
    args=['ssh.exe','-T','-F','none','-o','BatchMode=yes','-o','StrictHostKeyChecking=yes',
          '-o','UserKnownHostsFile=tools/deploy/goufayu_test_known_hosts','-o','HostKeyAlgorithms=ssh-ed25519',
          '-o','IdentitiesOnly=yes','-o','ConnectTimeout=10',
          '-i',str(Path.home()/'.ssh/goufayu_ecs_ed25519_v2'),
          'root@47.110.238.248',REMOTE_PY+' -B -']
    result=subprocess.run(args,input=source.encode('utf-8'),capture_output=True,timeout=timeout,cwd=ROOT,
                          creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    (REPORT/(name+'.stdout.txt')).write_bytes(result.stdout)
    (REPORT/(name+'.stderr.txt')).write_bytes(result.stderr)
    print(result.stdout.decode('utf-8','replace'),end='')
    if result.returncode:
        print('REMOTE_FAILED; protected diagnostic saved locally; exit='+str(result.returncode))
        raise SystemExit(result.returncode)
    lines=result.stdout.decode('utf-8').splitlines()
    parsed=json.loads(next(line for line in reversed(lines) if line.startswith('{')))
    (REPORT/(name+'.json')).write_text(json.dumps(parsed,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    return parsed

def upload(restage=False):
    release=ROOT/'design_refs/commerce_points_20261016/release/archive-commerce-points-caf4493bb7ad'
    payment=ROOT/'design_refs/commerce_logic_audit_20261016/release/payment_starjoy_progress_v1.tar.gz'
    paths={
        'archive_patch.tar.gz':release/'archive_patch.tar.gz',
        'payment_starjoy_progress_v1.tar.gz':payment,
        'deploy_remote.py':Path(__file__).with_name('deploy_remote.py'),
        'deploy_online_patch.py':Path(__file__).with_name('deploy_online_patch.py'),
    }
    if restage:
        paths['earned_stat_rule.sql']=Path(__file__).with_name('earned_stat_rule.sql')
        paths['synthetic_worker_review.py']=REPORT/'synthetic_worker_review.py'
        for name in ['upgrade_archive_points_compat.sql','test_archive_points_compat.py','archive_points_compat_manifest.json']:
            paths[name]=Path(__file__).with_name(name)
    items={name:{'sha256':sha(path.read_bytes()),'base64':base64.b64encode(path.read_bytes()).decode('ascii')} for name,path in paths.items()}
    assert items['archive_patch.tar.gz']['sha256']=='00204767f881085d674a41cfdfa8fbf4ba5a7d2be3613d12868bf77b65d0d6f3'
    assert items['payment_starjoy_progress_v1.tar.gz']['sha256']=='09dfe0928c3cff34a6a10da9fe722a2d3eabae29269ea9d131651e3c00da3ba4'
    prior_report=REPORT/('restage.json' if (REPORT/'restage.json').exists() else 'upload.json')
    old_operator=json.loads(prior_report.read_text('utf-8'))['files']['deploy_remote.py'] if restage else None
    code='''from pathlib import Path
import base64,hashlib,json,os
os.umask(0o077)
root=Path(STAGE)
if root.is_symlink():raise RuntimeError('stage_symlink_refused')
root.mkdir(mode=0o700,exist_ok=True)
files=ITEMS
for name,record in files.items():
 raw=base64.b64decode(record['base64'],validate=True)
 if hashlib.sha256(raw).hexdigest()!=record['sha256']:raise RuntimeError('upload_digest_mismatch')
 path=root/name
 if path.is_symlink():raise RuntimeError('upload_symlink_refused')
 if path.exists():
  if path.read_bytes()!=raw:
   if name!='deploy_remote.py' or hashlib.sha256(path.read_bytes()).hexdigest()!=OLD_OPERATOR:raise RuntimeError('stage_file_changed:'+name)
   previous=root/('deploy_remote.previous-'+OLD_OPERATOR+'.py')
   if previous.exists():
    if previous.read_bytes()!=path.read_bytes():raise RuntimeError('previous_operator_changed')
   else:
    with previous.open('xb') as stream:stream.write(path.read_bytes())
   tmp=root/'deploy_remote.next.py'
   with tmp.open('xb') as stream:stream.write(raw)
   os.replace(tmp,path)
 else:
  with path.open('xb') as stream:stream.write(raw)
  path.chmod(0o600)
print(json.dumps({'status':'UPLOADED_NOT_ACTIVATED','stage':str(root),'files':{n:r['sha256'] for n,r in files.items()}}))
'''.replace('STAGE',repr(STAGE),1).replace('ITEMS',repr(items),1).replace('OLD_OPERATOR',repr(old_operator))
    return remote('restage' if restage else 'upload',code)

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('action',choices=['upload','restage','backup','prepare','validate','activate','verify']);a=ap.parse_args()
    if a.action in {'upload','restage'}:upload(a.action=='restage')
    else:
        code="import runpy,sys\nsys.argv=['deploy_remote.py',"+repr(a.action)+"]\nrunpy.run_path("+repr(STAGE+'/deploy_remote.py')+",run_name='__main__')\n"
        remote(a.action,code,timeout=300)
