from pathlib import Path
import json,csv,io
root=Path.cwd()
labels={
'hero_damage_attack_growth':'英雄造成伤害加攻击','hero_attributes_per_damage':'英雄造成伤害加属性',
'tower_damage_attack_growth':'箭塔造成伤害加攻击','hero_attack_bonus_pct':'英雄攻击加成',
'hero_attribute_bonus_pct':'英雄全属性加成','hero_attack_armor_reduction':'英雄攻击减甲',
'hero_final_damage_bonus_pct':'英雄最终伤害','tower_attack_bonus_pct':'箭塔攻击加成',
'tower_final_damage_bonus_pct':'箭塔最终伤害','tower_critical_chance_pct':'箭塔暴击几率',
'hero_critical_chance_pct':'英雄暴击几率','initial_wood':'开局木材','wall_armor':'墙护甲',
'wall_health_per_second':'墙每秒生命','tower_attack_speed_bonus_pct':'箭塔攻击速度',
'hero_initial_attributes':'英雄初始全属性','wood_per_second':'每秒木材','tower_attack_flat':'箭塔攻击力',
'gold_mine_efficiency_pct':'金矿效率','lumberjack_efficiency':'伐木效率',
'lumberjack_attack_speed_bonus_pct':'伐木工攻速','lumberjack_attack_growth':'伐木工攻击成长',
'tower_attack_per_second':'箭塔每秒攻击','wall_health_bonus_pct':'墙生命加成',
'wall_armor_bonus_pct':'墙护甲加成','wall_damage_reduction_pct':'墙伤害减免','initial_population_cap':'人口',
'tower_attack_armor_reduction':'箭塔攻击减甲','wall_armor_per_second':'墙每秒护甲',
'gold_mine_build_cap':'金矿建造上限','hero_attributes_per_second':'英雄每秒属性',
'hero_attack_attribute_efficiency_pct':'英雄攻击属性效率','lumberjack_critical_chance_pct':'伐木暴击几率',
'lumberjack_critical_yield_bonus_pct':'伐木暴击收益','hero_damage_wood_bonus_pct':'英雄造成伤害加木材',
'starjoy_points':'星悦积分'}
levels=json.loads((root/'data/archive/vip_recharge_levels.json').read_text(encoding='utf-8'))['levels']
assert [r['level'] for r in levels]==list(range(1,13))
assert all(r['required_recharge_fen']==r['required_recharge_yuan']*100 for r in levels)
assert all(a['required_recharge_fen']<b['required_recharge_fen'] for a,b in zip(levels,levels[1:]))
rows=[]
def add(id,name,group,level,price,effects,condition,**extra):
    description='；'.join(labels[k]+'+'+str(v)+('%' if k.endswith('_pct') else '') for k,v in effects.items())
    rows.append(dict(reward_id=id,display_name=name,group_id=group,level=level,price=price,condition=condition,description=description,
        effect_ids=list(effects),effect_values=list(effects.values()),enabled=True,**extra))
fields=list(labels)[:9]
for n,value in enumerate([1,1.5,2,2.5,3,3.5,4,5,7,10,10,10],1):
    add(f'vip_privilege_{n:02}',f'V{n}特权礼包','privileges',n,0,dict.fromkeys(fields,value),f"累计充值{levels[n-1]['required_recharge_yuan']}元达到VIP{n}；手动免费领取一次，各级累计")
medal_fields=['tower_critical_chance_pct','tower_final_damage_bonus_pct','hero_final_damage_bonus_pct','hero_critical_chance_pct','hero_attribute_bonus_pct']
for n,value in enumerate([1,1.2,1.4,1.6,1.8,2,2.5,3,4,5],1):
    add(f'vip_medal_{n:02}',f'VIP{n}勋章','medals',n,0,dict.fromkeys(medal_fields,value),f'购买VIP{n}专属礼包后免费附送，自动生效；每枚仅获得一次')
gifts=[
(10,{'initial_wood':50,'wall_armor':10,'wall_health_per_second':3,'tower_attack_speed_bonus_pct':5,'hero_initial_attributes':5000}),
(19,{'wood_per_second':1,'tower_attack_flat':300,'tower_attack_speed_bonus_pct':10,'gold_mine_efficiency_pct':5}),
(39,{'lumberjack_efficiency':1,'gold_mine_efficiency_pct':5,'lumberjack_attack_speed_bonus_pct':5,'lumberjack_attack_growth':2,'tower_attack_per_second':1}),
(59,{'wall_health_per_second':10,'wall_health_bonus_pct':10,'wall_armor_bonus_pct':10,'wall_damage_reduction_pct':3,'wall_armor':10,'initial_population_cap':2}),
(79,{'tower_attack_per_second':2,'tower_attack_bonus_pct':8,'tower_attack_speed_bonus_pct':8,'hero_attribute_bonus_pct':12,'hero_damage_attack_growth':5}),
(119,{'hero_attributes_per_damage':3,'hero_damage_attack_growth':3,'tower_critical_chance_pct':5,'hero_critical_chance_pct':5,'hero_attribute_bonus_pct':10,'hero_attack_armor_reduction':5}),
(129,{'tower_final_damage_bonus_pct':15,'hero_final_damage_bonus_pct':15,'tower_attack_armor_reduction':0.1,'hero_attribute_bonus_pct':8,'hero_attack_armor_reduction':5}),
(188,{'wall_armor_per_second':0.1,'gold_mine_build_cap':1,'hero_final_damage_bonus_pct':10,'tower_attack_armor_reduction':0.1,'hero_attribute_bonus_pct':10,'lumberjack_efficiency':3,'hero_attributes_per_second':100}),
(199,{'hero_attack_attribute_efficiency_pct':5,'lumberjack_critical_chance_pct':5,'lumberjack_critical_yield_bonus_pct':10,'tower_attack_armor_reduction':0.2,'hero_attack_armor_reduction':5}),
(239,{'hero_attack_attribute_efficiency_pct':10,'lumberjack_critical_chance_pct':5,'lumberjack_critical_yield_bonus_pct':10,'tower_attack_armor_reduction':0.2,'hero_attack_armor_reduction':10,'hero_damage_wood_bonus_pct':10,'hero_attribute_bonus_pct':10,'tower_attack_bonus_pct':10,'hero_attributes_per_damage':10})]
for n,(price,effects) in enumerate(gifts,1):
    add(f'vip_package_{n:02}',f'VIP{n}专属礼包','packages',n,price,effects,f'VIP会员可购买一次；附送VIP{n}勋章',medal_id=f'vip_medal_{n:02}')
