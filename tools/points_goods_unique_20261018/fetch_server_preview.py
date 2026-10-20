"""Read-only inventory counts/repair totals from the existing server; no player IDs."""
from pathlib import Path
import importlib.util
import json
import subprocess

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('points_readonly_transport', ROOT/'tools/endless_leaderboard_20261016/deploy_driver.py')
transport = importlib.util.module_from_spec(spec)
spec.loader.exec_module(transport)
planner = (ROOT/'server/archive_backend/unique_points.py').read_text('utf-8-sig')
code = '''from pathlib import Path
from types import SimpleNamespace
import hashlib,json,sys
sys.dont_write_bytecode=True
archive=Path('/opt/goufayu/releases/current').resolve(strict=True)
payment=Path('/opt/goufayu/payments/current').resolve(strict=True)
digest=json.loads((archive/'addon/server/bundles/current.json').read_text())['hash']
directory=archive/'addon/server/bundles'/digest
raw=(directory/'bundle.json').read_bytes()
assert hashlib.sha256(raw).hexdigest()==digest
data=json.loads(raw)
planner={}
exec(PLANNER_SOURCE,planner)
items,aliases=planner['catalog'](SimpleNamespace(configs=data['configs'],directory=directory))
sys.path.insert(0,str(payment))
from deploy import connection
totals={}
accounts=changed=extra=converted=0
with connection() as conn:
 conn.execute('SET TRANSACTION READ ONLY')
 cursor=conn.execute("SELECT content_inventory,coalesce(archive,'{}'::jsonb) FROM public.player_archive_state")
 for inventory,saved in cursor:
  accounts+=1
  candidate=planner['preview'](inventory,saved,items,aliases)
  if not candidate['changed_items']:continue
  changed+=1
  converted+=candidate['converted_points']
  for detail in candidate['details']:
   row=totals.setdefault(detail['id'],{'id':detail['id'],'affected_accounts':0,'previous_copies':0,'extra_copies':0,'converted_points':0})
   row['affected_accounts']+=1
   row['previous_copies']+=detail['previous_count']
   row['extra_copies']+=detail['extra_copies']
   row['converted_points']+=detail['converted_points']
   extra+=detail['extra_copies']
 conn.rollback()
print(json.dumps({'status':'READ_ONLY_POINTS_INVENTORY_PREVIEW','archive_release':archive.name,'payment_release':payment.name,'archive_bundle':digest,
 'unique_item_count':len(items),'inventory_storage':'public.player_archive_state.content_inventory jsonb',
 'scanned_accounts':accounts,'changed_accounts':changed,'extra_copies':extra,'converted_points':converted,
 'items':sorted(totals.values(),key=lambda r:(-r['converted_points'],r['id'])),'database_writes':0,
 'orders_created':0,'individual_account_ids_exported':False},ensure_ascii=False))
'''.replace('PLANNER_SOURCE', repr(planner), 1)
result = subprocess.run(transport.options(), input=code.encode('utf-8'), capture_output=True,
                        cwd=ROOT, timeout=60, creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
out = ROOT/'design_refs/points_goods_unique_20261018/server'
out.mkdir(parents=True,exist_ok=True)
if result.returncode:
    # Diagnostic exception names suffice; do not print credentials or raw remote output.
    (out/'preview_error.txt').write_bytes(result.stderr)
    raise RuntimeError('Read-only server preview failed; diagnostics saved locally')
report=json.loads(result.stdout)
(out/'inventory_preview.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report,ensure_ascii=False))
