local rules=require("config/generated/archive_daily_rules").by_id.default
local schedule=require("config/generated/archive_daily_schedule")
local items=require("config/generated/archive_daily_items")
local M={}
local MAX_INTEGER=9007199254740991
local function duplicate_rate(item)
    -- One formal source for the commerce duplicate wallet; daily rewards use
    -- the same quality rates as permanent lottery point items.
    local rate=nil
    for _,row in ipairs(require("config/lottery_config").items) do
        if row.item_type=="积分道具" and string.lower(row.quality)==string.lower(item.quality) then
            assert(rate==nil or rate==row.duplicate_points,"daily_duplicate_rate_conflict")
            rate=row.duplicate_points
        end
    end
    assert(type(rate)=="number" and rate>0 and rate==math.floor(rate),"daily_duplicate_rate_missing")
    return rate
end
local function credit_duplicates(save,item,count)
    if count<=0 then return end
    local rate=duplicate_rate(item)
    save.commerce=save.commerce or {};save.commerce.balances=save.commerce.balances or {}
    local wallet=save.commerce.balances;local before=wallet.shop_points or 0
    assert(type(before)=="number" and before==before and before>=0
        and before<=MAX_INTEGER and before==math.floor(before),"commerce_wallet_invalid")
    assert(count<=math.floor((MAX_INTEGER-before)/rate),"commerce_wallet_limit")
    wallet.shop_points=before+count*rate
end
local function unique_state(daily)
    if type(daily.item_counts)~="table" then return false,"daily_unique_migration_required" end
    for _,item in ipairs(items.rows) do if item.enabled~=false then
        local count=daily.item_counts[item.item_id] or 0
        -- Historical quantities and their already-applied effects require
        -- the backed-up repair, not a silent clamp during an ordinary claim.
        if type(count)~="number" or count~=count or count<0 or count>1 or count~=math.floor(count) then
            return false,"daily_unique_migration_required"
        end
        assert(item.max_owned==1,"daily_unique_limit_invalid")
    end end
    return true
end
local function state(save, day)
    save.daily_rewards=save.daily_rewards or {first_day=day, claimed={}, count=0, item_counts={}}
    return save.daily_rewards
end
function M.apply(command,save,stats,pass,apply)
    local day=command.today
    local daily=state(save,day)
    local valid,reason=unique_state(daily)
    if not valid then return false,reason end
    if command.kind=="daily_init" then return true end
    local target=tonumber(command.target_day)
    if not target or target~=math.floor(target) or target>day or target<daily.first_day then return false,"签到日期无效" end
    if target<day and (not pass or target<day-rules.makeup_days+1) then return false,"补签需要有效月卡，且仅限最近30天" end
    local key=tostring(target)
    if daily.claimed[key] then return false,"该日期已领取" end
    local function grant(id,count)
        local item=assert(items.by_id[id],id)
        assert(type(count)=="number" and count>=0 and count==math.floor(count),"daily_reward_count_invalid")
        local accepted=math.max(0,math.min(count,1-(daily.item_counts[id] or 0)))
        for _=1,accepted do apply(stats,item) end
        daily.item_counts[id]=(daily.item_counts[id] or 0)+accepted
        credit_duplicates(save,item,count-accepted)
    end
    daily.count=daily.count+1
    local row=schedule.by_id[(daily.count-1)%7+1]
    for i,id in ipairs(row.item_ids) do grant(id,tonumber(row.item_counts[i])) end
    if pass then for i,n in ipairs(rules.pass_milestones) do
        local id=rules.pass_item_ids[i]
        -- A milestone is a one-time entitlement. Rechecking eligibility on
        -- later claims must not invent a fresh SSR duplicate every day.
        if daily.count>=tonumber(n) and (daily.item_counts[id] or 0)==0 then grant(id,1) end
    end end
    daily.claimed[key]=true
    return true
