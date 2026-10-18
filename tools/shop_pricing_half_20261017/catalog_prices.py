"""Apply the reviewed 2026-10-17 price policy once, then export exact catalogs.

No network, activation, order edits or account writes. Re-running is idempotent:
the authority CSV stores the final price and its immutable previous-price basis.
The monthly pass has a later fixed 58-yuan policy and never receives a discount.
"""
from __future__ import annotations
import argparse
import csv
from decimal import Decimal
import hashlib
import io
import json
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/shop_pricing_half_20261017/catalog'
POLICY='half_current_20261017'
MONTHLY_FIXED_POLICY='monthly_fixed_58_20261017'
MONTHLY_FIXED_YUAN=Decimal('58.00')
RATE=100
COMMERCE='data/csv/商城兑换系统/commerce_products.csv'
PAYMENT='data/csv/商城支付系统/payment_products.csv'
DISPLAY='data/ui/video_shop_bundles_20261015.json'
JS='panorama/src/scripts/custom_game/video_shop_bundles.js'

def read(path):
    with path.open(encoding='utf-8-sig',newline='') as f:
        reader=csv.DictReader(f);records=list(reader)
    return list(reader.fieldnames),records

def backup(relative):
    destination=OUT/'before'/relative
    if not destination.exists():
        destination.parent.mkdir(parents=True,exist_ok=True)
        destination.write_bytes((ROOT/relative).read_bytes())

def update_prices(relative,field,basis_field,expected_count):
    path=ROOT/relative;original=path.read_bytes();fields,records=read(path)
    additions={'price_policy':'string',basis_field:'number'}
    for key in additions:
        if key not in fields:fields.append(key)
    changes=[]
    for record in records:
        if record['sku'].startswith('#'):
            for key,kind in additions.items():
                record[key]=kind if record['sku'].startswith('#types:') else '折扣规则' if key=='price_policy' else '折扣前实际售价'
            continue
        current=Decimal(record[field]);policy=record.get('price_policy','')
        if relative==PAYMENT and record['sku']=='archive_pass_monthly':
            assert field=='price_yuan' and basis_field=='price_baseline_yuan'
            basis=Decimal(record[basis_field]) if policy else current
            assert basis==20,record['sku']+':historical_baseline_changed'
            assert ((policy==MONTHLY_FIXED_POLICY and current==MONTHLY_FIXED_YUAN)
                    or (policy==POLICY and current*2==basis)
                    or (not policy and current==basis)),record['sku']+':invalid_existing_policy'
            current=MONTHLY_FIXED_YUAN
            record.update(price_policy=MONTHLY_FIXED_POLICY,price_yuan=format(current,'.2f'),price_baseline_yuan=format(basis,'.2f'))
            record['description']=record['description'].replace('20元开通','58元开通').replace('10元开通','58元开通')
        elif policy:
            assert policy==POLICY and current*2==Decimal(record[basis_field]),record['sku']+':invalid_existing_policy'
            basis=Decimal(record[basis_field])
        else:
            basis=current;current=basis/2
            assert current>0 and (current==current.to_integral() if field=='price' else current*100==(current*100).to_integral()),record['sku']+':fractional_currency'
            record['price_policy']=POLICY;record[basis_field]=record[field]
            record[field]=str(int(current)) if field=='price' else format(current,'.2f')
        if record['sku']=='special_lottery_ticket_single':record['description']=record['description'].replace('50元一张','25元一张')
        changes.append(dict(sku=record['sku'],currency=record.get('currency','CNY'),before=str(basis),after=str(current),enabled=record['enabled'],price_policy=record['price_policy']))
    assert len(changes)==expected_count,(relative,len(changes),expected_count)
    newline='\r\n' if original.count(b'\r\n') else '\n'
    stream=io.StringIO(newline='');writer=csv.DictWriter(stream,fieldnames=fields,lineterminator=newline)
    writer.writeheader();writer.writerows(records)
    output=stream.getvalue().encode('utf-8')
    if original.startswith(b'\xef\xbb\xbf'):output=b'\xef\xbb\xbf'+output
    backup(relative)
    if output!=original:path.write_bytes(output)
    return changes

