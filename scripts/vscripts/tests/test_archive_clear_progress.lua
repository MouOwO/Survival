-- Standalone real module, deterministic config fixture; no Dota engine needed.
package.path = "scripts/vscripts/?.lua;" .. package.path
local function row(id, mode, difficulty, required, extra)
    local item = { achievement_id=id, mode_id=mode, difficulty_id=difficulty, required_count=required,
        display_name=id, description="reward", icon_style="scroll", enabled=true,
        effect_ids={"wood"}, effect_values={10} }
    for key,value in pairs(extra or {}) do item[key]=value end
    return item
end
local rows = {
    row("clear_n1_1", nil, "n1", 1),
    row("pure_first", "pure", "n1", 1),
    row("rich_first", "rich", "n1", 1),
    row("cold_first", "cold", "n1", 1),
    row("scourge_first", "scourge", "n1", 1),
    row("cold_future", "cold", "n20", 1),
    row("future_mode", "future", "n1", 1),
    row("rich_repeated", "rich", "n2", 30, {reward_mode="per_clear",reward_start=10,reward_limit=20}),
    row("renamed_standard", "standard", "n3", 3),
    row("disabled", "pure", "n1", 1, {enabled=false}),
}
package.loaded["config/generated/archive_achievements"] = {rows=rows}
local available_cold=4
package.loaded["config/difficulty_config"] = {client_options=function(progression,mode)
    assert(progression == nil, "availability follows configured combat support, not unlock progress")
    local maximum=mode=="cold" and available_cold or mode=="scourge" and 2 or 10
    local result={}; for i=1,maximum do result[#result+1]={difficulty_id="N"..i} end; return result
end}
package.loaded["config/recorded_mode_balance"] = {has_difficulty=function()
    error("recorded sample coverage must not override formula-mode availability")
end}
local progress = require("systems/archive_clear_progress")
local function apply(stats,item) stats.wood=(stats.wood or 0)+item.effect_values[1] end
local function record(archive,stats,mode,difficulty,count)
    local ok,reason=progress.record(archive,{mode_id=mode,difficulty_id=difficulty,count=count or 1},stats,apply)
    assert(ok,reason)
end
local function find(list,id) for _,r in ipairs(list) do if r.id==id then return r end end end

local archive={clear_counts={n1=99,n3=3}, completed={clear_n1_1=true,clear_n3_3=true}}
local stats={}
record(archive,stats,"pure","n1")
assert(archive.mode_clear_counts.pure.n1==1 and archive.mode_clear_counts.standard==nil)
assert(archive.clear_counts.n1==99 and archive.completed.clear_n1_1==true)
assert(stats.wood==10 and archive.completed["pure:pure_first"]==true)
record(archive,stats,"pure","n1")
assert(stats.wood==10,"a one-time milestone cannot be awarded on each later clear")
record(archive,stats,"standard","n1")
record(archive,stats,"standard","n3",3)
assert(stats.wood==10,"old standard receipts and renamed IDs must not grant twice")
for _,mode in ipairs({"rich","cold","scourge"}) do record(archive,stats,mode,"n1") end
assert(stats.wood==40 and archive.mode_clear_counts.rich.n1==1 and archive.mode_clear_counts.cold.n1==1)
assert(archive.mode_clear_counts.scourge.n1==1 and archive.mode_clear_counts.standard.n1==1)
assert(archive.mode_clear_counts.standard.n3==3)
assert(archive.rich_clear_counts==nil,"module must not fabricate or mutate compatibility counters")

local standard=find(progress.rows(archive,{mode_id="standard"}),"clear_n1_1")
assert(standard.count==99 and standard.completed==1 and standard.target==1 and standard.mode_name=="常规模式")
assert(find(progress.rows(archive,{mode_id="pure"}),"pure_first").count==2)
assert(find(progress.rows(archive),"cold_future")==nil and find(progress.rows(archive),"future_mode")==nil)
assert(find(progress.rows(archive),"disabled")==nil and #rows==10,"hidden configuration must remain intact")
assert(find(progress.rows(archive,{mode_id="cold",max_available_difficulty=20}),"cold_future"))
assert(find(progress.rows(archive,{max_available_difficulty={cold=20}}),"cold_future"))
assert(progress.max_available("cold")==4 and progress.max_available("scourge")==2)
available_cold=10
assert(progress.max_available("cold")==10,"availability must follow live balance changes")

local unchanged=archive.mode_clear_counts.cold.n20
local ok,reason=progress.record(archive,{mode_id="cold",difficulty_id="n20",count=1},stats,apply)
assert(not ok and reason=="archive_mode_difficulty_unavailable" and archive.mode_clear_counts.cold.n20==unchanged)
available_cold=50
assert(progress.max_available("cold")==50)
record(archive,stats,"cold","N50",2)
assert(archive.mode_clear_counts.cold.n50==2, "N50 progress must survive without a lower hard cap")
ok,reason=progress.record(archive,{mode_id="cold",difficulty_id="n51",count=1},stats,apply)
assert(not ok and reason=="archive_mode_difficulty_unavailable")
for _,command in ipairs({{mode_id="fishing",difficulty_id="n1",count=1},
    {mode_id="pure",difficulty_id="n1",count=true},{mode_id="pure",difficulty_id="n1",count=-1},
    {mode_id="pure",difficulty_id="n0",count=1},{mode_id="pure",difficulty_id="n21",count=1}}) do
    assert(not progress.record(archive,command,stats,apply))
end

local repeated,repeat_stats={},{}
record(repeated,repeat_stats,"rich","n2",10)
assert((repeat_stats.wood or 0)==0)
record(repeated,repeat_stats,"rich","n2",2)
assert(repeat_stats.wood==20 and repeated.mode_clear_rewards["rich:rich_repeated"]==2)
local displayed=find(progress.rows(repeated,{mode_id="rich"}),"rich_repeated")
assert(displayed.count==12 and displayed.target==30 and displayed.reward_count==2 and displayed.completed==0)
record(repeated,repeat_stats,"rich","n2",30)
assert(repeat_stats.wood==200 and repeated.mode_clear_rewards["rich:rich_repeated"]==20)
record(repeated,repeat_stats,"rich","n2",1)
assert(repeat_stats.wood==200 and find(progress.rows(repeated),"rich_repeated").completed==1)
assert(repeated.mode_clear_counts.rich.n2==43,"reward caps must not cap real clear progress")
print("archive mode clear progression: passed")