end
function M.snapshot(profile,day,pass)
    local daily=profile.save.archive and profile.save.archive.daily_rewards
        or {first_day=day,claimed={},count=0,item_counts={}}
    local cycle={}
    local claimed_today=daily.claimed[tostring(day)] == true
    local current=(claimed_today and math.max(0,daily.count-1) or daily.count)%7+1
    local function row_rewards(row)
        local rewards={}
        for i,id in ipairs(row.item_ids) do
            local item=items.by_id[id]
            rewards[#rewards+1]={id=id,name=item.display_name,count=tonumber(row.item_counts[i]),description=item.description,quality=item.quality,
                max_owned=1,owned_count=(tonumber(daily.item_counts[id]) or 0)>0 and 1 or 0,
                duplicate_points=duplicate_rate(item),duplicate_currency="shop_points",converted_currency="shop_points"}
        end
        return rewards
    end
    for _, row in ipairs(schedule.rows) do
        cycle[#cycle+1]={day=row.day_id,rewards=row_rewards(row),
            status=row.day_id<current and "claimed" or row.day_id==current and (claimed_today and "claimed" or "claimable") or "not_open",
            is_today=row.day_id==current and 1 or 0}
    end
    -- A four-week presentation of the existing seven-claim reward schedule.
    -- Keep today's completed claim visible at a window boundary; an unclaimed
    -- day (including after makeup claims) points at the next cumulative claim.
    local calendar_anchor=math.max(0,daily.count-(claimed_today and 1 or 0))
    local calendar_start=math.floor(calendar_anchor/28)*28
    local calendar_current=calendar_anchor-calendar_start+1
    local calendar={}
    for i=1,28 do
        local absolute_count=calendar_start+i
        local row=schedule.by_id[(absolute_count-1)%7+1]
        calendar[#calendar+1]={day=i,absolute_count=absolute_count,rewards=row_rewards(row),
            status=i<calendar_current and "claimed" or i==calendar_current and (claimed_today and "claimed" or "claimable") or "not_open",
            is_today=i==calendar_current and 1 or 0}
    end
    local missed={}
    for d=math.max(daily.first_day,day-rules.makeup_days+1),day-1 do
        if not daily.claimed[tostring(d)] then missed[#missed+1]=d end
    end
    local specials={}
    for i,id in ipairs(rules.pass_item_ids) do
        local item=items.by_id[id]
        local owned=(tonumber(daily.item_counts[id]) or 0)>0 and 1 or 0
        specials[#specials+1]={id=id,day=tonumber(rules.pass_milestones[i]),name=item.display_name,description=item.description,owned=owned,
            max_owned=1,owned_count=owned,duplicate_points=duplicate_rate(item),duplicate_currency="shop_points"}
    end
    local entitlement=(profile.entitlements or {})[rules.pass_entitlement_id] or {}
    return {today=day,claimed=daily.claimed[tostring(day)] and 1 or 0,count=daily.count,
        cycle_mode="claim_count",current_day=current,period_id=tostring(math.floor(math.max(0,daily.count-(claimed_today and 1 or 0))/7)),
        calendar28=calendar,calendar_current_day=calendar_current,calendar_start_count=calendar_start,
        ordinary_status=claimed_today and "claimed" or "claimable",
        premium={status="unconfigured",name="周末高级装备",description="周周期与装备候选池尚未配置；现有累计签到通行证奖励仍按原规则发放。"},
        subtitle="每日领取 · 七次循环",rule_text="每日零点刷新；断签不重置累计进度。通行证奖励按累计签到次数发放。",
        makeup_days=rules.makeup_days,
        next_day=daily.count%7+1,has_pass=pass and 1 or 0,expires_at=tostring(entitlement.expires_at or ""),
        missed=missed,cycle=cycle,specials=specials,price=rules.price_text,duration_days=rules.duration_days,
        purchase_enabled=rules.purchase_enabled and 1 or 0}
end
function M.points(profile)
    local counts=profile.save.archive and profile.save.archive.daily_rewards and profile.save.archive.daily_rewards.item_counts or {}
    local rows={}
    -- A collection catalogue includes unowned definitions; account ownership
    -- changes the state, never the capacity of the page. Read-only projection.
    for _,item in ipairs(items.rows) do if item.enabled~=false then
        local count=(tonumber(counts[item.item_id]) or 0)>0 and 1 or 0
        rows[#rows+1]={id=item.item_id,name=item.display_name,description=item.description,quality=item.quality,
            icon_type="custom",icon_style="seal",rune="签",count=count,target=1,max_owned=1,
            count_known=1,unlocked=count,item_type="积分道具",source_kind="daily",
            duplicate_points=duplicate_rate(item),duplicate_currency="shop_points",converted_currency="shop_points"}
    end end
    return rows
end
return M