add('vip_little_jacket','小棉袄','packages',0,19,{'initial_wood':200,'lumberjack_efficiency':1,'gold_mine_efficiency_pct':6,'lumberjack_attack_speed_bonus_pct':6,'hero_attribute_bonus_pct':6,'tower_attack_bonus_pct':6,'initial_population_cap':3,'starjoy_points':68},'使用商城付费币购买一次')
source={'version':1,'currency':'shop_paid_currency','currency_name':'商城付费币','recharge_thresholds_pending':False,'recharge_levels':levels,'recharge_exchange_rate_pending':True,'rewards':rows}
p=root/'data/archive/vip_rewards_20261003.json';p.parent.mkdir(exist_ok=True,parents=True);p.write_text(json.dumps(source,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
headers=['reward_id','display_name','group_id','level','price','condition','description','effect_ids','effect_values','medal_id','enabled']
s=io.StringIO(newline='');w=csv.writer(s,lineterminator='\n');w.writerow(headers);s.write('#types:string,string,string,number,number,string,string,list,list,string,boolean\n')
for r in rows:w.writerow(['|'.join(map(str,r[h])) if isinstance(r.get(h),list) else ('1' if r.get(h) is True else r.get(h,'')) for h in headers])
(root/'data/csv/存档系统/archive_vip_rewards.csv').write_text(s.getvalue(),encoding='utf-8')
stats=root/'data/csv/玩家档案系统/player_gameplay_stats.csv';t=stats.read_text(encoding='utf-8-sig')
for id,maximum,note in [('vip_recharge_total_fen','9007199254740991','累计已验证充值金额，单位分；支付回执去重入账，不随付费币消费扣减。'),('vip_level','12','VIP等级缓存；支付服务根据累计实付充值更新，领取时按累计充值额重新判定。'),('shop_paid_currency','2147483647','商城付费币余额；仅经支付验证后入账，VIP礼包结算原子扣款；不同于软妹币。')]:
    if not any(x.startswith(id+',') for x in t.splitlines()):t+='\n'+','.join([id,'integer','0','count','0',maximum,'1',note])
t=t.replace('VIP等级；仅由服务端按累计充值门槛设置，门槛尚待配置；UI测试点亮不增加等级。','VIP等级缓存；支付服务根据累计实付充值更新，领取时按累计充值额重新判定。')
stats.write_text(t.rstrip()+'\n',encoding='utf-8')
# This is display metadata only. The server always resolves effects and prices from CSV.
js='// Generated by tools/build_vip_rewards.py; display metadata, never a grant authority.\nGameUI.CustomUIConfig().VIPRewardCatalog='+json.dumps(source,ensure_ascii=False,separators=(',',':'))+';\n'
(root/'panorama/src/scripts/custom_game/vip_catalog.js').write_text(js,encoding='utf-8')
print('VIP catalog:',len(rows),'rewards;',sum(len(x['effect_ids']) for x in rows),'effect entries')

s=io.StringIO(newline='');w=csv.writer(s,lineterminator='\n')
w.writerow(['level_id','level','required_recharge_fen','required_recharge_yuan'])
s.write('#types:string,number,number,number\n')
for row in levels:w.writerow([f"vip_level_{row['level']:02}",row['level'],row['required_recharge_fen'],row['required_recharge_yuan']])
(root/'data/csv/存档系统/archive_vip_levels.csv').write_text(s.getvalue(),encoding='utf-8')
p=root/'server/payment_backend/upgrade_vip_recharge.sql'
if p.exists():
    sql=p.read_text(encoding='utf-8-sig');a=sql.index('-- BEGIN VIP LEVEL VALUES');b=sql.index('-- END VIP LEVEL VALUES',a)
    values=',\n'.join(f"({r['level']},{r['required_recharge_fen']})" for r in levels)
    sql=sql[:a]+'-- BEGIN VIP LEVEL VALUES (generated from vip_recharge_levels.json)\n'+values+'\n'+sql[b:]
    p.write_text(sql,encoding='utf-8')
