-- Pure save projection; archive_service commits it with gameplay stats in one revision.
local challenges = require("config/generated/archive_challenge_definitions")
local fragments = require("config/generated/archive_fragment_definitions")
local levels = require("config/generated/archive_fragment_levels")
local shadow = require("config/generated/archive_shadow_items")
local shadow_drop_rules = require("config/generated/archive_shadow_challenge_drop_rules")
local cage = require("config/generated/archive_cage_items")
local rules = require("config/generated/archive_challenge_rules").by_id.default
local daily_limits = require("systems/archive_daily_limits")
local eligibility = require("systems/archive_challenge_reward_eligibility")
local M = {}
local point_rules = {
    football={name="绿茵积分", count=10, description="绿茵挑战获得的永久积分；每次10点，每日最多100点。"},
    watermelon={name="西瓜积分", count=1, description="西瓜挑战获得的永久积分；每次1点，每日最多10点。"},
}
local function normalize(save)
    save.fragment_counts = save.fragment_counts or {}
    save.fragment_totals = save.fragment_totals or {}
    save.fragment_levels = save.fragment_levels or {}
    save.cage_counts = save.cage_counts or {}
    save.daily = save.daily or {}
end
local function next_fragment_levels(save, stats, definition, apply)
    local id = definition.fragment_id
    local total = save.fragment_totals[id] or 0
    local old = save.fragment_levels[id] or 0
    local new = math.min(definition.max_level, math.floor(total / definition.fragments_per_level))
    for _, row in ipairs(levels.rows) do
        if row.enabled and row.fragment_id == id and row.level > old and row.level <= new then apply(stats, row) end
    end
    save.fragment_levels[id] = math.max(old, new)
end
local function grant_fragment(save, stats, definition, count, apply)
    local id = definition.fragment_id
    local accepted = math.max(0, math.min(count, definition.max_owned - (save.fragment_counts[id] or 0)))
    save.fragment_counts[id] = (save.fragment_counts[id] or 0) + accepted
    save.fragment_totals[id] = (save.fragment_totals[id] or 0) + accepted
    next_fragment_levels(save, stats, definition, apply)
    return accepted
