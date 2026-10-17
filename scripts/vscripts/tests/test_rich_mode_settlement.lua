package.path = "scripts/vscripts/?.lua;" .. package.path
local reducer=require("systems/archive_settlement")
local config=require("config/generated/player_gameplay_stats")
local profile={save={archive={clear_counts={n5=3,n10=1}},gameplay_stats={},content_inventory={}}}
for _,row in ipairs(config.rows) do profile.save.gameplay_stats[row.field_id]=row.default_value end
local function settle(kind,difficulty,id)
    local result=reducer.settle(profile,{kind=kind,id=id,difficulty_id=difficulty,count=1,day_key="20000"},false)
    assert(result.ok);profile.save.archive,profile.save.gameplay_stats=result.archive,result.gameplay_stats
    return result
end
settle("clear","n10","pure:first")
local faith = profile.save.archive.buildings.faith
assert(profile.save.archive.clear_counts.n10==2 and profile.save.archive.standard_clear_counts.n10==1,
    "first new pure clear freezes historical ordinary provenance before incrementing mixed counters")
settle("rich_clear","n5","rich:first")
assert(profile.save.archive.buildings.faith > faith,"rich retains ordinary capped victory faith")
assert(profile.save.archive.rich_clear_counts.n5==1 and profile.save.archive.clear_counts.n5==3)
assert(profile.save.archive.standard_clear_counts.n5==3)
assert(settle("rich_clear","n5","rich:first").duplicate)
assert(profile.save.archive.rich_clear_counts.n5==1,"lost acknowledgements cannot add another rich clear")
settle("rich_clear","n10","rich:second")
assert(profile.save.archive.standard_clear_counts.n10==1 and profile.save.archive.clear_counts.n10==2)
settle("standard_clear","n10","standard:first")
assert(profile.save.archive.standard_clear_counts.n10==2 and profile.save.archive.clear_counts.n10==3)
assert(profile.save.archive.rich_clear_counts.n10==1)
assert(require("systems/archive_welfare_rewards").wins(profile.save.archive)==8,
    "both modes count towards shared victory welfare without merging difficulty unlocks")
local clean={save={archive={},gameplay_stats=profile.save.gameplay_stats,content_inventory={}}}
local first=reducer.settle(clean,{kind="clear",id="pure:new-account",difficulty_id="n10",count=1,day_key="20000"},false)
assert(first.ok and first.archive.standard_clear_counts.n10==nil,
    "new pure N10 must not establish a rich qualification")
print("RICH_MODE_SETTLEMENT_PASS: historical freeze, separate permanent counters, standard-only provenance and idempotence")
