package.path='scripts/vscripts/?.lua;'..package.path
local rewards=require('systems/archive_welfare_rewards')
local settlement=require('systems/archive_settlement')
local schema=require('config/generated/player_gameplay_stats')
local function near(a,b) assert(math.abs((a or 0)-b)<.000001,tostring(a)..' expected '..b) end
local function defaults() local s={} for _,r in ipairs(schema.rows) do s[r.field_id]=r.default_value end return s end
local function unlocked(a,prefix) local n=0;prefix=prefix or "welfare_victory_";for _,r in ipairs(rewards.rows(a)) do if r.id:sub(1,#prefix)==prefix then n=n+r.completed end end return n end
assert(#rewards.rows({})==36 and unlocked({})==0)
for wins=0,14 do
 local archive={clear_counts={n1=math.min(wins,5),n2=math.max(0,wins-5)}}
 local stats=defaults()
 rewards.reconcile(archive,stats,settlement.apply_effects)
 assert(rewards.wins(archive)==wins and unlocked(archive)==math.min(wins,13))
 assert(not rewards.needs_reconcile(archive))
 local saved={} for k,v in pairs(stats) do saved[k]=v end
 rewards.reconcile(archive,stats,settlement.apply_effects)
 for k,v in pairs(saved) do near(stats[k],v) end
end
local stats,base=defaults(),defaults()
local archive={clear_counts={n1=5,n2=8}}
rewards.reconcile(archive,stats,settlement.apply_effects)
local expected={hero_attribute_bonus_pct=5,initial_wood=560,wall_health_bonus_pct=5,wood_per_second=1,tower_attack_flat=300,
 initial_population_cap=8,hero_initial_attributes=5000,gold_mine_efficiency_pct=2,lumberjack_efficiency=2,
 tower_attack_speed_bonus_pct=10,hero_damage_attack_growth=1,lumberjack_attack_speed_bonus_pct=5}
for k,v in pairs(expected) do near(stats[k]-base[k],v) end
for k,v in pairs(stats) do if not expected[k] then near(v,base[k]) end end
local profile={save={archive={clear_counts={n1=12}},gameplay_stats=defaults()}}
assert(rewards.needs_reconcile(profile.save.archive))
-- Reading must never grant attributes or mark milestones.
assert(unlocked(profile.save.archive)==0 and profile.save.archive.completed==nil)
local out=settlement.settle(profile,{id='old:welfare_reconcile',kind='welfare_reconcile'},false)
assert(out.ok and unlocked(out.archive)==12 and profile.save.archive.completed==nil)
profile.save={archive=out.archive,gameplay_stats=out.gameplay_stats}
out=settlement.settle(profile,{id='new:clear',kind='clear',difficulty_id='n2',count=1,day_key=20000},false)
assert(out.ok and unlocked(out.archive)==13 and rewards.wins(out.archive)==13)
profile.save={archive=out.archive,gameplay_stats=out.gameplay_stats}
local duplicate=settlement.settle(profile,{id='new:clear',kind='clear',difficulty_id='n2',count=1,day_key=20000},false)
assert(duplicate.duplicate and rewards.wins(duplicate.archive)==13)
for k,v in pairs(out.gameplay_stats) do near(duplicate.gameplay_stats[k],v) end
-- Durable claimed milestones survive retry-ID pruning and a later session.
profile.save.archive.processed={}
local retry=settlement.settle(profile,{id='another:welfare_reconcile',kind='welfare_reconcile'},false)
for k,v in pairs(out.gameplay_stats) do near(retry.gameplay_stats[k],v) end
print('PASS welfare: 13 thresholds, mixed difficulties, cumulative exact totals, backfill, read purity, duplicate clear, durable claims')
-- Each five cooperative victories unlocks one additional reward; solo history cannot backfill them.
local expected_coop={gold_mine_efficiency_pct=5,hero_basic_attack_growth=3,wood_per_second=20,gold_per_second=20,
 hero_attack_armor_reduction=7,initial_population_cap=3,wall_health_bonus_pct=8,hero_attribute_growth=3,hero_final_damage_bonus_pct=5}
for wins=0,51 do
 local archive={clear_counts={},cooperative_clear_count=wins}
 local stats=defaults()
 rewards.reconcile(archive,stats,settlement.apply_effects)
 assert(unlocked(archive,"welfare_coop_")==math.min(10,math.floor(wins/5)))
 for i,row in ipairs(rewards.rows(archive)) do
  if row.progress_kind=="cooperative" then assert(row.count==wins and row.target==(i-13)*5 and row.progress_kind=='cooperative') end
 end
 assert(not rewards.needs_reconcile(archive))
end
local stats,base=defaults(),defaults()
rewards.reconcile({cooperative_clear_count=50},stats,settlement.apply_effects)
for k,v in pairs(stats) do near(v-base[k],expected_coop[k] or 0) end
local legacy={clear_counts={n1=999}}
rewards.reconcile(legacy,defaults(),settlement.apply_effects)
assert(unlocked(legacy)==13 and rewards.cooperative_wins(legacy)==0)
local profile={save={archive={clear_counts={},cooperative_clear_count=4},gameplay_stats=defaults()}}
local solo=settlement.settle(profile,{id='solo:clear',day_key=20000,kind='clear',difficulty_id='n1',count=1},false)
assert(solo.ok and solo.archive.cooperative_clear_count==4 and not solo.archive.completed.welfare_coop_01)
profile.save={archive=solo.archive,gameplay_stats=solo.gameplay_stats}
local co=settlement.settle(profile,{id='coop:clear',day_key=20000,kind='clear',difficulty_id='n2',count=1,cooperative_win=1},false)
assert(co.ok and co.archive.cooperative_clear_count==5 and co.archive.completed.welfare_coop_01)
near(co.gameplay_stats.gold_mine_efficiency_pct-solo.gameplay_stats.gold_mine_efficiency_pct,5)
profile.save={archive=co.archive,gameplay_stats=co.gameplay_stats}
local duplicate=settlement.settle(profile,{id='coop:clear',day_key=20000,kind='clear',difficulty_id='n2',count=1,cooperative_win=1},false)
assert(duplicate.duplicate and duplicate.archive.cooperative_clear_count==5)
assert(rewards.wins(duplicate.archive)==2)
print('PASS cooperative welfare: 5..50 boundaries, 10 exact rewards, independent solo/co-op counters, no legacy inference, atomic duplicate protection')
-- New batch uses total wins; already claimed earlier batches must not be reissued.
local finish_totals={hero_attribute_bonus_pct=11,hero_attack_bonus_pct=17,hero_attribute_growth=20,
 hero_attack_armor_reduction=21,hero_final_damage_bonus_pct=14,hero_basic_attack_growth=9}
local function prior_claims()
 local completed={}
 for _,row in ipairs(rewards.rows({})) do if not row.id:match('^welfare_finish_') then completed[row.id]=true end end
 return completed
end
for wins=0,131 do
 local archive={clear_counts={n1=math.min(60,wins),n3=math.max(0,wins-60)},completed=prior_claims()}
 local stats=defaults()
 rewards.reconcile(archive,stats,settlement.apply_effects)
 assert(unlocked(archive,'welfare_finish_')==math.min(13,math.floor(wins/10)))
 for i,row in ipairs(rewards.rows(archive)) do
  if row.id:match('^welfare_finish_') then assert(row.count==wins and row.target==(i-23)*10 and row.progress_kind=='victory') end
 end
 local before={} for k,v in pairs(stats) do before[k]=v end
 rewards.reconcile(archive,stats,settlement.apply_effects)
 for k,v in pairs(before) do near(stats[k],v) end
 if wins==130 then for k,v in pairs(stats) do near(v-defaults()[k],finish_totals[k] or 0) end end
end
local profile={save={archive={clear_counts={n1=70,n2=60},cooperative_clear_count=50,completed=prior_claims()},gameplay_stats=defaults()}}
assert(rewards.needs_reconcile(profile.save.archive))
local result=settlement.settle(profile,{id='finish-history:welfare_reconcile',kind='welfare_reconcile'},false)
assert(result.ok and unlocked(result.archive,'welfare_finish_')==13)
for k,v in pairs(result.gameplay_stats) do near(v-profile.save.gameplay_stats[k],finish_totals[k] or 0) end
assert(unlocked(profile.save.archive,'welfare_finish_')==0,'input profile stays immutable')
result.archive.processed={}
local again=settlement.settle({save={archive=result.archive,gameplay_stats=result.gameplay_stats}},{id='finish-retry:welfare_reconcile',kind='welfare_reconcile'},false)
for k,v in pairs(result.gameplay_stats) do near(again.gameplay_stats[k],v) end
-- Winning the boundary match unlocks the new batch through the ordinary clear transaction.
local p={save={archive={clear_counts={n1=9},completed=prior_claims()},gameplay_stats=defaults()}}
local crossed=settlement.settle(p,{id='finish-boundary:clear',kind='clear',difficulty_id='n2',count=1,day_key=20000},false)
assert(crossed.ok and crossed.archive.completed.welfare_finish_01 and not crossed.archive.completed.welfare_finish_02)
near(crossed.gameplay_stats.hero_attribute_bonus_pct-p.save.gameplay_stats.hero_attribute_bonus_pct,5)
print('PASS finish gifts: every 10..130 boundary, six exact additive totals, historical backfill, durable dedup, ordinary-clear unlock')
