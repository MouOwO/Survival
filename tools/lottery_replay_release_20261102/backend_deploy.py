"""Narrow receipt-projection API rollout. Default is a zero-effect plan.

Uses the existing pinned SSH transport. Two Python files only; no SQL, bundle,
payment, credential or player-data write. Preserve the full original release.
"""
from pathlib import Path
import argparse,base64,hashlib,importlib.util,json,re,subprocess,sys
ROOT=Path(__file__).resolve().parents[2]
TRANSPORT=ROOT/'tools/archive_release_20261029/server_deploy.py'
TRANSPORT_SHA='66413c174fb6fe27d5ae84dc267ceea07366c6f6a855a9406e5ffdaf388b1cc5'
PARENT='20261029-redemption-2f918e4c0edd'
PARENT_MANIFEST='a70ec3b61bc56321751892982f0a79c6244836348084e1e350b80b737fc76138'
SERVICE_SHA='b75684f5052930b579d5dc3e0df6004e83328ff171c75c650f5564b813998165'
REPORT=ROOT/'output/lottery_replay_release_20261102/backend'
sha=lambda raw:hashlib.sha256(raw).hexdigest()

REMOTE=r'''
from pathlib import Path,PurePosixPath
import base64,hashlib,json,os,shutil,subprocess,time,urllib.request
sha=lambda raw:hashlib.sha256(raw).hexdigest()
base=Path('/opt/goufayu/releases');current=base/'current';old=base/PARENT
assert old.is_dir() and not old.is_symlink() and old.parent==base
assert sha((old/'release_manifest.json').read_bytes())==PARENT_MANIFEST
manifest=json.loads((old/'release_manifest.json').read_bytes())
service='backend/archive_backend/service.py'
assert sha((old/service).read_bytes())==SERVICE_SHA
def safe(root,name):
 p=PurePosixPath(name);assert not p.is_absolute() and '..' not in p.parts
 target=root/name;assert not target.is_symlink() and target.resolve().is_relative_to(root.resolve());return target
def state(unit):return subprocess.check_output(['systemctl','show','--property=MainPID','--value',unit],text=True).strip()
payment=state('goufayu-payment.service');dbpid=state('goufayu-db.service')
for name,digest in manifest['files'].items():assert sha(safe(old,name).read_bytes())==digest
old_raw=(old/service).read_bytes();old_text=old_raw.decode('utf-8').replace('\r\n','\n')
needle='        result=self.finish_prepared(database_id,command["id"],prepared)\n        return self.app._public_response(result,database_id,account)'
assert old_text.count(needle)==1
replacement='        result=self.finish_prepared(database_id,command["id"],prepared)\n        reply=self.app._public_response(result,database_id,account)\n        from .lottery_receipt_snapshot import attach\n        return attach(self,reply,command,requested_hash)'
payloads={service:old_text.replace(needle,replacement).encode(),
 'backend/archive_backend/lottery_receipt_snapshot.py':base64.b64decode(HELPER,validate=True)}
for name,raw in payloads.items():compile(raw,name,'exec')
pins={name:sha(raw) for name,raw in payloads.items()}
new=base/('20261102-lottery-receipt-'+sha(json.dumps(pins,sort_keys=True).encode())[:12])
if MODE=='audit':
 print(json.dumps(dict(ok=True,status='READ_ONLY_RECEIPT_ROLLOUT_AUDIT',parent=PARENT,new_release=new.name,
  current=current.resolve().name,payload_sha256=pins,payment_pid=payment,db_pid=dbpid,mutations=0)))
elif MODE=='prepare':
 assert current.resolve()==old and not new.exists()
 originals=dict(manifest['files'])
 for source in (old/'backend').rglob('*.py'):
  if not source.is_symlink() and '__pycache__' not in source.parts:originals[source.relative_to(old).as_posix()]=sha(source.read_bytes())
 new.mkdir(mode=0o755)
 for name,digest in originals.items():
  source=safe(old,name);assert sha(source.read_bytes())==digest
  dest=safe(new,name);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,dest);dest.chmod(source.stat().st_mode&0o777)
 (new/'.venv').symlink_to(old/'.venv',target_is_directory=True)
 for name,raw in payloads.items():
  dest=safe(new,name);dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(raw);dest.chmod(0o644)
 prepared=dict(manifest);prepared.update(release=new.name,archive_parent=old.name,
  files={**originals,**pins},lottery_receipt_parent_manifest_sha256=PARENT_MANIFEST,
  lottery_receipt_source_revision=SOURCE,lottery_receipt_operator_revision=OPERATOR,
  lottery_receipt_changed_files=sorted(pins),database_changed=False)
 (new/'release_manifest.json').write_text(json.dumps(prepared,sort_keys=True,separators=(',',':')))
 assert state('goufayu-payment.service')==payment and state('goufayu-db.service')==dbpid
 print(json.dumps(dict(ok=True,status='RECEIPT_API_PREPARED_NOT_ACTIVE',release=new.name,parent=PARENT,
  manifest_sha256=sha((new/'release_manifest.json').read_bytes()),payload_sha256=pins,database_writes=0,payment_untouched=True)))
else:
 assert new.is_dir() and not new.is_symlink()
 prepared=json.loads((new/'release_manifest.json').read_bytes())
 assert prepared['lottery_receipt_source_revision']==SOURCE and prepared['lottery_receipt_operator_revision']==OPERATOR
 assert prepared['lottery_receipt_changed_files']==sorted(pins)
 for name,digest in prepared['files'].items():assert sha(safe(new,name).read_bytes())==digest
 assert all(prepared['files'][name]==digest for name,digest in pins.items())
 def health():
  with urllib.request.urlopen('http://127.0.0.1:8765/health',timeout=5) as response:assert response.status==200
 def restart():
  assert subprocess.run(['systemctl','restart','goufayu-api.service'],capture_output=True,timeout=45).returncode==0
  for attempt in range(40):
   try:health();return
   except Exception:
    if attempt==39:raise
    time.sleep(.5)
 def switch(target):
  temporary=base/('current.receipt.'+str(os.getpid()));assert not temporary.exists() and not temporary.is_symlink()
  temporary.symlink_to(target,target_is_directory=True);os.replace(temporary,current)
 if MODE=='activate':
  assert current.resolve()==old
  # Public read-only pending/online checks through the existing private connection; no rows exported.
  import sys
  sys.path.insert(0,str(Path('/opt/goufayu/payments/current').resolve()))
  from deploy import connection
  with connection() as conn:
   conn.execute('SET TRANSACTION READ ONLY')
   assert conn.info.dbname=='goufayu_test'
   assert conn.execute('SELECT count(*) FROM public.archive_operations WHERE NOT done').fetchone()[0]==0
   conn.rollback()
  switch(new)
  try:restart()
  except Exception:
   if current.resolve()==new:switch(old);restart()
   raise
 assert current.resolve()==new;health()
 assert state('goufayu-payment.service')==payment and state('goufayu-db.service')==dbpid
 print(json.dumps(dict(ok=True,status='RECEIPT_API_ACTIVE_VERIFIED',release=new.name,parent=PARENT,
  manifest_sha256=sha((new/'release_manifest.json').read_bytes()),payload_sha256=pins,
  source_revision=SOURCE,operator_revision=OPERATOR,api_pid=state('goufayu-api.service'),
  payment_pid=payment,db_pid=dbpid,database_writes=0,payment_untouched=True,original_release_preserved=True)))
'''


