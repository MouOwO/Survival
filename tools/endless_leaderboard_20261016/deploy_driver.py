"""Pinned transport for the explicitly authorized archive leaderboard release."""
from pathlib import Path,PurePosixPath
import argparse,base64,hashlib,json,re,subprocess,sys,tarfile
ROOT=Path(__file__).resolve().parents[2]
RELEASE=ROOT/'design_refs/endless_leaderboard_20261016/release'
REPORT=ROOT/'design_refs/endless_leaderboard_20261016/deployment'
STAGE='/tmp/survival-endless-leaderboard-20261016-v2'
HOST='47.110.238.248'
def need(value,reason):
    if not value:raise RuntimeError(reason)
def sha(raw):return hashlib.sha256(raw).hexdigest()
def checked():
    plan_raw=(RELEASE/'release_plan.json').read_bytes();plan=json.loads(plan_raw)
    need(plan['version']==1 and plan['kind']=='endless_leaderboard_readonly','release_kind_invalid')
    need(plan['old_release']=='/opt/goufayu/releases/20261016-endless-titles-v1','release_baseline_invalid')
    archive=RELEASE/'overlay.tar.gz';need(sha(archive.read_bytes())==plan['tar_sha256'],'archive_changed')
    actual={}
    with tarfile.open(archive,'r:gz') as tar:
        for member in tar:
            name=PurePosixPath(member.name)
            need(member.isfile() and not name.is_absolute() and '..' not in name.parts and '\\' not in member.name
              and ':' not in member.name and member.name not in actual,'unsafe_archive_member')
            actual[member.name]=sha(tar.extractfile(member).read())
    need(actual==plan['files'],'payload_manifest_changed')
    return {'status':'LOCAL_ARTIFACTS_VERIFIED','plan_sha256':sha(plan_raw),
      'operator_sha256':sha(Path(__file__).with_name('deploy_remote.py').read_bytes()),
      'tar_sha256':plan['tar_sha256'],'payload_files':len(actual),'remote_executed':False}
def options():
    sys.path.insert(0,str(ROOT/'tools'))
    import aliyun_local_config
    from aliyun_test_connection import ECS_HOST,verify_known_hosts
    need(ECS_HOST==HOST,'host_changed');settings=aliyun_local_config.load(ROOT)
    known=ROOT/'tools/deploy/goufayu_test_known_hosts';verify_known_hosts(known)
    return ['ssh.exe','-T','-F','none','-o','BatchMode=yes','-o','StrictHostKeyChecking=yes',
      '-o','UserKnownHostsFile='+known.relative_to(ROOT).as_posix(),'-o','GlobalKnownHostsFile=none',
      '-o','HostKeyAlgorithms=ssh-ed25519','-o','IdentitiesOnly=yes','-o','ConnectTimeout=10',
      '-o','PreferredAuthentications=publickey','-o','PasswordAuthentication=no','-o','KbdInteractiveAuthentication=no',
      '-i',str(settings['ssh_key']),'root@'+HOST,'/opt/goufayu/payments/current/.venv/bin/python -B -']
def remote(action,code):
    REPORT.mkdir(parents=True,exist_ok=True)
    result=subprocess.run(options(),input=code.encode(),capture_output=True,cwd=ROOT,timeout=300,
      creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    (REPORT/(action+'.stdout.txt')).write_bytes(result.stdout);(REPORT/(action+'.stderr.txt')).write_bytes(result.stderr)
    parsed=None
    for line in reversed(result.stdout.decode('utf-8','replace').splitlines()):
        if line.startswith('{'):
            try:parsed=json.loads(line);break
            except ValueError:continue
    if parsed is not None:(REPORT/(action+'.json')).write_text(json.dumps(parsed,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    need(result.returncode==0 and parsed and parsed.get('status')!='FAILED','remote_'+action+'_failed_diagnostics_saved')
    return parsed
def upload():
    review=checked()
    paths={'overlay.tar.gz':RELEASE/'overlay.tar.gz','release_plan.json':RELEASE/'release_plan.json',
      'deploy_remote.py':Path(__file__).with_name('deploy_remote.py')}
    entries={name:{'sha256':sha(path.read_bytes()),'data':base64.b64encode(path.read_bytes()).decode()} for name,path in paths.items()}
    code='''from pathlib import Path
import base64,hashlib,json,os
os.umask(0o077)
root=Path(STAGE_VALUE)
if root.is_symlink():raise RuntimeError('stage_symlink_refused')
root.mkdir(mode=0o700,exist_ok=True)
if root.stat().st_uid!=0 or root.stat().st_mode&0o077:raise RuntimeError('stage_not_private')
entries=ENTRIES_VALUE
for name,entry in entries.items():
 raw=base64.b64decode(entry['data'],validate=True)
 if hashlib.sha256(raw).hexdigest()!=entry['sha256']:raise RuntimeError('upload_hash_invalid')
 path=root/name
 if path.is_symlink():raise RuntimeError('upload_symlink_refused')
 if path.exists():
  if not path.is_file() or path.read_bytes()!=raw:raise RuntimeError('uploaded_artifact_immutable')
 else:
  with path.open('xb') as out:out.write(raw)
  path.chmod(0o600)
print(json.dumps({'status':'UPLOADED_NOT_ACTIVATED','files':{name:value['sha256'] for name,value in entries.items()}}))
'''.replace('STAGE_VALUE',repr(STAGE),1).replace('ENTRIES_VALUE',repr(entries),1)
    result=remote('upload',code)
    need(result['files']['release_plan.json']==review['plan_sha256'] and result['files']['deploy_remote.py']==review['operator_sha256'],'upload_pins_differ')
    return result
def execute(action):
    if action=='check':return checked()
    if action=='upload':return upload()
    review=checked();args=['deploy_remote.py',action,'--plan-sha',review['plan_sha256'],'--operator-sha',review['operator_sha256']]
    code='import runpy,sys\nsys.dont_write_bytecode=True\nsys.argv='+repr(args)+'\nrunpy.run_path('+repr(STAGE+'/deploy_remote.py')+',run_name="__main__")\n'
    return remote(action,code)
def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('action',choices=['check','upload','backup','prepare','validate','activate','verify'])
    print(json.dumps(execute(parser.parse_args().action),ensure_ascii=False))
if __name__=='__main__':main()
