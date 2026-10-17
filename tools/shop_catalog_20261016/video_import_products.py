"""Append only two fully reviewed video products, preserving existing commerce.

P151 stays disabled by default until its complete archive/void projection has
passed the owning agent's checks. --enable-p151 is an explicit operator switch
to run only after that check; it never changes any pre-existing product.
"""
import argparse,csv,hashlib,io,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'data/csv/商城兑换系统'
REPORT=ROOT/'design_refs/shop_catalog_20261016/video/import'
NEW_SKUS={'video_p140','video_p151'}

def digest(data):return hashlib.sha256(data).hexdigest()
def read(path):
    with path.open(encoding='utf-8-sig',newline='') as stream:
        reader=csv.DictReader(stream);return reader.fieldnames,list(reader)
def actual(rows,key):return [r for r in rows if not r[key].startswith('#')]
def serialize(fields,rows):
    stream=io.StringIO(newline='');writer=csv.DictWriter(stream,fieldnames=fields,lineterminator='\n');writer.writerows(rows);return stream.getvalue().encode('utf8')
def append_rows(path,fields,old,new,key):
    before=path.read_bytes();index={r[key]:r for r in old};added=[]
    for row in new:
        if row[key] in index:
            assert index[row[key]]==row,f'existing new row differs: {row[key]}'
        else:added.append(row)
    if added:
        after=before+(b'' if before.endswith(b'\n') else b'\n')+serialize(fields,added)
        assert after.startswith(before),'original bytes changed';path.write_bytes(after)
    return [r[key] for r in added]

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--enable-p151',action='store_true');a=parser.parse_args()
    REPORT.mkdir(parents=True,exist_ok=True)
    targets=[BASE/n for n in ['commerce_products.csv','commerce_rewards.csv','commerce_import_status.csv']]
    originals={p.name:p.read_bytes() for p in targets}
    pf,products=read(targets[0]);rf,rewards=read(targets[1]);sf,status=read(targets[2])
    old_products=[r for r in products if r['sku']not in NEW_SKUS];old_rewards=[r for r in rewards if r['sku']not in NEW_SKUS]
    assert len(actual(old_products,'sku'))==123,'unexpected legacy product count'
    assert all(next(r for r in products if r['sku']==s)['enabled']=='0' for s in ['video_p037','video_p038']),'shop gold must remain closed'
    for path in targets:
        backup=REPORT/('before_'+path.name)
        if not backup.exists():backup.write_bytes(originals[path.name])
    evidence=json.loads((ROOT/'design_refs/shop_catalog_20261016/video/new_items_reviewed.json').read_text(encoding='utf8'))
    source={r['source_id']:r for r in evidence['items']}
    new_products=[]
    for source_id,price,ownership,icon in [
      ('P140',588,'lottery_nature_spirit','custom_game/reward_art_v5/lottery_nature_spirit.png'),
      ('P151',5000,'commerce_p151','custom_game/reward_art_v5/lottery_muramasa.png')]:
        n=int(source_id[1:]);s=source[source_id]
        assert (ROOT/'panorama/src/images'/icon).is_file(),'missing actual icon'
        row={k:'' for k in pf}
        row.update(sku=f'video_p{n}',display_name='自然精粹·永久' if n==140 else '斩魄刀·永久',category_id='item',product_type='single',currency='shop_points',price=str(price),purchase_limit='1',enabled='1' if n==140 or a.enable_p151 else '0',sort_order=str(n),icon=icon,description=s['full_effect_text'],ownership_id=ownership,source_id=source_id,source_current_price=str(price),source_time=str(s['description_evidence_seconds']),price_date='2026-10-16',description_date='2026-10-16',ownership_quantity='1')
        new_products.append(row)
    # This sole update affects only our new P151 row after explicit full-effect
    # verification. Its original appended row is deterministic and byte-located.
    existing_new={r['sku']:r for r in products if r['sku'] in NEW_SKUS}
    for row in new_products:
        previous=existing_new.get(row['sku'])
        if previous and previous!=row:
            assert row['sku']=='video_p151' and a.enable_p151
            difference={k for k in pf if previous[k]!=row[k]};assert difference=={'enabled'} and previous['enabled']=='0' and row['enabled']=='1',difference
            before=targets[0].read_bytes();old_bytes=serialize(pf,[previous]);new_bytes=serialize(pf,[row])
            assert before.count(old_bytes)==1,'new row cannot be located exactly'
            targets[0].write_bytes(before.replace(old_bytes,new_bytes,1));previous.update(row)
    added_products=append_rows(targets[0],pf,products,new_products,'sku')
    effects=[
      ('video_p140','wood_per_second','1','每秒木材'),
      ('video_p151','map_level','1','地图等级'),
      ('video_p151','wall_armor','1000','墙护甲'),
      ('video_p151','wall_armor_per_second','0.15','墙每秒护甲'),
      ('video_p151','hero_final_damage_bonus_pct','35','英雄最终伤害'),
      ('video_p151','hero_attribute_bonus_pct','35','英雄全属性加成'),
      ('video_p151','hero_attribute_growth','35','英雄攻击全属性'),
      ('video_p151','hero_attack_armor_reduction','35','英雄攻击减甲'),
      ('video_p151','hero_damage_attack_growth','35','英雄造成伤害加攻击'),
      ('video_p151','starjoy_points','200','星悦积分')]
    counters={};new_rewards=[]
    for sku,field,amount,label in effects:
        counters[sku]=counters.get(sku,0)+1
        new_rewards.append(dict(reward_id=f'{sku}_r{counters[sku]}',sku=sku,reward_type='stat',target_id=field,amount=amount,display_name=label,enabled='1'))
    added_rewards=append_rows(targets[1],rf,rewards,new_rewards,'reward_id')
    # P140 is the only historical assessment amended. IDs P141-P151 are new
    # local review identifiers; they are not claimed to come from the video.
    p140=next(r for r in status if r['source_id']=='P140')
    p140.update(assessment='A',status='ready',batch='2026-10-16完整视频补录',implementation_notes='新视频531秒已实际核对：永久、588积分、每秒木材+1；复用正式lottery_nature_spirit物品身份与同名图标，限拥有1件；与现有抽奖持有记录共用限额。',source_differences='原missing_description已由本次录屏补齐；不修改旧抽奖奖励、概率或分解规则。')
    states={141:('','missing_description','录屏仅出现名称/SSR/永久/2388积分，未悬停说明；不杜撰效果，不上架。'),142:('','missing_description','录屏仅出现名称/SSR/永久/2388积分，未悬停说明；不杜撰效果，不上架。'),143:('','missing_description','录屏仅出现名称/SSR/永久/2388积分，未悬停说明；不杜撰效果，不上架。'),144:('','missing_description','录屏仅出现名称/SSR/永久/2388积分，未悬停说明；不杜撰效果，不上架。'),145:('E','excluded_model','说明完整，但沧澜女王英雄模型、专属技能与蔷薇之刃/魔法少女/齐天大圣的继承羁绊未有完整接入；不只发静态数值冒充完整英雄商品。'),146:('E','excluded_model','说明完整，但承诺获得宠物皮肤幽冥妖姬，项目无对应正式外观绑定；不以其他模型替代后冒充原品。'),147:('D','deferred','说明完整；每局英雄技能刷新次数额外+5和英雄攻击属性效率、EX伤害/属性独立叠加口径尚需完整权威实现与验收。'),148:('D','deferred','说明完整；依赖已有双传说词条存档装备额外随机两个传说词条的装备实例、生成及持久化链路，不只发基础属性替代。'),149:('D','deferred','说明完整；提前挑战缩短180秒、提前通关难度系数降低50%及城墙致命伤害周围眩晕10秒需统一结算与去重测试。'),150:('D','deferred','说明完整；宠物额外两条词条与每局宝物额外刷新+5依赖正式词条/宝物接口；原文英雄攻击全属性+60%含百分号，不能擅自按固定60导入。'),151:('B','ready','完整说明已补录；静态9项按正式字段导入。秘法牢笼与虚空之影属性额外20%由永久奖励投影按持有commerce_p151实现；'+('完整投影验收已由操作方确认，商品开放。' if a.enable_p151 else '完整投影验收通过后方可开放，当前商品enabled=0，避免不完整权益可购。'))}
    existing_status={r['source_id']:r for r in status}
    for n,(assessment,state,notes) in states.items():
        key=f'P{n}';row={k:'' for k in sf};row.update(source_id=key,display_name=source[key]['video_name']+'*永久',assessment=assessment,status=state,batch='2026-10-16完整视频补录',implementation_notes=notes,source_differences='本项目新分配审阅ID；录屏未提供商品ID。')
        if key in existing_status:
            assert key=='P151' or existing_status[key]==row,'unexpected prior new assessment change'
            existing_status[key].update(row)
        else:status.append(row)
    with targets[2].open('w',encoding='utf-8-sig',newline='') as stream:
        writer=csv.DictWriter(stream,fieldnames=sf,lineterminator='\n');writer.writeheader();writer.writerows(status)
    _,after_products=read(targets[0]);_,after_rewards=read(targets[1]);_,after_status=read(targets[2])
    assert [r for r in after_products if r['sku']not in NEW_SKUS]==old_products,'legacy product fields changed'
    assert [r for r in after_rewards if r['sku']not in NEW_SKUS]==old_rewards,'legacy reward fields changed'
    old_status_rows=list(csv.DictReader(io.StringIO(originals['commerce_import_status.csv'].decode('utf-8-sig'),newline='')))
    after_status_index={r['source_id']:r for r in after_status}
    assert all(after_status_index[r['source_id']]==r for r in old_status_rows if r['source_id']not in {'P140',*[f'P{n}' for n in range(141,152)]}),'old assessment changed outside P140'
    assert len(actual(after_products,'sku'))==125
    result={'ok':True,'legacy_product_count':123,'legacy_products_all_fields_unchanged':True,'legacy_rewards_all_fields_unchanged':True,'historical_status_changes':['P140'],'new_status_sources':[f'P{n}'for n in range(141,152)],'products_appended':added_products,'reward_rows_appended':added_rewards,'total_products':125,'p151_enabled':a.enable_p151,'p151_complete_projection_verified_by_operator':a.enable_p151,'shop_gold_products_remain_disabled':True,'source_evidence':'design_refs/shop_catalog_20261016/video/new_items_reviewed.json','files':{p.name:{'before_sha256':digest(originals[p.name]),'after_sha256':digest(p.read_bytes())}for p in targets}}
    payload=json.dumps(result,ensure_ascii=False,indent=2)+'\n'
    initial=REPORT/'initial_report.json'
    if not initial.exists():
        previous=REPORT/'report.json'
        initial.write_text(previous.read_text(encoding='utf8') if previous.exists() else payload,encoding='utf8')
    (REPORT/'report.json').write_text(payload,encoding='utf8')
    print(json.dumps({k:v for k,v in result.items()if k!='files'},ensure_ascii=False))

if __name__=='__main__':main()
