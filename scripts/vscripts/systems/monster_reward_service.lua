local event_bus = require("core/event_bus")
local events = require("core/events")

local reward_profiles = require("config/generated/reward_profiles")
local reward_effects = require("config/generated/reward_effects")
local return_home = require("systems/hero_return_home_service")

local M = {}
local granted_non_repeatable = {}
local granted_transactions = {}

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
    return_home.return_unit(hero, result.player_id)
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

local function scaled_effects(effects, challenge_wave_number)
    local result = {}
    local multiplier = math.max(1, tonumber(challenge_wave_number) or 1)
    for _, source in ipairs(effects) do
        local effect = {}
        for key, value in pairs(source) do effect[key] = value end
        if effect.stack_mode == "multiply_by_challenge_wave" then
            effect.value = (tonumber(effect.value) or 0) * multiplier
        end
        result[#result + 1] = effect
    end
    return result
end

local function split_effects(effects)
    local resource = { wood = 0, gold = 0 }
    local progression = {}
    local challenge = {}

    for _, effect in ipairs(effects) do
        local value = tonumber(effect.value) or 0
        if effect.effect_type == "add_wood" then
            resource.wood = resource.wood + value
        elseif effect.effect_type == "add_gold" then
            resource.gold = resource.gold + value
        elseif string.match(tostring(effect.effect_type), "^challenge_") then
            table.insert(challenge, effect)
        else
            table.insert(progression, effect)
        end
    end
    return resource, progression, challenge
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
    local transaction_id = tostring(payload.reward_transaction_id or "")
    if transaction_id ~= "" and granted_transactions[transaction_id] then
        return { ok = true, idempotent = true, reward_profile_id = profile_id }
    end
    if profile.repeatable ~= true
        and transaction_id == ""
        and granted_non_repeatable[player_id][profile_id] then
        return { ok = true, idempotent = true, reward_profile_id = profile_id }
    end

    local effects = scaled_effects(
        effects_for(profile_id),
        payload.challenge_wave_number
    )
    local resources, progression, challenge = split_effects(effects)

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

    local challenge_result = { ok = true }
    if #challenge > 0 then
        challenge_result = event_bus.request(
            events.TECHNOLOGY_STATS_CHALLENGE_ADD_REQUEST,
            {
                player_id = payload.player_id,
                effects = challenge,
                reason = "monster_reward:" .. profile_id,
            }
        ) or { ok = false, error = "challenge_stats_handler_missing" }
    end

    local result = {
        ok = resource_result.ok == true
            and progression_result.ok == true
            and challenge_result.ok == true,
        player_id = payload.player_id,
        team = payload.team,
        encounter_id = payload.encounter_id,
        reward_profile_id = profile_id,
        reward_text = profile.reward_text or "",
        effects = effects,
        resources = resources,
        resource_result = resource_result,
        progression_result = progression_result,
        challenge_result = challenge_result,
    }

    if result.ok then
        if transaction_id ~= "" then
            granted_transactions[transaction_id] = true
        elseif profile.repeatable ~= true then
            granted_non_repeatable[player_id][profile_id] = true
        end
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
    granted_transactions = {}
    event_bus.handle_request(events.MONSTER_REWARD_GRANT_REQUEST, grant_reward)
    event_bus.subscribe(events.MONSTER_KILLED, on_monster_killed)
    event_bus.subscribe(events.MONSTER_ENCOUNTER_COMPLETED, on_encounter_completed)
end

return M
