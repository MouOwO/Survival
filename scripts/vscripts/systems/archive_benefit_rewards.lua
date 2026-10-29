-- Welfare progress is credited only by server online checkpoints and clear receipts.
-- All daily account systems refresh at 05:00 Beijing; weeks start Monday 05:00.
local config = require("config/generated/archive_benefit_rewards")
local calendar = require("systems/archive_calendar")
local M = {}
local OFFSET, DAY = 3 * 3600, 86400
local MAX_INTEGER = 9007199254740991
local PUBLIC_BETA_TIER = "public_beta_login"
local names = {
    lottery_ticket = {name="普通抽奖券", description="用于地图抽奖。"},
    special_lottery_ticket = {name="金色抽奖券", description="用于修仙、龙骑与暑期宝箱。"},
}
local function integer(value)
    return type(value)=="number" and value==value and value>=0
        and value<=MAX_INTEGER and value==math.floor(value)
end
function M.day(timestamp) return math.floor((timestamp + OFFSET) / DAY) end
function M.week(timestamp) return math.floor((M.day(timestamp) + 3) / 7) end
local function active(row, timestamp)
    if not row or row.enabled ~= true then return false end
    local starts, finishes = tonumber(row.starts_at) or 0, tonumber(row.ends_at) or 0
    return (starts == 0 or timestamp >= starts) and (finishes == 0 or timestamp < finishes)
end
-- Read-only account projection. The popup cannot create a bucket, a claim, or
-- inventory merely by requesting its eligibility.
function M.public_beta_snapshot(profile, timestamp)
    timestamp = timestamp or calendar.now()
    local row, day = config.by_id[PUBLIC_BETA_TIER], M.day(timestamp)
    local archive = profile and profile.save and profile.save.archive or {}
    local days = archive.benefits and archive.benefits.days or {}
    local bucket = days[tostring(day)] or {}
    local claimed = (bucket.claimed or {})[PUBLIC_BETA_TIER] ~= nil
    local enabled = active(row, timestamp)
    return {active=enabled and 1 or 0, day_key=tostring(day),
        refresh_at=(day+1)*DAY-OFFSET, eligible=enabled and not claimed and 1 or 0,
        claimed=claimed and 1 or 0, ticket_id="special_lottery_ticket",
        ticket_name="金色抽奖券", ticket_count=2,
        revision=profile and profile.revision or 0}
end
local function event_time(command)
    -- HTTP supplies the immutable database operation time. The local observer
    -- supplies its server sample time. Never fall back to a client date.
    if integer(command.event_at) then return command.event_at end
    return math.floor(calendar.now())
end
local function state(archive)
    archive.benefits = archive.benefits or {version=1, days={}, weeks={}}
    local result=archive.benefits
    result.days=result.days or {};result.weeks=result.weeks or {}
    return result
end
local function period(state, kind, key)
    local map=kind=="day" and state.days or state.weeks
    key=tostring(key)
    map[key]=map[key] or {seconds=0,wins=0,claimed={}}
    map[key].claimed=map[key].claimed or {}
    return map[key]
end
local function prune(s, timestamp)
    local day,week=M.day(timestamp),M.week(timestamp)
    -- Late outbox items update their own period, never reset a newer bucket.
    -- Keep a bounded overlap for in-flight receipts around daily/weekly reset.
    for key in pairs(s.days) do if tonumber(key) and tonumber(key)<day-7 then s.days[key]=nil end end
    for key in pairs(s.weeks) do if tonumber(key) and tonumber(key)<week-2 then s.weeks[key]=nil end end
end
function M.record_online(archive, elapsed, command)
    if not integer(elapsed) or elapsed==0 then return end
    local finish=event_time(command)
    if elapsed>finish then return end
    local start, s=finish-elapsed,state(archive)
    while start<finish do
        local key=M.day(start)
        local boundary=(key+1)*DAY-OFFSET
        local stop=math.min(finish,boundary)
        local seconds=stop-start
        local daily=period(s,"day",key)
        daily.seconds=(tonumber(daily.seconds) or 0)+seconds
        local weekly=period(s,"week",math.floor((key+3)/7))
        weekly.seconds=(tonumber(weekly.seconds) or 0)+seconds
        start=stop
    end
    prune(s,math.max(finish,math.floor(calendar.now())))
end
function M.record_win(archive, command)
    if command.test_only then return end
    local timestamp=event_time(command)
    local s=state(archive)
    local daily=period(s,"day",M.day(timestamp))
    daily.wins=(tonumber(daily.wins) or 0)+1
    prune(s,math.max(timestamp,math.floor(calendar.now())))
