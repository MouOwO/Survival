local event_bus = require("core/event_bus")
local events = require("core/events")
local weapons = require("config/generated/weapon_definitions")
local items = require("config/generated/item_definitions")
local content = require("config/generated/content_catalog")

local M = {}

local by_legacy_id = {}
local by_content_id = {}
for _, definition in ipairs(weapons.rows or {}) do
    local legacy_id = tostring(definition.legacy_id or "")
    by_content_id[tostring(definition.content_id or "")] = definition
    if legacy_id ~= "" and definition.enabled ~= false then
        by_legacy_id[legacy_id] = definition
    end
end
for _, definition in ipairs(items.rows or {}) do
    local legacy_id = tostring(definition.legacy_id or "")
    by_content_id[tostring(definition.content_id or "")] = definition
    if legacy_id ~= "" and definition.enabled ~= false then
        assert(by_legacy_id[legacy_id] == nil,
            "duplicate legacy item id: " .. legacy_id)
        by_legacy_id[legacy_id] = definition
    end
end

local function notify(context, message)
    event_bus.emit(events.UI_NOTIFICATION, {
        player_id = context.player_id,
        message = message,
        level = "info",
    })
end

function M.give_growth_sword(context)
    local result = event_bus.request(
        events.CONTENT_INVENTORY_GRANT_REQUEST,
        {
            player_id = context.player_id,
            content_id = "weapon_growth_sword_01",
            count = 1,
            reason = "cheat_give_growth_sword",
        }
    )
    return result and result.ok == true,
        result and result.error or "growth_sword_grant_failed"
end

function M.add_item(context)
    local legacy_id = tostring(context.args[1] or "")
    local count = math.floor(tonumber(context.args[2]) or 1)
    if legacy_id == "" or count < 1 then
        return false, "usage: additem <legacy_id> [count]"
    end
    local definition = by_legacy_id[legacy_id]
    if not definition then
        return false, "legacy_item_id_not_found:" .. legacy_id
    end
    local result = event_bus.request(
        events.CONTENT_INVENTORY_GRANT_REQUEST,
        {
            player_id = context.player_id,
            content_id = definition.content_id,
            count = count,
            reason = "cheat_additem:" .. legacy_id,
        }
    )
    if not result or not result.ok then
        return false, result and result.error or "additem_grant_failed"
    end
    local catalog = (content.by_id or {})[definition.content_id] or {}
    notify(context, string.format(
        "已添加 %s ×%d（旧版ID %s）",
        tostring(definition.display_name or catalog.name or definition.content_id),
        count,
        legacy_id
    ))
    return true
end

function M.list_items(context)
    local result = event_bus.request(
        events.CONTENT_INVENTORY_GET_REQUEST,
        { player_id = context.player_id }
    )
    if not result or not result.ok or not result.snapshot then
        return false, result and result.error or "inventory_get_failed"
    end
    local rows = {}
    for content_id, quantity in pairs(result.snapshot.counts or {}) do
        if (tonumber(quantity) or 0) > 0 then
            local definition = by_content_id[content_id] or {}
            local catalog = (content.by_id or {})[content_id] or {}
            rows[#rows + 1] = {
                content_id = content_id,
                legacy_id = tostring(definition.legacy_id or "-"),
                name = tostring(definition.display_name
                    or catalog.name or content_id),
                quantity = math.floor(tonumber(quantity) or 0),
            }
        end
    end
    table.sort(rows, function(left, right)
        local left_id = tonumber(left.legacy_id)
        local right_id = tonumber(right.legacy_id)
        if left_id and right_id then return left_id < right_id end
        return left.content_id < right.content_id
    end)
    if #rows == 0 then
        notify(context, "内容背包为空")
        return true
    end
    notify(context, "内容背包（旧版ID / 名称 / 数量）：")
    for _, row in ipairs(rows) do
        notify(context, string.format(
            "%s / %s / ×%d",
            row.legacy_id,
            row.name,
            row.quantity
        ))
    end
    return true
end

function M.grow_weapon(context)
    local result = event_bus.request(
        events.WEAPON_GROWTH_DEBUG_REQUEST,
        {
            player_id = context.player_id,
            count = tonumber(context.args[1]) or 1,
        }
    )
    return result and result.ok == true,
        result and result.error or "weapon_growth_failed"
end

function M.give_forging_hammer(context)
    local count = math.max(1, math.floor(tonumber(context.args[1]) or 1))
    local result = event_bus.request(
        events.CONTENT_INVENTORY_GRANT_REQUEST,
        {
            player_id = context.player_id,
            content_id = "item_forging_hammer",
            count = count,
            reason = "cheat_give_forging_hammer",
        }
    )
    return result and result.ok == true,
        result and result.error or "forging_hammer_grant_failed"
end

function M.set_attack_40b(context)
    local result = event_bus.request(
        events.HERO_COMBAT_STATS_DEBUG_ATTACK_REQUEST,
        { player_id = context.player_id, attack = 4000000000 }
    )
    if result and result.ok then
        notify(context, "测试攻击力已设置为 4000000000")
    end
    return result and result.ok == true,
        result and result.error or "debug_attack_failed"
end

function M.reset_attack(context)
    local result = event_bus.request(
        events.HERO_COMBAT_STATS_DEBUG_ATTACK_REQUEST,
        { player_id = context.player_id, reset = true }
    )
    if result and result.ok then
        notify(context, "测试攻击力覆盖已取消")
    end
    return result and result.ok == true,
        result and result.error or "debug_attack_reset_failed"
end

function M.weapon_stats(context)
    local result = event_bus.request(
        events.HERO_COMBAT_STATS_GET_REQUEST,
        { player_id = context.player_id }
    )
    if not result or not result.ok then
        return false, result and result.error or "combat_stats_failed"
    end
    local data = result.snapshot
    notify(
        context,
        "攻击 " .. tostring(data.attack_min)
        .. "-" .. tostring(data.attack_max)
        .. " | 武器成长+" .. tostring(data.weapon_growth_attack)
        .. " | 力敏智 " .. tostring(data.strength)
        .. "/" .. tostring(data.agility)
        .. "/" .. tostring(data.intellect)
    )
    return true
end

return M
