"""Narrow, repeatable functional imports; never change existing prices/rewards."""
import argparse,csv,hashlib,io,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'data/csv/商城兑换系统'
BEFORE=ROOT/'design_refs/shop_functional_20261016/before/data/csv/商城兑换系统'
NEW={'video_p016','video_p028','video_p079','video_p147'}
def read(path):
    with path.open(encoding='utf-8-sig',newline='') as f:
        reader=csv.DictReader(f);return reader.fieldnames,list(reader)
def dump(fields,rows):
    s=io.StringIO(newline='');w=csv.DictWriter(s,fieldnames=fields,lineterminator='\n');w.writeheader();w.writerows(rows);return b'\xef\xbb\xbf'+s.getvalue().encode('utf8')
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--enable-verified-functions',action='store_true');args=ap.parse_args()
    pf,products=read(BEFORE/'commerce_products.csv');rf,rewards=read(BEFORE/'commerce_rewards.csv')
    sf,statuses=read(BEFORE/'commerce_import_status.csv');mf,members=read(BEFORE/'commerce_bundle_members.csv')
    reviewed=json.loads((ROOT/'design_refs/shop_catalog_20261016/video/catalog_reviewed.json').read_text('utf8'))
    source={r['source_id']:r for r in reviewed['all_products']}
    seed=next(r for r in json.loads((ROOT/'design_refs/shop_catalog_20261016/video/new_items_reviewed.json').read_text('utf8'))['items'] if r['source_id']=='P147')
    definitions={
      'P016':('泰坦护盾·永久（功能版）','commerce_p016','custom_game/reward_art_v5/lottery_dimensional_barrier.png',
        '周围2000范围内友军护甲+100\n周围2000范围内友军每秒回血+1000\n周围2000范围内敌军护甲-30\n星悦积分+298\n购买后自动激活\n本项目功能版：不包含腾龙光环皮肤。光环跟随自己的英雄；没有存活英雄时跟随自己的建造者。同类光环不叠加。',
        {'starjoy_points':298}),
      'P028':('熟练工头·永久（功能版）','commerce_p028','custom_game/reward_art_v5/lottery_seed_of_all_wood.png',
        '伐木效率+2\n每秒木材+3\n每秒金币+2\n金矿效率+10%\n金矿建造上限+1\n星悦积分+238\n购买后自动激活\n本项目功能版：保留采集与收益功能，不包含农民皮肤。',
        {'lumberjack_efficiency':2,'wood_per_second':3,'gold_per_second':2,'gold_mine_efficiency_pct':10,'gold_mine_build_cap':1,'starjoy_points':238}),
      'P079':('齐天大圣·永久','lottery_monkey_king','custom_game/reward_art_v5/lottery_monkey_king.png',
        '地图等级+1\n英雄攻击减甲+10\n英雄攻击加攻击+10\n英雄攻击全属性+10\n英雄攻击加成+10%\n英雄全属性加成+10%\n英雄最终伤害+10%\n星悦积分+200\n解锁英雄：齐天大圣\n购买后自动激活\n本项目规则：与现有齐天大圣抽奖道具共用持有身份，不重复购买。使用本项目现有英雄与技能；不包含魔法少女羁绊及羁绊一转效果。',
        {'map_level':1,'hero_attack_armor_reduction':10,'hero_basic_attack_growth':10,'hero_attribute_growth':10,'hero_attack_bonus_pct':10,'hero_attribute_bonus_pct':10,'hero_final_damage_bonus_pct':10,'starjoy_points':200}),
      'P147':('悲叹之种·永久','commerce_p147','custom_game/reward_art_v5/lottery_seed_of_all_wood.png',
        seed['full_effect_text'].replace('EX+8%.英雄','EX+8%\n英雄')+'\n本项目规则：EX为独立乘区；技能重抽每局额外5次，读取最新存档后生效，重连不重复发放。',
        {'hero_attack_armor_reduction':25,'hero_basic_attack_growth':25,'hero_attribute_growth':25,'hero_attack_bonus_pct':25,'hero_attribute_bonus_pct':25,'hero_final_damage_bonus_pct':25,'hero_attack_armor_reduction_pct':8,'hero_attack_attribute_efficiency_pct':8}),
    }
    labels={'starjoy_points':'星悦积分','lumberjack_efficiency':'伐木效率','wood_per_second':'每秒木材','gold_per_second':'每秒金币',
      'gold_mine_efficiency_pct':'金矿效率','gold_mine_build_cap':'金矿建造上限','map_level':'地图等级',
      'hero_attack_armor_reduction':'英雄攻击减甲','hero_basic_attack_growth':'英雄攻击加攻击','hero_attribute_growth':'英雄攻击全属性',
      'hero_attack_bonus_pct':'英雄攻击加成','hero_attribute_bonus_pct':'英雄全属性加成','hero_final_damage_bonus_pct':'英雄最终伤害',
      'hero_attack_armor_reduction_pct':'英雄攻击减甲百分比','hero_attack_attribute_efficiency_pct':'英雄攻击属性效率'}
    for sid,(title,marker,icon,description,effects) in definitions.items():
        s=source[sid];n=int(sid[1:]);sku='video_'+sid.lower();price=s.get('video_original_price') or s['video_price']
        assert price and (ROOT/'panorama/src/images'/icon).is_file()
        row={k:'' for k in pf};row.update(sku=sku,display_name=title,category_id='technology' if s['currency']=='u_coin' else 'item',
          product_type='single',currency=s['currency'],price=str(price),purchase_limit='1',enabled='1' if args.enable_verified_functions else '0',
          sort_order=str(n),icon=icon,description=description,ownership_id=marker,source_id=sid,source_current_price=str(s['video_price']),
          source_original_price=str(s.get('video_original_price') or ''),source_time=str(s['evidence_seconds']),price_date='2026-10-16',description_date='2026-10-16',ownership_quantity='1')
        products.append(row)
        for i,(field,amount) in enumerate(effects.items(),1):
            rewards.append(dict(reward_id=sku+'_r'+str(i),sku=sku,reward_type='stat',target_id=field,amount=str(amount),display_name=labels[field],enabled='1'))
        old=next(r for r in statuses if r['source_id']==sid)
        old.update(assessment='B',status='ready' if args.enable_verified_functions else 'validation_pending',batch='2026-10-16功能版补录',
          implementation_notes=description,source_differences='用户明确要求接入视频中可实现的非皮肤功能；原价保留。商品实际权益按本项目说明，未实现皮肤/羁绊不作承诺。')
    parent=next(r for r in products if r['sku']=='video_bundle_b003')
    parent['enabled']='1' if args.enable_verified_functions else '0'
    component=next(r for r in members if r['bundle_sku']==parent['sku'] and r['target_id']=='P028')
    component.update(member_type='product',target_id='video_p028')
    index={r['sku']:r for r in products}
    parent['description']='本项目功能版：不包含农民皮肤。\n限购1次，与单品共用持有记录；重复领取不会重复加成。\n'+'\n\n'.join(index[m['target_id']]['display_name']+' ×1\n'+index[m['target_id']]['description'] for m in members if m['bundle_sku']==parent['sku'])
    before_products={r['sku']:r for r in read(BEFORE/'commerce_products.csv')[1]}
    assert len([r for r in products if not r['sku'].startswith('#')])==129
    assert all(r==before_products[r['sku']] for r in products if r['sku'] in before_products and r['sku']!='video_bundle_b003')
    assert parent['price']==before_products[parent['sku']]['price']=='46560'
    state_file=ROOT/'design_refs/shop_functional_20261016/import_state.json'
    prior_state=json.loads(state_file.read_text('utf8')) if state_file.exists() else {'files':{}}
    state={'files':{}};writes=[]
    for name,fields,rows in [('commerce_products',pf,products),('commerce_rewards',rf,rewards),('commerce_import_status',sf,statuses),('commerce_bundle_members',mf,members)]:
        target=BASE/(name+'.csv');current=target.read_bytes();baseline=(BEFORE/target.name).read_bytes();new=dump(fields,rows)
        relative=target.relative_to(ROOT).as_posix()
        assert current in (baseline,new) or hashlib.sha256(current).hexdigest()==prior_state['files'].get(relative),'concurrent_change:'+name
        writes.append((target,new))
        state['files'][relative]=hashlib.sha256(new).hexdigest()
    for target,new in writes:target.write_bytes(new)
    state_file.write_text(json.dumps(state,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    # Insert the imports in recorded order, retaining the existing five groups.
    presentation_path=ROOT/'data/ui/shop_catalog_presentation_20261016.json'
    old=json.loads(presentation_path.read_text('utf8'));presentation=json.loads(json.dumps(old))
    mapping={r['source_id']:r['project_sku'] for r in reviewed['all_products'] if r['project_sku']}
    mapping.update({sid:'video_'+sid.lower() for sid in [*definitions,'P140','P151']})
    single=[mapping[r['source_id']] for r in reviewed['all_products'] if r['source_id'] in mapping]
    all_rows=single+reviewed['groups']['bundles']['skus']+reviewed['groups']['vip']['skus']
    presentation['groups'].update(home=all_rows,all=all_rows,promotions=[mapping[s] for s in reviewed['groups']['promotions']['sources'] if s in mapping])
    presentation['metadata']['all']['mapped_single_count']=len(single)
    presentation['metadata']['promotions']['mapped_count']=len(presentation['groups']['promotions'])
    presentation['metadata']['reserved_import_skus']=sorted(NEW|{'video_p140','video_p151'})
    presentation['metadata']['unmapped_sources_omitted']=[r['source_id'] for r in reviewed['all_products'] if r['source_id'] not in mapping]
    presentation_path.write_text(json.dumps(presentation,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    js=ROOT/'panorama/src/scripts/custom_game/video_shop_bundles.js';raw=js.read_text('utf8')
    import re
    raw,count=re.subn(r'(GameUI\.CustomUIConfig\(\)\.SurvivalShopPresentation=).*?(;\n// END SURVIVAL SHOP PRESENTATION 20261016)',lambda m:m[1]+json.dumps(presentation,ensure_ascii=False,separators=(',',':'))+m[2],raw,flags=re.S)
    assert count==1
    # Read-only fallback stays explicitly pending until the authenticated catalog.
    pattern=r'(GameUI\.CustomUIConfig\(\)\.VideoShopBundleCatalog=)(.*?)(;\n)'
    match=re.search(pattern,raw);fallback=json.loads(match[2]);pack=next(p for p in fallback['products'] if p['sku']==parent['sku'])
    pack.update(description=parent['description'],configured_enabled=args.enable_verified_functions,disabled_reason='payment_catalog_pending',disabled_message='商品目录正在同步，请稍后重试。')
    pack['reward_lines']=[dict(kind='product',id=m['target_id'],quantity=1,label=index[m['target_id']]['display_name'],icon=index[m['target_id']]['icon'],description=index[m['target_id']]['description']) for m in members if m['bundle_sku']==parent['sku']]
    raw=raw[:match.start(2)]+json.dumps(fallback,ensure_ascii=False,separators=(',',':'))+raw[match.end(2):];js.write_text(raw,encoding='utf8')
    print(json.dumps({'added':sorted(NEW),'starterpack_enabled':parent['enabled'],'starterpack_price_unchanged':parent['price'],'all_prices_preserved':True,'fallback_cannot_authorize_purchase':True},ensure_ascii=False))
if __name__=='__main__':main()
