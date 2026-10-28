"""Compile reviewed product/VIP bundles from server-owned references only."""
from __future__ import annotations
import copy
import csv
from decimal import Decimal
import io
import re
from .csv_catalog import ID, SOURCES, compile_catalog, flag, indexed, number, rows, validate_price_policy, FIXED_QUALITY_SHOP_POINTS_POLICY

MEMBER_TABLE = 'commerce_bundle_members'
EMPTY_MEMBERS = 'member_id,bundle_sku,member_type,target_id,quantity,sort_order,enabled\n'
VIP_SOURCE = '存档系统/archive_vip_rewards.csv'
STATUS_SOURCE = '商城兑换系统/commerce_import_status.csv'
PRODUCT_FIELDS = ('sku','display_name','category_id','product_type','price_yuan','purchase_limit','enabled','sort_order','icon','description','ownership_id')
REWARD_FIELDS = ('reward_id','sku','reward_type','target_id','amount','display_name','enabled','duration_days')

def csv_text(records,fields):
    output=io.StringIO(); writer=csv.DictWriter(output,fieldnames=fields)
    writer.writeheader(); writer.writerows({key:row.get(key,'') for key in fields} for row in records)
    return output.getvalue()

def price(product,bundle=False):
    value=number(product['price'],True,1,100000000)
    expected=(product.get('source_current_price') if bundle else product.get('source_original_price') or product.get('source_current_price'))
    expected=number(expected,True,1,100000000)
    discounted=validate_price_policy(product,value,'price_baseline',expected_baseline=expected)
    if not discounted and value!=expected:
        raise ValueError('commerce_reference_price_mismatch:'+product['sku'])
    original=product.get('source_original_price')
    if bundle and original and number(original,True,1,100000000)<value:
        raise ValueError('commerce_bundle_discount_invalid:'+product['sku'])
    return value

