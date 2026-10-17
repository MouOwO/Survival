"""Exact commerce overlay on the freshly fetched production bundle."""
from pathlib import Path
import ast,copy,hashlib,json,sys
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'server'))
from archive_backend.bundle import read_csv
from payment_backend.csv_catalog import canonical,SOURCES,TABLES
from payment_backend.ucoin_catalog import COMMERCE_TABLES,compile_payment_catalog
from payment_backend.commerce_bundles import compile_commerce
OUT=ROOT/'design_refs/shop_functional_20261016/release'
DEPLOY=ROOT/'design_refs/shop_functional_20261016/deployment'
NEW={'video_p016','video_p028','video_p079','video_p147'}
def sha(b):return hashlib.sha256(b).hexdigest()
def write(path,raw):
    path.parent.mkdir(parents=True,exist_ok=True)
    if path.exists():assert path.read_bytes()==raw,'immutable_changed:'+str(path)
    else:path.write_bytes(raw)
def main():
    preflight=json.loads((DEPLOY/'preflight.json').read_bytes());meta=preflight['metadata'];base_hash=meta['bundle']
    baseline=DEPLOY/'online_baseline';original=(baseline/'archive/addon/server/bundles'/base_hash/'bundle.json').read_bytes()
    assert sha(original)==base_hash
    base=json.loads(original);data=copy.deepcopy(base)
    paths=['data/csv/商城兑换系统/'+n+'.csv' for n in [*COMMERCE_TABLES,'commerce_import_status']]
    pointers=['server/bundles/current.json','scripts/vscripts/config/generated/archive_http_bundle.lua']
    assert json.loads((ROOT/pointers[0]).read_bytes())['hash']==base_hash
    assert base_hash.encode() in (ROOT/pointers[1]).read_bytes()
    old_reference={n:(baseline/'payment/reference_csv'/n).read_text('utf-8-sig') for n in SOURCES}
    reference=dict(old_reference)
    reference[SOURCES[-1]]=(ROOT/'data/csv'/SOURCES[-1]).read_text('utf-8-sig')
    # These three authoring tables are package inputs, not runtime references.
    # Recompilation must exactly match the live cash hash before using them.
    tables={n:(ROOT/'data/csv/商城支付系统'/(n+'.csv')).read_text('utf-8-sig') for n in TABLES}
    commerce_tables={n:(ROOT/'data/csv/商城兑换系统'/(n+'.csv')).read_text('utf-8-sig') for n in COMMERCE_TABLES}
    old_tables={n:(baseline/'payment/reference_csv/商城兑换系统'/(n+'.csv')).read_text('utf-8-sig') for n in COMMERCE_TABLES}
    old_cash=compile_payment_catalog(tables,old_tables,old_reference)
    assert sha(canonical(old_cash))==meta['catalog_hash'],'baseline_cash_recompile_failed'
    cash=compile_payment_catalog(tables,commerce_tables,reference)
    commerce=compile_commerce(commerce_tables,reference,tables['payment_categories'])
    old={r['sku']:r for r in base['configs']['commerce_catalog']['rows']};new={r['sku']:r for r in commerce['products']}
    assert new.keys()-old.keys()==NEW and old.keys()<=new.keys()
    assert all(new[k]==v for k,v in old.items() if k!='video_bundle_b003'),'unrelated_old_product_changed'
    pack=new['video_bundle_b003'];assert pack['enabled'] and not pack.get('bundle_pending') and pack['price']==old[pack['sku']]['price']==46560
    assert pack['effects']['starjoy_points']==662
    assert {c['sku'] for c in pack['grants']['components']}=={'video_p028','video_p020','video_p018','video_p032'}
    assert len(new)==129 and sum(r['enabled'] for r in new.values())==126
    assert all(new[k]['enabled'] and new[k]['purchase_limit']==1 for k in NEW)
    a={p['sku']:p for p in old_cash['products']};b={p['sku']:p for p in cash['products']}
    assert b.keys()-a.keys()=={'video_p016','video_p028'}
    assert all(b[k]==v for k,v in a.items() if k!='video_bundle_b003')
    assert all(b[k]['amount']==v['amount'] for k,v in a.items()),'existing_price_changed'
    assert sum(p['enabled'] for p in cash['products'])==47
    for name in [*COMMERCE_TABLES,'commerce_import_status']:
        p=ROOT/'data/csv/商城兑换系统'/(name+'.csv');data['configs'][name]=read_csv(p)
        data['csv_hashes'][p.relative_to(ROOT).as_posix()]=sha(p.read_bytes().replace(b'\r\n',b'\n'))
    data['configs']['commerce_catalog']={'key':'sku','rows':commerce['products']}
    tree=ast.parse((baseline/'archive/backend/archive_backend/service.py').read_text('utf8'))
    fields=next(n.value for n in tree.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='FIELDS' for t in n.targets))
    data.setdefault('compatible_config_hashes',{})[base_hash]={'commands':sorted(set(ast.literal_eval(fields))|{'lottery_snapshot'}),'upgrade_commands':[]}
    configs_changed=[n for n in data['configs'] if data['configs'][n]!=base['configs'][n]]
    assert set(configs_changed)=={'commerce_products','commerce_rewards','commerce_bundle_members','commerce_import_status','commerce_catalog'}
    assert data['sources']==base['sources']
    assert all(data['compatible_config_hashes'][k]==v for k,v in base.get('compatible_config_hashes',{}).items())
    raw=canonical(data);digest=sha(raw);bundle=OUT/'candidate/addon/server/bundles'/digest
    write(bundle/'bundle.json',raw)
    for name,text in data['sources'].items():write(bundle/name,text.encode('utf8'))
    write(OUT/'candidate/addon/server/bundles/current.json',canonical({'hash':digest,'protocol':1}))
    write(OUT/'candidate/addon/scripts/vscripts/config/generated/archive_http_bundle.lua',('-- AUTO-GENERATED functional commerce overlay\nreturn { protocol = 1, hash = "'+digest+'" }\n').encode())
    package=dict(tables=tables,commerce_tables=commerce_tables,reference_hashes={n:sha(s.encode()) for n,s in reference.items()},catalog=cash,catalog_hash=sha(canonical(cash)))
    write(OUT/'payment_package.json',canonical(package));write(OUT/'payment_catalog.json',canonical(cash));write(OUT/'commerce_catalog.json',canonical(commerce))
    write(OUT/'archive_config.json',canonical({'configs':data['configs'],'compatible_config_hashes':data['compatible_config_hashes']}))
    for n in SOURCES:
        source=ROOT/'data/csv'/n if n==SOURCES[-1] else baseline/'payment/reference_csv'/n
        write(OUT/'payment_reference'/n,source.read_bytes())
    for n in COMMERCE_TABLES:write(OUT/'payment_reference/商城兑换系统'/(n+'.csv'),(ROOT/'data/csv/商城兑换系统'/(n+'.csv')).read_bytes())
    # Save the exact publication inputs and both local recovery pointers.
    for n in pointers:write(OUT/'rollback_local'/n,(ROOT/n).read_bytes())
    report={'version':1,'kind':'functional_commerce','base':base_hash,'candidate':digest,
      'old_release':meta['archive_release'],'old_payment':meta['payment_release'],
      'target_release':'/opt/goufayu/releases/20261016-shop-functional-v1','target_payment':'/opt/goufayu/payments/20261016-shop-functional-v1',
      'old_manifest':sha((baseline/'archive/release_manifest.json').read_bytes()),'old_payment_manifest':sha((baseline/'payment/manifest.json').read_bytes()),
      'old_cash_hash':meta['catalog_hash'],'cash_hash':package['catalog_hash'],
      'old_sync':sha(preflight['function_definitions']['public.archive_sync_config(text,jsonb)'].encode()),
      'apply_sha':sha(preflight['function_definitions']['payments.apply_effects(text,jsonb,boolean)'].encode()),
      'new_skus':sorted(NEW),'old_prices_unchanged':True,'configs_changed':configs_changed,'sources_changed':[],
      'wallet_count':129,'wallet_enabled':126,'cash_count':len(cash['products']),'cash_enabled':47,
      'input_hashes':{n:sha((ROOT/n).read_bytes()) for n in paths},'pointer_hashes':{n:sha((ROOT/n).read_bytes()) for n in pointers}}
    write(OUT/'release_plan.json',canonical(report))
    print(json.dumps(report,ensure_ascii=False))
if __name__=='__main__':main()
