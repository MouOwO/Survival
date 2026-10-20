package.path = 'scripts/vscripts/?.lua;' .. package.path
local calendar = require('systems/archive_calendar')
local now = 1000
calendar.set_clock(function() return now end)
local settlement = require('systems/archive_settlement')
local rules = require('config/generated/archive_social_rules')
local challenges = require('config/generated/archive_challenge_definitions')
local function profile(pass)
 return {entitlements={archive_pass={active=pass,expires_at=2000}},save={archive={},gameplay_stats={}}}
end
local function commit(p,c)
 local result=settlement.settle(p,c,calendar.has_pass(p))
 assert(result.ok,result.error)
 p.save.archive=result.archive;p.save.gameplay_stats=result.gameplay_stats
 return result
end
for _,pool in ipairs({'beast','ex','friend','wife'}) do
 local challenge
 for _,def in ipairs(challenges.rows) do if def.reward_kind=='social_ticket' and def.reward_key==pool then challenge=def.challenge_id;break end end
 assert(challenge,pool)
 for _,pass in ipairs({false,true}) do
  local p=profile(pass);local rule=rules.by_id[pool]
  for i=1,rule.daily_limit+1 do
   local c={kind='challenge',id=pool..i,challenge_id=challenge,day_key='today'}
   local result=commit(p,c);local before=p.save.archive.social_tickets[rule.currency_id]
   assert(commit(p,c).duplicate);assert(p.save.archive.social_tickets[rule.currency_id]==before)
  end
  assert(p.save.archive.social_tickets[rule.currency_id]==rule.daily_limit*(pass and 2 or 1),pool)
  assert(p.save.archive.daily.today['social_'..pool]==rule.daily_limit*(pass and 2 or 1))
 end
 local p=profile(true);now=2000
 commit(p,{kind='challenge',id=pool..':expired',challenge_id=challenge,day_key='today'})
 assert(p.save.archive.social_tickets[rules.by_id[pool].currency_id]==1)
 now=1000
end
local daily_limits=require('systems/archive_daily_limits')
for _,pass in ipairs({false,true}) do
 local expected=pass and 40 or 20
 for i=1,12 do
  local key=string.format('fragment_%02d',i);local archive={}
  assert(daily_limits.grant(archive,key,1000,'quota_test',pass)==expected,key)
  assert(daily_limits.grant(archive,key,1,'quota_test',pass)==0,'quota cannot be refunded')
 end
 local archive={};assert(daily_limits.grant(archive,'cage',1000,'quota_test',pass)==(pass and 90 or 30))
end
local monthly=require('systems/archive_monthly_effects')
local p=profile(true)
p.save.archive.online={map_level=5,work_levels={work_01=1,work_02=1,work_04=1}}
local extra=monthly.project(p)
assert(extra.map_level==nil and extra.initial_wood==nil and extra.initial_population_cap==nil, "map only doubles time")
assert(extra.lumberjack_attack_speed_bonus_pct==2 and extra.tower_attack_flat==100 and extra.wall_initial_health==1000)
assert(monthly.project(p).tower_attack_flat==100,'projection cannot stack')
now=2000;assert(next(monthly.project(p))==nil,'expiry removes bonus');now=1000
p.entitlements.archive_pass.active=false;assert(next(monthly.project(p))==nil)
p=profile(true);p.mode='pure';assert(next(monthly.project(p))==nil,'empty projected match excludes history')
print('ARCHIVE_MONTHLY_PASS: four pools/base/pass/expired/daily cap/duplicate; work projection/expiry/idempotency; map time only PASS')
-- Exercise the actual runtime projection and entitlement-change refresh path.
local bus,events=require('core/event_bus'),require('core/events')
local frozen=false
package.loaded['systems/gameplay_phase_guard']={post_clear_frozen=function()return frozen end}
package.loaded['core/scheduler']={every=function()end}
local runtime=profile(true)
runtime.save.archive.online={map_level=5,work_levels={work_02=1,work_04=1}}
runtime.save.gameplay_stats={tower_attack_flat=100,wall_initial_health=1000,map_level=5}
package.loaded['systems/player_profile_service']={get_profile=function()return runtime end}
require('systems/permanent_reward_effect_service').init()
local function refresh(reason)
 bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0,reason=reason})
 return bus.request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST,{player_id=0}).totals
end
local values=refresh('profile_changed')
assert(values.tower_attack_flat==200 and values.wall_initial_health==2500)
assert(values.map_level==5 and values.wall_health_regen_per_second==25,'map attribute must remain single')
assert(refresh('profile_changed').tower_attack_flat==200,'repeat profile refresh cannot stack')
now=2000;values=refresh('archive_boss_refresh')
assert(values.tower_attack_flat==100 and values.wall_initial_health==1500,'expiry retracts bonus')
now=1000;values=refresh('archive_boss_refresh');assert(values.tower_attack_flat==200)
frozen=true;now=2000;values=refresh('archive_boss_refresh')
assert(values.tower_attack_flat==100 and values.wall_initial_health==1500,'post-clear expiry removes only monthly layer')
now=1000;assert(refresh('archive_boss_refresh').tower_attack_flat==200)
assert(refresh('archive_boss_refresh').tower_attack_flat==200,'frozen refresh cannot stack')
print('ARCHIVE_MONTHLY_RUNTIME: normal/frozen refresh, actual map effects unchanged, expiry/reactivation PASS')
