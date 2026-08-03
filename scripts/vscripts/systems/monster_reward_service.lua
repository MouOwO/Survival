local event_bus = require("core/event_bus")
local events = require("core/events")

local reward_profiles = require("config/generated/reward_profiles")
local reward_effects = require("config/generated/reward_effects")
local return_home = require("systems/hero_return_home_service")

local M = {}
local granted_non_repeatable = {}

local function return_rebirth_hero_home(result)
    if not string.match(
        tostring(result.encounter_id or ""),
        "^encounter_rebirth_%d+$"
    ) then
        return
    end
    local summoned = event_bus.request(events.HERO_SUMMON_GET_REQUEST, {
        player_id = result.player_id,
    })
    local hero = summoned and summoned.unit
        or PlayerResource:GetSelectedHeroEntity(result.player_id)
    local returned = return_home.return_unit(hero, result.player_id)
    if not returned or not returned.ok then return end
    local player = PlayerResource:GetPlayer(result.player_id)
    local position = returned.position
    if player and position then
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
end

local function effects_for(profile_id)
    local result = {}
    for _, effect in ipairs(reward_effects.rows or {}) do
        if effect.reward_profile_id == profile_id
            and effect.enabled ~= false then
            table.insert(result, effect)
        end
    end
    table.sort(result, function(a, b)
        return (a.sort_order or 0) < (b.sort_order or 0)
    end)
    return result
end

local function split_effects(effects)
    local resource = { wood = 0, gold = 0 }
    local progression = {}

    for _, effect in ipairs(effects) do
        local value = tonumber(effect.value) or 0
        if effect.effect_type == "add_wood" then
            resource.wood = resource.wood + value
        elseif effect.effect_type == "add_gold" then
            resource.gold = resource.gold + value
        else
            table.insert(progression, effect)
        end
    end
    return resource, progression
end

local function grant_reward(payload)
    local profile_id = tostring(payload.reward_profile_id or "")
    local profile = reward_profiles.by_id[profile_id]
    if not profile or profile.enabled == false then
        return {
            ok = false,
            error = "reward_profile_disabled_or_missing",
        }
    end

    local player_id = tonumber(payload.player_id)
    if player_id == nil or player_id < 0 then
        return { ok = false, error = "reward_player_invalid" }
    end
    granted_non_repeatable[player_id] = granted_non_repeatable[player_id] or {}
    if profile.repeatable ~= true
        and granted_non_repeatable[player_id][profile_id] then
        return { ok = true, idempotent = true, reward_profile_id = profile_id }
    end

    local effects = effects_for(profile_id)
    local resources, progression = split_effects(effects)

    local resource_result = { ok = true }
    if resources.wood ~= 0 or resources.gold ~= 0 then
        resource_result = event_bus.request(events.RESOURCE_ADD_REQUEST, {
            team = payload.team,
            wood = resources.wood,
            gold = resources.gold,
            reason = "monster_reward:" .. profile_id,
        }) or { ok = false, error = "resource_handler_missing" }
    end

    local progression_result = { ok = true }
    if #progression > 0 then
        progression_result = event_bus.request(
            events.HERO_PROGRESSION_APPLY_REQUEST,
            {
                player_id = payload.player_id,
                effects = progression,
                reason = "monster_reward:" .. profile_id,
            }
        ) or {
            ok = false,
            error = "hero_progression_handler_missing",
        }
    end

    local result = {
        ok = resource_result.ok == true
            and progression_result.ok == true,
        player_id = payload.player_id,
        team = payload.team,
        encounter_id = payload.encounter_id,
        reward_profile_id = profile_id,
        reward_text = profile.reward_text or "",
        effects = effects,
        resources = resources,
        resource_result = resource_result,
        progression_result = progression_result,
    }

    if result.ok and profile.repeatable ~= true then
        granted_non_repeatable[player_id][profile_id] = true
    end

    event_bus.emit(events.MONSTER_REWARD_GRANTED, result)
    return_rebirth_hero_home(result)
    if payload.player_id and payload.player_id >= 0 then
        event_bus.emit(events.UI_NOTIFICATION, {
            player_id = payload.player_id,
            message = "获得奖励：" .. (profile.reward_text or ""),
            level = result.ok and "success" or "error",
        })
    end
    return result
end

local function on_monster_killed(payload)
    if tostring(payload.reward_profile_id or "") == "" then return end
    local profile = reward_profiles.by_id[payload.reward_profile_id]
    if profile and profile.trigger_type == "on_encounter_complete" then return end
    grant_reward(payload)
end

local function on_encounter_completed(payload)
    if tostring(payload.reward_profile_id or "") == "" then return end
    local profile = reward_profiles.by_id[payload.reward_profile_id]
    if not profile or profile.trigger_type ~= "on_encounter_complete" then return end
    grant_reward(payload)
end

function M.init()
    granted_non_repeatable = {}
    event_bus.handle_request(events.MONSTER_REWARD_GRANT_REQUEST, grant_reward)
    event_bus.subscribe(events.MONSTER_KILLED, on_monster_killed)
    event_bus.subscribe(events.MONSTER_ENCOUNTER_COMPLETED, on_encounter_completed)
end

return M
