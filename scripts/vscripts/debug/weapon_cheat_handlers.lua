local event_bus = require("core/event_bus")
local events = require("core/events")

local M = {}

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
