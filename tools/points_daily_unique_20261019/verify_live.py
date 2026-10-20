"""Read-only post-release verification of both inventories and the actual repair."""
from pathlib import Path
import importlib.util
import json
import subprocess
import sys

sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/points_daily_unique_20261019/release_v3'
plan=json.loads((OUT/'plan.json').read_bytes())
activated=json.loads((OUT/'remote/activate.json').read_bytes())['records'][-1]
assert activated['status']=='ACTIVATED' and activated['bundle']==plan['bundle']
run=activated['database']['repair']['run_id']
spec=importlib.util.spec_from_file_location('daily_readonly_transport',ROOT/'tools/endless_leaderboard_20261016/deploy_driver.py')
transport=importlib.util.module_from_spec(spec);spec.loader.exec_module(transport)
code='EXPECTED='+repr({key:plan[key] for key in ['archive_release','bundle','payment_release','payment_manifest_sha256']})+'\nRUN='+repr(run)+'\n'+r"""
from pathlib import Path
import hashlib,json,sys,urllib.request
sys.dont_write_bytecode=True
release=Path('/opt/goufayu/releases/current').resolve(strict=True)
payment=Path('/opt/goufayu/payments/current').resolve(strict=True)
assert release.name==EXPECTED['archive_release'] and payment.name==EXPECTED['payment_release']
assert hashlib.sha256((payment/'manifest.json').read_bytes()).hexdigest()==EXPECTED['payment_manifest_sha256']
sys.path[:0]=[str(release/'backend'),str(payment)]
from archive_backend.bundle import Bundle
from archive_backend import daily_unique,unique_points
from deploy import connection
digest=json.loads((release/'addon/server/bundles/current.json').read_bytes())['hash']
assert digest==EXPECTED['bundle']
bundle=Bundle(release/'addon/server/bundles'/digest)
daily,_=daily_unique.catalog(bundle);lottery,aliases=unique_points.catalog(bundle)
assert all(item['max_owned']==1 for item in daily)
scanned=0;max_daily=max_lottery=0;daily_extras=lottery_extras=0;growth=[]
with connection() as conn:
 conn.execute('SET TRANSACTION READ ONLY');conn.execute('SET LOCAL ROLE goufayu_owner')
 assert conn.execute("SELECT convalidated FROM pg_constraint WHERE conrelid='public.player_archive_state'::regclass AND conname='archive_unique_points_20261019_check'").fetchone()==(True,)
 assert conn.execute("SELECT has_function_privilege('goufayu_app','public.archive_unique_points_20261019_valid(jsonb,jsonb)','EXECUTE'),has_function_privilege('goufayu_owner','public.archive_unique_points_20261019_valid(jsonb,jsonb)','EXECUTE')").fetchone()==(False,True)
 assert conn.execute('SELECT count(*) FROM public.player_archive_state WHERE NOT public.archive_unique_points_20261019_valid(archive,content_inventory)').fetchone()==(0,)
 for archive,inventory in conn.execute('SELECT archive,content_inventory FROM public.player_archive_state'):
  scanned+=1;counts=archive.get('daily_rewards',{}).get('item_counts',{})
  for item in daily:
   value=counts.get(item['item_id'],0)
   assert type(value) in (int,float) and value in (0,1)
   max_daily=max(max_daily,value);daily_extras+=max(0,value-1)
  if counts.get('daily_growth_gem',0):growth.append(counts['daily_growth_gem'])
  totals={}
  for key,value in inventory.items():
   canonical=aliases.get(key,key)
   if canonical in lottery:totals[canonical]=totals.get(canonical,0)+value
  for value in totals.values():
   assert value in (0,1);max_lottery=max(max_lottery,value);lottery_extras+=max(0,value-1)
 assert daily_unique.plans(conn,bundle)[0]==[]
 backups=conn.execute('''SELECT before_archive,after_archive,before_stats,after_stats,inventory,details,converted_points
     FROM public.archive_daily_unique_backups WHERE run_id=%s AND rolled_back_at IS NULL''',(RUN,)).fetchall()
 converted=extras=0;removed={}
 for before,after,before_stats,after_stats,inventory,details,points in backups:
  projected=daily_unique.preview({'save':{'archive':before,'gameplay_stats':before_stats,'content_inventory':inventory}},bundle)
  assert projected['archive']==after and projected['gameplay_stats']==after_stats
  assert projected['converted_points']==points and projected['details']==details
  converted+=points;extras+=sum(item['extra_copies'] for item in details)
  for key,delta in projected['deltas'].items():removed[key]=removed.get(key,0)-delta
 assert len(backups)==3 and extras==16 and converted==400
 conn.rollback()
health={}
for name,port in [('archive',8765),('payment',8766)]:
 with urllib.request.urlopen('http://127.0.0.1:'+str(port)+'/health',timeout=10) as response:
  health[name]=response.status==200 and json.load(response).get('ok') is True
assert all(health.values())
print(json.dumps({'status':'LIVE_DAILY_UNIQUE_VERIFIED','archive_release':release.name,'bundle':digest,
 'daily_items':len(daily),'lottery_items':len(lottery),'scanned_accounts':scanned,
 'daily_extra_copies_remaining':daily_extras,'lottery_extra_copies_remaining':lottery_extras,
 'max_daily_count':max_daily,'max_lottery_count':max_lottery,'growth_gem_owners':len(growth),'growth_gem_counts':growth,
 'repaired_accounts':len(backups),'removed_extra_copies':extras,'credited_shop_points':converted,'removed_duplicate_effects':removed,
 'validated_database_constraint':True,'runtime_role_cannot_execute_constraint_helper':True,'backup_repair_matches_exact_preview':True,'health':health,
 'payment_unchanged':True,'database_writes':0,'individual_account_ids_exported':False},ensure_ascii=False))
"""
result=subprocess.run(transport.options(),input=code.encode('utf-8'),capture_output=True,cwd=ROOT,timeout=75,
                      creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
destination=ROOT/'design_refs/points_daily_unique_20261019/server';destination.mkdir(parents=True,exist_ok=True)
if result.returncode:
    (destination/'live_verify_error.txt').write_bytes(result.stderr)
    raise RuntimeError('Read-only post-release verification failed; diagnostics saved locally')
report=json.loads(result.stdout)
(destination/'live_verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report,ensure_ascii=False))
