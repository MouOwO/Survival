"""Read-only recovery/health and sanitized startup diagnostics; no service actions."""
from pathlib import Path
import contextlib
import importlib.util
import io
import json

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'output/points_daily_unique_20261019/release_v2'
plan = json.loads((OUT / 'plan.json').read_bytes())
stage = '/tmp/survival-points-daily-unique-20261019-v2-' + plan['tar_sha256'][:12]
source = 'STAGE=' + repr(stage) + '\nPLAN=' + repr({key: plan[key] for key in ('parent_bundle', 'bundle', 'old_sync_sha256', 'new_sync_sha256', 'payment_catalog_hash')}) + '\n' + r'''
from pathlib import Path
import hashlib,json,re,subprocess,sys,urllib.request
sys.dont_write_bytecode=True
archive=Path('/opt/goufayu/releases/current').resolve(strict=True)
payment=Path('/opt/goufayu/payments/current').resolve(strict=True)
stage=Path(STAGE)
health={}
for name,port in [('archive',8765),('payments',8766)]:
 try:
  with urllib.request.urlopen('http://127.0.0.1:'+str(port)+'/health',timeout=2) as response:
   raw=json.load(response);health[name]={'status':response.status,'ok':raw.get('ok') is True}
 except Exception as error:health[name]={'ok':False,'error_type':type(error).__name__}
files={}
intent=None
for name in ('database_commit_intent','database_committed','database_rollback','rollback','activated','validated','prepared'):
 path=stage/(name+'.json')
 if not path.exists():continue
 value=json.loads(path.read_bytes())
 if name=='database_commit_intent':intent=value
 safe={key:value[key] for key in ('status','bundle','run_id','changed_accounts','changed_items','converted_points') if key in value}
 if 'result' in value:safe['result']={key:value['result'][key] for key in ('run_id','rolled_back_accounts') if key in value['result']}
 if 'database' in value:
  db=value['database'];safe['database']={key:db[key] for key in ('published','durable_player_updates','payment_updates','orders_created') if key in db}
  if 'repair' in db:safe['database']['repair']={key:db['repair'][key] for key in ('run_id','changed_accounts','changed_items','converted_points') if key in db['repair']}
 files[name]=safe
state=subprocess.run(['systemctl','show','goufayu-api.service','-p','ActiveState','-p','SubState','-p','Result','-p','ExecMainStatus','-p','ExecMainCode','-p','NRestarts'],capture_output=True,text=True,timeout=10)
systemd=dict(line.split('=',1) for line in state.stdout.splitlines() if '=' in line)
journal=subprocess.run(['journalctl','-u','goufayu-api.service','-n','180','--no-pager','-o','cat'],capture_output=True,text=True,timeout=10).stdout
errors=[];frames=[]
for line in journal.splitlines():
 match=re.match(r'^\s*File "(/opt/goufayu/[A-Za-z0-9_./-]+\.py)", line ([0-9]+), in ([A-Za-z0-9_<>]+)',line)
 if match:frames.append({'file':Path(match.group(1)).name,'line':int(match.group(2)),'function':match.group(3)})
 match=re.search(r'\b([A-Za-z_][A-Za-z0-9_.]*(?:Error|Exception)):\s*(.*)',line)
 if match:
  detail=match.group(2).strip()
  code=detail if re.fullmatch(r'[A-Za-z_][A-Za-z0-9_.:-]{0,140}',detail) else 'details_suppressed'
  errors.append({'type':match.group(1),'code':code})
database={}
sys.path.insert(0,str(payment))
from deploy import connection
with connection() as conn:
 conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY')
 conn.execute('SET ROLE goufayu_owner')
 definition=conn.execute("SELECT pg_get_functiondef('public.archive_sync_config(text,jsonb)'::regprocedure)").fetchone()[0]
 digest=hashlib.sha256(definition.encode()).hexdigest()
 database['sync_state']='BASELINE' if digest==PLAN['old_sync_sha256'] else 'CANDIDATE' if digest==PLAN['new_sync_sha256'] else 'UNKNOWN'
 database['constraint_present']=conn.execute("SELECT 1 FROM pg_constraint WHERE conrelid='public.player_archive_state'::regclass AND conname='archive_unique_points_20261019_check'").fetchone() is not None
 database['payment_catalog_unchanged']=conn.execute('SELECT catalog_hash FROM payments.catalog_state WHERE singleton').fetchone()[0]==PLAN['payment_catalog_hash']
 counts=conn.execute("SELECT coalesce(archive->'daily_rewards'->'item_counts','{}'::jsonb) FROM public.player_archive_state").fetchall()
 multiple=extra=0
 for (items,) in counts:
  values=[int(v) for key,v in items.items() if key.startswith('daily_')]
  if any(n>1 for n in values):multiple+=1
  extra+=sum(max(0,n-1) for n in values)
 database.update(daily_multiple_accounts=multiple,daily_extra_copies=extra)
 if intent and conn.execute("SELECT to_regclass('public.archive_daily_unique_backups')").fetchone()[0] is not None:
  total,active,restored=conn.execute('SELECT count(*),count(*) FILTER(WHERE rolled_back_at IS NULL),count(*) FILTER(WHERE rolled_back_at IS NOT NULL) FROM public.archive_daily_unique_backups WHERE run_id=%s',(intent['run_id'],)).fetchone()
  database['repair_run']={'total_accounts':total,'active_accounts':active,'rolled_back_accounts':restored}
 conn.rollback()
print(json.dumps({'status':'READONLY_ACTIVATION_DIAGNOSTIC','archive_release':archive.name,'archive_bundle':json.loads((archive/'addon/server/bundles/current.json').read_bytes())['hash'],
 'payment_release':payment.name,'health':health,'stage':files,'systemd':systemd,'startup_errors':errors[-20:],'traceback_frames':frames[-20:],
 'database':database,'database_writes':0,'service_actions':0,'individual_account_ids_exported':False}))
'''


def main():
    spec = importlib.util.spec_from_file_location('daily_diagnostic_transport', ROOT / 'tools/shop_pricing_half_20261017/remote.py')
    transport = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(transport)
    transport.OUT = OUT / 'remote'
    with contextlib.redirect_stdout(io.StringIO()):
        result = transport.execute(source, 'activation_diagnostic', timeout=60)
    print(json.dumps(result['records'][0], ensure_ascii=False))


if __name__ == '__main__':
    main()
