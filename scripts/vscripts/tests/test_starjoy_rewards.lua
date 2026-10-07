package.path='scripts/vscripts/?.lua;'..package.path
local rewards=require('systems/archive_starjoy_rewards')
local settle=require('systems/archive_settlement')
local cfg=require('config/generated/archive_starjoy_levels')
local definitions=require('config/generated/player_gameplay_stats')
local function near(a,b) assert(math.abs((a or 0)-b)<.000001,tostring(a)..' expected '..b) end
local function defaults()local s={}for _,r in ipairs(definitions.rows)do s[r.field_id]=r.default_value end;return s end
local thresholds={50,200,400,800,1000,1500,2000,2500,3000,3500,4000,4500,5000,5500,6000,6800,7500,8000,8500,9000,10000,11000,12000,13000}
assert(#cfg.rows==24)
for i,threshold in ipairs(thresholds) do
 assert(cfg.rows[i].level==i and cfg.rows[i].required_points==threshold)
 local stats=defaults();stats.starjoy_points=threshold-1;rewards.reconcile(stats);assert(rewards.level(stats)==i-1)
 rewards.change(stats,threshold-1,threshold);assert(rewards.level(stats)==i)
 local rows=rewards.project({save={gameplay_stats=stats}});assert(#rows==24)
 for n,row in ipairs(rows)do assert(row.unlocked==(n<=i and 1 or 0))end
 for _,effect in ipairs(cfg.rows[i].effect_ids)do assert(definitions.by_id[effect])end
end
print('PASS all 24 exact thresholds, below-threshold locking and 24 projected rows')
local stats=defaults();stats.starjoy_points=13000;rewards.reconcile(stats)
near(stats.wood_per_second,59);near(stats.gold_per_second,50)
near(stats.lumberjack_efficiency,9);near(stats.lumberjack_attack_speed_bonus_pct,30)
near(stats.hero_attribute_bonus_pct,127);near(stats.hero_final_damage_bonus_pct,77)
near(stats.hero_attribute_growth,84);near(stats.hero_basic_attack_growth,64)
near(stats.hero_attack_armor_reduction,92);near(stats.hero_critical_chance_pct,25)
near(stats.hero_critical_damage_bonus_pct,320);near(stats.wall_health_bonus_pct,83)
near(stats.wall_armor_bonus_pct,60);near(stats.tower_attack_bonus_pct,68)
near(stats.tower_attack_speed_bonus_pct,60);near(stats.tower_attack_range,500)
near(stats.hero_initial_gold,5000);near(stats.training_room_income_bonus_pct,23)
near(stats.gold_mine_efficiency_pct,38);near(stats.gold_mine_build_cap,1)
local saved={}for k,v in pairs(stats)do saved[k]=v end
for i=1,10 do rewards.reconcile(stats)end
for k,v in pairs(saved)do near(stats[k],v)end
rewards.change(stats,13000,0);near(stats.starjoy_points_earned,13000);near(stats.starjoy_reward_level,24)
rewards.change(stats,0,13000,true);near(stats.starjoy_points_earned,13000)
rewards.change(stats,13000,13200);near(stats.starjoy_points_earned,13200)
print('PASS full-tier independent totals, no repeated rewards, exchange and refund retain lifetime points')
local legacy={starjoy_points=800};assert(rewards.needs_reconcile(legacy))
local result=settle.settle({save={gameplay_stats=legacy}},{id='legacy:reconcile',kind='starjoy_reconcile'},false)
assert(result.ok);near(result.gameplay_stats.starjoy_reward_level,4);near(result.gameplay_stats.initial_wood,110)
assert(legacy.starjoy_points_earned==nil,'settlement must not mutate original profile')
local duplicate=settle.settle({save=result},{id='legacy:reconcile',kind='starjoy_reconcile'},false)
assert(duplicate.ok and duplicate.duplicate);near(duplicate.gameplay_stats.initial_wood,110)
print('PASS legacy balance migration and idempotent server reconciliation')
RandomInt=function(a,b)return a end
for _,level in ipairs({20,21})do
 local s=defaults();s.starjoy_points=thresholds[level];rewards.reconcile(s)
 for _,pass in ipairs({false,true})do
  local c={id='match:shadow',kind='challenge',challenge_id='shadow_4',difficulty_id='n4',day_key='test'}
  local r=settle.settle({save={gameplay_stats=s}},c,pass);assert(r.ok)
  assert(#c.drops==2+(pass and 1 or 0))
  local replay=settle.settle({save=r},c,pass);assert(replay.duplicate)
 end
end
print('PASS starjoy has no extra shadow drops; pass and settlement deduplication preserved')
assert(not cfg.rows[5].pending_effect and not cfg.rows[17].pending_effect)
assert(cfg.rows[17].description:find('BOSS',1,true))
assert(not cfg.rows[5].description:find('分解',1,true))
assert(not cfg.rows[21].description:find('掉落',1,true))
local lottery=require('systems/lottery_http_settlement')
local lottery_cfg=require('config/lottery_config')
local pool=lottery_cfg.pool_order[1];local item
for _,x in ipairs(pool.items)do if x.exchange_enabled~=false and x.exchange_points>0 then item=x;break end end
assert(item)
local start=defaults();start.starjoy_points=13000+item.exchange_points
local exchanged=lottery.settle({save={gameplay_stats=start}}, {kind='lottery_exchange',pool_id=pool.id,item_id=item.id,request_id='starjoy-test'})
assert(exchanged.ok);assert(exchanged.gameplay_stats.starjoy_points_earned>=start.starjoy_points)
assert(exchanged.gameplay_stats.starjoy_reward_level==24)
print('PASS real HTTP lottery exchange preserves unlocks and awards item normally')
-- Simulate backend pure-view subtraction: only rewards newly earned in this match remain.
local old=defaults();old.starjoy_points=49;rewards.reconcile(old)
local new={}for k,v in pairs(old)do new[k]=v end
rewards.change(new,49,50)
near(new.wood_per_second-old.wood_per_second,1)
rewards.change(new,50,0);near(new.wood_per_second-old.wood_per_second,1)
print('PASS newly crossed tier contributes an additive match delta without double projection')
STARJOY_TEST_PROFILE={save={gameplay_stats=stats}}
STARJOY_TEST_ROWS=rewards.project(STARJOY_TEST_PROFILE)
