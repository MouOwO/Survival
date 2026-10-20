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

local schedule=require("config/generated/archive_daily_schedule")
local items=require("config/generated/archive_daily_items")
local duplicate_rates={}
for _,item in ipairs(require("config/lottery_config").items) do
    if item.item_type=="积分道具" then
        local quality=string.lower(item.quality)
        assert(not duplicate_rates[quality] or duplicate_rates[quality]==item.duplicate_points)
        duplicate_rates[quality]=item.duplicate_points
    end
end
local function fixture(count,claimed_today)
    return {save={archive={daily_rewards={first_day=100,claimed=claimed_today and {["200"]=true} or {},
        count=count,item_counts={}}}},entitlements={}}
end
local function same(actual,expected,message)
    assert(type(actual)==type(expected),message or "Value types differ")
    if type(expected)~="table" then assert(actual==expected,message or "Values differ");return end
    for key,value in pairs(expected) do same(actual[key],value,message) end
    for key in pairs(actual) do assert(expected[key]~=nil,message or "Unexpected field") end
end
local function copy(value)
    if type(value)~="table" then return value end
    local result={};for key,item in pairs(value) do result[key]=copy(item) end;return result
end
-- Current position is a cumulative claim ordinal, never a calendar date or a
-- second entitlement/reward cycle. Rollover preserves a just-claimed day 28.
local cases={
    {0,false,0,1}, {1,true,0,1}, {6,false,0,7}, {7,true,0,7}, {7,false,0,8},
    {27,false,0,28}, {28,true,0,28}, {28,false,28,1}, {29,true,28,1},
    {55,false,28,28}, {56,true,28,28}, {56,false,56,1}, {85,false,84,2}
}
for _,case in ipairs(cases) do
    local count,claimed_today,start,current28=unpack(case)
    local source=fixture(count,claimed_today)
    local saved=copy(source)
    local snapshot=daily.snapshot(source,200,false)
    assert(#snapshot.calendar28==28 and snapshot.calendar_start_count==start)
    assert(snapshot.calendar_current_day==current28)
    assert(#snapshot.cycle==7,"The authoritative seven-claim compatibility view is preserved")
    assert(snapshot.current_day==(current28-1)%7+1)
    assert(snapshot.period_id==tostring(math.floor(math.max(0,count-(claimed_today and 1 or 0))/7)))
    local highlighted,claimable=0,0
    for index,row in ipairs(snapshot.calendar28) do
        assert(row.day==index and row.absolute_count==start+index)
        local expected_status=index<current28 and "claimed" or index==current28
            and (claimed_today and "claimed" or "claimable") or "not_open"
        assert(row.status==expected_status,"Calendar state must reflect only real cumulative claims")
        assert(row.is_today==(index==current28 and 1 or 0))
        highlighted=highlighted+row.is_today
        if row.status=="claimable" then claimable=claimable+1 end
        local official=schedule.by_id[(row.absolute_count-1)%7+1]
        assert(#row.rewards==#official.item_ids,"Day five/six retain both configured rewards in each of four rounds")
        for reward_index,reward in ipairs(row.rewards) do
            local id=official.item_ids[reward_index]
            same(reward,{id=id,name=items.by_id[id].display_name,count=tonumber(official.item_counts[reward_index]),
                description=items.by_id[id].description,quality=items.by_id[id].quality,
                max_owned=1,owned_count=0,duplicate_points=assert(duplicate_rates[string.lower(items.by_id[id].quality)]),
                duplicate_currency="shop_points",converted_currency="shop_points"},"Calendar uses real configured rewards")
        end
    end
    assert(highlighted==1 and claimable==(claimed_today and 0 or 1))
    assert(#snapshot.specials==3 and snapshot.specials[3].day==21,"The fourth visual row never invents a fourth pass reward")
    assert(snapshot.premium.status=="unconfigured")
    same(source,saved,"Rendering a calendar must not edit saved progress")
end
local fresh={save={},entitlements={}}
local fresh_snapshot=daily.snapshot(fresh,200,false)
assert(fresh_snapshot.calendar_current_day==1 and fresh_snapshot.calendar_start_count==0)
assert(fresh.save.archive==nil,"Snapshot presentation must not initialize or persist a save")
-- Reward tables belong to their presentation row and do not mutate another
-- round, the compatibility cycle, or the generated reward configuration.
fresh_snapshot.calendar28[1].rewards[1].count=99
assert(fresh_snapshot.calendar28[8].rewards[1].count==3)
assert(fresh_snapshot.cycle[1].rewards[1].count==3)
assert(tonumber(schedule.by_id[1].item_counts[1])==3)

-- Exercise real makeup settlement: an older date advances the claim count but
-- leaves today's ordinary claim available, including across a 28-claim edge.
local makeup=fixture(27,false)
local applied={}
local function record(_,item) applied[item.item_id]=(applied[item.item_id] or 0)+1 end
assert(daily.apply({kind="daily_claim",today=200,target_day=199},makeup.save.archive,{},true,record))
local makeup_snapshot=daily.snapshot(makeup,200,true)
assert(makeup_snapshot.count==28 and makeup_snapshot.claimed==0)
assert(makeup_snapshot.calendar_start_count==28 and makeup_snapshot.calendar_current_day==1)
assert(makeup_snapshot.calendar28[1].absolute_count==29 and makeup_snapshot.calendar28[1].status=="claimable")
assert(makeup_snapshot.current_day==1 and makeup_snapshot.period_id=="4")
assert(applied.daily_gold_gem==1 and makeup.save.archive.daily_rewards.item_counts.daily_gold_gem==1,
    "The 28th claim unlocks its ordinary seventh-day reward once")
assert(makeup.save.archive.commerce.balances.shop_points==2*duplicate_rates.r,
    "The other two configured seventh-day copies convert into the formal quality-rate wallet")
assert(applied.daily_wealth_talisman==1 and applied.daily_ancient_tree==1 and applied.daily_forest_origin==1)
assert(daily.apply({kind="daily_claim",today=200,target_day=200},makeup.save.archive,{},true,record))
local completed=daily.snapshot(makeup,200,true)
assert(completed.count==29 and completed.calendar_start_count==28 and completed.calendar_current_day==1)
assert(completed.calendar28[1].status=="claimed" and completed.calendar28[2].status=="not_open")
assert(applied.daily_growth_gem==1 and makeup.save.archive.daily_rewards.item_counts.daily_growth_gem==1,
    "The next claim unlocks its ordinary first-day reward once")
assert(makeup.save.archive.commerce.balances.shop_points==4*duplicate_rates.r,
    "Window rollover preserves the prior wallet and converts only the next two actual duplicates")
assert(applied.daily_wealth_talisman==1 and applied.daily_ancient_tree==1 and applied.daily_forest_origin==1,
    "Changing calendar windows never renews one-time pass rewards")
assert(not daily.apply({kind="daily_claim",today=200,target_day=200},makeup.save.archive,{},true,record),
    "Calendar presentation does not allow duplicate daily grants")
print("DAILY_SNAPSHOT_PASS: authoritative 7/28 claim views, rollover and makeup boundaries, all real multi-item rewards, unchanged one-time pass grants, read-only snapshots")
