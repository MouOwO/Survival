local event_bus = require("core/event_bus")
local events = require("core/events")
local destination_validation = require("systems/destination_validation_service")
local home_destination = require("systems/hero_summon_destination")
local player_context = require("systems/player_context_service")

local M = {}

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

function M.return_unit(hero, player_id)
    player_id = tonumber(player_id)
    if not player_id or player_id < 0 or player_id ~= math.floor(player_id) then
        return { ok = false, error = "player_id_invalid" }
    end
    if not valid(hero) then
        notify(player_id, "英雄尚未就绪或已经阵亡，无法回城", "error")
        return { ok = false, error = "hero_not_ready" }
    end
    -- A matching engine owner is insufficient: builders, illusions and old
    -- replaced heroes must not become a return-home target.
    local summoned = event_bus.request(events.HERO_SUMMON_GET_REQUEST, {
        player_id = player_id,
    })
    if not summoned or summoned.ok ~= true or summoned.unit ~= hero
        or not player_context.is_owned_by(player_id, hero) then
        notify(player_id, "只能让自己的正式英雄回城", "error")
        return { ok = false, error = "hero_not_owned" }
    end

    -- Summon and return use the same authoritative own-city landing policy:
    -- bounded nearby rings, building hull clearance, walkable land and regions.
    -- The moving hero is not an obstacle against its own destination.
    local position, _, metadata = home_destination.resolve(nil, nil, player_id, hero)
    if not position then
        local missing_city = metadata and metadata.last_reason == "main_city_not_found"
        notify(player_id, missing_city and "自己的主基地尚未建成或已被摧毁，无法回城"
            or "自己的主基地周围没有安全落点，请清理障碍后重试", "error")
        return { ok = false, error = missing_city and "main_city_not_found"
            or "return_position_not_found" }
    end

    hero:Stop()
    ProjectileManager:ProjectileDodge(hero)
    local moved, move_error = destination_validation.teleport(hero, position, false)
    if not moved then
        notify(player_id, "回城落点暂不可用，请稍后重试", "error")
        return { ok = false, error = move_error }
    end
    position = hero:GetAbsOrigin()
    -- Leave rooms only once movement succeeds. A blocked home destination must
    -- not cancel the player's current encounter or begin its retry cooldown.
    event_bus.request(events.TRAINING_ROOM_EXIT_REQUEST, {
        player_id = player_id,
        reason = "return_home",
    })
    event_bus.emit(events.HERO_RETURNED_HOME, {
        player_id = player_id,
        hero = hero,
        position = position,
    })
    follow_hero_camera(hero, player_id, position)
    notify(player_id, "已返回自己的主基地旁")
    return { ok = true, position = position }
end

return M
