"""Validate only the reviewed two-byte gold-product disable; no global generation."""
from pathlib import Path
import sys,json,hashlib,copy
root=Path(__file__).resolve().parents[2];sys.path.insert(0,str(root/'server'))
from payment_backend.csv_catalog import build,SOURCES,canonical
from payment_backend.commerce_bundles import compile_commerce
from payment_backend.ucoin_catalog import compile_payment_catalog
from archive_backend.bundle import read_csv
out=root/'design_refs/commerce_points_20261016';(out/'generated').mkdir(parents=True,exist_ok=True)
f=root/'data/csv/商城兑换系统/commerce_products.csv';raw=(out/'baseline/commerce_products.csv').read_bytes();changed=f.read_bytes()
assert len(changed)==len(raw);assert sum(a!=b for a,b in zip(raw,changed))==2
expected=raw
for identity in ['video_p037','video_p038']:
 prefix=next(line for line in raw.splitlines() if line.startswith((identity+',').encode()));parts=prefix.split(b',');assert parts[4]==b'shop_gold' and parts[7]==b'1'
 replacement=b','.join(parts[:7]+[b'0']+parts[8:]);assert expected.count(prefix)==1;expected=expected.replace(prefix,replacement,1)
assert changed==expected,'Only enabled flags may change'
p=build(root);ref={n:(root/'data/csv'/n).read_text(encoding='utf-8-sig') for n in SOURCES}
tables=copy.deepcopy(p['commerce_tables']);tables['commerce_products']=raw.decode('utf-8-sig').replace('\r\n','\n')
before=compile_commerce(tables,ref,p['tables']['payment_categories']);cash_before=compile_payment_catalog(p['tables'],tables,ref)
tables['commerce_products']=changed.decode('utf-8-sig').replace('\r\n','\n');after=compile_commerce(tables,ref,p['tables']['payment_categories']);cash=compile_payment_catalog(p['tables'],tables,ref)
diffs=[]
for a,b in zip(before['products'],after['products']):
 assert a['sku']==b['sku'];fields=[k for k in a.keys()|b.keys() if a.get(k)!=b.get(k)]
 if fields:diffs.append({'sku':a['sku'],'fields':fields,'old':a['enabled'],'new':b['enabled']})
assert diffs==[{'sku':'video_p037','fields':['enabled'],'old':True,'new':False},{'sku':'video_p038','fields':['enabled'],'old':True,'new':False}],diffs
assert canonical(cash)==canonical(cash_before),'cash catalog must remain exactly unchanged'
for name,data in [('commerce_catalog',{'key':'sku','rows':after['products']}),('commerce_products',read_csv(f))]:
 (out/'generated'/f'{name}.json').write_bytes(canonical(data))
report={'status':'PASS','scope':'Only two enabled bytes changed; no whole-config generation, global bundle/current pointer or payment catalog modified.','csv_path':str(f.relative_to(root)),'byte_changes':2,'byte_length_preserved':True,'encoding_BOM_preserved':raw.startswith(b'\xef\xbb\xbf')==changed.startswith(b'\xef\xbb\xbf'),'CRLF_preserved':raw.count(b'\r\n')==changed.count(b'\r\n'),'csv_sha256_before':hashlib.sha256(raw).hexdigest(),'csv_sha256_after':hashlib.sha256(changed).hexdigest(),'catalog_diffs':diffs,'catalog_total':len(after['products']),'enabled_before':sum(x['enabled'] for x in before['products']),'enabled_after':sum(x['enabled'] for x in after['products']),'cash_products':len(cash['products']),'cash_catalog_unchanged':True,'cash_catalog_hash':hashlib.sha256(canonical(cash)).hexdigest(),'derived_configs':{n:hashlib.sha256((out/'generated'/f'{n}.json').read_bytes()).hexdigest() for n in ['commerce_catalog','commerce_products']},'existing_global_pointer':(root/'server/bundles/current.json').read_text(encoding='utf-8')}
(out/'gold_product_disable_validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps(report,ensure_ascii=True,indent=2))
