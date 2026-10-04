"""Compile commercial CSVs against existing game capabilities; fail, never skip rewards."""
import csv
from decimal import Decimal, InvalidOperation
import hashlib
import io
import json
from pathlib import Path
import re

ID=re.compile(r'[a-z][a-z0-9_]{2,63}\Z')
SOURCES=('商店系统/entitlement_definitions.csv','玩家档案系统/player_gameplay_stats.csv',
         '玩家档案系统/map_level_effect_rules.csv','抽奖系统/lottery_item_definitions.csv','抽奖系统/lottery_currency_definitions.csv')
TABLES=('payment_categories','payment_products','payment_rewards')
SUPPORTED_ENTITLEMENTS={'vip','archive_pass'}

def rows(text):
    result=[]
    for row in csv.DictReader(io.StringIO(text.lstrip('\ufeff'))):
        key=next(iter(row.values()),'')
        if not key or key.startswith('#'):continue
        if None in row or any(v is None for v in row.values()):raise ValueError('CSV列数不正确')
        result.append({k:v.strip() for k,v in row.items()})
    return result

def flag(value):
    if value not in ('0','1'):raise ValueError('启用值必须是0或1')
    return value=='1'

def number(value, integer=False, minimum=0, maximum=100000000):
    try:n=Decimal(str(value))
    except InvalidOperation:raise ValueError('数值格式不正确') from None
    if not n.is_finite() or not minimum<=n<=maximum or (integer and n!=n.to_integral()):raise ValueError('数值超出范围或需要整数')
    return int(n) if n==n.to_integral() else float(n)

def indexed(data,key):
    result={}
    for row in data:
        value=row[key]
        if not ID.fullmatch(value) or value in result:raise ValueError('ID无效或重复: '+value)
        result[value]=row
    return result

def canonical(data):return json.dumps(data,ensure_ascii=False,sort_keys=True,separators=(',',':'),allow_nan=False).encode()

