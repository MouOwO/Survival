"""Host operator: clone verified current archive release, apply only reviewed bundle.

Run with the existing payment virtualenv. Staging never changes the current
release. Validation always rolls back; activation keeps additive compatibility
if service health fails and restores the previous code pointer.
"""
from pathlib import Path
import fcntl,hashlib,importlib.util,json,os,secrets,shutil,subprocess,sys,time

BASE=Path('/opt/goufayu/releases')
OLD=BASE/'20261010-endless-batch-v1'
TARGET=BASE/'20261015-video-bundles-v1'
PAY=Path('/opt/goufayu/payments/20261015-payment01')
STAGE=Path('/tmp/survival-video-bundles-20261015')

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def load(name,p):
 spec=importlib.util.spec_from_file_location(name,p);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m

def expected_current():
 if (BASE/'current').resolve()!=OLD:raise RuntimeError('archive_release_changed_since_review')

def manifest_check(directory,manifest):
 for name,digest in manifest['files'].items():
  p=directory/name
  if Path(name).is_absolute() or '..' in Path(name).parts or p.is_symlink() or not p.is_file() or sha(p)!=digest:raise RuntimeError('archive_manifest_mismatch:'+name)

def prepare(report):
 expected_current();old=json.loads((OLD/'release_manifest.json').read_text());manifest_check(OLD,old)
 for name,digest in report['baseline_manifest_files'].items():
  if old['files'].get(name)!=digest:raise RuntimeError('baseline_manifest_changed')
 digest=report['candidate_hash'];bundle=STAGE/'archive_bundle_overlay'/digest
 data=json.loads((bundle/'bundle.json').read_text())
 if sha(bundle/'bundle.json')!=digest:raise RuntimeError('candidate_bundle_digest_mismatch')
 for name,source in data['sources'].items():
  p=bundle/name
  if p.is_symlink() or p.read_text()!=source:raise RuntimeError('candidate_source_mismatch')
 if TARGET.exists():raise RuntimeError('named_archive_target_exists')
 TARGET.mkdir(mode=0o755)
 for name in old['files']:
  source=OLD/name;dest=TARGET/name;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,dest)
 for p in bundle.rglob('*'):
  if p.is_symlink():raise RuntimeError('candidate_symlink_refused')
  if p.is_file():
   dest=TARGET/'addon/server/bundles'/digest/p.relative_to(bundle);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dest);dest.chmod(0o644)
 (TARGET/'addon/server/bundles/current.json').write_text(json.dumps({'hash':digest,'protocol':1}))
 old['release']=TARGET.name;old['archive_bundle']=digest;old['previous_release']=OLD.name
 old['files']={p.relative_to(TARGET).as_posix():sha(p) for p in TARGET.rglob('*') if p.is_file()}
 changed=[n for n in report['baseline_manifest_files'] if old['files'].get(n)!=report['baseline_manifest_files'][n]]
 if changed!=['addon/server/bundles/current.json']:raise RuntimeError('unrelated_archive_file_changed')
 (TARGET/'release_manifest.json').write_text(json.dumps(old,ensure_ascii=False,indent=2)+'\n')
 (TARGET/'.venv').symlink_to(OLD/'.venv',target_is_directory=True)
 manage=load('reviewed_archive_manage',TARGET/'deploy/manage.py');manage.validated_release(str(TARGET))
 return {'prepared':TARGET.name,'candidate_hash':digest,'existing_files_changed':changed,'all_original_backend_code_preserved':True}

def verify_prepared(report):
 manifest=json.loads((TARGET/'release_manifest.json').read_text());manifest_check(TARGET,manifest)
 if manifest['archive_bundle']!=report['candidate_hash']:raise RuntimeError('prepared_bundle_changed')
 for name,digest in report['baseline_manifest_files'].items():
  if name!='addon/server/bundles/current.json' and sha(TARGET/name)!=digest:raise RuntimeError('prepared_original_source_changed')
 if sha(TARGET/'addon/server/bundles'/report['candidate_hash']/'bundle.json')!=report['candidate_hash']:raise RuntimeError('prepared_bundle_hash_changed')
 payment_manifest=PAY/'manifest.json'
 if sha(payment_manifest)!=report['payment_manifest_sha256']:raise RuntimeError('prepared_payment_manifest_changed')
 for name,digest in json.loads(payment_manifest.read_text()).items():
  p=PAY/name
  if Path(name).is_absolute() or '..' in Path(name).parts or p.is_symlink() or sha(p)!=digest:raise RuntimeError('prepared_payment_source_changed')

