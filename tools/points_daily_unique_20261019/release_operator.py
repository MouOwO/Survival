"""Explicit checked transport; default check is local. No automatic activation."""
from pathlib import Path, PurePosixPath
import argparse
import base64
import contextlib
import hashlib
import importlib.util
import io
import json
import tarfile

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/points_daily_unique_20261019/release_v3'


def sha(raw):return hashlib.sha256(raw).hexdigest()


def checked():
    plan=json.loads((OUT/'plan.json').read_bytes())
    assert plan['status']=='SEALED_NOT_DEPLOYED' and plan['kind']=='daily_unique_archive_repair','release_not_sealed'
    raw=(OUT/'release.tar.gz').read_bytes()
    assert sha(raw)==plan['tar_sha256'],'reviewed_tar_changed'
    assert sha(Path(__file__).with_name('remote_operator.py').read_bytes())==plan['operator_sha256'],'reviewed_operator_changed'
    with tarfile.open(fileobj=io.BytesIO(raw),mode='r:gz') as stream:
        files={}
        for member in stream.getmembers():
            relative=PurePosixPath(member.name)
            assert member.isfile() and member.name not in files and not relative.is_absolute() and '..' not in relative.parts and '\\' not in member.name and ':' not in member.name,'unsafe_payload_member'
            files[member.name]=stream.extractfile(member).read()
    payload=json.loads(files.pop('plan.json'))
    assert payload=={key:value for key,value in plan.items() if key!='tar_sha256'},'embedded_plan_changed'
    expected={'configuration.json':plan['configuration_sha256'],'archive_sync_before.sql':plan['old_sync_sha256'],'archive_sync_candidate.sql':plan['new_sync_sha256'],
              'daily_constraint.sql':plan['daily_constraint_sha256'],'daily_database_checks.py':plan['daily_checks_sha256'],
              'lottery_database_checks.py':plan['lottery_checks_sha256']}
    expected.update({'archive/'+name:digest for name,digest in plan['archive_files'].items()})
    assert {name:sha(raw) for name,raw in files.items()}==expected,'payload_manifest_changed'
    return plan,raw


def main(mode='check'):
    plan,raw=checked()
    if mode=='check':
        print(json.dumps(dict(status='LOCAL_RELEASE_VERIFIED',bundle=plan['bundle'],archive_release=plan['archive_release'],tar_sha256=plan['tar_sha256'],remote_executed=False)))
        return
    spec=importlib.util.spec_from_file_location('points_operator_transport',ROOT/'tools/shop_pricing_half_20261017/remote.py')
    transport=importlib.util.module_from_spec(spec);spec.loader.exec_module(transport)
    transport.OUT=OUT/'remote'
    stage='/tmp/survival-points-daily-unique-20261019-v3-'+plan['tar_sha256'][:12]
    source='STAGE='+repr(stage)+'\nMODE='+repr(mode)+'\n'
    if mode=='upload':
        source+='PAYLOAD='+repr(base64.b64encode(raw).decode())+'\nEXPECTED='+repr(plan['tar_sha256'])+'\n'
        source+=r'''
from pathlib import Path,PurePosixPath
import base64,hashlib,io,json,tarfile
directory=Path(STAGE);assert not directory.is_symlink(),'stage_symlink'
directory.mkdir(mode=0o700,exist_ok=True);directory.chmod(0o700)
raw=base64.b64decode(PAYLOAD,validate=True);assert hashlib.sha256(raw).hexdigest()==EXPECTED,'upload_digest_changed'
with tarfile.open(fileobj=io.BytesIO(raw),mode='r:gz') as stream:
 seen=set()
 for member in stream.getmembers():
  relative=PurePosixPath(member.name)
  assert member.isfile() and member.name not in seen and not relative.is_absolute() and '..' not in relative.parts and '\\' not in member.name and ':' not in member.name,'unsafe_payload_member'
  seen.add(member.name);target=directory/member.name
  for parent in [target,*target.parents]:
   if parent==directory.parent:break
   assert not parent.is_symlink(),'stage_parent_symlink'
  target.parent.mkdir(mode=0o700,parents=True,exist_ok=True)
  raw=stream.extractfile(member).read()
  if target.exists():assert target.read_bytes()==raw,'immutable_stage_changed'
  else:target.write_bytes(raw)
  target.chmod(0o600)
print(json.dumps(dict(status='UPLOADED_NOT_DEPLOYED',database_writes=0,pointer_changes=0)))
'''
    else:
        source+=Path(__file__).with_name('remote_operator.py').read_text('utf-8-sig')
    with contextlib.redirect_stdout(io.StringIO()):
        report=transport.execute(source,mode,timeout=300)
    print(json.dumps(report['records'][-1],ensure_ascii=False))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode',choices=('check','upload','backup','prepare','validate','activate','verify'),nargs='?',default='check')
    main(parser.parse_args().mode)
