local items = require("config/generated/archive_social_items")
local rules = require("config/generated/archive_social_rules")
local M = {}
local quality_order = {"N", "R", "SR", "SSR", "UR"}
local function normalize(save)
    save.social_counts = save.social_counts or {}
    save.social_tickets = save.social_tickets or {}
    save.social_unlocks = save.social_unlocks or {}
    save.daily = save.daily or {}
end
-- Select a quality first, then select a remaining copy within that quality.
-- Empty qualities leave the pool, so their weight is redistributed among the
-- qualities which still contain a drawable item. This same distribution is
-- used by both snapshots and settlement; displayed odds cannot drift from rolls.
local function distribution(save, pool, initial)
    local rule = rules.by_id[pool]
    local groups, ordered, total_weight = {}, {}, 0
    for _, quality in ipairs(quality_order) do
        groups[quality] = {quality=quality, weight=tonumber(rule and rule["quality_weight_" .. quality:lower()]) or 0,
            remaining=0, entries={}}
    end
    for _, item in ipairs(items.rows) do
        if item.enabled and item.draw_enabled ~= false and item.pool_id == pool then
            local remaining = math.max(0, item.max_owned - (initial and 0 or (save.social_counts[item.item_id] or 0)))
            if remaining > 0 then
                local group = assert(groups[item.quality], "social_draw_quality_invalid")
                group.remaining = group.remaining + remaining
                group.entries[#group.entries+1] = {item=item, remaining=remaining, edge=group.remaining}
            end
        end
    end
    local probabilities, quality_probabilities = {}, {}
    for _, quality in ipairs(quality_order) do
        local group = groups[quality]
        quality_probabilities[quality] = 0
        if group.remaining > 0 and group.weight > 0 then
            group.start = total_weight
            total_weight = total_weight + group.weight
            group.edge = total_weight
            ordered[#ordered+1] = group
        end
    end
    for _, group in ipairs(ordered) do
        local probability = group.weight / total_weight
        quality_probabilities[group.quality] = probability
        for _, entry in ipairs(group.entries) do
            probabilities[entry.item.item_id] = probability * entry.remaining / group.remaining
        end
    end
    return {groups=ordered, total_weight=total_weight, probabilities=probabilities, quality_probabilities=quality_probabilities}
end
function M.rows(save, pool)
    normalize(save)
    local rows = {}
    local current, initial = distribution(save, pool, false), distribution(save, pool, true)
    for _, item in ipairs(items.rows) do
        if item.enabled and item.pool_id == pool then
            local draw_enabled = item.draw_enabled ~= false
            rows[#rows+1] = { id=item.item_id, name=item.display_name, quality=item.quality,
                draw_probability=current.probabilities[item.item_id] or 0,
                initial_draw_probability=initial.probabilities[item.item_id] or 0,
                quality_draw_probability=current.quality_probabilities[item.quality] or 0,
                description=draw_enabled and (item.description .. "（每件）\n已拥有" .. (save.social_counts[item.item_id] or 0) .. "件，效果按数量叠加") or item.description,
                draw_enabled=draw_enabled and 1 or 0, availability_note=item.availability_note or "", count=save.social_counts[item.item_id] or 0,
                target=item.max_owned, icon_style="seal", rune=item.display_name:sub(1,3) }
        end
    end
    if pool == "wife" then table.sort(rows, function(a, b) return a.id < b.id end) end
    return rows
end
function M.info(save, pool)
    normalize(save)
    local rule = rules.by_id[pool]
    if not rule then return nil end
    local total, remaining = 0, 0
    for _, item in ipairs(items.rows) do
        if item.enabled and item.draw_enabled ~= false and item.pool_id == pool then
            local count = save.social_counts[item.item_id] or 0
            total = total + count
            remaining = remaining + math.max(0, item.max_owned - count)
        end
    end
    local current, initial = distribution(save, pool, false), distribution(save, pool, true)
    return { tickets=save.social_tickets[rule.currency_id] or 0, currency_name=rule.currency_name,
        draw_cost=rule.draw_cost, remaining=remaining, total=total,
        rarity_probabilities=current.quality_probabilities, rarity_base_probabilities=initial.quality_probabilities,
        unlocked=save.social_unlocks.friend_100 and 1 or 0 }
end
function M.grant_ticket(command, save, pool)
    normalize(save)
    local rule = rules.by_id[pool]
    if not rule or not rule.enabled then return false, "奖池无效" end
    local day = save.daily[command.day_key] or {}
    save.daily[command.day_key] = day
    local key = "social_" .. pool
    if (day[key] or 0) < rule.daily_limit then
        day[key] = (day[key] or 0) + 1
        save.social_tickets[rule.currency_id] = (save.social_tickets[rule.currency_id] or 0) + 1
    end
    return true
end
function M.apply(command, save, stats, apply_effects)
    normalize(save)
    if command.kind == "social_ticket_cheat" then
        local amount = tonumber(command.amount)
        if not amount or amount ~= math.floor(amount) or amount < 0 or amount > 1000000 then
            return false, "义帖数量无效"
        end
        local rule = rules.by_id[command.pool_id or "friend"]
        if not rule then return false, "奖池无效" end
        save.social_tickets[rule.currency_id] = (save.social_tickets[rule.currency_id] or 0) + amount
        return true
    end
    local rule = rules.by_id[command.pool_id]
    if not rule or not rule.enabled then return false, "奖池无效" end
    local currency = rule.currency_id
    if (save.social_tickets[currency] or 0) < rule.draw_cost then return false, rule.currency_name .. "不足" end
    local pool = distribution(save, command.pool_id, false)
    if pool.total_weight == 0 then return false, "本奖池已全部集满" end
    -- Preserve the random fraction on this queued command across failed writes.
    command.roll = command.roll or ((RandomInt and RandomInt(0, 1000000000) or math.random(0,1000000000)) / 1000000001)
    assert(type(command.roll) == "number" and command.roll >= 0 and command.roll < 1, "social_draw_roll_invalid")
    local roll = command.roll * pool.total_weight
    local chosen
    for _, group in ipairs(pool.groups) do
        if roll < group.edge then
            -- The fraction already drawn for quality also chooses the item.
            -- Keep half-open intervals: an exact boundary belongs to the next
            -- quality/item and a failed persistence retry reuses the same roll.
            local within = (roll - group.start) / group.weight * group.remaining
            for _, entry in ipairs(group.entries) do
                if within < entry.edge then chosen=entry.item; break end
            end
            -- Subtraction/division can round the final sub-interval up to its
            -- right edge even though the validated source fraction is below 1.
            chosen = chosen or group.entries[#group.entries].item
            break
        end
    end
    assert(chosen, "social_draw_invalid")
    save.social_tickets[currency] = save.social_tickets[currency] - rule.draw_cost
    save.social_counts[chosen.item_id] = (save.social_counts[chosen.item_id] or 0) + 1
    local before, effects = {}, {}
    for _, field in ipairs(chosen.effect_ids) do before[field] = tonumber(stats[field]) or 0 end
    apply_effects(stats, chosen)
    for field, value in pairs(before) do effects[field] = (tonumber(stats[field]) or 0) - value end
    save.social_last_draw = {pool_id=command.pool_id, name=chosen.display_name, id=command.id, effects=effects}
    if M.info(save, "friend").total >= rules.by_id.friend.unlock_count then save.social_unlocks.friend_100=true end
    if M.info(save, "beast").total >= rules.by_id.beast.unlock_count then save.social_unlocks.ex_100=true end
    return true
end
return M
