package.path="scripts/vscripts/?.lua;"..package.path
local calendar=require("systems/archive_calendar")
local benefits=require("systems/archive_benefit_rewards")
local settlement=require("systems/archive_settlement")
local encoder=require("core/json_encoder")
local now=1792962000 -- Monday 2026-10-26 05:00 Beijing.
calendar.set_clock(function() return now end)
local boundary=now
assert(calendar.day(boundary-1)+1==calendar.day(boundary))
assert(benefits.week(boundary-1)+1==benefits.week(boundary))
assert(calendar.day(boundary-5*3600-1)==calendar.day(boundary-1),"Midnight does not reset any daily system")
local profile={save={archive={},gameplay_stats={},content_inventory={}},entitlements={}}
local before=encoder.encode(profile)
local snapshot=benefits.snapshot(profile,false)
assert(snapshot.daily_time.progress==0 and #snapshot.daily_time.rows==6)
assert(#snapshot.daily_wins.rows==5 and #snapshot.weekly_time.rows==9)
assert(snapshot.daily_time.rows[1].status=="locked" and snapshot.daily_time.rows[1].can_claim==0)
assert(snapshot.daily_time.rows[1].id=="daily_time_0" and snapshot.daily_time.rows[1].monthly_only==1
 and snapshot.daily_time.rows[1].auto_claim==0 and #snapshot.daily_time.rows[1].base_rewards==0)
assert(snapshot.refresh_at==boundary+86400 and snapshot.weekly_refresh_at==boundary+7*86400)
assert(encoder.encode(profile)==before,"Read-only welfare snapshots cannot initialize saved state")
local function apply(command,pass)
 local result=settlement.settle(profile,command,pass==true)
 if result.ok and not result.duplicate then
  profile.save.archive=result.archive;profile.save.gameplay_stats=result.gameplay_stats
  if result.content_inventory then profile.save.content_inventory=result.content_inventory end
 end
 return result
end
local login={id="local:login:0",kind="benefit_claim",track="daily_time",tier_id="daily_time_0",event_at=now}
assert(not apply(login,false).ok and profile.save.archive.benefits==nil,
 "A free player cannot consume an empty-base login claim")
local manual=benefits.snapshot(profile,true).daily_time.rows[1]
assert(manual.status=="claimable" and manual.can_claim==1 and manual.auto_claim==0,"Login rewards require an explicit claim click")
assert(apply(login,true).ok and profile.save.content_inventory.special_lottery_ticket==1)
assert(apply(login,true).duplicate and profile.save.content_inventory.special_lottery_ticket==1)
now=boundary+30
assert(apply({id="local:online:60",kind="online_checkpoint",session="local",
 actual_seconds=60,map_seconds=120,event_at=now}).ok)
local days=profile.save.archive.benefits.days
assert(days[tostring(benefits.day(boundary-1))].seconds==30)
assert(days[tostring(benefits.day(boundary))].seconds==30)
assert(apply({id="local:online:retry",kind="online_checkpoint",session="local",
 actual_seconds=60,map_seconds=120,event_at=now}).ok)
assert(days[tostring(benefits.day(boundary))].seconds==30,"Session cursors prevent duplicate credited seconds")
now=boundary+1800
assert(apply({id="local:online:1830",kind="online_checkpoint",session="local",
 actual_seconds=1830,map_seconds=3660,event_at=now}).ok)
local snap=benefits.snapshot(profile,true)
assert(snap.daily_time.progress==30 and snap.daily_time.rows[2].status=="claimable")
assert(snap.weekly_time.progress==30,"Weighted map-level time cannot double welfare time")
local claim={id="local:claim:30",kind="benefit_claim",track="daily_time",tier_id="daily_time_30",event_at=now}
assert(apply(claim,true).ok)
assert(profile.save.content_inventory.lottery_ticket==2)
assert(apply(claim,true).duplicate)
assert(profile.save.content_inventory.lottery_ticket==2)
assert(benefits.snapshot(profile,true).daily_time.rows[2].status=="claimed")
assert(not apply({id="local:claim:repeat",kind="benefit_claim",track="daily_time",tier_id="daily_time_30",event_at=now},true).ok)
now=boundary+86400
assert(benefits.snapshot(profile,true).daily_time.progress==0)
assert(benefits.snapshot(profile,true).weekly_time.progress==30,"Daily refresh retains weekly progress")
profile.save.content_inventory.welfare_zongzi=149
local near_cap=benefits.snapshot(profile,true).daily_time.rows[5]
assert(near_cap.base_rewards[2].count==1 and near_cap.monthly_rewards[2].count==1,
 "Snapshot preserves configured base and month-card quantities")
assert(near_cap.base_rewards[2].actual_count==1 and near_cap.monthly_rewards[2].actual_count==0,
 "The two grants share one remaining zongzi slot")
local config=require("config/generated/archive_benefit_rewards")
for _,row in ipairs(config.rows) do row.enabled=false end
local disabled=benefits.snapshot(profile,true)
assert(#disabled.daily_time.rows==0 and #disabled.daily_wins.rows==0 and #disabled.weekly_time.rows==0)
for _,row in ipairs(config.rows) do row.enabled=true end
-- A pause is not played time. Its gap must not move the last partial minute
-- from before 05:00 into the new day when the observer resumes.
local previous_context=package.loaded["systems/player_context_service"]
package.loaded["systems/player_context_service"]={is_defeated=function() return false end}
PlayerResource={GetConnectionState=function() return 2 end}
local observer=require("systems/archive_online_clock")
local checkpoints={}
observer.init("pause-session",function(_,command) checkpoints[#checkpoints+1]=command end)
now=boundary-60
observer.observe(0,{entitlements={}})
for _=1,50 do now=now+1;observer.sample(0,{entitlements={}}) end
now=boundary+60;observer.sample(0,{entitlements={}})
assert(#checkpoints==1 and checkpoints[1].actual_seconds==50 and checkpoints[1].event_at==boundary-10)
for _=1,10 do now=now+1;observer.sample(0,{entitlements={}}) end
observer.flush(0)
assert(#checkpoints==2 and checkpoints[2].actual_seconds==60)
local paused={}
benefits.record_online(paused,50,checkpoints[1]);benefits.record_online(paused,10,checkpoints[2])
assert(paused.benefits.days[tostring(benefits.day(boundary-1))].seconds==50)
assert(paused.benefits.days[tostring(benefits.day(boundary))].seconds==10)
package.loaded["systems/player_context_service"]=previous_context
print("ARCHIVE_BENEFITS_PASS: 20 tiers, monthly-only manual login, read-only snapshot, actual seconds, Monday 05:00 split, deduplicated claims")
