local items = require("config/generated/archive_social_items")
local rules = require("config/generated/archive_social_rules")
local M = {}
local function normalize(save)
    save.social_counts = save.social_counts or {}
    save.social_tickets = save.social_tickets or {}
    save.social_unlocks = save.social_unlocks or {}
    save.daily = save.daily or {}
end
function M.rows(save, pool)
    normalize(save)
    local rows = {}
    for _, item in ipairs(items.rows) do
        if item.enabled and item.pool_id == pool then
            rows[#rows+1] = { id=item.item_id, name=item.display_name, quality=item.quality,
                description=item.description .. "（每件）\n已拥有" .. (save.social_counts[item.item_id] or 0) .. "件，效果按数量叠加", count=save.social_counts[item.item_id] or 0,
                target=item.max_owned, icon_style="seal", rune=item.display_name:sub(1,3) }
        end
    end
    return rows
end
function M.info(save, pool)
    normalize(save)
    local rule = rules.by_id[pool]
    if not rule then return nil end
    local total, remaining = 0, 0
    for _, item in ipairs(items.rows) do
        if item.enabled and item.pool_id == pool then
            local count = save.social_counts[item.item_id] or 0
            total = total + count
            remaining = remaining + math.max(0, item.max_owned - count)
        end
    end
    return { tickets=save.social_tickets[rule.currency_id] or 0, currency_name=rule.currency_name,
        draw_cost=rule.draw_cost, remaining=remaining, total=total,
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
    local pool, total = {}, 0
    for _, item in ipairs(items.rows) do
        if item.enabled and item.pool_id == command.pool_id then
            local remaining = math.max(0, item.max_owned - (save.social_counts[item.item_id] or 0))
            if remaining > 0 then
                total = total + remaining
                pool[#pool+1] = {item=item, edge=total}
            end
        end
    end
    if total == 0 then return false, "本奖池已全部集满" end
    -- Preserve the random fraction on this queued command across failed writes.
    command.roll = command.roll or ((RandomInt and RandomInt(0, 1000000000) or math.random(0,1000000000)) / 1000000001)
    local roll = math.floor(command.roll * total) + 1
    local chosen
    for _, entry in ipairs(pool) do if roll <= entry.edge then chosen=entry.item; break end end
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
