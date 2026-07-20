local event_bus = require("core/event_bus")
local events = require("core/events")

local M = {}

local MODIFIER_NAME = "modifier_debug_fixed_attack_rate"
local enabled_by_player = {}

local function notify(player_id, message)
    event_bus.emit(events.UI_NOTIFICATION, {
        player_id = player_id,
        message = message,
        level = "info",
    })
end

local function apply(hero)
    if not hero or hero:IsNull() then
        return false
    end
    hero:RemoveModifierByName(MODIFIER_NAME)
    local modifier = hero:AddNewModifier(
        hero, nil, MODIFIER_NAME, {}
    )
    if modifier then
        print(
            "[AddSpeed] fixed attack rate applied to summoned hero "
                .. tostring(hero:entindex())
        )
    end
    return modifier ~= nil
end

local function summoned_hero(player_id)
    local result = event_bus.request(
        events.HERO_SUMMON_GET_REQUEST,
        { player_id = player_id }
    )
    return result and result.ok and result.unit or nil
end

local function on_hero_summoned(payload)
    local player_id = payload and tonumber(payload.player_id) or nil
    if player_id and enabled_by_player[player_id] then
        apply(payload.unit)
    end
end

function M.execute(context)
    local player_id = context.player_id
    enabled_by_player[player_id] = true
    local hero = summoned_hero(player_id)
    if not hero or hero:IsNull() then
        notify(player_id, "addspeed已启用，召唤祭坛英雄后生效")
        return true
    end
    if not apply(hero) then
        return false, "fixed_attack_rate_failed"
    end
    notify(player_id, "祭坛英雄固定攻击间隔：0.1秒")
    return true
end

function M.init()
    enabled_by_player = {}
    event_bus.subscribe(events.HERO_SUMMONED, on_hero_summoned)
end

return M
