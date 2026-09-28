package.path='scripts/vscripts/?.lua;'..package.path
local m=require('combat/hero_display_bonus')
local function near(a,b)assert(math.abs(a-b)<.00001,tostring(a)..' ~= '..tostring(b))end
local a={base={attack_max=100,strength=10,agility=10,intellect=10},technology={},permanent={},equipment={},weapon={},progression={},essence={},level=1,base_armor=-2,intellect_attack_per_point=2,configured_attack_time=2,final_attack_time=2}
local d=m.calculate(a)
for key,value in pairs(d)do near(value,0)end
a.technology={attack_flat=20,attack_bonus_pct=10};a.equipment={attack_flat=30,armor_flat=8,all_attributes_flat=5,attack_speed_pct=50};a.permanent={hero_initial_attack=10,hero_initial_armor=2,hero_armor_bonus_pct=20};a.weapon={base_attack_max=5};a.progression={display_all_attributes=2,all_attributes=999999,attack_flat=3}
d=m.calculate(a)
near(d.display_attack_bonus,(100+17*2+20+30+10+5+3)*1.1-120)
near(d.display_attack_pct,10);near(d.display_armor_bonus,14);near(d.display_armor_pct,20)
near(d.display_strength_bonus,7);near(d.display_attack_speed_bonus,.25)
local before=d.display_attack_bonus
a.progression.all_attributes=999999999;a.growth={attack=999999};d=m.calculate(a);near(d.display_attack_bonus,before)
local bus,events=require('core/event_bus'),require('core/events')
local tech=require('systems/technology_stat_manager');tech.init()
local fixed=m.static_technology(tech.get(0)).attack_flat
local response=bus.request(events.TECHNOLOGY_STATS_GROWTH_ADD_REQUEST,{player_id=0,section='hero',field='attack',amount=9000})
assert(response.ok);near(tech.get(0).final.hero.attack_flat,fixed+9000)
near(m.static_technology(tech.get(0)).attack_flat,fixed)
local prog=require('systems/hero_progression_system');prog.init()
local rewards=bus.request(events.HERO_PROGRESSION_APPLY_REQUEST,{player_id=0,effects={{effect_type='add_all_attributes',value=20},{effect_type='add_attack_all_attribute_gain',value=3}}})
assert(rewards and rewards.ok)
bus.emit(events.HERO_MAIN_ATTACK_LANDED,{player_id=0})
local p=bus.request(events.HERO_PROGRESSION_GET_REQUEST,{player_id=0}).snapshot
assert(p.all_attributes==23 and p.display_all_attributes==20)
print('HERO_FIXED_BONUS_PASS: fixed equipment/research/rewards, negative base armor, actual percentages, no growth inflation; real technology and progression events')