end
local function public_rewards(ids, counts, source_save, reserved)
    local rows={}
    reserved=reserved or {}
    for index,id in ipairs(ids or {}) do
        local item=names[id]
        local stackable=require("systems/archive_stackable_items").definition(id)
        if stackable then
            item={name=stackable.name,description=stackable.description or "永久道具；持有数量自动计算属性。"}
        end
        if not item then
            local definition=require("config/lottery_config").by_id[id]
            assert(definition,"benefit_item_unknown:"..id)
            item={name=definition.name,description=definition.description}
        end
        local count=tonumber(counts[index])
        local owned=stackable and require("systems/archive_stackable_items").count(source_save,id) or nil
        local accepted=count
        if stackable and stackable.max_owned>0 then
            accepted=math.min(count,math.max(0,stackable.max_owned-owned-(reserved[id] or 0)))
            reserved[id]=(reserved[id] or 0)+accepted
        end
        rows[#rows+1]={id=id,name=item.name,description=item.description,count=count,
            quality=stackable and stackable.quality or nil,
            max_owned=stackable and stackable.max_owned or nil,owned_count=owned,
            actual_count=accepted,overflow_count=count-accepted,
            at_max_owned=stackable and stackable.max_owned>0 and owned>=stackable.max_owned and 1 or 0}
    end
    return rows
end
function M.snapshot(profile, pass, timestamp)
    timestamp=timestamp or calendar.now()
    local s=(profile.save.archive or {}).benefits or {}
    local day,week=M.day(timestamp),M.week(timestamp)
    local result={has_pass=pass and 1 or 0,timezone="Asia/Shanghai",reset_hour=5,
        refresh_at=(day+1)*DAY-OFFSET,weekly_refresh_at=((week+1)*7-3)*DAY-OFFSET}
    for _,track in ipairs({"daily_time","daily_wins","weekly_time"}) do
        local key=track=="weekly_time" and week or day
        local saved=((track=="weekly_time" and s.weeks or s.days) or {})[tostring(key)] or {}
        local progress=track=="daily_wins" and (tonumber(saved.wins) or 0) or math.floor((tonumber(saved.seconds) or 0)/60)
        local group={period_id=tostring(key),progress=progress,rows={}}
        for _,row in ipairs(config.rows) do if row.enabled and row.track==track then
            local claimed=(saved.claimed or {})[row.reward_id]~=nil
            local ready=progress>=row.required and (not row.monthly_only or pass==true)
            local reserved={}
            local base=public_rewards(row.base_item_ids,row.base_counts,profile.save,reserved)
            local monthly=public_rewards(row.pass_item_ids,row.pass_counts,profile.save,reserved)
            group.rows[#group.rows+1]={id=row.reward_id,required=row.required,
                base_rewards=base,monthly_rewards=monthly,
                monthly_only=row.monthly_only and 1 or 0,auto_claim=row.auto_claim and 1 or 0,
                status=claimed and "claimed" or ready and "claimable" or "locked",
                can_claim=not row.auto_claim and not claimed and ready and 1 or 0}
        end end
        result[track]=group
    end
    return result
end
local function grant_item(id, count, inventory, stats, archive, source_save)
    assert(integer(count) and count>0,"benefit_reward_invalid")
    if id=="lottery_ember_of_legacy" or id=="welfare_zongzi" then
        local accepted,overflow=require("systems/archive_stackable_items").grant(
            {content_inventory=inventory,lottery_applied_item_effects=(source_save or {}).lottery_applied_item_effects},
            archive,stats,id,count)
        return {id=id,count=accepted,overflow=overflow or 0,converted_points=0}
    end
    assert(names[id],"benefit_item_unknown:"..id)
    local old=inventory[id] or 0
    assert(integer(old) and count<=MAX_INTEGER-old,"benefit_inventory_invalid")
    inventory[id]=old+count
    return {id=id,count=count,converted_points=0}
end
function M.apply(command, archive, stats, inventory, pass, source_save)
    local row=config.by_id[command.tier_id]
    if not row or not row.enabled or row.track~=command.track then return false,"福利档位不存在" end
    -- An empty-base monthly login tier must never consume a free player's
    -- daily claim; buying a month card later that day still earns the reward.
    if row.monthly_only and pass~=true then return false,"该福利需要有效月卡" end
    local timestamp=event_time(command)
    if not active(row, timestamp) then return false,"活动尚未开始或已结束" end
    local key=row.period=="week" and M.week(timestamp) or M.day(timestamp)
    local s=state(archive)
    local saved=period(s,row.period,key)
    if saved.claimed[row.reward_id] then return false,"该档福利已领取" end
    local progress=row.metric=="wins" and (tonumber(saved.wins) or 0) or math.floor((tonumber(saved.seconds) or 0)/60)
    if progress<row.required then return false,"福利领取条件尚未达成" end
    local granted={}
    local function grant(ids,counts)
        for index,id in ipairs(ids or {}) do
            granted[#granted+1]=grant_item(id,tonumber(counts[index]),inventory,stats,archive,source_save)
        end
    end
    grant(row.base_item_ids,row.base_counts)
    if pass then grant(row.pass_item_ids,row.pass_counts) end
    saved.claimed[row.reward_id]={at=timestamp,has_pass=pass and 1 or 0}
    prune(s,math.max(timestamp,math.floor(calendar.now())))
    return true,{ok=true,track=command.track,tier_id=command.tier_id,period_id=tostring(key),rewards=granted}
end
return M
