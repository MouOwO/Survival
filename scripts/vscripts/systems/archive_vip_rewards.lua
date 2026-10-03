-- Server-owned VIP catalog and one-time additive rewards. UI previews grant nothing.
local catalog = require("config/generated/archive_vip_rewards")
local M = {}
local function integer(value)
    return type(value)=="number" and value==value and value>=0 and value<math.huge and value==math.floor(value)
end
local levels = require("config/generated/archive_vip_levels")
function M.recharge_total(profile)
    local n=tonumber(profile and profile.save and profile.save.gameplay_stats and profile.save.gameplay_stats.vip_recharge_total_fen) or 0
    return integer(n) and n<=9007199254740991 and n or 0
end
function M.level(profile)
    local total,level=M.recharge_total(profile),0
    for _,row in ipairs(levels.rows) do
        if total>=row.required_recharge_fen then level=math.max(level,row.level) end
    end
    return level
end
function M.member(profile)
    if M.level(profile)>0 then return true end
    local e=profile and profile.entitlements and profile.entitlements.vip
    if type(e)~="table" or e.active~=true then return false end
    if e.expires_at==nil and e.starts_at==nil then return true end
    local ok,now=pcall(function() return require("systems/archive_calendar").now() end)
    return ok and (e.starts_at==nil or tonumber(e.starts_at)~=nil and tonumber(e.starts_at)<=now)
        and (e.expires_at==nil or tonumber(e.expires_at)~=nil and tonumber(e.expires_at)>now)
end
function M.balance(profile)
    local n=tonumber(profile and profile.save and profile.save.gameplay_stats and profile.save.gameplay_stats.shop_paid_currency) or 0
    return integer(n) and n or 0
end
function M.apply(command,profile,archive,stats,apply_effects)
    local row=catalog.by_id[tostring(command.reward_id or "")]
    if not row or not row.enabled then return false,"VIP奖励不存在" end
    if (command.kind=="vip_claim" and row.group_id~="privileges")
        or (command.kind=="vip_purchase" and row.group_id~="packages") then return false,"VIP领取方式无效" end
    archive.vip_claimed=archive.vip_claimed or {}
    if archive.vip_claimed[row.reward_id]==true then return true end
    if row.group_id=="privileges" then
        if M.level(profile)<row.level then return false,"VIP等级不足" end
    else
        if row.level>0 and not M.member(profile) then return false,"需要先开通VIP" end
        local balance=M.balance(profile)
        if balance<row.price then return false,"商城付费币不足" end
        stats.shop_paid_currency=balance-row.price
    end
    -- All effects and the bundled medal are in one archive transaction with the debit.
    apply_effects(stats,row)
    archive.vip_claimed[row.reward_id]=true
    if row.medal_id then
        local medal=assert(catalog.by_id[row.medal_id],"vip_medal_missing")
        if not archive.vip_claimed[medal.reward_id] then
            apply_effects(stats,medal)
            archive.vip_claimed[medal.reward_id]=true
        end
    end
    return true
end
function M.snapshot(profile)
    if not profile then return {ok=false,error="档案尚未载入"} end
    local archive=profile.save and profile.save.archive or {}
    local claimed=archive.vip_claimed or {}
    local level,member,balance=M.level(profile),M.member(profile),M.balance(profile)
    local rows={}
    for _,row in ipairs(catalog.rows) do
        if row.enabled then
            local owned=claimed[row.reward_id]==true
            local eligible=row.group_id=="privileges" and level>=row.level
                or row.group_id=="packages" and (row.level==0 or member)
            rows[#rows+1]={id=row.reward_id,owned=owned and 1 or 0,eligible=eligible and 1 or 0,
                affordable=balance>=row.price and 1 or 0}
        end
    end
    return {ok=true,level=level,member=member and 1 or 0,balance=balance,rows=rows,revision=profile.revision,
        recharge_total_fen=M.recharge_total(profile),
        next_level_required_fen=levels.rows[level+1] and levels.rows[level+1].required_recharge_fen or nil}
end
return M
