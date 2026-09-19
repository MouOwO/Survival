package.path="scripts/vscripts/?.lua;"..package.path
local daily=require("systems/archive_daily_rewards")
local profile={save={archive={daily_rewards={first_day=100,claimed={},count=6,item_counts={}}}},entitlements={}}
local before=daily.snapshot(profile,106,false)
assert(before.current_day==7 and before.ordinary_status=="claimable")
assert(before.cycle[7].status=="claimable" and before.cycle[7].is_today==1)
assert(before.cycle[1].status=="claimed")
assert(before.cycle[5].rewards[2].id=="daily_wood_gem")
assert(before.cycle[5].rewards[2].count==3)
assert(before.premium.status=="unconfigured","Do not invent weekly equipment eligibility")
profile.save.archive.daily_rewards.count=7
profile.save.archive.daily_rewards.claimed["106"]=true
local after=daily.snapshot(profile,106,true)
assert(after.current_day==7 and after.cycle[7].status=="claimed")
assert(after.ordinary_status=="claimed" and after.has_pass==1)
local next_day=daily.snapshot(profile,107,true)
assert(next_day.current_day==1 and next_day.period_id~=after.period_id)
assert(next_day.cycle[1].status=="claimable" and next_day.cycle[2].status=="not_open")
assert(next_day.cycle_mode=="claim_count")
assert(next_day.count==7 and next_day.specials[1].id=="daily_wealth_talisman")
print("DAILY_SNAPSHOT_PASS: authoritative statuses, actual item IDs/counts, seventh claim, cycle rollover, no invented premium")