def git_blob(revision,name):
    if not re.fullmatch('[0-9a-f]{40}',revision or ''):raise ValueError('immutable_revision_required')
    return subprocess.check_output(['git','show',revision+':'+name],cwd=ROOT)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode',nargs='?',default='plan',choices=('plan','audit','prepare','activate','verify'))
    parser.add_argument('--source-revision');parser.add_argument('--operator-revision')
    args=parser.parse_args()
    if args.mode=='plan':print(json.dumps(dict(status='STATIC_RECEIPT_API_PLAN',files=2,database_writes=0,remote_actions=0)));return
    helper=git_blob(args.source_revision,'server/archive_backend/lottery_receipt_snapshot.py')
    own=git_blob(args.operator_revision,Path(__file__).relative_to(ROOT).as_posix())
    if own!=Path(__file__).read_bytes().replace(b'\r\n',b'\n'):raise ValueError('operator_worktree_drift')
    if sha(TRANSPORT.read_bytes())!=TRANSPORT_SHA:raise ValueError('pinned_transport_changed')
    spec=importlib.util.spec_from_file_location('receipt_pinned_transport',TRANSPORT)
    transport=importlib.util.module_from_spec(spec);spec.loader.exec_module(transport)
    context=dict(MODE=args.mode,PARENT=PARENT,PARENT_MANIFEST=PARENT_MANIFEST,SERVICE_SHA=SERVICE_SHA,
                 HELPER=base64.b64encode(helper).decode(),SOURCE=args.source_revision,OPERATOR=args.operator_revision)
    source='\n'.join(name+'='+repr(value) for name,value in context.items())+'\n'+REMOTE
    result=transport.remote(source,timeout=240)
    REPORT.mkdir(parents=True,exist_ok=True)
    path=REPORT/(args.mode+'.json')
    if path.exists():raise ValueError('preserve_existing_receipt_choose_new_operation')
    path.write_text(json.dumps(result,ensure_ascii=True,indent=2)+'\n',encoding='utf8')
    print(json.dumps(result))


if __name__=='__main__':main()
