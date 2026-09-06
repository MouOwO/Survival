local rules=require("config/generated/archive_daily_rules").by_id.default
local schedule=require("config/generated/archive_daily_schedule")
local items=require("config/generated/archive_daily_items")
local M={}
local function state(save, day)
    save.daily_rewards=save.daily_rewards or {first_day=day, claimed={}, count=0, item_counts={}}
    return save.daily_rewards
end
function M.apply(command,save,stats,pass,apply)
    local day=command.today
    local daily=state(save,day)
    if command.kind=="daily_init" then return true end
    local target=tonumber(command.target_day)
    if not target or target~=math.floor(target) or target>day or target<daily.first_day then return false,"签到日期无效" end
    if target<day and (not pass or target<day-rules.makeup_days+1) then return false,"补签需要有效月卡，且仅限最近30天" end
    local key=tostring(target)
    if daily.claimed[key] then return false,"该日期已领取" end
    local function grant(id,count)
        local item=assert(items.by_id[id],id)
        local accepted=math.max(0,math.min(count,item.max_owned-(daily.item_counts[id] or 0)))
        for _=1,accepted do apply(stats,item) end
        daily.item_counts[id]=(daily.item_counts[id] or 0)+accepted
    end
    daily.count=daily.count+1
    local row=schedule.by_id[(daily.count-1)%7+1]
    for i,id in ipairs(row.item_ids) do grant(id,tonumber(row.item_counts[i])) end
    if pass then for i,n in ipairs(rules.pass_milestones) do
        if daily.count>=tonumber(n) then grant(rules.pass_item_ids[i],1) end
    end end
    daily.claimed[key]=true
    return true
end
function M.snapshot(profile,day,pass)
    local daily=profile.save.archive and profile.save.archive.daily_rewards
        or {first_day=day,claimed={},count=0,item_counts={}}
    local cycle={}
    for _, row in ipairs(schedule.rows) do
        local rewards={}
        for i,id in ipairs(row.item_ids) do
            local item=items.by_id[id]
            rewards[#rewards+1]={name=item.display_name,count=tonumber(row.item_counts[i]),description=item.description}
        end
        cycle[#cycle+1]={day=row.day_id,rewards=rewards}
    end
    local missed={}
    for d=math.max(daily.first_day,day-rules.makeup_days+1),day-1 do
        if not daily.claimed[tostring(d)] then missed[#missed+1]=d end
    end
    local specials={}
    for i,id in ipairs(rules.pass_item_ids) do
        local item=items.by_id[id]
        specials[#specials+1]={day=tonumber(rules.pass_milestones[i]),name=item.display_name,description=item.description,owned=daily.item_counts[id] or 0}
    end
    local entitlement=(profile.entitlements or {})[rules.pass_entitlement_id] or {}
    return {today=day,claimed=daily.claimed[tostring(day)] and 1 or 0,count=daily.count,
        next_day=daily.count%7+1,has_pass=pass and 1 or 0,expires_at=tostring(entitlement.expires_at or ""),
        missed=missed,cycle=cycle,specials=specials,price=rules.price_text,duration_days=rules.duration_days,
        purchase_enabled=rules.purchase_enabled and 1 or 0}
end
function M.points(profile)
    local counts=profile.save.archive and profile.save.archive.daily_rewards and profile.save.archive.daily_rewards.item_counts or {}
    local rows={}
    for _,item in ipairs(items.rows) do if (counts[item.item_id] or 0)>0 then
        rows[#rows+1]={id=item.item_id,name=item.display_name,description=item.description,quality=item.quality,
            icon_type="custom",icon_style="seal",rune="签",count=counts[item.item_id],target=item.max_owned}
    end end
    return rows
end
return M
