local event_bus = require("core/event_bus")
local events = require("core/events")
local effect_state = require("systems/rogue_effect_state_service")
local tower_combat_rules = require("config/tower_combat_rules")
local attack_cadence = require("combat/attack_cadence")
local hero_attack_projection = require("combat/rogue_hero_attack_projection")

local M = {}
local towers = {}
local subscriptions = {}

if LinkLuaModifier then
    LinkLuaModifier("modifier_rogue_ultimate_tower_effects",
        "modifiers/modifier_rogue_ultimate_tower_effects", LUA_MODIFIER_MOTION_NONE)
end

local function valid(unit)
    return unit and not unit:IsNull() and unit.survival_ultimate_tower == true
        and (not unit.IsAlive or unit:IsAlive())
end

local function attack_bonus(player_id)
    return effect_state.numeric(player_id, "unit_attack_bonus_pct")
        + effect_state.tower_projection(player_id, "max_tower_count_attack_bonus_pct")
end

function M.hero_attack_projection(player_id)
    local pct = effect_state.numeric(player_id, "tower_hero_attack_projection_pct")
    return hero_attack_projection.calculate(player_id, pct)
end

function M.attack_bonus_delta(unit)
    local baseline = unit.survival_ultimate_rogue_baseline or {}
    return attack_bonus(unit.survival_player_id) - (baseline.attack_bonus_pct or 0)
end

function M.hero_attack_delta(unit)
    local baseline = unit.survival_ultimate_rogue_baseline or {}
    return (M.hero_attack_projection(unit.survival_player_id)
        - (baseline.hero_attack_projection or 0))
        / math.max(1, tonumber(unit.survival_endless_attack_scale) or 1)
end

function M.technology_attack_delta(unit)
    local baseline = unit.survival_ultimate_rogue_baseline or {}
    return ((tonumber(unit.survival_ultimate_technology_attack_flat) or 0)
        - (tonumber(baseline.technology_attack_flat) or 0))
        / math.max(1, tonumber(unit.survival_endless_attack_scale) or 1)
end

function M.pre_attack_delta(unit)
    return M.hero_attack_delta(unit) + M.technology_attack_delta(unit)
end

local function refresh(unit, snapshot)
    if not valid(unit) then return false end
    if not snapshot then
        local result = event_bus.request(events.TECHNOLOGY_STATS_GET_REQUEST,
            { player_id = unit.survival_player_id }) or {}
        snapshot = result.snapshot or {}
    end
    local tower = snapshot.final and snapshot.final.tower or {}
    local attack_flat = tonumber(tower.attack_flat) or 0
    local changed = unit.survival_ultimate_technology_attack_flat ~= attack_flat
    unit.survival_ultimate_technology_attack_flat = attack_flat
    -- Materials contribute their attack damage, but their cadence and range
    -- are not inherited. Rebuild these from the fusion's fixed native bases.
    local base_interval = 1 / math.max(0.01,
        tonumber(unit.survival_ultimate_base_attack_speed) or 3)
    local interval, detail = attack_cadence.calculate(base_interval, {}, {
        { label = "科技", value = tonumber(tower.attack_speed_bonus_pct) or 0 },
    }, 0.0001)
    if unit.survival_attack_interval ~= interval then
        unit:SetBaseAttackTime(interval)
        changed = true
    end
    unit.survival_research_base_attack_time = base_interval
    unit.survival_attack_cadence = detail
    unit.survival_attack_speed = 1 / interval
    unit.survival_attack_interval = interval
    local range = (tonumber(unit.survival_ultimate_base_attack_range) or tower_combat_rules.attack_range())
        + (tonumber(tower.attack_range_bonus) or 0)
    if unit.survival_attack_range ~= range
        or not unit:HasModifier("modifier_survival_hero_attack_range") then
        tower_combat_rules.set_attack_range(unit, range)
        changed = true
    end
    return changed
end

function M.initialize(unit, player_id, selected, base_attack_speed)
    -- Ordinary fusion has already baked the materials' attack modifiers into
    -- base damage. Commerce builds have synthetic materials and bake none.
    local inherited = true
    for _, source in ipairs(selected or {}) do
        if not source.unit then inherited = false break end
    end
    local result = event_bus.request(events.TECHNOLOGY_STATS_GET_REQUEST,
        { player_id = player_id }) or {}
    local snapshot = result.snapshot or {}
    local tower = snapshot.final and snapshot.final.tower or {}
    local technology_attack_flat = tonumber(tower.attack_flat) or 0
    unit.survival_ultimate_technology_attack_flat = technology_attack_flat
    unit.survival_ultimate_rogue_baseline = {
        attack_bonus_pct = inherited and attack_bonus(player_id) or 0,
        hero_attack_projection = inherited and M.hero_attack_projection(player_id) or 0,
        technology_attack_flat = inherited and technology_attack_flat or 0,
    }
    unit.survival_ultimate_base_attack_speed = base_attack_speed
    unit.survival_ultimate_base_attack_range = tower_combat_rules.current_attack_range(unit)
    assert(unit:AddNewModifier(unit, nil, "modifier_rogue_ultimate_tower_effects", {}),
        "ultimate_tower_rogue_effects_missing")
    refresh(unit, snapshot)
end

function M.init()
    for _, subscription in ipairs(subscriptions) do event_bus.unsubscribe(subscription) end
    subscriptions, towers = {}, {}
    local function subscribe(event_name, callback)
        subscriptions[#subscriptions + 1] = event_bus.subscribe(event_name, callback)
    end
    subscribe(events.TOWER_FUSION_RUNTIME_CHANGED, function(payload)
        local unit = payload and payload.unit
        if not valid(unit) then return end
        towers[unit:entindex()] = unit
        refresh(unit)
    end)
    subscribe(events.TOWER_FUSION_RUNTIME_REMOVED, function(payload)
        if payload then towers[payload.entindex] = nil end
    end)
    subscribe(events.TECHNOLOGY_STATS_CHANGED, function(payload)
        if not payload then return end
        -- Per-hit worker/hero growth publishes the same technology event. It
        -- cannot affect a tower's range or cadence, and must not reset its BAT.
        if payload.changed_section and payload.changed_section ~= "tower" then return end
        for entindex, unit in pairs(towers) do
            if not valid(unit) then towers[entindex] = nil
            elseif tonumber(unit.survival_player_id) == tonumber(payload.player_id) then
                if refresh(unit, payload.snapshot) then
                    event_bus.emit(events.UNIT_COMBAT_STATS_CHANGED, {
                        unit = unit, entindex = entindex, player_id = unit.survival_player_id,
                        reason = "ultimate_tower_technology_changed",
                    })
                end
            end
        end
    end)
end

return M