def display():
    path=ROOT/DISPLAY;data=json.loads(path.read_bytes());_,records=read(ROOT/COMMERCE)
    lookup={p['sku']:p for p in records if not p['sku'].startswith('#')}
    assert len(data['products'])==15
    for p in data['products']:
        authority=lookup[p['sku']];price=int(authority['price'])
        assert authority['currency']=='u_coin' and authority['price_policy']==POLICY
        p.update(currency_name='G币',price=price,u_coin_price=price,u_coin_per_yuan=RATE,amount_fen=price,
                 price_policy=POLICY,price_baseline=int(authority['price_baseline']))
        assert p['original_price']==int(authority['source_original_price'])
    data['pricing']='1人民币=100G币；商品按2026-10-17改价前实际售价减半，原价仅展示，充值不打折'
    data['price_policy']=POLICY
    backup(DISPLAY);path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
    path=ROOT/JS;raw=path.read_bytes().decode('utf-8')
    marker='GameUI.CustomUIConfig().VideoShopBundleCatalog='
    assert raw.count(marker)==1
    start=raw.index(marker)+len(marker)
    old,consumed=json.JSONDecoder().raw_decode(raw[start:])
    assert len(old['products'])==15 and raw[start+consumed]==';'
    updated=raw[:start]+json.dumps(data,ensure_ascii=False,separators=(',',':'))+raw[start+consumed:]
    backup(JS)
    path.write_bytes(updated.encode('utf-8'))
    return len(data['products'])

def monthly_rule():
    _,products=read(ROOT/PAYMENT)
    monthly=next(p for p in products if p['sku']=='archive_pass_monthly')
    assert monthly['price_policy']==MONTHLY_FIXED_POLICY and Decimal(monthly['price_yuan'])==MONTHLY_FIXED_YUAN
    price_text=format(Decimal(monthly['price_yuan']).normalize(),'f')+'元'
    relative='data/csv/存档系统/archive_daily_rules.csv';path=ROOT/relative;raw=path.read_bytes()
    _,records=read(path);entry=next(p for p in records if p.get('pass_sku')=='archive_pass_monthly')
    old=entry['price_text'];assert old in ('20元','10元',price_text)
    assert raw.count((','+old+',').encode())==1
    backup(relative)
    path.write_bytes(raw.replace((','+old+',').encode(),(','+price_text+',').encode()))
    sys.path.insert(0,str(ROOT/'tools'))
    from build_configs import build
    target=ROOT/'scripts/vscripts/config/generated/archive_daily_rules.lua'
    backup(target.relative_to(ROOT).as_posix());build(path,target)

def apply():
    OUT.mkdir(parents=True,exist_ok=True)
    commerce=update_prices(COMMERCE,'price','price_baseline',129)
    payment=update_prices(PAYMENT,'price_yuan','price_baseline_yuan',8)
    previews=display();monthly_rule()
    report=dict(status='PASS',policy=POLICY,discounted_commerce_count=len(commerce),discounted_payment_count=sum(p['price_policy']==POLICY for p in payment),
                fixed_price_payment_count=sum(p['price_policy']==MONTHLY_FIXED_POLICY for p in payment),
                preview_count=previews,recharge_discounted=False,new_u_coin_per_yuan=RATE,commerce=commerce,payment=payment)
    (OUT/'price_changes.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in report.items() if k not in ('commerce','payment')},ensure_ascii=False))

def export():
    sys.path.insert(0,str(ROOT/'server'))
    from payment_backend.csv_catalog import build,canonical,SOURCES
    from payment_backend.commerce_bundles import compile_commerce
    from payment_backend.ucoin_catalog import U_COIN_PER_YUAN
    assert U_COIN_PER_YUAN==RATE,'payment_rate_not_updated'
    package=build(ROOT)
    reference={p:(ROOT/'data/csv'/p).read_text(encoding='utf-8-sig') for p in SOURCES}
    commerce=compile_commerce(package['commerce_tables'],reference,package['tables']['payment_categories'])
    OUT.mkdir(parents=True,exist_ok=True)
    artifacts={'commerce_catalog.json':commerce,'payment_catalog.json':package['catalog'],'payment_package.json':package}
    for filename,value in artifacts.items():(OUT/filename).write_bytes(canonical(value))
    print(json.dumps({'status':'PASS','commerce':len(commerce['products']),'payment':len(package['catalog']['products']),
        'payment_catalog_hash':package['catalog_hash'],'artifacts':{n:hashlib.sha256(canonical(v)).hexdigest() for n,v in artifacts.items()}},ensure_ascii=False))

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--apply',action='store_true');parser.add_argument('--export',action='store_true')
    args=parser.parse_args();assert args.apply or args.export,'choose --apply or --export'
    if args.apply:apply()
    if args.export:export()