def compile_commerce(tables,reference,category_text,*,max_products=200):
    """Return complete flat rewards plus component/claim atomicity metadata.

    A recorded half-price policy validates the previous actual selling price
    against the historical reference. The CSV price is final and is never
    discounted while compiling. Unmarked historical fixtures keep their rule.
    """
    products=indexed(rows(tables['commerce_products']),'sku')
    reward_rows=rows(tables['commerce_rewards'])
    indexed(reward_rows,'reward_id')
    memberships=rows(tables.get(MEMBER_TABLE,EMPTY_MEMBERS))
    indexed(memberships,'member_id')
    by_bundle={}
    for member in memberships:
        parent=products.get(member['bundle_sku'])
        if not parent or parent['product_type']!='bundle':
            raise ValueError('commerce_bundle_parent_invalid:'+member['member_id'])
        if member['member_type'] not in ('product','vip_reward','unavailable'):
            raise ValueError('commerce_bundle_member_type_invalid:'+member['member_id'])
        number(member['quantity'],True,1,100)
        number(member['sort_order'],True,0,1000000)
        if flag(member['enabled']):by_bundle.setdefault(member['bundle_sku'],[]).append(member)
    for sku,members in by_bundle.items():
        members.sort(key=lambda m:(number(m['sort_order'],True),m['member_id']))
        if any(r['sku']==sku and flag(r['enabled']) for r in reward_rows):
            raise ValueError('commerce_bundle_rewards_duplicated:'+sku)
    for reward in reward_rows:
        if reward['sku'] not in products:raise ValueError('commerce_reward_product_missing:'+reward['sku'])
        if reward['reward_type'] not in ('stat','item'):raise ValueError('commerce_reward_type_unsupported:'+reward['sku'])
    for sku,p in products.items():
        if p['currency'] not in ('u_coin','shop_points','shop_gold'):
            raise ValueError('unsupported_commerce_currency:'+sku)
        price(p,sku in by_bundle)
        if p.get('price_policy')==FIXED_QUALITY_SHOP_POINTS_POLICY:
            definition=next((item for item in rows(reference[SOURCES[3]]) if item['item_id']==p['ownership_id']),None)
            if definition and definition['quality'].lower()!=p.get('point_quality'):
                raise ValueError('commerce_fixed_quality_mismatch:'+sku)
    unique_points={r['item_id'] for r in rows(reference[SOURCES[3]])
                   if flag(r['enabled']) and r['item_type']=='积分道具' and r['item_id']!='lottery_ember_of_legacy'}
    for sku,p in products.items():
        # Disabled historical offers retain their exact price and reward data.
        # A live offer may never reintroduce stacked permanent lottery goods.
        if flag(p['enabled']) and p['ownership_id'] in unique_points:
            if number(p.get('ownership_quantity') or 1,True,1,100)!=1 or number(p['purchase_limit'],True)!=1:
                raise ValueError('commerce_unique_points_ownership_invalid:'+sku)
    leaves=[p for sku,p in products.items() if sku not in by_bundle]
    converted=[]
    for p in leaves:
        product={key:p[key] for key in PRODUCT_FIELDS if key!='price_yuan'};product['price_yuan']='1.00'
        if p.get('source_id')=='P103':
            if p['ownership_id']!='lottery_ember_of_legacy':
                raise ValueError('commerce_ember_ownership_invalid')
            product['ownership_id']+='_single'
        converted.append(product)
    leaf_catalog=compile_catalog({'payment_categories':category_text,
        'payment_products':csv_text(converted,PRODUCT_FIELDS),
        'payment_rewards':csv_text([r for r in reward_rows if r['sku'] not in by_bundle],REWARD_FIELDS)},reference,max_products=max_products) if leaves else {'products':[]}
    compiled={p['sku']:p for p in leaf_catalog['products']}
    for sku,product in compiled.items():
        # New ember quantities use the inventory-derived combat projection.
        # Keep disabled historical bulk offers intact for immutable receipts.
        marker=products[sku]['ownership_id']
        if marker in ('lottery_ember_of_legacy','welfare_zongzi') and flag(products[sku]['enabled']):
            product['effects'].pop('hero_basic_attack_growth',None)
            product['grants']['effect_labels'].pop('hero_basic_attack_growth',None)
            product['grants']['lines']=[dict(kind='item',id=marker,
                quantity=number(products[sku].get('ownership_quantity') or 1,True,1,100),
                label='薪火余烬' if marker=='lottery_ember_of_legacy' else '粽子')]
    # Validate all roots, including disabled ones; their marker and icon are never
    # exempted from the formal catalog contract.
    markers={}
    for sku,p in products.items():
        marker=p['ownership_id']
        existing=markers.get(marker)
        shared_ember=existing and marker=='lottery_ember_of_legacy' and {existing.get('source_id'),p.get('source_id')}=={'P089','P103'}
        if not ID.fullmatch(marker) or existing and not shared_ember:raise ValueError('commerce_ownership_marker_invalid:'+sku)
        markers[marker]=p
    vip_rows={row['reward_id']:row for row in rows(reference.get(VIP_SOURCE,''))}
    statuses={row['source_id']:row for row in rows(reference.get(STATUS_SOURCE,''))}
    vip_cache={}
    def vip_reward(identity,icon):
        row=vip_rows.get(identity)
        if not re.fullmatch(r'vip_(package|medal)_(0[1-9]|1[0-2])',identity) or not row or not flag(row['enabled']) or row['group_id'] not in ('packages','medals'):
            raise ValueError('commerce_vip_reward_invalid:'+identity)
        if identity not in vip_cache:
            fields=row['effect_ids'].split('|'); values=row['effect_values'].split('|')
            if len(fields)!=len(values):raise ValueError('commerce_vip_effect_mismatch:'+identity)
            synthetic='bundle_ref_'+identity
            product=dict(sku=synthetic,display_name=row['display_name'],category_id='bundles',product_type='single',
                price_yuan='1.00',purchase_limit=1,enabled=1,sort_order=0,icon=icon,description=row['description'],ownership_id='ref_'+identity)
            rewards=[dict(reward_id=synthetic+'_'+str(i),sku=synthetic,reward_type='stat',target_id=field,amount=value,display_name=field,enabled=1)
                for i,(field,value) in enumerate(zip(fields,values))]
            vip_cache[identity]=compile_catalog({'payment_categories':category_text,'payment_products':csv_text([product],PRODUCT_FIELDS),
                'payment_rewards':csv_text(rewards,REWARD_FIELDS)},reference)['products'][0]['effects']
        return row,vip_cache[identity]
    def bundle(sku):
        if sku in compiled:return compiled[sku]
        root=products[sku]; enabled=flag(root['enabled']); components={}; vip={}; lines=[]; pending=[]; leaf_uses=[]
        def walk(identity,quantity,stack,show=False):
            if identity in stack:raise ValueError('commerce_bundle_cycle:'+identity)
            product=products.get(identity)
            if not product:raise ValueError('commerce_bundle_product_missing:'+identity)
            if enabled and not flag(product['enabled']):raise ValueError('commerce_bundle_member_disabled:'+identity)
            if show:lines.append(dict(kind='product',id=identity,quantity=quantity,label=product['display_name'],
                icon=product['icon'],description=product['description']))
            if identity!=sku:
                component=components.setdefault(identity,dict(sku=identity,item_id=product['ownership_id'],quantity=0,purchase_limit=number(product['purchase_limit'],True,0,10000)))
                component['quantity']+=quantity*number(product.get('ownership_quantity') or 1,True,1,100)
            if identity not in by_bundle:
                leaf_uses.append((identity,quantity));return
            for member in by_bundle[identity]:
                count=quantity*number(member['quantity'],True,1,100);target=member['target_id'];kind=member['member_type']
                if count>100:raise ValueError('commerce_bundle_quantity_excessive:'+sku)
                if kind=='product':walk(target,count,stack+[identity],identity==sku)
                elif kind=='vip_reward':
                    if count!=1:raise ValueError('commerce_vip_reward_quantity_invalid:'+target)
                    row,_=vip_reward(target,root['icon'])
                    if row['group_id']=='packages' and target in vip:raise ValueError('commerce_vip_package_duplicated:'+target)
                    vip[target]=row
                    if identity==sku and not any(line['kind']=='vip_reward' and line['id']==target for line in lines):
                        lines.append(dict(kind='vip_reward',id=target,quantity=1,label=row['display_name'],
                            icon=root['icon'],description=row['description']))
                else:
                    status=statuses.get(target)
                    if enabled:raise ValueError('commerce_bundle_unavailable_member:'+target)
                    if not status or status.get('status')=='ready':raise ValueError('commerce_bundle_pending_reference_invalid:'+target)
                    pending.append(target)
                    if identity==sku:lines.append(dict(kind='unavailable',id=target,quantity=count,label=status['display_name'],
                        icon=root['icon'],description=status.get('implementation_notes') or '',reason=status.get('implementation_notes') or status.get('status')))
        walk(sku,1,[])
        for identity,row in list(vip.items()):
            if row['group_id']=='packages' and row.get('medal_id'):
                medal,_=vip_reward(row['medal_id'],root['icon']);vip[medal['reward_id']]=medal
        package_medals={row.get('medal_id') for row in vip.values() if row['group_id']=='packages'}
        for identity,row in vip.items():
            if row['group_id']=='medals' and identity not in package_medals:
                raise ValueError('commerce_vip_medal_without_package:'+identity)
        effects={};inventory={};limits={};labels={};claim_effects={}
        def add_effects(values,multiplier=1):
            for key,value in values.items():effects[key]=number(Decimal(str(effects.get(key,0)))+Decimal(str(value))*multiplier)
        def add_item(identity,count,limit):
            inventory[identity]=inventory.get(identity,0)+count
            limits[identity]=min(limits.get(identity,limit),limit)
            if inventory[identity]>limits[identity]:raise ValueError('commerce_bundle_component_limit:'+identity)
        if not pending:
            component_markers=[c['item_id'] for c in components.values()]
            if len(set(component_markers))!=len(component_markers):raise ValueError('commerce_bundle_component_marker_duplicate:'+sku)
            for identity,quantity in leaf_uses:
                leaf=compiled[identity];add_effects(leaf['effects'],quantity);labels.update(leaf['grants']['effect_labels'])
                for item,count in leaf['grants']['items'].items():add_item(item,count*quantity,leaf['grants']['item_limits'][item])
            for component in components.values():
                limit=component['purchase_limit'] or 100000000
                add_item(component['item_id'],component['quantity'],limit)
            for component in components.values():
                if inventory[component['item_id']]!=component['quantity']:raise ValueError('commerce_bundle_component_item_conflict:'+sku)
            for identity,row in vip.items():
                _,values=vip_reward(identity,root['icon']);add_effects(values)
                if row['group_id']=='medals':claim_effects[identity]=copy.deepcopy(values)
            definitions={row['field_id']:row for row in rows(reference[SOURCES[1]])}
            for field,value in effects.items():
                maximum=definitions[field].get('max_value')
                if maximum and Decimal(str(value))>Decimal(maximum):raise ValueError('commerce_bundle_effect_limit:'+field)
        # Reuse the original product validator for bundle identity, category,
        # price and icon grammar without inventing an actual reward to publish.
        category=next((c for c in rows(category_text) if c['category_id']==root['category_id'] and flag(c['enabled'])),None)
        if not category or not ID.fullmatch(sku) or len(sku)<4:raise ValueError('commerce_bundle_identity_invalid:'+sku)
        if not re.fullmatch(r'custom_game/[a-zA-Z0-9_/-]+\.png',root['icon']) or '..' in root['icon']:raise ValueError('commerce_icon_invalid:'+sku)
        product=dict(sku=sku,item_id=root['ownership_id'],title=root['display_name'],description=root['description'],amount=100,
            effects=effects,enabled=enabled,sort_order=number(root['sort_order'],True),purchase_limit=number(root['purchase_limit'],True,0,10000),
            category_id=root['category_id'],product_type='bundle',icon=root['icon'],grants=dict(items=inventory,item_limits=limits,entitlements=[],lines=lines,effect_labels=labels))
        if pending:
            product['bundle_pending']=True;product['pending_members']=pending
        else:
            if root['ownership_id'] in inventory:raise ValueError('commerce_bundle_root_marker_conflict:'+sku)
            if components:product['grants']['components']=list(components.values())
            if vip:
                required=max(number(row['level'],True,0,12) for row in vip.values())
                if required<1:raise ValueError('commerce_vip_level_invalid:'+sku)
                product['grants'].update(vip_claims=list(vip),vip_claim_effects=claim_effects,required_vip_level=required)
        compiled[sku]=product;return product
    for sku in by_bundle:bundle(sku)
    if len(products)>max_products:raise ValueError('commerce_products_limit')
    for sku,p in compiled.items():
        original=products[sku];p['item_id']=original['ownership_id'];p.pop('amount',None)
        p.update(currency=original['currency'],currency_name={'u_coin':'U币','shop_points':'积分','shop_gold':'金币'}[original['currency']],
            price=price(original,sku in by_bundle),source_id=original['source_id'],purchase_method='wallet',
            ownership_quantity=number(original.get('ownership_quantity') or 1,True,1,100))
        if original.get('price_policy')==FIXED_QUALITY_SHOP_POINTS_POLICY:
            p.update(price_policy=FIXED_QUALITY_SHOP_POINTS_POLICY,point_quality=original['point_quality'])
        if sku in by_bundle:p['original_price']=number(original.get('source_original_price') or original['price'],True,1,100000000)
    return dict(protocol=4,categories=leaf_catalog.get('categories') or [],products=sorted(compiled.values(),key=lambda p:p['sort_order']))
