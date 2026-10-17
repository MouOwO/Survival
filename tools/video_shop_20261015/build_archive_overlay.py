"""Build a scope-locked bundle from deployed 310; never edit active pointers."""
from pathlib import Path
import copy,csv,hashlib,io,json,sys
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'server'))
from archive_backend.bundle import read_csv
from payment_backend.csv_catalog import SOURCES,build,canonical,rows
from payment_backend.commerce_bundles import compile_commerce
from payment_backend.ucoin_catalog import compile_payment_catalog
BASE='310d3063f3e320b4d541b8715d3e2005b08a68aacfabdf471da9d1c85380fca4'
DEST=ROOT/'output/video_shop_20261015/release'
CONFIGS={'commerce_catalog','commerce_products','archive_vip_rewards','commerce_bundle_members','commerce_import_status'}
SOURCE_NAMES={'systems/commerce_settlement.lua','systems/archive_vip_rewards.lua'}
CSV_NAMES={'商城兑换系统/commerce_products.csv','商城兑换系统/commerce_bundle_members.csv','商城兑换系统/commerce_import_status.csv','存档系统/archive_vip_rewards.csv'}

def sha(raw):return hashlib.sha256(raw).hexdigest()
def write_json(path,data):path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(canonical(data))
def main():
 basepath=ROOT/'server/bundles'/BASE/'bundle.json';raw=basepath.read_bytes();assert sha(raw)==BASE
 base=json.loads(raw);data=copy.deepcopy(base)
 game=(ROOT/'scripts/vscripts/config/generated/archive_http_bundle.lua').read_bytes();pointer=(ROOT/'server/bundles/current.json').read_bytes()
 reference={name:(ROOT/'data/csv'/name).read_text(encoding='utf-8-sig') for name in SOURCES}
 oldstats=base['configs']['player_gameplay_stats'];current=read_csv(ROOT/'data/csv/玩家档案系统/player_gameplay_stats.csv')
 a={r['field_id']:r for r in oldstats['rows']};b={r['field_id']:r for r in current['rows']};assert a.keys()==b.keys()
 statdiff=[]
 for identity,old in a.items():
  for key in old.keys()|b[identity].keys():
   if old.get(key)!=b[identity].get(key):
    assert identity=='lumberjack_attack_growth' and key=='notes','non-task stat drift'
    note=b[identity][key];assert reference[SOURCES[1]].count(note)==1
    reference[SOURCES[1]]=reference[SOURCES[1]].replace(note,old[key])
    statdiff.append({'field':identity,'property':key,'preserved':'deployed baseline'})
 package=build(ROOT)
 commerce=compile_commerce(package['commerce_tables'],reference,package['tables']['payment_categories'])
 oldproducts={p['sku']:p for p in base['configs']['commerce_catalog']['rows']};allproducts={p['sku']:p for p in commerce['products']}
 for identity,old in oldproducts.items():assert allproducts[identity]==old,'old commerce product changed: '+identity
 assert len(oldproducts)==108 and len(allproducts)==123
 expected={'video_bundle_b00'+str(i) for i in range(1,6)}|{'video_bundle_vip_'+str(i).zfill(2) for i in range(1,11)}
 assert allproducts.keys()-oldproducts.keys()==expected
 for folder,name in [('商城兑换系统','commerce_products'),('商城兑换系统','commerce_bundle_members'),('商城兑换系统','commerce_import_status'),('存档系统','archive_vip_rewards')]:
  data['configs'][name]=read_csv(ROOT/'data/csv'/folder/(name+'.csv'))
 data['configs']['commerce_catalog']={'key':'sku','rows':commerce['products']}
 # All existing source rows are untouched; the only new product rows are the 15 reviewed packs.
 oldsource={r['sku']:r for r in base['configs']['commerce_products']['rows']}
 newsource={r['sku']:r for r in data['configs']['commerce_products']['rows']}
 assert newsource.keys()-oldsource.keys()==expected
 for k,v in oldsource.items():assert newsource[k]==v
 oldvip={r['reward_id']:r for r in base['configs']['archive_vip_rewards']['rows']}
 newvip={r['reward_id']:r for r in data['configs']['archive_vip_rewards']['rows']};assert oldvip.keys()==newvip.keys()
 vipdiff=[]
 for identity,old in oldvip.items():
  fields=[k for k in old.keys()|newvip[identity].keys() if old.get(k)!=newvip[identity].get(k)]
  allowed={'condition'} if identity.startswith('vip_package_') else set()
  if identity=='vip_package_05':allowed|={'description','effect_values'}
  if identity=='vip_package_10':allowed|={'description','effect_ids'}
  assert set(fields)<=allowed,'unexpected VIP data drift: '+identity
  if fields:vipdiff.append({'id':identity,'fields':fields})
 for name in SOURCE_NAMES:data['sources'][name]=(ROOT/'scripts/vscripts'/name).read_text(encoding='utf-8-sig')
 for name in CSV_NAMES:data['csv_hashes']['data/csv/'+name]=sha((ROOT/'data/csv'/name).read_bytes().replace(b'\r\n',b'\n'))
 # Existing compatibility rules remain exactly intact. The newly accepted 310
 # alias never upgrades recorded operations to a different reducer.
 alias_commands=['boss_kill','building_upgrade','challenge','clear','commerce_catalog','commerce_purchase','daily_claim','daily_init','endless','endless_reconcile','lottery_draw','lottery_exchange','lottery_read','lottery_snapshot','promotion','social_draw','starjoy_reconcile','title_equip','vip_claim','vip_purchase','welfare_reconcile','work_upgrade']
 data.setdefault('compatible_config_hashes',{})[BASE]={'commands':alias_commands,'upgrade_commands':[]}
 changed_configs=[k for k in base['configs'].keys()|data['configs'].keys() if base['configs'].get(k)!=data['configs'].get(k)]
 changed_sources=[k for k in base['sources'].keys()|data['sources'].keys() if base['sources'].get(k)!=data['sources'].get(k)]
 changed_csv=[k for k in base['csv_hashes'].keys()|data['csv_hashes'].keys() if base['csv_hashes'].get(k)!=data['csv_hashes'].get(k)]
 assert set(changed_configs)==CONFIGS and set(changed_sources)==SOURCE_NAMES
 assert set(changed_csv)=={'data/csv/'+x for x in CSV_NAMES}
 assert data['configs']['player_gameplay_stats']==oldstats
 assert data['sources']['worker.lua']==base['sources']['worker.lua']
 body=canonical(data);digest=sha(body);destination=DEST/'archive_bundle_overlay'/digest;destination.mkdir(parents=True,exist_ok=True)
 (destination/'bundle.json').write_bytes(body)
 for name,text in data['sources'].items():out=destination/name;out.parent.mkdir(parents=True,exist_ok=True);out.write_text(text,encoding='utf-8',newline='\n')
 write_json(destination.parent/'current.json',{'hash':digest,'protocol':1})
 # A matching payment package uses a release-local reference override; formal
 # workspace CSVs and the running game's pointers remain untouched.
 paid=compile_payment_catalog(package['tables'],package['commerce_tables'],reference)
 package.update(catalog=paid,reference_hashes={k:sha(v.encode()) for k,v in reference.items()},catalog_hash=sha(canonical(paid)))
 write_json(DEST/'payment_catalog_310_overlay.json',package)
 override=DEST/'reference_csv'/SOURCES[1];override.parent.mkdir(parents=True,exist_ok=True);override.write_text(reference[SOURCES[1]],encoding='utf-8',newline='\n')
 report={'status':'PASS','base':BASE,'overlay':digest,'changed_configs':sorted(changed_configs),'changed_sources':sorted(changed_sources),'changed_csv_hashes':sorted(changed_csv),'compatibility_added':{BASE:data['compatible_config_hashes'][BASE]},'existing_compatibility_rules_preserved':all(data.get('compatible_config_hashes',{}).get(k)==v for k,v in base.get('compatible_config_hashes',{}).items()),'worker_unchanged':True,'all_other_configs_sources_preserved':True,'old_108_commerce_products_exactly_preserved':True,'stat_differences_excluded':statdiff,'vip_changes':vipdiff,'new_products':sorted(expected),'payment_catalog_hash':package['catalog_hash'],'payment_reference_override':SOURCES[1],'payment_reference_override_sha256':sha(reference[SOURCES[1]].encode()),'game_pointer_unchanged':True,'server_pointer_unchanged':True,'production_deployed':False}
 assert (ROOT/'scripts/vscripts/config/generated/archive_http_bundle.lua').read_bytes()==game
 assert (ROOT/'server/bundles/current.json').read_bytes()==pointer
 write_json(DEST/'archive_overlay_diff.json',report)
 print(json.dumps({'overlay':digest,'payment_catalog_hash':package['catalog_hash'],'configs':sorted(changed_configs),'sources':sorted(changed_sources)}))
 return destination,report
if __name__=='__main__':main()
