"""Build human-reviewed video ordering/mapping evidence, never production config."""
import csv,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'design_refs/shop_catalog_20261016/video'

def read(path):
    return [r for r in csv.DictReader(path.open(encoding='utf-8-sig',newline='')) if not next(iter(r.values())).startswith('#')]

def main():
    status={r['source_id']:r for r in read(ROOT/'data/csv/商城兑换系统/commerce_import_status.csv')}
    products={r['source_id']:r for r in read(ROOT/'design_refs/shop_catalog_20261016/baseline/data/csv/商城兑换系统/commerce_products.csv')}
    rows='''001 002 009 003
010 033 029 005
015 030 034 006
012 032 039 018
007 013 017 020
014 026 004 008
028 011 031 019
036 023 022 025
035 016 024 027
021 040 037 038
141 142 143 144
145 146 147 148
149 150 151 041
042 043 044 048
047 046 045 049
050 051 052 056
055 054 053 057
058 059 060 064
063 062 061 065
066 067 068 072
071 070 069 073
074 075 076 080
079 078 077 081
082 083 084 088
087 086 085 089
090 091 092 093
094 095 096 100
099 098 097 101
102 103 104 108
107 106 105 109
110 111 112 115
114 140 113 116
117 118 119 123
122 121 120 124
125 126 127 131
130 129 128 132
133 134 135 139
138 137 136'''
    grouped=[[f'P{n}' for n in line.split()] for line in rows.splitlines()]
    all_ids=[n for row in grouped for n in row]
    assert len(all_ids)==151 and len(set(all_ids))==151 and set(all_ids)=={f'P{i:03d}' for i in range(1,152)}
    frame_seconds=[234,246,258,270,273,276,279,282,285,297,315,318,333,345,354,366,375,384,393,405,411,429,438,450,462,474,486,492,501,516,522,531,531,531,540,540,552,570]
    promo_ids=[f'P{i:03d}' for i in [4,8,7,6,11,5,12,22,26,25,23,16,27,28,24,20,21,19,18,32,31,17,13,14,30,15,29,33]]
    new_names=dict(zip(range(141,152),['碎梦古铃','亡语沙漏','幽雾镜','蚀月骨匣','沧澜女王','幽冥妖姬','悲叹之种','命运面具','天之锁','贤者之石','斩魄刀']))
    new_descriptions={
      145:(327,'英雄','地图等级+1\n英雄攻击减甲+25\n英雄攻击攻击+25\n英雄攻击全属性+25\n英雄攻击加成+25%\n英雄全属性加成+25%\n英雄最终伤害+25%\n星悦积分+200\n解锁英雄：沧澜女王\n与蔷薇之刃羁绊\n英雄全属性加成EX+3%.英雄最终伤害EX+3%\n英雄攻击减甲百分比+5%\n英雄攻击属性效率+5%\n拥有魔法少女继承眩晕效果\n拥有齐天大圣继承削血与终极塔效果'),
      146:(322,'皮肤','英雄最终伤害+40%\n英雄攻击减甲+40\n英雄全属性加成+40%\n英雄攻击全属性+40\n英雄暴击伤害+300%\n英雄攻击加成+35%\n星悦积分+200\n英雄攻击属性效率+20%\n获得宠物皮肤：幽冥妖姬'),
      147:(320,'特权','英雄攻击减甲+25\n英雄攻击攻击+25\n英雄攻击全属性+25\n英雄攻击加成+25%\n英雄全属性加成+25%\n英雄最终伤害+25%\n英雄全属性加成EX+8%.英雄最终伤害EX+8%\n英雄攻击减甲百分比+8%\n英雄攻击属性效率+8%\n每局英雄技能刷新次数额外+5'),
      148:(318,'特权','每秒金币+100\n每秒木材+100\n伐木效率+20\n金矿效率+30%\n英雄全属性加成+50%\n英雄最终伤害+50%英雄每秒属性+5000\n英雄攻击加成+50%\n英雄攻击全属性+50\n英雄攻击减甲+50\n星悦积分+200\n已有的双传说词条装备会额外随机出两个传说词条'),
      149:(330,'特权','英雄初始属性+50W\n英雄造成伤害加攻击+80\n英雄暴击伤害+200%\n英雄攻击减甲+50\n英雄攻击全属性+50\n英雄全属性加成+50%\n英雄最终伤害+50%\n星悦积分+200\n提前挑战时间缩短180秒\n降低提前通关的50%难度系数加成\n敌人如果对城墙造成致命伤害则会立刻眩晕周围敌人10秒'),
      150:(333,'特权','箭塔攻击减甲+1.5\n箭塔最终伤害+60%\n箭塔攻击加成+60%\n英雄全属性加成+60%\n英雄最终伤害+60%\n英雄造成伤害加攻击+60\n英雄攻击全属性+60%\n英雄攻击减甲+60\n星悦积分+200\n宠物额外解锁两条词条\n每局宝物额外刷新次数+5'),
      151:(336,'特权','地图等级+1\n墙护甲+1000\n墙每秒护甲+0.15\n英雄最终伤害+35%\n英雄全属性加成+35%\n英雄攻击全属性+35\n英雄攻击减甲+35\n英雄造成伤害加攻击+35\n星悦积分+200\n秘法牢笼与虚空之影属性额外提升20%'),
      140:(531,'特权','每秒木材+1')
    }
    base_missing={2:800,3:9800,6:6800,7:29800,8:64800,9:23800,10:600,16:29800,28:23800,34:6800,35:600,36:3000,39:3800,40:3000}
    reviewed=[]
    for row_index,(ids,t) in enumerate(zip(grouped,frame_seconds),1):
      for column,source_id in enumerate(ids,1):
        n=int(source_id[1:]);old=products.get(source_id);s=status.get(source_id,{})
        name=new_names.get(n) or s['display_name']
        base=int(old['price']) if old else (base_missing[n] if n in base_missing else (588 if n in [115,140] else (2388 if n in range(141,145) else 5000)))
        currency=old['currency'] if old else ('u_coin' if n<41 else 'shop_points')
        price=base*4//5 if source_id in promo_ids else base
        r={'source_id':source_id,'source_id_is_proposed':n>=141,'video_name':name,'all_order':len(reviewed)+1,'all_row':row_index,'all_column':column,'project_sku':old['sku'] if old else None,'project_current_name':old['display_name'] if old else None,'project_enabled':bool(int(old['enabled'])) if old else False,'project_price':int(old['price']) if old else None,'video_price':price,'video_original_price':base if source_id in promo_ids else None,'currency':currency,'evidence_seconds':t,'evidence_frame':f'design_refs/shop_catalog_20261016/video/frames/t{t*1000:06d}.jpg','evidence_ocr':'design_refs/shop_catalog_20261016/video/ocr.json','assessment':s.get('status','new_in_recording'),'implementation_notes':s.get('implementation_notes','新增商品；正式能力映射由独立审计决定。'),'description_source':'existing_project_configuration_not_retranscribed','full_effect_text':old['description'] if old else None,'groups':['all']+(['promotions'] if source_id in promo_ids else [])}
        if n in new_descriptions:
          dt,typ,desc=new_descriptions[n];r.update(description_source='manual_reviewed_video_tooltip',full_effect_text=desc+'\n购买后自动激活',video_item_type=typ,description_evidence_seconds=dt,description_evidence=f'design_refs/shop_catalog_20261016/video/supplement_{dt*1000:06d}.json')
        if n in range(141,145):r.update(description_source='not_hovered_in_recording',full_effect_text=None,implementation_notes='仅名称、SSR、永久、2388积分有证据；视频未悬停此商品，不可杜撰完整效果，不可标记可购买。')
        if n==2:r['alternative_video_prices']=[{'currency':'u_coin','price':800},{'currency':'shop_points','price':100}];r['implementation_notes']+='新视频237秒显示同件抽奖券可800U币或100积分兑换；100积分是第二渠道，不是折扣。'
        reviewed.append(r)
    catalog={'schema_version':1,'reviewed_at':'2026-10-16','review_kind':'local_video_ocr_and_manual_frame_review','source':json.loads((OUT/'metadata.json').read_text(encoding='utf8')),'scope':'仅审阅证据，不是正式配置；P141至P151为建议分配ID，不宣称原视频存在这些ID。','all_ordering':'全部商品页，四列逐行，自左向右，自上向下；151单品，不含礼包/VIP礼包。','all_products':reviewed,'groups':{'home':{'observed':False,'reason':'视频开始位于礼包页，未进入首页；不能从导航标签推导首页商品排序。','suggested_policy':'按all排序聚合已开放商品；明确这是项目实现选择而非视频证据。'},'bundles':{'observed':True,'sources':[f'B{i:03d}' for i in range(1,6)],'skus':[f'video_bundle_b{i:03d}' for i in range(1,6)],'evidence_seconds':[0,30],'names':['大佬礼包','剑圣D闪礼包','新手礼包','新人礼包','新皮肤礼包']},'promotions':{'observed':True,'sources':promo_ids,'evidence_seconds':[69,84,90,105,120,135,150,159],'activity_dates':['2026-10-09—2026-10-30','2026-10-01—2026-10-30'],'discount':'已查看28项均8折；应按权威活动到期，不将促销折扣当永久原价。'},'vip':{'observed':True,'sources':['VIPB'+str(i) for i in range(1,11)],'skus':[f'video_bundle_vip_{i:02d}' for i in range(1,11)],'evidence_seconds':[177,195,210,228],'condition':'达到V1…V10可购买；未达成不是无原因的暂不可购。'},'all':{'observed':True,'sources':all_ids,'count':151}},'counts':{'singles_in_recording':151,'existing_single_sku_matches':sum(bool(r['project_sku']) for r in reviewed),'unmatched_singles':sum(not r['project_sku'] for r in reviewed),'new_items_beyond_prior_p140':11,'normal_bundles':5,'vip_bundles':10,'unique_singles_and_packs':166,'promo_items':28},'uncertainties':['新增4个SSR没有悬停说明，只能保留证据，不能杜撰效果。','首页内容未展示；首页聚合规则须作为项目选择标记。','贤者之石原文“英雄攻击全属性+60%”确有百分号，不擅自改成固定60。','命运面具、贤者之石等依赖永久装备传说词条/宠物词条；不能只发基础属性就称整件完成。','沧澜女王和幽冥妖姬承诺具体英雄/宠物皮肤及羁绊，需正式资源和玩法。','视频价格与当前项目价格差异主要来自2026-10-30止的8折活动；不可只改客户端金额。']}
    (OUT/'catalog_reviewed.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    new={'schema_version':1,'items':[r for r in reviewed if int(r['source_id'][1:])>=140],'notes':catalog['uncertainties']}
    (OUT/'new_items_reviewed.json').write_text(json.dumps(new,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    fields=['all_order','all_row','all_column','source_id','video_name','project_sku','project_enabled','currency','video_price','video_original_price','project_price','assessment','evidence_seconds','description_source']
    with (OUT/'商品顺序与SKU映射.csv').open('w',encoding='utf-8-sig',newline='') as f:
      w=csv.DictWriter(f,fieldnames=fields,extrasaction='ignore');w.writeheader();w.writerows(reviewed)
    missing=[r for r in reviewed if not r['project_sku']]
    (OUT/'unmatched_reviewed.json').write_text(json.dumps(missing,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    print(json.dumps(catalog['counts'],ensure_ascii=False))

if __name__=='__main__':main()
