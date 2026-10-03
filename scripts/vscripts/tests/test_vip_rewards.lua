package.path='scripts/vscripts/?.lua;'..package.path
local vip=require('systems/archive_vip_rewards')
local catalog=require('config/generated/archive_vip_rewards')
local schema=require('config/generated/player_gameplay_stats')
local settle=require('systems/archive_settlement')
local function near(a,b) assert(math.abs((a or 0)-b)<.000001,tostring(a)..' expected '..b) end
local function profile(level,coins,member)
 local stats={}for _,r in ipairs(schema.rows)do stats[r.field_id]=r.default_value end
 stats.vip_level=level or 0;stats.vip_recharge_total_fen=level and level>0 and require("config/generated/archive_vip_levels").rows[level].required_recharge_fen or 0;stats.shop_paid_currency=coins or 0
 return {save={gameplay_stats=stats,archive={}},entitlements={vip={active=member==true}},revision=1}
end
local serial=0
local function apply(p,kind,id)
 serial=serial+1
 local r=settle.settle(p,{id='viptest:'..serial,kind=kind,reward_id=id},false)
 if r.ok then p.save.archive=r.archive;p.save.gameplay_stats=r.gameplay_stats end
 return r
end
assert(#catalog.rows==33)
for _,row in ipairs(catalog.rows)do
 assert(#row.effect_ids==#row.effect_values)
 for i,k in ipairs(row.effect_ids)do local r=assert(schema.by_id[k],k);assert(r.enabled);local v=assert(tonumber(row.effect_values[i]));if r.storage_type=='integer'then assert(v==math.floor(v),k)end end
end
for level=0,12 do
 local p=profile(level)
 for n=1,12 do
  local result=apply(p,'vip_claim',string.format('vip_privilege_%02d',n))
  assert(result.ok==(n<=level),'wrong threshold '..level..':'..n)
 end
end
local p=profile(12)
for n=1,12 do assert(apply(p,'vip_claim',string.format('vip_privilege_%02d',n)).ok)end
for _,k in ipairs(catalog.by_id.vip_privilege_01.effect_ids)do near(p.save.gameplay_stats[k],schema.by_id[k].default_value+59.5)end
for n=1,12 do assert(apply(p,'vip_claim',string.format('vip_privilege_%02d',n)).ok)end
near(p.save.gameplay_stats.hero_damage_attack_growth,59.5)
print('PASS all 12 tier boundaries, 59.5 additive totals, decimals and cross-session duplicate claims')
local unowned=profile(0,1000,false)
assert(not apply(unowned,'vip_claim','vip_privilege_01').ok)
assert(not apply(unowned,'vip_purchase','vip_package_01').ok)
assert(not apply(unowned,'vip_claim','vip_medal_01').ok)
assert(not apply(unowned,'vip_purchase','vip_medal_01').ok)
near(unowned.save.gameplay_stats.shop_paid_currency,1000)
local poor=profile(1,9,true)
assert(not apply(poor,'vip_purchase','vip_package_01').ok)
near(poor.save.gameplay_stats.shop_paid_currency,9);assert(not poor.save.archive.vip_claimed)
local first=profile(1,10,true)
assert(apply(first,'vip_purchase','vip_package_01').ok)
near(first.save.gameplay_stats.shop_paid_currency,0)
assert(first.save.archive.vip_claimed.vip_package_01 and first.save.archive.vip_claimed.vip_medal_01)
near(first.save.gameplay_stats.initial_wood,60);near(first.save.gameplay_stats.hero_initial_attributes,5000)
near(first.save.gameplay_stats.hero_attribute_bonus_pct,1);near(first.save.gameplay_stats.tower_critical_chance_pct,1)
assert(apply(first,'vip_purchase','vip_package_01').ok);near(first.save.gameplay_stats.initial_wood,60)
print('PASS price boundary, insufficient funds no mutation, exact atomic debit + medal, repeated purchase no charge')
local all=profile(12,10000,true);local expected={};local cost=0
for _,row in ipairs(catalog.rows)do
 if row.group_id~='privileges' then
  for i,k in ipairs(row.effect_ids)do expected[k]=(expected[k] or 0)+tonumber(row.effect_values[i])end
 end
 if row.group_id=='packages' then cost=cost+row.price;assert(apply(all,'vip_purchase',row.reward_id).ok)end
end
-- Little jacket's 68 lifetime points also unlock starjoy LV1 (+1 wood/s).
expected.wood_per_second=expected.wood_per_second+1
for k,v in pairs(expected)do near(all.save.gameplay_stats[k],schema.by_id[k].default_value+v)end
near(all.save.gameplay_stats.shop_paid_currency,10000-cost)
near(all.save.gameplay_stats.starjoy_points_earned,68);near(all.save.gameplay_stats.starjoy_reward_level,1)
near(all.save.gameplay_stats.tower_attack_armor_reduction,.6)
local s=vip.snapshot(all);assert(#s.rows==33 and s.level==12)
for _,r in ipairs(s.rows)do assert(r.owned==(r.id:match('vip_privilege') and 0 or 1))end
print('PASS every package effect and gifted medal, six-tenths tower reduction, 68 points + cumulative starjoy reward')
local calendar=require('systems/archive_calendar');calendar.set_clock(function()return 1000 end)
local expiring=profile(0,100,true);expiring.entitlements.vip.expires_at=999
assert(not apply(expiring,'vip_purchase','vip_package_01').ok)
local pure=profile(2);local r=settle.settle(pure,{id='viptest:pure',kind='vip_claim',reward_id='vip_privilege_02',price=0,vip_level=12},false)
assert(r.ok);near(r.gameplay_stats.hero_damage_attack_growth,1.5);near(pure.save.gameplay_stats.hero_damage_attack_growth,0)
print('PASS expired membership rejected, original profile immutable, all 223 effect entries valid')

local expected={5000,10000,25000,50000,100000,150000,250000,400000,600000,750000,1000000,1250000}
for level,fen in ipairs(expected) do
 local p=profile(0);local stats=p.save.gameplay_stats
 stats.vip_level=12 -- A stale/cache-only grade cannot bypass verified money.
 stats.vip_recharge_total_fen=fen-1;assert(vip.level(p)==level-1)
 stats.vip_recharge_total_fen=fen;assert(vip.level(p)==level)
 stats.vip_recharge_total_fen=fen+1;assert(vip.level(p)==level)
 stats.shop_paid_currency=0;assert(vip.level(p)==level)
 local snapshot=vip.snapshot(p);near(snapshot.recharge_total_fen,fen+1)
 if level<12 then near(snapshot.next_level_required_fen,expected[level+1]) else assert(snapshot.next_level_required_fen==nil) end
end
local p=profile(0);p.save.gameplay_stats.vip_level=12;assert(vip.level(p)==0)
for _,invalid in ipairs({-1,5000.5,math.huge,0/0,9007199254740992})do
 p.save.gameplay_stats.vip_recharge_total_fen=invalid;assert(vip.level(p)==0)
end
p.save.gameplay_stats.vip_recharge_total_fen=125000000;assert(vip.level(p)==12)
print('PASS all 12 recharge thresholds +/-1 fen, grade-cache rejection, spend does not downgrade, VIP12 ceiling')