def database_review(report,commit=False):
 verify_prepared(report)
 sys.path.insert(0,str(PAY));from deploy import connection
 from payment_backend.upgrade_commerce_bundles import preserved_state
 sys.path.insert(0,str(TARGET/'backend'));from archive_backend.bundle import Bundle
 bundle=Bundle(TARGET/'addon/server/bundles'/report['candidate_hash'])
 cfg={'configs':bundle.configs,'compatible_config_hashes':{k:{n:sorted(v) for n,v in rule.items()} for k,rule in bundle.compatible_config_hashes.items()}}
 sql_path=STAGE/report['compatibility_sql_file']
 if sha(sql_path)!=report['compatibility_sql_sha256']:raise RuntimeError('compatibility_sql_transfer_mismatch')
 with connection() as c:
  try:
   c.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ');c.execute("SET lock_timeout='5s'");c.execute('SET ROLE goufayu_owner')
   current=c.execute("SELECT pg_get_functiondef('public.archive_sync_config(text,jsonb)'::regprocedure)").fetchone()[0]
   if hashlib.sha256(current.encode()).hexdigest() not in (report['previous_function_sha256'],report['patched_function_sha256']):raise RuntimeError('archive_sync_function_changed_since_review')
   before=preserved_state(c);c.execute(sql_path.read_text())
   from psycopg.types.json import Jsonb
   result=c.execute('SELECT public.archive_sync_config(%s,%s)',(bundle.hash,Jsonb(cfg))).fetchone()[0]
   if result.get('ok') is not True or preserved_state(c)!=before:raise RuntimeError('archive_registration_modified_player_or_order_state')
   expected_current()
   if not commit:c.rollback()
  except BaseException:c.rollback();raise
 return {'config_registered':True,'existing_player_order_rewards_preserved':True,'rolled_back':not commit}

def activate(report):
 expected_current();checks=database_review(report)
 sys.path.insert(0,str(PAY));from deploy import backup
 backup();database_review(report,commit=True);expected_current()
 temp=BASE/('.video-bundles-'+secrets.token_hex(8));temp.symlink_to(TARGET,target_is_directory=True)
 try:
  os.replace(temp,BASE/'current')
  subprocess.run(['systemctl','restart','goufayu-api.service'],check=True,timeout=30)
  manage=load('reviewed_new_archive_manage',TARGET/'deploy/manage.py')
  for attempt in range(20):
   try:manage.health();break
   except Exception:
    if attempt==19:raise RuntimeError('archive_activation_health_failed')
    time.sleep(.5)
 except BaseException:
  if (BASE/'current').resolve()==TARGET:
   rollback=BASE/('.video-bundles-rollback-'+secrets.token_hex(8));rollback.symlink_to(OLD,target_is_directory=True);os.replace(rollback,BASE/'current')
   subprocess.run(['systemctl','restart','goufayu-api.service'],check=True,timeout=30)
   load('restored_archive_manage',OLD/'deploy/manage.py').health()
  raise
 finally:
  if temp.is_symlink():temp.unlink()
 return {'activated':TARGET.name,'archive_bundle':report['candidate_hash'],'existing_player_order_rewards_preserved':True,'gateway_orders_created':0,'rollback_validation':checks}

if __name__=='__main__':
 if os.geteuid()!=0:raise SystemExit('root_required')
 action=sys.argv[1];report=json.loads((STAGE/'archive_operator_input.json').read_text())
 with open('/var/lock/goufayu-video-bundles-20261015.lock','w') as guard:
  fcntl.flock(guard,fcntl.LOCK_EX|fcntl.LOCK_NB)
  if action=='prepare':result=prepare(report)
  elif action=='validate':expected_current();result=database_review(report)
  elif action=='activate':result=activate(report)
  else:raise RuntimeError('operator_action_required')
 print(json.dumps(result))
