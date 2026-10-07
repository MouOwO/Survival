"""Isolated real Lua settlement: screenshot rewards, duplicate safety, themed pool and growth."""
import json,sys
from pathlib import Path
sys.path.insert(0,'output/python_test_runtime')
from lupa.lua51 import LuaRuntime
root=Path.cwd()
source=json.loads((root/'data/lottery/summer_item_attributes_20261003.json').read_text(encoding='utf-8'))
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute("package.path='scripts/vscripts/?.lua;'..package.path")
lua.globals().source_json=json.dumps(source,ensure_ascii=False)
lua.execute(r'''
local source=require('core/json_decoder').decode(source_json)
local config=require('config/lottery_config')
local service=require('systems/lottery_http_settlement')
local pool=config.pools.summer
assert(#pool.items==23 and #pool.by_quality.ur==5 and #pool.by_quality.ssr==8)
assert(not pool.by_id.lottery_rose_blade and not config.by_id.lottery_rose_blade and not pool.by_quality.n)
assert(#config.pools.map.items==30 and #config.pools.cultivation.items==26 and #config.pools.dragon_knight.items==26)
local function profile()return {save={content_inventory={special_lottery_ticket=100},gameplay_stats={},archive={}}}end
local function choose(item)
 local qualityRoll=1
 for _,q in ipairs(config.quality_order) do if q==item.quality then break end;qualityRoll=qualityRoll+(pool.quality_weights[q] or 0) end
 local index
 for i,v in ipairs(pool.by_quality[item.quality])do if v.id==item.id then index=i end end
 assert(index)
 RandomInt=function(a,b) if b==10000 then return qualityRoll end;return math.floor((index-.5)/#pool.by_quality[item.quality]*1000000000)+1 end
end
local tiers=require('config/generated/archive_starjoy_levels').rows
local function tier_bonus(points,field)
 local total=0
 for _,tier in ipairs(tiers)do if tier.enabled and points>=tier.required_points then
  for i,id in ipairs(tier.effect_ids)do if id==field then total=total+tonumber(tier.effect_values[i])end end
 end end
 return total
end
local function tier_level(points)local level=0;for _,r in ipairs(tiers)do if points>=r.required_points then level=r.level end end;return level end
local earned={}
for _,row in ipairs(source.items) do
 if row.enabled=='1' then
  local item=assert(pool.by_id[row.item_id]);choose(item)
  local p=profile()
  local r=service.settle(p,{kind='lottery_draw',pool_id='summer',count=1,request_id='test'})
  assert(r.ok and r.response.results[1].id==item.id)
  assert(r.content_inventory[item.id]==1 and r.content_inventory.special_lottery_ticket==99)
  assert(r.gameplay_stats.starjoy_points==(item.quality=='ur' and 200 or 88),'first acquisition points: '..item.id)
  for field,value in pairs(item.effect_values) do assert(r.gameplay_stats[field]==value+tier_bonus(r.gameplay_stats.starjoy_points,field),'effect missing: '..item.id..':'..field) end
  assert(p.save.content_inventory.special_lottery_ticket==100 and next(p.save.gameplay_stats)==nil,'input mutated')
  local old=r.gameplay_stats
  local again=service.settle({save=r},{kind='lottery_draw',pool_id='summer',count=1,request_id='test2'})
  assert(again.ok and again.response.results[1].duplicate and again.content_inventory[item.id]==1)
  for field,value in pairs(old)do
   local expected=value+tier_bonus(again.gameplay_stats.starjoy_points_earned,field)-tier_bonus(old.starjoy_points_earned,field)
   if field=='starjoy_points' or field=='starjoy_points_earned' then expected=value+item.duplicate_points end
   if field=='starjoy_reward_level' then expected=tier_level(again.gameplay_stats.starjoy_points_earned) end
   assert(again.gameplay_stats[field]==expected,'duplicate regrants effect: '..field)
  end
  if item.id~='lottery_magnetic_disruption_turret' then
   assert(not item.exchange_enabled)
   assert(not service.settle(p,{kind='lottery_exchange',pool_id='summer',item_id=item.id}).ok)
  end
  earned[item.id]=r
 end
end
assert(earned.lottery_sword_of_promise.gameplay_stats.hero_initial_attributes==300000)
assert(earned.lottery_kings_treasure.gameplay_stats.wall_armor==800)
assert(earned.lottery_muramasa.gameplay_stats.tower_attack_armor_reduction==1.5)
assert(earned.lottery_law_of_cycles.gameplay_stats.hero_attack_attribute_efficiency_pct==10)
for _,seed0 in ipairs({1,7,42,100,65535,123456}) do
 local seed=seed0
 RandomInt=function(a,b)seed=seed*48271%2147483647;return a+math.floor(seed/2147483647*(b-a+1))end
 local r=service.settle(profile(),{kind='lottery_draw',pool_id='summer',count=10})
 assert(r.ok and #r.response.results==10 and r.response.guarantee_quality=='ur' and r.response.guarantee_satisfied)
 assert(r.content_inventory.special_lottery_ticket==90)
 for _,item in ipairs(r.response.results)do assert(pool.by_id[item.id])end
end
-- Real permanent-effects projection and attack event verify attribute growth semantics.
local bus=require('core/event_bus');local events=require('core/events')
package.loaded['core/scheduler']={every=function()end}
local p={mode='pure',revision=1,save={gameplay_stats={},permanent_effects={},match_boss_effects={}}}
package.loaded['systems/player_profile_service']={get_profile=function()return p end}
local permanent=require('systems/permanent_reward_effect_service');permanent.init()
p.save.gameplay_stats=earned.lottery_law_of_cycles.gameplay_stats
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0})

local get=function()return bus.request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST,{player_id=0}).totals end
local t=get();assert(t.hero_final_damage_bonus_pct==25 and t.hero_attribute_bonus_pct==25)
-- Event identity comes from service subscription, not a manually simulated formula.
local attributes=t.hero_all_attributes_flat
bus.emit(events.HERO_MAIN_ATTACK_LANDED,{player_id=0})
assert(math.abs(get().hero_all_attributes_flat-attributes-27.5)<0.00001,'25 attributes with 10% efficiency')
bus.emit(events.HERO_MAIN_ATTACK_LANDED,{player_id=0,is_multishot_secondary=true})
assert(math.abs(get().hero_all_attributes_flat-attributes-27.5)<0.00001,'secondary attack must not double growth')
p.save.gameplay_stats=earned.lottery_sword_of_promise.gameplay_stats
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0})
local attack=get().hero_attack_flat
local hero={}
bus.emit(events.COMBAT_DAMAGE_RESOLVED,{player_id=0,owner_hero=hero,attacker=hero})
assert(get().hero_attack_flat==attack+50,'damage must add 50 attack')
print('SUMMER_ATTRIBUTES_PASS: 10 first rewards, 10 duplicate safety checks, 23-member pool, removed rose excluded, six ten-draw UR guarantees, permanent projection')
''')