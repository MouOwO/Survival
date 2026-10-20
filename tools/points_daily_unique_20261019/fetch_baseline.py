"""Read-only immutable baseline and anonymous preview of BOTH point inventories."""
from pathlib import Path
import base64
import contextlib
import importlib.util
import io
import json

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'output/points_daily_unique_20261019/release'

SOURCE = r'''
from pathlib import Path,PurePosixPath
from decimal import Decimal
import base64,hashlib,json,re,sys,urllib.request
sys.dont_write_bytecode=True
archive=Path('/opt/goufayu/releases/current').resolve(strict=True)
payment=Path('/opt/goufayu/payments/current').resolve(strict=True)
sha=lambda raw:hashlib.sha256(raw).hexdigest()
manifest_raw=(archive/'release_manifest.json').read_bytes()
manifest=json.loads(manifest_raw)
pointer=json.loads((archive/'addon/server/bundles/current.json').read_bytes())
digest=pointer['hash']
assert re.fullmatch('[0-9a-f]{64}',digest),'invalid_bundle_hash'
def public(name):
 p=PurePosixPath(name)
 assert not p.is_absolute() and '..' not in p.parts and '\\' not in name and ':' not in name,'unsafe_manifest_path'
 assert not any(word in name.lower() for word in ('.env','.pem','secret','password','private_key','config.json')),'private_file_refused'
 source=archive/name
 assert not source.is_symlink(),'release_symlink_refused'
 raw=source.read_bytes()
 assert sha(raw)==manifest['files'][name],'archive_manifest_drift'
 return raw
for name in manifest['files']:
 p=archive/name
 assert not p.is_symlink() and sha(p.read_bytes())==manifest['files'][name],'archive_manifest_drift'
bundle_name='addon/server/bundles/'+digest+'/bundle.json'
raw=public(bundle_name)
assert sha(raw)==digest,'bundle_changed'
data=json.loads(raw)
names=['addon/server/bundles/current.json',bundle_name,
 'backend/archive_backend/service.py','backend/archive_backend/bundle.py',
 'backend/archive_backend/config_compatibility.py','backend/archive_backend/commerce_catalog.py',
 'backend/archive_backend/unique_points.py']
exports={name:base64.b64encode(public(name)).decode() for name in names if name in manifest['files']}
exports['release_manifest.json']=base64.b64encode(manifest_raw).decode()
daily={r['item_id']:r for r in data['configs']['archive_daily_items']['rows'] if r.get('enabled') is not False}
lottery={r['item_id']:r for r in data['configs']['lottery_item_definitions']['rows']
 if r.get('enabled') is not False and r.get('item_type')=='积分道具'}
literal=re.search(r'local aliases\s*=\s*\{(.*?)\n\}',data['sources']['config/content_id_aliases.lua'],re.S)
assert literal,'aliases_missing'
aliases=dict(re.findall(r'^\s*([A-Za-z0-9_]+)\s*=\s*"([A-Za-z0-9_]+)"\s*,?\s*$',literal.group(1),re.M))
rules={r['field_id']:r for r in data['configs']['player_gameplay_stats']['rows']}
rates={'N':5,'R':25,'SR':100,'SSR':400,'UR':1000}
def quantity(value):
 n=Decimal(str(value))
 assert n.is_finite() and n>=0 and n==int(n),'invalid_saved_quantity'
 return int(n)
def number(value):
 n=Decimal(str(value))
 assert n.is_finite(),'invalid_saved_stat'
 return n
def serial(value):
 if isinstance(value,Decimal):return int(value) if value==int(value) else float(value)
 raise TypeError('unsupported_public_value')
daily_totals={key:dict(id=key,name=r['display_name'],quality=r['quality'],old_max_owned=r['max_owned'],
 duplicate_points=rates[r['quality'].upper()],owned_accounts=0,multiple_accounts=0,previous_copies=0,extra_copies=0,converted_points=0,
 effects=[dict(field=f,value=number(v),maximum=rules[f].get('max_value'),minimum=rules[f].get('min_value'),
 database_column_present=False) for f,v in zip(r['effect_ids'],r['effect_values'])]) for key,r in daily.items()}
lottery_totals={}
daily_inventory_totals={}
field_totals={}
accounts=daily_accounts=daily_multiple=lottery_multiple=both_multiple=0
missing_stats=insufficient_accounts=bounded_accounts=0
sys.path.insert(0,str(payment))
from deploy import connection
with connection() as conn:
 conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY')
 assert conn.execute('SELECT current_database()').fetchone()[0]=='goufayu_test','database_scope_changed'
 columns={r[0] for r in conn.execute("SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name='player_gameplay_stats'")}
 for row in daily_totals.values():
  for effect in row['effects']:effect['database_column_present']=effect['field'] in columns
 rows=conn.execute("""SELECT s.content_inventory,coalesce(s.archive,'{}'::jsonb),
   to_jsonb(g)-'player_id'-'created_at'-'updated_at'
   FROM public.player_archive_state s
   LEFT JOIN public.player_gameplay_stats g ON g.player_id=s.account_id""")
 for inventory,saved,stats in rows:
  accounts+=1
  counts=((saved.get('daily_rewards') or {}).get('item_counts') or {})
  has_daily=False;daily_extra=False;lottery_extra=False;deductions={};total_daily={};bounded=False
  for key,item in daily.items():
   count=quantity(counts.get(key,0));row=daily_totals[key]
   if count:row['owned_accounts']+=1;has_daily=True
   for effect in row['effects']:
    field=effect['field']
    total_daily[field]=total_daily.get(field,Decimal(0))+effect['value']*count
   excess=max(0,count-1)
   row['previous_copies']+=count
   if not excess:continue
   row['multiple_accounts']+=1;row['extra_copies']+=excess
   row['converted_points']+=excess*row['duplicate_points'];daily_extra=True
   for effect in row['effects']:
    field=effect['field'];delta=effect['value']*excess
    deductions[field]=deductions.get(field,Decimal(0))+delta
    bounded=bounded or effect['maximum'] is not None or field=='starjoy_points'
  if has_daily:daily_accounts+=1
  aggregate={}
  for key,value in inventory.items():
   key=aliases.get(key,key)
   if key in daily and quantity(value)>0:
    row=daily_inventory_totals.setdefault(key,dict(id=key,owned_accounts=0,copies=0,accounts_also_in_daily_counts=0))
    row['owned_accounts']+=1;row['copies']+=quantity(value)
    if quantity(counts.get(key,0))>0:row['accounts_also_in_daily_counts']+=1
   if key in lottery:aggregate[key]=aggregate.get(key,0)+quantity(value)
  for key,count in aggregate.items():
   excess=max(0,count-1)
   if not excess:continue
   lottery_extra=True
   row=lottery_totals.setdefault(key,dict(id=key,multiple_accounts=0,extra_copies=0,converted_points=0))
   row['multiple_accounts']+=1;row['extra_copies']+=excess
   row['converted_points']+=excess*lottery[key]['duplicate_points']
  if daily_extra:daily_multiple+=1
  if lottery_extra:lottery_multiple+=1
  if daily_extra and lottery_extra:both_multiple+=1
  if not daily_extra:continue
  if stats is None:missing_stats+=1
  insufficient=False
  for field,delta in deductions.items():
   row=field_totals.setdefault(field,dict(field=field,affected_accounts=0,proposed_remove=Decimal(0),
       insufficient_accounts=0,maximum=rules[field].get('max_value'),minimum=rules[field].get('min_value'),
       default=rules[field].get('default_value'),existing_aggregate=Decimal(0),total_daily_contribution=Decimal(0),
       exact_unbounded_additive=rules[field].get('max_value') is None and field!='starjoy_points'))
   row['affected_accounts']+=1;row['proposed_remove']+=delta
   row['total_daily_contribution']+=total_daily.get(field,Decimal(0))
   if stats is None or field not in stats:
    insufficient=True;row['insufficient_accounts']+=1;continue
   actual=number(stats[field]);row['existing_aggregate']+=actual
   minimum=number(rules[field].get('min_value',0));default=number(rules[field].get('default_value',0))
   if actual-delta<minimum or actual-default<total_daily.get(field,Decimal(0)):
    insufficient=True;row['insufficient_accounts']+=1
  if insufficient:insufficient_accounts+=1
  if bounded:bounded_accounts+=1
 definition=conn.execute("SELECT pg_get_functiondef('public.archive_sync_config(text,jsonb)'::regprocedure)").fetchone()[0]
 catalog_hash=conn.execute('SELECT catalog_hash FROM payments.catalog_state WHERE singleton').fetchone()[0]
 configs={r[0]:sha(json.dumps(r[1],ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()) for r in conn.execute('SELECT config_hash,config FROM public.archive_config_sets')}
 conn.rollback()
health={}
for name,port in [('archive',8765),('payments',8766)]:
 with urllib.request.urlopen('http://127.0.0.1:'+str(port)+'/health',timeout=10) as response:
  assert response.status==200 and json.load(response).get('ok') is True,'unhealthy_service'
  health[name]=True
preview=dict(storage=['public.player_archive_state.content_inventory','public.player_archive_state.archive.daily_rewards.item_counts'],
 scanned_accounts=accounts,daily_catalog_count=len(daily),lottery_catalog_count=len(lottery),daily_owned_accounts=daily_accounts,
 daily_multiple_accounts=daily_multiple,lottery_multiple_accounts=lottery_multiple,both_multiple_accounts=both_multiple,
 daily_extra_copies=sum(r['extra_copies'] for r in daily_totals.values()),daily_converted_points=sum(r['converted_points'] for r in daily_totals.values()),
 lottery_extra_copies=sum(r['extra_copies'] for r in lottery_totals.values()),lottery_converted_points=sum(r['converted_points'] for r in lottery_totals.values()),
 daily_items=list(daily_totals.values()),lottery_items=list(lottery_totals.values()),daily_top_level_inventory=list(daily_inventory_totals.values()),
 daily_stat_deductions=list(field_totals.values()),missing_stats_accounts=missing_stats,insufficient_stat_accounts=insufficient_accounts,
 bounded_or_loyalty_effect_accounts=bounded_accounts,
 exact_deduction_scope='Unbounded additive stats only; capped effects and loyalty progression require explicit review',
 database_writes=0,orders_created=0,individual_account_ids_exported=False)
print(json.dumps(dict(status='READONLY_DAILY_UNIQUE_PREFLIGHT_PASS',archive_release=archive.name,payment_release=payment.name,
 archive_bundle=digest,archive_manifest_sha256=sha(manifest_raw),payment_manifest_sha256=sha((payment/'manifest.json').read_bytes()),
 archive_manifest=manifest,functions={'public.archive_sync_config(text,jsonb)':dict(definition=definition,sha256=sha(definition.encode()))},
 export_files=exports,catalog_hash=catalog_hash,config_rows=configs,health=health,inventory_preview=preview,
 database_writes=0,orders_created=0,gateway_requests=0),ensure_ascii=False,default=serial))
'''


