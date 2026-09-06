local event_bus = require("core/event_bus")
local events = require("core/events")

local M = {}

local MODIFIER_NAME = "modifier_debug_fixed_attack_rate"
local DEFAULT_ATTACKS_PER_SECOND = 10
local interval_by_player = {}

local function notify(player_id, message)
    event_bus.emit(events.UI_NOTIFICATION, {
        player_id = player_id,
        message = message,
        level = "info",
    })
end

local function apply(hero, attack_interval)
    if not hero or hero:IsNull() then
        return false
    end
    hero:RemoveModifierByName(MODIFIER_NAME)
    local modifier = hero:AddNewModifier(
        hero, nil, MODIFIER_NAME, {
            attack_interval = attack_interval,
        }
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
    local attack_interval = player_id and interval_by_player[player_id] or nil
    if attack_interval then
        apply(payload.unit, attack_interval)
    end
end

function M.set_rate(player_id, attacks_per_second)
    local rate = tonumber(attacks_per_second)
    if not rate or rate <= 0 or rate > 100 then
        return false, "fixed_attack_rate_invalid"
    end
    local attack_interval = 1 / rate
    interval_by_player[player_id] = attack_interval
    local hero = summoned_hero(player_id)
    if not hero or hero:IsNull() then
        return false, "hero_not_summoned"
    end
    if not apply(hero, attack_interval) then
        return false, "fixed_attack_rate_apply_failed"
    end
    return true
end

function M.execute(context)
    local player_id = context.player_id
    local ok, error_code = M.set_rate(
        player_id,
        DEFAULT_ATTACKS_PER_SECOND
    )
    if not ok and error_code == "hero_not_summoned" then
        interval_by_player[player_id] = 1 / DEFAULT_ATTACKS_PER_SECOND
        notify(player_id, "addspeed已启用，召唤祭坛英雄后生效")
        return true
    end
    if not ok then return false, error_code end
    notify(player_id, "祭坛英雄固定攻击间隔：0.1秒")
    return true
end

function M.init()
    interval_by_player = {}
    event_bus.subscribe(events.HERO_SUMMONED, on_hero_summoned)
end

return M
