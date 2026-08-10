local event_bus = require("core/event_bus")
local events = require("core/events")
local destination_validation = require("systems/destination_validation_service")
local building_system = require("systems/building_system")

local M = {}

local SEARCH_RADII = { 420, 520, 640, 760, 900 }
local ANGLE_STEP = 30
local CLEAR_RADIUS = 96

local function valid(unit)
    return unit and not unit:IsNull() and unit:IsAlive()
end

local function notify(player_id, message, level)
    event_bus.emit(events.UI_NOTIFICATION, {
        player_id = player_id,
        message = message,
        level = level or "info",
    })
end

local function follow_hero_camera(hero, player_id, position)
    local player = PlayerResource:GetPlayer(player_id)
    if not player then return end
    CustomGameEventManager:Send_ServerToPlayer(
        player,
        "ui_camera_follow_hero",
        {
            entindex = hero:entindex(),
            target_x = position.x,
            target_y = position.y,
            target_z = position.z,
        }
    )
end

local function position_is_clear(position, hero)
    local valid_destination = destination_validation.validate(position, hero)
    if not valid_destination then return false end
    if GridNav:IsBlocked(position) or not GridNav:IsTraversable(position) then
        return false
    end
    local occupied = FindUnitsInRadius(
        hero:GetTeamNumber(),
        position,
        nil,
        CLEAR_RADIUS,
        DOTA_UNIT_TARGET_TEAM_BOTH,
        DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC,
        DOTA_UNIT_TARGET_FLAG_NONE,
        FIND_ANY_ORDER,
        false
    ) or {}
    for _, unit in ipairs(occupied) do
        if unit ~= hero and valid(unit) then return false end
    end
    return true
end

local function safe_position(city, hero)
    local origin = city:GetAbsOrigin()
    local forward = city:GetForwardVector()
    local base_angle = math.deg(math.atan2(forward.y, forward.x))
    for _, radius in ipairs(SEARCH_RADII) do
        for offset = 0, 330, ANGLE_STEP do
            local angle = math.rad(base_angle + offset)
            local position = origin + Vector(
                math.cos(angle) * radius,
                math.sin(angle) * radius,
                0
            )
            position.z = GetGroundHeight(position, hero)
            if position_is_clear(position, hero) then return position end
        end
    end
    return nil
end

function M.return_unit(hero, player_id)
    player_id = tonumber(player_id)
    if not valid(hero) then
        return { ok = false, error = "hero_not_ready" }
    end
    if player_id == nil or hero:GetPlayerOwnerID() ~= player_id then
        return { ok = false, error = "hero_not_owned" }
    end

    local city = building_system.main_city_for_team(hero:GetTeamNumber())
    if not valid(city) then
        notify(player_id, "主城不存在，无法回城", "error")
        return { ok = false, error = "main_city_not_found" }
    end
    local position = safe_position(city, hero)
    if not position then
        notify(player_id, "主城周围没有安全落点", "error")
        return { ok = false, error = "return_position_not_found" }
    end

    event_bus.request(events.TRAINING_ROOM_EXIT_REQUEST, {
        player_id = player_id,
        reason = "return_home",
    })

    hero:Stop()
    ProjectileManager:ProjectileDodge(hero)
    local moved, move_error = destination_validation.teleport(hero, position, false)
    if not moved then return { ok = false, error = move_error } end
    position = hero:GetAbsOrigin()
    follow_hero_camera(hero, player_id, position)
    notify(player_id, "已返回主城")
    return { ok = true, position = position }
end

return M