end
local function roll(items, count, filter, random_int)
    local pool, result = {}, {}
    for _, row in ipairs(items) do if row.enabled and filter(row) then pool[#pool + 1] = row.item_id end end
    assert(#pool > 0, "archive_challenge_empty_pool")
    for _ = 1, count do
        local index = random_int and random_int(1, #pool)
            or RandomInt and RandomInt(1, #pool) or math.random(1, #pool)
        result[#result + 1] = pool[index]
    end
    return result
end
local function accepted_reward(response, id, name, quality, count)
    if count <= 0 then return end
    for _, reward in ipairs(response.rewards) do
        if reward.item_id == id then reward.count = reward.count + count; return end
    end
    response.rewards[#response.rewards + 1] = {
        item_id=id, name=name, quality=quality, count=count,
    }
end
function M.apply(command, save, stats, pass, apply, random_int)
    local definition = challenges.by_id[command.challenge_id]
    if not definition or not definition.enabled then return false, "archive_challenge_unknown" end
    local eligible, reason = eligibility.check(save, definition)
    if not eligible then return true, {awarded=0, rewards={}, skipped_reason=reason, challenge_id=command.challenge_id} end
    normalize(save)
    local response = {awarded=0, rewards={}, challenge_id=command.challenge_id}
    if definition.reward_kind == "fragment" then
        local fragment = fragments.by_id[definition.reward_key]
        local remaining = daily_limits.remaining(save, fragment.fragment_id, assert(command.day_key), pass)
        local count = grant_fragment(save, stats, fragment, math.min(fragment.drop_count, remaining), apply)
        daily_limits.grant(save, fragment.fragment_id, count, command.day_key, pass)
        response.awarded = count
        local name = fragment.display_name
        if not name:find("碎片", 1, true) then name = name .. "碎片" end
        accepted_reward(response, fragment.fragment_id, name, "gold", count)
    elseif definition.reward_kind == "shadow" then
        local drop_rule = shadow_drop_rules.by_id[definition.challenge_id]
        if not drop_rule or not drop_rule.enabled then
            return false, "archive_shadow_drop_rule_missing"
        end
        local drop_count = drop_rule.drop_count
            + (pass and drop_rule.pass_extra_count or 0)
        command.drops = command.drops or roll(shadow.rows, drop_count,
            function(row)
                return row.source_boss_difficulty == drop_rule.source_boss_difficulty
            end, random_int)
        save.shadow_counts = save.shadow_counts or {}
        local remaining = daily_limits.remaining(save, "shadow", assert(command.day_key), pass)
        for _, id in ipairs(command.drops) do
            local item = shadow.by_id[id]
            local count = save.shadow_counts[id] or 0
            if remaining > 0 and count < item.max_owned then
                save.shadow_counts[id] = count + 1
                remaining = remaining - daily_limits.grant(save, "shadow", 1, command.day_key, pass)
                apply(stats, item)
                response.awarded = response.awarded + 1
                accepted_reward(response, id, item.display_name, item.quality, 1)
            end
        end
    elseif definition.reward_kind == "social_ticket" then
        local ok, result = require("systems/archive_social_rewards").grant_ticket(command, save, definition.reward_key, pass)
        if not ok then return false, result end
        response = result
        response.challenge_id, response.rewards = command.challenge_id, {}
        accepted_reward(response, response.currency_id, response.currency_name, "gold", response.awarded)
    elseif definition.reward_kind == "challenge_points" then
        local point = point_rules[definition.reward_key]
        if not point then return false, "archive_challenge_points_unknown" end
        save.challenge_points = save.challenge_points or {}
        local accepted = daily_limits.grant(save, definition.reward_key, point.count, assert(command.day_key), pass)
        save.challenge_points[definition.reward_key] = (save.challenge_points[definition.reward_key] or 0) + accepted
        response.awarded, response.currency_id, response.currency_name = accepted, definition.reward_key, point.name
        accepted_reward(response, definition.reward_key, point.name, "gold", accepted)
    elseif definition.reward_kind == "cage" then
        local remaining = daily_limits.remaining(save, "cage", assert(command.day_key), pass)
        local count = rules.cage_drop_count + (pass and rules.pass_cage_extra_count or 0)
        command.drops = command.drops or roll(cage.rows, count,
            function(row) return row.pool_id == definition.reward_key end, random_int)
        for _, id in ipairs(command.drops) do
            local item = cage.by_id[id]
            local owned = save.cage_counts[id] or 0
            if remaining > 0 and owned < item.max_owned then
                save.cage_counts[id] = owned + 1
                remaining = remaining - daily_limits.grant(save, "cage", 1, command.day_key, pass)
                apply(stats, item)
                response.awarded = response.awarded + 1
                accepted_reward(response, id, item.display_name, "purple", 1)
            end
        end
    else return false, "archive_challenge_reward_unknown" end
    if response.awarded == 0 then response.skipped_reason = response.skipped_reason or "今日获取次数已达上限或物品已集满" end
    return true, response
end
function M.promote(command, save, stats, apply)
    normalize(save)
    local source = fragments.by_id[command.fragment_id]
    local target = source and fragments.by_id[source.promotion_target or ""]
    if not source or not target then return false, "该神兵没有晋升兑换" end
    if (save.fragment_totals[source.fragment_id] or 0) < source.promotion_required_total then
        return false, "累计碎片未达到晋升门槛"
    end
    if (save.fragment_counts[source.fragment_id] or 0) < source.promotion_cost then
        return false, "晋升所需碎片不足"
    end
    if (save.fragment_counts[target.fragment_id] or 0) >= target.max_owned then return false, "目标碎片已满" end
    save.fragment_counts[source.fragment_id] = save.fragment_counts[source.fragment_id] - source.promotion_cost
    grant_fragment(save, stats, target, 1, apply)
    return true
end
function M.fragment_rows(profile, save)
    normalize(save)
    local rows = {}
    for _, item in ipairs(fragments.rows) do
        local total, owned = save.fragment_totals[item.fragment_id] or 0, save.fragment_counts[item.fragment_id] or 0
        if item.enabled then
            local level = save.fragment_levels[item.fragment_id] or 0
            local effects = {}
            for _, row in ipairs(levels.rows) do
                if row.fragment_id == item.fragment_id and row.enabled then
                    effects[#effects + 1] = "Lv" .. row.level .. " " .. row.description
                end
            end
            local target = fragments.by_id[item.promotion_target or ""]
            rows[#rows + 1] = { id = item.fragment_id, name = item.display_name,
                description = "当前Lv" .. level .. "，累计获得" .. total .. "片。每20片晋升1级。\n" .. table.concat(effects, "\n"),
                icon_style = "seal", quality = "gold", count = owned, target = item.max_owned, level = level,
                promotion_target = target and target.display_name or "",
                promotion_cost = item.promotion_cost,
                can_promote = target and total >= item.promotion_required_total and owned >= item.promotion_cost
                    and (save.fragment_counts[target.fragment_id] or 0) < target.max_owned and 1 or 0 }
        end
    end
    return rows
end
function M.cage_rows(profile, save)
    normalize(save)
    local rows = {}
    for _, item in ipairs(cage.rows) do
        local count = save.cage_counts[item.item_id] or 0
        if item.enabled and count > 0 then
            rows[#rows + 1] = { id = item.item_id, name = item.display_name, description = item.description,
                icon_style = "shard", quality = "purple", count = count, target = item.max_owned }
        end
    end
    return rows
end
function M.point_rows(save)
    local rows = {}
    for _, key in ipairs({"football", "watermelon"}) do
        local rule = point_rules[key]
        rows[#rows+1] = {id="challenge_points_" .. key, name=rule.name, description=rule.description,
            count=tonumber((save.challenge_points or {})[key]) or 0, quality="gold", icon_style="seal", count_known=1}
    end
    return rows
end
return M
