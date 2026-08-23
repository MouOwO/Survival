local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")

local M = {}
local totals_by_player = {}
local hero_ticks_by_player = {}
local tower_ticks_by_player = {}
local tower_damage_bonus_by_player = {}

local function copy(source)
    local result = {}
    for key, value in pairs(source or {}) do
        result[tostring(key)] = tonumber(value) or 0
    end
    return result
end

local function refresh(payload)
    local player_id = tonumber(payload and payload.player_id)
    if player_id == nil then return end
    local profile_service = require("systems/player_profile_service")
    local profile = profile_service.get_profile(player_id)
    totals_by_player[player_id] = copy(
        profile and profile.save and profile.save.permanent_effects or {}
    )
    hero_ticks_by_player[player_id] = hero_ticks_by_player[player_id] or 0
    tower_ticks_by_player[player_id] = tower_ticks_by_player[player_id] or 0
    tower_damage_bonus_by_player[player_id] = tower_damage_bonus_by_player[player_id] or 0
    print("[PermanentReward] projection_refreshed player_id=" .. tostring(player_id)
        .. " revision=" .. tostring(profile and profile.revision or 0)
        .. " hero_all_attributes_flat="
        .. tostring(totals_by_player[player_id].hero_all_attributes_flat or 0))
    event_bus.emit(events.PERMANENT_REWARD_EFFECTS_CHANGED, {
        player_id = player_id,
        totals = copy(totals_by_player[player_id]),
        revision = profile and profile.revision or 0,
    })
end

local function valid_entity(unit)
    if not unit then return false end
    if type(unit.IsNull) ~= "function" then return true end
    local ok, null = pcall(unit.IsNull, unit)
    return ok and not null
end

local function player_unit(player_id)
    local result = event_bus.request(events.HERO_SUMMON_GET_REQUEST, {
        player_id = player_id,
    })
    return result and (result.hero or result.unit)
end

local function apply_hero_tick(player_id)
    local amount = M.value(player_id, "hero_attributes_per_second")
    if amount <= 0 then return end
    local hero = player_unit(player_id)
    if not valid_entity(hero) or (hero.IsAlive and not hero:IsAlive()) then return end
    hero_ticks_by_player[player_id] = (hero_ticks_by_player[player_id] or 0) + 1
    event_bus.emit(events.HERO_PROGRESSION_CHANGED, {
        player_id = player_id,
        reason = "star_blessing_attributes_per_second",
        amount = amount,
        tick = hero_ticks_by_player[player_id],
    })
end

local function apply_tower_tick(player_id)
    local amount = M.value(player_id, "tower_attack_per_second")
    if amount <= 0 then return end
    tower_ticks_by_player[player_id] = (tower_ticks_by_player[player_id] or 0) + 1
    event_bus.emit(events.PERMANENT_REWARD_EFFECTS_CHANGED, {
        player_id = player_id,
        reason = "star_blessing_tower_attack_per_second",
        amount = amount,
        tick = tower_ticks_by_player[player_id],
    })
end

local function on_damage(payload)
    local player_id = tonumber(payload and payload.player_id)
    if player_id == nil then return end
    local attacker = payload.attacker
    local flat = M.value(player_id, "tower_damage_attack_flat")
    if flat > 0 and attacker and attacker.survival_building_id
        and attacker.SetBaseDamageMin then
        tower_damage_bonus_by_player[player_id] =
            (tower_damage_bonus_by_player[player_id] or 0) + flat
        event_bus.emit(events.PERMANENT_REWARD_EFFECTS_CHANGED, {
            player_id = player_id,
            reason = "star_blessing_tower_damage_attack_flat",
            amount = flat,
            damage = tonumber(payload.final_damage) or 0,
        })
    end
end

local function get(payload)
    local player_id = tonumber(payload and payload.player_id)
    if player_id == nil or player_id < 0 then
        return { ok = false, error = "player_id_invalid" }
    end
    local totals = copy(totals_by_player[player_id])
    totals.hero_all_attributes_flat = (totals.hero_all_attributes_flat or 0)
        + (totals.hero_attributes_per_second or 0)
            * (hero_ticks_by_player[player_id] or 0)
    totals.tower_attack_flat = (totals.tower_attack_flat or 0)
        + (totals.tower_attack_per_second or 0)
            * (tower_ticks_by_player[player_id] or 0)
        + (tower_damage_bonus_by_player[player_id] or 0)
    return { ok = true, totals = totals }
end

function M.value(player_id, effect_key)
    return tonumber((totals_by_player[tonumber(player_id)] or {})[effect_key]) or 0
end

function M.init()
    totals_by_player = {}
    hero_ticks_by_player = {}
    tower_ticks_by_player = {}
    tower_damage_bonus_by_player = {}
    event_bus.handle_request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST, get)
    event_bus.subscribe(events.PLAYER_PROFILE_CHANGED, refresh)
    event_bus.subscribe(events.COMBAT_DAMAGE_RESOLVED, on_damage)
    scheduler.every(1, function()
        for player_id in pairs(totals_by_player) do
            apply_hero_tick(player_id)
            apply_tower_tick(player_id)
        end
        return true
    end, "star_blessing_effect_ticks")
end

return M