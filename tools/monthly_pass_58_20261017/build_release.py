"""Freeze a single-product price update on the freshly verified live baseline."""
from pathlib import Path
import base64
import copy
import hashlib
import io
import json
import sys
import tarfile

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/monthly_pass_58_20261017'
sys.path.insert(0,str(ROOT/'server'))
from archive_backend.bundle import Bundle,read_csv
from payment_backend.csv_catalog import build


def canonical(value):
    return json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':'),allow_nan=False).encode()


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def main():
    audit=json.loads((OUT/'remote/preflight.json').read_bytes())['records'][0]
    for name,encoded in audit['export_files'].items():
        p=Path(name);assert not p.is_absolute() and '..' not in p.parts
        target=OUT/'baseline'/p;raw=base64.b64decode(encoded,validate=True)
        if target.exists():assert target.read_bytes()==raw,'immutable_baseline_changed'
        else:target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(raw)
    before=next(p for p in audit['products'] if p['sku']=='archive_pass_monthly')
    assert before['amount']==1000 and before['description'].startswith('10元开通30天'), 'monthly_baseline_drift'
    compiled=next(p for p in build(ROOT)['catalog']['products'] if p['sku']=='archive_pass_monthly')
    product=copy.deepcopy(before);product.update(amount=5800,description=before['description'].replace('10元开通','58元开通'))
    for field in ('amount','description','grants','effects','item_id','purchase_limit','category_id','product_type','enabled'):
        assert product[field]==compiled[field], 'monthly_compiled_contract_mismatch:'+field
    catalog_hash=digest(canonical(dict(kind='monthly_fixed_58_20261017',previous_hash=audit['catalog_hash'],product=product)))
    parent_dir=OUT/'baseline/archive/addon/server/bundles'/audit['archive_bundle']
    parent=json.loads((parent_dir/'bundle.json').read_bytes())
    assert digest((parent_dir/'bundle.json').read_bytes())==audit['archive_bundle']
    data=copy.deepcopy(parent)
    csv_name='data/csv/存档系统/archive_daily_rules.csv'
    rules=read_csv(ROOT/csv_name);old_rules=copy.deepcopy(rules)
    assert len(rules['rows'])==1 and rules['rows'][0]['price_text']=='58元'
    old_rules['rows'][0]['price_text']='10元'
    assert old_rules==parent['configs']['archive_daily_rules'],'nonprice_daily_rule_change'
    data['configs']['archive_daily_rules']=rules
    data['csv_hashes'][csv_name]=digest((ROOT/csv_name).read_bytes().replace(b'\r\n',b'\n'))
    compatibility=data['compatible_config_hashes']
    assert audit['archive_bundle'] not in compatibility
    commands=sorted({c for rule in compatibility.values() for c in rule['commands']})
    compatibility[audit['archive_bundle']]=dict(commands=commands,upgrade_commands=['commerce_purchase'])
    raw=canonical(data);bundle=digest(raw)
    directory=OUT/'candidate/archive/addon/server/bundles'/bundle
    directory.mkdir(parents=True,exist_ok=True);(directory/'bundle.json').write_bytes(raw)
    for name,source in data['sources'].items():
        target=directory/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_text(source,encoding='utf8',newline='\n')
    Bundle(directory)
    archive_files={p.relative_to(OUT/'candidate/archive').as_posix():p.read_bytes() for p in directory.rglob('*') if p.is_file()}
    archive_files['addon/server/bundles/current.json']=canonical(dict(hash=bundle,protocol=1))
    archive_files['addon/'+csv_name]=(ROOT/csv_name).read_bytes()
    files={name:(OUT/'baseline/payment'/name).read_bytes() for name in audit['payment_manifest']}
    files['payment_backend/csv_catalog.py']=(ROOT/'server/payment_backend/csv_catalog.py').read_text(encoding='utf-8-sig').replace('\r\n','\n').encode()
    files['reference_csv/商城支付系统/payment_products.csv']=(ROOT/'data/csv/商城支付系统/payment_products.csv').read_text(encoding='utf-8-sig').replace('\r\n','\n').encode()
    archive_sync=audit['archive_functions']['public.archive_sync_config(text,jsonb)']
    plan=dict(version=1,payment_baseline=audit['payment_release'],payment_manifest_sha256=audit['payment_manifest_sha256'],
              archive_baseline=audit['archive_release'],archive_manifest_sha256=audit['archive_manifest_sha256'],
              parent_bundle=audit['archive_bundle'],bundle=bundle,payment_release='20261017-monthly-58-v1',archive_release='20261017-monthly-58-v1',
              catalog_hash=catalog_hash,baseline_catalog_hash=audit['catalog_hash'],monthly_product=product,
              monthly_before_sha256=digest(canonical(before)),archive_sync_sha256=archive_sync['sha256'],
              baseline_functions={s:f['sha256'] for s,f in audit['functions'].items()},
              archive_files={n:digest(v) for n,v in archive_files.items()},payment_files={n:digest(v) for n,v in files.items()})
    files['manifest.json']=json.dumps(plan['payment_files'],ensure_ascii=False,indent=2).encode()+b'\n'
    payload={'plan.json':canonical(plan),'archive_sync_before.sql':archive_sync['definition'].encode()}
    payload.update({'payment/'+n:v for n,v in files.items()});payload.update({'archive/'+n:v for n,v in archive_files.items()})
    with tarfile.open(OUT/'release.tar.gz','w:gz') as archive:
        for name,raw in sorted(payload.items()):
            info=tarfile.TarInfo(name);info.size=len(raw);info.mode=0o644;archive.addfile(info,io.BytesIO(raw))
    plan['tar_sha256']=digest((OUT/'release.tar.gz').read_bytes())
    (OUT/'plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    print(json.dumps({k:v for k,v in plan.items() if not isinstance(v,dict)},ensure_ascii=False))


if __name__=='__main__':main()
