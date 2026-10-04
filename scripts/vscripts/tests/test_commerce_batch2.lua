package.path='scripts/vscripts/?.lua;'..package.path
local effects=require('systems/commerce_effects')
local save={content_inventory={},archive={clear_counts={n1=4,n9=6}},fishing_inventory={a=99,b=1}}
local function own(key,n) save.content_inventory[effects.ids[key] or key]=n or 1 end
assert(next(effects.project(save,{map_level=10}))==nil)
own('treasury');own('omniscience');own('chosen');own('kunpeng');own('stele')
local p=effects.project(save,{map_level=10})
assert(p.hero_attribute_bonus_pct==25.05 and p.wall_health_bonus_pct==10 and p.wall_health_per_second==50)
assert(p.hero_damage_attack_growth==3 and p.hero_attributes_per_damage==3 and p.tower_damage_attack_growth==3)
assert(math.abs(p.hero_final_damage_bonus_pct-.7)<1e-9)
assert(effects.project(save,{map_level=10}).hero_attribute_bonus_pct==p.hero_attribute_bonus_pct,'projection must not accumulate')
save.content_inventory={};own('ember',50)
assert(not effects.project(save,{}).hero_attribute_growth)
own('ember',51);assert(effects.project(save,{}).hero_attribute_growth==5)
own('ember',1500);assert(effects.project(save,{}).hero_attribute_growth==45)
own('ember',1501);p=effects.project(save,{})
assert(p.hero_attribute_growth==125 and p.hero_final_damage_bonus_pct==130 and p.hero_attack_armor_reduction==80)
save.content_inventory={};own('ur_collector');own('ssr_collector');own('muramasa')
local definitions=require('config/generated/lottery_item_definitions')
local ur,ssr
for _,i in ipairs(definitions.rows) do if i.quality=='ur' then ur=i.item_id elseif i.quality=='ssr' then ssr=i.item_id end end
own(ur,100);own(ssr,3);p=effects.project(save,{})
assert(p.hero_health_bonus_pct==1 and p.hero_armor_bonus_pct==1 and p.hero_final_damage_bonus_pct==5)
assert(p.wall_health_bonus_pct==3 and p.wall_armor==10,'count kinds, not copies')
own('longinus');p=effects.project(save,{hero_attribute_growth=100,hero_final_damage_bonus_pct=20})
assert(p.hero_attribute_growth==5 and p.hero_final_damage_bonus_pct==6.25)
local damage,state=effects.shield(nil,100,50,100,0)
assert(damage==0 and state.remaining==0 and state.ready_at==30)
damage,state=effects.shield(state,100,50,100,1);assert(damage==100,'cooldown prevents refresh')
damage,state=effects.shield(state,60,50,100,30);assert(damage==0 and state.remaining==40)
damage,state=effects.shield(state,45,50,100,31);assert(damage==5 and state.remaining==0)
damage,state=effects.shield(nil,60,50,100,0)
damage,state=effects.shield(state,10,50,100,10);assert(damage==10,'shield expires after ten seconds')
local tracker=require('systems/worker_training_progress').create({rows={{training_id='train_lumberjack_01',training_type='unit',level=1,max_count=1},{training_id='train_lumberjack_02',training_type='unit',level=2,max_count=1}}})
tracker:set_capacity_bonus(0,1);assert(tracker:get_for(0,'train_lumberjack_01').max_count==2)
assert(tracker:get_for(1,'train_lumberjack_01').max_count==1,'capacity must stay owner-specific')
tracker:record_independent(0,'train_lumberjack_01');assert(tracker:get(0).level==1)
tracker:record_independent(0,'train_lumberjack_01');assert(tracker:get(0).level==2)
local online=require('systems/archive_online_rewards');local archive={}
save.content_inventory={};own('diary')
for i=1,5 do assert(online.apply({kind='online_checkpoint',session='a',actual_seconds=i*60,map_seconds=i*60},archive,{},function()end,save)) end
assert(archive.online.coins==6 and archive.online.commerce_bonus_fifths==0)
online.apply({kind='online_checkpoint',session='a',actual_seconds=300,map_seconds=300},archive,{},function()end,save)
assert(archive.online.coins==6,'checkpoint replay does not grant extra welfare')
print('COMMERCE_BATCH2_RULES_PASS')

local bus=require('core/event_bus');local events=require('core/events')
package.loaded['core/scheduler']={every=function()end}
package.loaded['systems/player_profile_service']={get_profile=function()return {save={gameplay_stats={tower_basic_attack_growth=2,tower_damage_attack_growth=3}}}end}
local permanent=require('systems/permanent_reward_effect_service');permanent.init()
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0})
local tower={survival_player_id=0}
local function attack() return bus.request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST,{player_id=0}).totals.tower_attack_flat end
bus.emit(events.TOWER_ATTACK_LANDED,{tower=tower});assert(attack()==2,'attack event does not grant damage growth')
bus.emit('commerce.tower_damage',{tower=tower,damage=0});assert(attack()==2)
bus.emit('commerce.tower_damage',{tower=tower,damage=10});assert(attack()==5)
bus.emit('commerce.tower_damage',{tower=tower,damage=10});assert(attack()==8,'separate skill hits each grow once')
print('COMMERCE_TOWER_DAMAGE_GROWTH_PASS')