def main():
    spec = importlib.util.spec_from_file_location('daily_unique_readonly_transport', ROOT / 'tools/shop_pricing_half_20261017/remote.py')
    transport = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(transport)
    transport.OUT = OUT / 'remote'
    with contextlib.redirect_stdout(io.StringIO()):
        result = transport.execute(SOURCE, 'preflight', timeout=90)
    record = result['records'][0]
    for name, encoded in record['export_files'].items():
        relative = Path(name)
        assert not relative.is_absolute() and '..' not in relative.parts
        target = OUT / 'baseline' / relative
        raw = base64.b64decode(encoded, validate=True)
        if target.exists():
            assert target.read_bytes() == raw, 'immutable_baseline_changed'
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(raw)
    (OUT / 'inventory_preview.json').write_text(json.dumps(record['inventory_preview'], ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({key: record[key] for key in ('status', 'archive_release', 'payment_release', 'archive_bundle', 'health')}, ensure_ascii=False))
    summary = record['inventory_preview']
    print(json.dumps({key: summary[key] for key in ('scanned_accounts', 'daily_multiple_accounts', 'lottery_multiple_accounts',
        'daily_extra_copies', 'daily_converted_points', 'missing_stats_accounts', 'insufficient_stat_accounts',
        'bounded_or_loyalty_effect_accounts', 'database_writes', 'individual_account_ids_exported')}, ensure_ascii=False))


if __name__ == '__main__':
    main()
