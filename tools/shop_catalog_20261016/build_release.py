"""Build an exact overlay on the reviewed running f44d release, not dirty globals.

Only two new point products, their rewards, and import review records may change.
All old canonical products, prices, sources, schemas and old compatibility stay.
"""
from pathlib import Path
import ast,copy,hashlib,json,sys,tarfile
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'server'))
from archive_backend.bundle import read_csv
from payment_backend.csv_catalog import build,canonical,SOURCES
from payment_backend.commerce_bundles import compile_commerce
from payment_backend.ucoin_catalog import compile_payment_catalog
OUT=ROOT/'design_refs/shop_catalog_20261016/release'
DEPLOY=ROOT/'design_refs/shop_catalog_20261016/deployment'
BASE='f44d6c2baaacb7a570dd5ebb2c03b01a8b1838fb1c8f102b8005cc09626669a4'
NEW={'video_p140','video_p151'}
def sha(raw):return hashlib.sha256(raw).hexdigest()
def write(path,raw):
    path.parent.mkdir(parents=True,exist_ok=True)
    if path.exists():assert path.read_bytes()==raw,'immutable_candidate_changed:'+str(path)
    else:path.write_bytes(raw)
def main():
    OUT.mkdir(parents=True,exist_ok=True)
    preflight=json.loads((DEPLOY/'preflight.json').read_text('utf-8'));baseline=DEPLOY/'online_baseline/archive'
    assert preflight['metadata']['bundle']==BASE
    original=(baseline/'addon/server/bundles'/BASE/'bundle.json').read_bytes();assert sha(original)==BASE
    assert (ROOT/'server/bundles'/BASE/'bundle.json').read_bytes()==original
    pointers={name:(ROOT/name).read_bytes() for name in ['server/bundles/current.json','scripts/vscripts/config/generated/archive_http_bundle.lua']}
    assert json.loads(pointers['server/bundles/current.json'])['hash']==BASE
    assert BASE.encode() in pointers['scripts/vscripts/config/generated/archive_http_bundle.lua']
    base=json.loads(original);data=copy.deepcopy(base);package=build(ROOT)
    reference={name:(ROOT/'data/csv'/name).read_text('utf-8-sig') for name in SOURCES}
    # One existing local stat note differs from the published authority. Never
    # turn that unrelated documentation edit into altered product effect labels.
    reference[SOURCES[1]]=(DEPLOY/'online_baseline/payment/reference_csv'/SOURCES[1]).read_text('utf-8-sig')
    commerce=compile_commerce(package['commerce_tables'],reference,package['tables']['payment_categories'])
    cash=compile_payment_catalog(package['tables'],package['commerce_tables'],reference)
    cash_hash=sha(canonical(cash));assert cash_hash==preflight['metadata']['catalog_hash'],'cash_catalog_must_stay_exact'
    old={p['sku']:p for p in base['configs']['commerce_catalog']['rows']};new={p['sku']:p for p in commerce['products']}
    assert len(old)==123 and new.keys()-old.keys()==NEW and all(new[k]==v for k,v in old.items())
    assert all(new[k]['enabled'] and new[k]['purchase_limit']==1 for k in NEW)
    assert new['video_p140']['price']==588 and new['video_p151']['price']==5000
    assert new['video_p140']['effects']=={'wood_per_second':1}
    expected={'map_level':1,'wall_armor':1000,'wall_armor_per_second':.15,
      'hero_final_damage_bonus_pct':35,'hero_attribute_bonus_pct':35,'hero_attribute_growth':35,
      'hero_attack_armor_reduction':35,'hero_damage_attack_growth':35,'starjoy_points':200}
    for row in base['configs']['map_level_effect_rules']['rows']:
        if row.get('enabled') is not False:expected[row['target_field_id']]=expected.get(row['target_field_id'],0)+row['value_per_level']
    assert new['video_p151']['effects']==expected
    changes={}
    for name,key in [('commerce_products','sku'),('commerce_rewards','reward_id'),('commerce_import_status','source_id')]:
        source=ROOT/'data/csv/商城兑换系统'/(name+'.csv');fresh=read_csv(source)
        a={r[key]:r for r in base['configs'][name]['rows']};b={r[key]:r for r in fresh['rows']}
        modified=[k for k,v in a.items() if b.get(k)!=v];added=sorted(b.keys()-a.keys())
        if name=='commerce_products':assert not modified and set(added)==NEW
        elif name=='commerce_rewards':assert not modified and len(added)==10 and all(b[k]['sku'] in NEW for k in added)
        else:assert modified==['P140'] and set(added)=={'P'+str(n) for n in range(141,152)}
        assert a.keys()<=b.keys();data['configs'][name]=fresh
        relative=source.relative_to(ROOT).as_posix();data['csv_hashes'][relative]=sha(source.read_bytes().replace(b'\r\n',b'\n'))
        changes[name]={'modified':modified,'added':added}
    data['configs']['commerce_catalog']={'key':'sku','rows':commerce['products']}
    tree=ast.parse((baseline/'backend/archive_backend/service.py').read_text('utf-8'))
    fields=next(n.value for n in tree.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='FIELDS' for t in n.targets))
    commands=sorted(set(ast.literal_eval(fields))|{'lottery_snapshot'})
    data.setdefault('compatible_config_hashes',{})[BASE]={'commands':commands,'upgrade_commands':[]}
    assert data['sources']==base['sources']
    assert all(data['configs'][k]==v for k,v in base['configs'].items() if k not in {'commerce_products','commerce_rewards','commerce_import_status','commerce_catalog'})
    assert all(data['compatible_config_hashes'][k]==v for k,v in base.get('compatible_config_hashes',{}).items())
    raw=canonical(data);digest=sha(raw);candidate=OUT/'candidate';bundle=candidate/'addon/server/bundles'/digest
    write(bundle/'bundle.json',raw)
    for name,text in data['sources'].items():write(bundle/name,text.encode('utf-8'))
    write(candidate/'addon/server/bundles/current.json',canonical({'hash':digest,'protocol':1}))
    write(candidate/'addon/scripts/vscripts/config/generated/archive_http_bundle.lua',
      ('-- AUTO-GENERATED by tools/shop_catalog_20261016/build_release.py\nreturn { protocol = 1, hash = "'+digest+'" }\n').encode())
    cfg={'configs':data['configs'],'compatible_config_hashes':data['compatible_config_hashes']}
    write(OUT/'archive_config.json',canonical(cfg));write(OUT/'commerce_catalog.json',canonical(commerce))
    write(OUT/'payment_catalog.json',canonical(cash))
    projection=json.loads((ROOT/'design_refs/shop_catalog_20261016/audit/source_projection_validation.json').read_text('utf-8'))
    assert 'PASS' in json.dumps(projection) and (ROOT/'scripts/vscripts/systems/commerce_archive_source_bonus.lua').is_file()
    inputs=['data/csv/商城兑换系统/'+n+'.csv' for n in ['commerce_products','commerce_rewards','commerce_import_status','commerce_bundle_members']]
    inputs+=['scripts/vscripts/systems/commerce_archive_source_bonus.lua','scripts/vscripts/systems/permanent_reward_effect_service.lua']
    report={'format':1,'status':'CANDIDATE_COMPAT_SQL_PENDING','base_hash':BASE,'candidate_hash':digest,
       'old_archive_release':preflight['metadata']['archive_release'],'old_payment_release':preflight['metadata']['payment_release'],
       'target_release':'/opt/goufayu/releases/20261016-shop-catalog-v1','rollback_release':'/opt/goufayu/releases/20261016-shop-catalog-rollback-v1',
       'old_archive_manifest_sha256':sha((baseline/'release_manifest.json').read_bytes()),
       'old_payment_manifest_sha256':sha((DEPLOY/'online_baseline/payment/manifest.json').read_bytes()),
       'old_service_sha256':sha((baseline/'backend/archive_backend/service.py').read_bytes()),
       'old_sync_definition_sha256':sha(preflight['function_definitions']['public.archive_sync_config(text,jsonb)'].encode()),
       'payment_catalog_hash':cash_hash,'payment_catalog_unchanged':True,'old_commerce_products_unchanged':True,
       'old_sources_and_schema_unchanged':True,'sources_changed':[],'configs_changed':sorted([*changes,'commerce_catalog']),
       'row_changes':changes,'added_skus':sorted(NEW),'commerce_products':125,'commerce_enabled':sum(p['enabled'] for p in commerce['products']),
       'cash_enabled':sum(p['enabled'] for p in cash['products']),'financial_upgrades_changed':False,
       'archive_config_sha256':sha(canonical(cfg)),'local_input_hashes':{n:sha((ROOT/n).read_bytes()) for n in inputs},
       'old_game_pointer_sha256':{n:sha(b) for n,b in pointers.items()},'production_deployed':False}
    write(OUT/'candidate_manifest.json',canonical({'files':{p.relative_to(candidate).as_posix():sha(p.read_bytes()) for p in candidate.rglob('*') if p.is_file()}}))
    (OUT/'release_plan.json').write_bytes(canonical(report))
    for name,raw in pointers.items():write(OUT/'rollback_local'/name,raw)
    print(json.dumps({k:report[k] for k in ['status','base_hash','candidate_hash','added_skus','commerce_products','commerce_enabled','cash_enabled','payment_catalog_unchanged','sources_changed','configs_changed']}))
if __name__=='__main__':main()