def compile_catalog(tables,reference, *, max_products=100):
    categories=indexed(rows(tables['payment_categories']),'category_id')
    products=indexed(rows(tables['payment_products']),'sku')
    rewards=indexed(rows(tables['payment_rewards']),'reward_id')
    stats=indexed(rows(reference[SOURCES[1]]),'field_id')
    items=indexed(rows(reference[SOURCES[3]]),'item_id')
    currencies=indexed(rows(reference[SOURCES[4]]),'currency_id')
    permissions=indexed(rows(reference[SOURCES[0]]),'entitlement_id')
    category_rows=[dict(id=k,label=v['display_name'],sort=number(v['sort_order'],True)) for k,v in categories.items() if flag(v['enabled'])]
    category_rows.sort(key=lambda x:x['sort'])
    if not category_rows or len(category_rows)>8:raise ValueError('启用分类应为1至8个')
    for row in rewards.values():
        if row['sku'] not in products:raise ValueError('奖励引用不存在商品: '+row['sku'])
    result=[];markers=set()
    for sku,p in products.items():
        if len(sku)<4:raise ValueError('商品sku至少4个字符: '+sku)
        enabled=flag(p['enabled'])
        if p['category_id'] not in categories or not flag(categories[p['category_id']]['enabled']):raise ValueError(sku+': 分类不存在或未启用')
        if p['product_type'] not in ('single','bundle'):raise ValueError(sku+': 商品类型必须为single或bundle')
        try:cents=Decimal(p['price_yuan'])*100
        except InvalidOperation:raise ValueError(sku+': 价格格式不正确') from None
        amount=number(cents,True,1,1000000)
        marker=p['ownership_id']
        if not ID.fullmatch(marker) or marker in markers:raise ValueError(sku+': 持有标记无效或重复')
        markers.add(marker)
        icon=p['icon']
        if '..' in icon or not re.fullmatch(r'custom_game/[a-zA-Z0-9_/-]+\.png',icon):raise ValueError(sku+': 图标路径不正确')
        effects={};inventory={};limits={};entitlements=[];lines=[]
        def add(field,value):
            rule=stats.get(field)
            if not rule or not flag(rule['enabled']) or field=='online_seconds_total':raise ValueError(sku+': 不支持的属性 '+field)
            amount=number(value,rule['storage_type']=='integer',0)
            if not amount:raise ValueError(sku+': 奖励必须大于0')
            total=Decimal(str(effects.get(field,0)))+Decimal(str(amount))
            if rule['max_value'] and total>Decimal(rule['max_value']):raise ValueError(sku+': 单次属性超过上限 '+field)
            effects[field]=number(total)
        selected=[r for r in rewards.values() if r['sku']==sku and flag(r['enabled'])]
        if not selected:raise ValueError(sku+': 商品没有奖励')
        for r in selected:
            kind,target=r['reward_type'],r['target_id']
            amount=number(r['amount'],kind!='stat',0.000001,1000000)
            if not ID.fullmatch(target):raise ValueError(sku+': 奖励目标无效')
            if kind=='stat':add(target,amount)
            elif kind=='item':
                if target in items:
                    item=items[target]
                    if not flag(item['enabled']) or item['effect_status']!='implemented' or item['duration_type']!='permanent':
                        raise ValueError(sku+': 道具不是完整实现的永久道具 '+target)
                    limits[target]=number(item['max_owned'],True,1)
                    ids=item['effect_ids'].split('|');values=item['effect_values'].split('|')
                    if len(ids)!=len(values):raise ValueError('道具属性配置不匹配: '+target)
                    for field,value in zip(ids,values):add(field,Decimal(value)*amount)
                elif target in currencies and flag(currencies[target]['enabled']) and currencies[target]['acquisition_policy']=='external_purchase_only':
                    limits[target]=2147483647
                else:raise ValueError(sku+': 不支持此付费道具或抽奖券 '+target)
                inventory[target]=inventory.get(target,0)+amount
                if inventory[target]>limits[target]:raise ValueError(sku+': 道具数量超过持有上限 '+target)
            elif kind=='entitlement':
                if target not in SUPPORTED_ENTITLEMENTS or target not in permissions or not flag(permissions[target]['enabled']) or amount!=1 or target in entitlements:
                    raise ValueError(sku+': 权限不存在、重复或数量不是1 '+target)
                entitlements.append(target)
            else:raise ValueError(sku+': 未支持的奖励类型 '+kind)
            lines.append(dict(kind=kind,id=target,quantity=amount,label=r['display_name'] or target))
        if marker in inventory:raise ValueError(sku+': 持有标记不能兼作礼包道具')
        # Follow the existing settlement's map-level derived fields.
        if effects.get('map_level'):
            for rule in rows(reference[SOURCES[2]]):
                if flag(rule['enabled']):add(rule['target_field_id'],Decimal(str(effects['map_level']))*Decimal(rule['value_per_level']))
        result.append(dict(sku=sku,item_id=marker,title=p['display_name'],description=p['description'],
            amount=number(cents,True,1,1000000),effects=effects,enabled=enabled,sort_order=number(p['sort_order'],True),
            purchase_limit=number(p['purchase_limit'],True,0,10000),category_id=p['category_id'],product_type=p['product_type'],icon=icon,
            grants=dict(items=inventory,item_limits=limits,entitlements=entitlements,lines=lines,
                effect_labels={field:re.split('[；。]',stats[field]['notes'])[0] or field for field in effects})))
    if len(result)>max_products or not any(x['enabled'] for x in result):raise ValueError(f'需有启用商品，最多{max_products}项')
    return dict(protocol=4,categories=category_rows,products=sorted(result,key=lambda x:x['sort_order']))

def build(root):
    base=Path(root)/'data/csv'
    tables={name:(base/'商城支付系统'/f'{name}.csv').read_text(encoding='utf-8-sig') for name in TABLES}
    reference={name:(base/name).read_text(encoding='utf-8-sig') for name in SOURCES}
    data=compile_catalog(tables,reference)
    return dict(tables=tables,reference_hashes={k:hashlib.sha256(v.encode()).hexdigest() for k,v in reference.items()},
                catalog=data,catalog_hash=hashlib.sha256(canonical(data)).hexdigest())
