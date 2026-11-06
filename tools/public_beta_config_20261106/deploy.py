"""Prepare/probe/register exactly one WS4 config. Default plan is local only.

No service operation, environment access, credential access, player read/write,
or automatic retry. A later API rollback must retain this added config/branch.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = next(path for path in HERE.parents if (path / 'AGENTS.md').is_file())
PREFIX = 'tools/public_beta_config_20261106/'
FILES = ('recipe.py', 'deploy.py', 'archive_sync_config.parent.sql')
TRANSPORT = ROOT / 'tools/archive_release_20261029/server_deploy.py'
TRANSPORT_SHA = '66413c174fb6fe27d5ae84dc267ceea07366c6f6a855a9406e5ffdaf388b1cc5'
OUTPUT = ROOT / 'output/public_beta_config_20261106_v01'


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    exec(compile(path.read_bytes(), str(path), 'exec'), module.__dict__)
    return module


recipe = load('public_beta_exact_config_recipe', HERE / 'recipe.py')

REMOTE = r'''
from pathlib import Path
import base64,contextlib,fcntl,hashlib,json,os,re,subprocess
sha=lambda raw:hashlib.sha256(raw).hexdigest()
def need(ok,code):
 if not ok:raise RuntimeError(code)
base=Path('/opt/goufayu-ws4/deployment_records')
need(re.fullmatch(r'20261106-public-beta-config-[a-f0-9]{12}',BINDING.get('record_name','')) is not None,'config_record_binding_required')
record=base/BINDING['record_name']
parent=Path('/opt/goufayu-ws4/releases')/BINDING['parent_release']
need(parent.is_dir() and parent.resolve()==parent and sha((parent/'release_manifest.json').read_bytes())==BINDING['parent_manifest_sha256'],'parent_release_changed')
need(BINDING['recipe']=='public-beta-exact-config-v1' and BINDING['source_bundle']=='f8ab7087c042cc82f43555500e134262211062e78c88190b6691dcce57ebff42','exact_config_recipe_required')
values={name:base64.b64decode(value,validate=True) for name,value in ARTIFACTS.items()}
need(set(values)=={'archive_sync_config.parent.sql','archive_sync_config.candidate.sql','config.json','probe.sql','activate.sql','verify.sql'},'exact_config_artifacts_required')
need({name:sha(raw) for name,raw in values.items()}==BINDING['artifacts'],'config_artifact_binding_changed')

def canonical(value):return json.dumps(value,sort_keys=True,separators=(',',':')).encode()
def safe_read(name):
 path=record/name
 need(path.is_file() and not path.is_symlink() and path.resolve().parent==record,'config_record_file_scope')
 return path.read_bytes()
def write_new(name,raw):
 need('/' not in name and '\\' not in name and name not in ('.','..'),'record_name_scope')
 with (record/name).open('xb') as stream:stream.write(raw);stream.flush();os.fsync(stream.fileno())
 (record/name).chmod(0o600)
def validate():
 need(base.is_dir() and not base.is_symlink() and record.is_dir() and not record.is_symlink(),'config_record_scope')
 need(json.loads(safe_read('binding.json'))==BINDING,'prepared_config_binding_changed')
 for name,raw in values.items():need(safe_read(name)==raw,'prepared_config_artifact_changed')
 need(json.loads(safe_read('function.metadata.json'))==BINDING['function_metadata'],'function_metadata_backup_changed')
def execute_sql(sql):
 need(isinstance(sql,str) and '\0' not in sql and len(sql.encode())<=8388608,'config_sql_budget')
 args=['podman','exec','-i','--user','postgres','--env','PGPASSFILE=/dev/null','--env','PGSERVICEFILE=/dev/null',
  'goufayu-ws4-db','psql','-X','-w','-qAt','-v','ON_ERROR_STOP=1','-U','postgres','-d','goufayu_ws4']
 result=subprocess.run(args,input=sql.encode(),stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=45)
 need(result.returncode==0,'exact_config_sql_failed_no_retry')
 try:value=json.loads(result.stdout)
 except Exception:raise RuntimeError('config_sql_receipt_invalid')
 need(value.get('ok') is True,'config_sql_check_failed')
 return value
def parent_active():
 raw=subprocess.check_output(['systemctl','show','goufayu-ws4.service','--property=MainPID,WorkingDirectory,ActiveState'],text=True,timeout=10)
 state=dict(row.split('=',1)for row in raw.splitlines()if '=' in row);pid=int(state.get('MainPID','0'))
 need(pid>0 and state.get('ActiveState')=='active' and Path(state.get('WorkingDirectory','')).resolve()==parent/'backend','config_parent_not_active')
 need(Path(os.readlink('/proc/%d/cwd'%pid)).resolve()==parent/'backend','config_process_lineage_changed')
def readonly(sql,status):
 return "BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;\nSET LOCAL statement_timeout='10000ms';\nSET LOCAL lock_timeout='1000ms';\n"+sql+"\nROLLBACK;\nSELECT json_build_object('ok',true,'status','"+status+"');\n"

with contextlib.ExitStack() as stack:
 for name in sorted(('/var/lock/goufayu_admission_five.lock','/var/lock/goufayu_ws4_worker_cache.lock')):
  lock=stack.enter_context(open(name,'a'));fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
 if MODE=='prepare':
  parent_active()
  need(not record.exists() and not base.is_symlink(),'preserve_existing_config_records')
  execute_sql(readonly(PARENT_GUARD,'CONFIG_PARENT_BASELINE_VERIFIED'))
  base.mkdir(mode=0o700,exist_ok=True)
  need(base.stat().st_uid==os.geteuid() and base.stat().st_mode&0o077==0,'config_control_permissions')
  record.mkdir(mode=0o700)
  for name,raw in values.items():write_new(name,raw)
  write_new('binding.json',canonical(BINDING));write_new('function.metadata.json',canonical(BINDING['function_metadata']))
  validate()
  result=dict(ok=True,status='PUBLIC_BETA_CONFIG_PREPARED_NOT_REGISTERED',database_writes=0)
 else:
  validate();need(not (record/(MODE+'.json')).exists(),'preserve_existing_config_receipt')
  if MODE=='probe':
   parent_active();result=execute_sql(values['probe.sql'].decode())
   need(result.get('status')=='PUBLIC_BETA_EXACT_CONFIG_PG_PROBE_PASS'
    and result.get('canonical_function_sha256')==BINDING['candidate_function_sha256'],'pg_exact_candidate_probe_required')
  elif MODE=='activate':
   parent_active();probe=json.loads(safe_read('probe.json'))
   need(probe.get('binding')==BINDING and probe.get('status')=='PUBLIC_BETA_EXACT_CONFIG_PG_PROBE_PASS'
    and probe.get('persistent_writes')==0 and probe.get('transaction_rollback_verified') is True,'isolated_pg_probe_required')
   write_new('activation.intent.json',canonical(dict(binding=BINDING,status='CONFIG_REGISTRATION_INTENT_NOT_COMPLETION')))
   result=execute_sql(values['activate.sql'].decode())
   need(result.get('status')=='PUBLIC_BETA_EXACT_CONFIG_REGISTERED','exact_registration_receipt_required')
  elif MODE=='verify':
   result=execute_sql(readonly(values['verify.sql'].decode(),'PUBLIC_BETA_CONFIG_ACTIVE_VERIFIED'))
   result.update(config_registration_verified=True,read_only=True,database_writes=0)
  else:raise RuntimeError('fixed_config_phase_required')
 result.update(binding=BINDING,player_rows_read=0,player_rows_written=0,service_changes=0,
  config_retained_on_api_rollback=True,credentials_read=False)
 write_new(MODE+'.json',canonical(result))
 print(json.dumps(result))
'''


def inputs(source, operator):
    operator_pins = {}
    for name in FILES:
        raw = recipe.git_blob(operator, PREFIX + name)
        recipe.need(raw == (HERE / name).read_bytes().replace(b'\r\n', b'\n'), 'operator_worktree_drift')
        operator_pins[PREFIX + name] = sha(raw)
    artifacts, binding = recipe.artifacts(source)
    binding.update(operator_revision=operator, operator_files=operator_pins)
    binding['record_name']='20261106-public-beta-config-'+sha(recipe.canonical(binding))[:12]
    return artifacts, binding


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', nargs='?', default='plan', choices=('plan','prepare','probe','activate','verify'))
    parser.add_argument('--source-revision')
    parser.add_argument('--operator-revision')
    args = parser.parse_args()
    if args.mode == 'plan':
        print(json.dumps(dict(status='EXACT_WS4_CONFIG_PLAN_NOT_EXECUTED',new_bundle=recipe.NEW_BUNDLE,
            new_function_sha256=sha(recipe.derive_function(recipe.parent_function())),
            config_jsonb_sha256=recipe.PG_CONFIG_SHA,remote_actions=0,
            phases=['prepare','probe','activate','verify'],player_data_changes=False,
            database_change='one exact function branch and one immutable config row; old rows retained',
            rollback='SQL failures roll back atomically; API rollback retains committed config admission'),indent=2));return 0
    recipe.need(sha(TRANSPORT.read_bytes())==TRANSPORT_SHA,'pinned_transport_changed')
    target=OUTPUT/(args.mode+'.json');recipe.need(not target.exists(),'preserve_local_config_receipt')
    values,binding=inputs(args.source_revision,args.operator_revision)
    context=dict(MODE=args.mode,BINDING=binding,ARTIFACTS={name:base64.b64encode(raw).decode()for name,raw in values.items()},
                 PARENT_GUARD=recipe.guard_sql(recipe.PARENT_FUNCTION,False))
    source='\n'.join(key+'='+repr(value)for key,value in context.items())+'\n'+REMOTE
    transport=load('fixed_ws4_config_transport',TRANSPORT)
    result=transport.remote(source,timeout=90)
    OUTPUT.mkdir(parents=True,exist_ok=True)
    with target.open('x',encoding='utf8')as stream:json.dump(result,stream,ensure_ascii=False,indent=2);stream.write('\n')
    print(json.dumps(result,ensure_ascii=False))
    return 0 if result.get('ok')is True else 2


if __name__=='__main__':
    raise SystemExit(main())
