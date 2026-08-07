local event_bus = require("core/event_bus")
local events = require("core/events")
local builder = require("ui/ability_runtime_builder")
local ability_utils = require("core/ability_utils")
local hero_skill_definitions = require("config/generated/hero_skill_definitions")
local hero_passive_definitions = require("config/hero_passive_skill_definitions")
local hero_skill_tooltip = require("ui/hero_skill_tooltip_view_model")

local M = {}

local state_by_unit = {}
local ability_keys_by_unit = {}
local tower_trace_by_ability = {}
local hero_runtime_trace_by_unit = {}
local hero_skill_by_ability = {}

for _, definition in ipairs(hero_skill_definitions.rows or {}) do
    if definition.ability_name and definition.ability_name ~= "" then
        hero_skill_by_ability[definition.ability_name] = definition
    end
end

local function is_tower_upgrade(ability_name)
    return ability_name == "ability_upgrade_tower"
        or ability_name == "ability_upgrade_tower_lv01"
        or ability_name == "ability_upgrade_tower_max"
end

local function ensure_tower_upgrade_active(ability, runtime)
    if runtime.available ~= 1 then
        return
    end
    if ability:GetLevel() < 1 then
        ability:SetLevel(1)
    end
    if not ability:IsActivated() then
        ability:SetActivated(true)
    end
    runtime.engine_level = ability:GetLevel()
    runtime.engine_activated = ability:IsActivated() and 1 or 0
end

local function valid_entity(entity)
    return entity and not entity:IsNull()
end

local function unit_from_payload(payload)
    if valid_entity(payload.unit) then
        return payload.unit
    end
    if not payload.entindex then
        return nil
    end
    local ok, entity = pcall(
        EntIndexToHScript,
        payload.entindex
    )
    return ok and valid_entity(entity) and entity or nil
end

local function resources(team)
    if not team then
        return nil
    end
    return event_bus.request(
        events.RESOURCE_GET_REQUEST,
        { team = team }
    )
end

local function normalize(payload, unit)
    local previous = state_by_unit[unit:entindex()] or {}
    return {
        unit = unit,
        team = payload.team or previous.team
            or unit:GetTeamNumber(),
        building_id = payload.building_id
            or previous.building_id,
        level = tonumber(payload.level)
            or tonumber(previous.level) or 1,
        tower_class = payload.tower_class ~= nil
            and payload.tower_class
            or previous.tower_class,
        tower_class_name =
            payload.tower_class_name ~= nil
            and payload.tower_class_name
            or previous.tower_class_name,
        display_name = payload.display_name ~= nil
            and payload.display_name
            or previous.display_name,
        city_level = payload.city_level ~= nil
            and payload.city_level
            or previous.city_level or 0,
        mine_level = payload.mine_level ~= nil
            and payload.mine_level
            or previous.mine_level or 1,
        efficiency_level = payload.efficiency_level ~= nil
            and payload.efficiency_level
            or previous.efficiency_level or 0,
        crit_level = payload.crit_level ~= nil
            and payload.crit_level
            or previous.crit_level or 0,
        income_per_second = payload.income_per_second ~= nil
            and payload.income_per_second
            or previous.income_per_second or 0,
        efficiency_percent = payload.efficiency_percent ~= nil
            and payload.efficiency_percent
            or previous.efficiency_percent or 0,
        crit_chance = payload.crit_chance ~= nil
            and payload.crit_chance
            or previous.crit_chance or 0,
        crit_multiplier = payload.crit_multiplier ~= nil
            and payload.crit_multiplier
            or previous.crit_multiplier or 0,
        auto_upgrading = payload.auto_upgrading ~= nil
            and payload.auto_upgrading
            or previous.auto_upgrading or 0,
        upgrade_in_progress = payload.upgrade_in_progress ~= nil
            and payload.upgrade_in_progress
            or (unit.survival_upgrade_in_progress and 1 or 0),
        upgrade_target_level = payload.upgrade_target_level ~= nil
            and payload.upgrade_target_level
            or unit.survival_upgrade_target_level,
        upgrade_target_model_asset_id =
            unit.survival_upgrade_target_model_asset_id,
        upgrade_target_model_path = unit.survival_upgrade_target_model_path,
        upgrade_model_status = unit.survival_upgrade_model_status,
        builder_stage = payload.builder_stage
            or previous.builder_stage or "",
        hero_summoned = payload.hero_summoned ~= nil
            and payload.hero_summoned
            or previous.hero_summoned or 0,
        player_id = payload.player_id ~= nil
            and tonumber(payload.player_id)
            or previous.player_id
            or unit:GetPlayerOwnerID(),
        building_counts = payload.building_counts
            or previous.building_counts or {},
    }
end

local function clear_removed(unit_key, current)
    local previous = ability_keys_by_unit[unit_key] or {}
    for ability_entindex, _ in pairs(previous) do
        if not current[ability_entindex] then
            CustomNetTables:SetTableValue(
                "survival_ability_runtime",
                tostring(ability_entindex),
                { removed = 1 }
            )
        end
    end
end

local function reconcile_authoritative_unit_state(state)
    if state.building_id ~= "arrow_tower" then return end
    local unit = state.unit
    if not valid_entity(unit) then return end

    -- BUILDING_CHANGED and RESOURCE_CHANGED are independent event streams. A
    -- resource event can therefore republish an older cached tower snapshot
    -- after the unit has already reached level 5. The upgrade system writes the
    -- authoritative route state onto the entity before emitting its UI event,
    -- so reconcile here before deriving class-button availability.
    state.level = tonumber(unit.survival_level) or state.level
    if unit.survival_tower_class ~= nil then
        state.tower_class = unit.survival_tower_class
    end
    if unit.survival_display_name ~= nil then
        state.tower_class_name = unit.survival_tower_class
            and unit.survival_display_name or state.tower_class_name
        state.display_name = unit.survival_display_name
    end
end

local function bool_flag(value)
    return value and 1 or 0
end

local function ability_behavior(ability)
    local ok, behavior = pcall(function()
        return ability:GetBehaviorInt()
    end)
    return ok and behavior or "unavailable"
end

local function trace_combat_hero_runtime(state)
    if state.building_id ~= "combat_hero" then return end
    local unit = state.unit
    if not valid_entity(unit) then return end

    local unit_key = unit:entindex()
    local rows = {}
    local count = math.max(0, tonumber(unit:GetAbilityCount()) or 0)
    for slot = 0, count - 1 do
        local ability = unit:GetAbilityByIndex(slot)
        if ability and not ability:IsNull() then
            local ability_name = ability:GetAbilityName()
            local project_visible = not ability:IsHidden() and (
                hero_skill_by_ability[ability_name] ~= nil
                    or ability_name == "ability_survival_return_home"
                    or ability_name == "ability_survival_pickup_materials"
            )
            if project_visible then
                rows[#rows + 1] = table.concat({
                    "engine_slot=" .. tostring(slot),
                    "name=" .. tostring(ability_name),
                    "entindex=" .. tostring(ability:entindex()),
                    "level=" .. tostring(ability:GetLevel()),
                    "hidden=" .. tostring(bool_flag(ability:IsHidden())),
                    "activated=" .. tostring(bool_flag(ability:IsActivated())),
                    "behavior=" .. tostring(ability_behavior(ability)),
                    "definition=" .. tostring(bool_flag(
                        hero_skill_by_ability[ability_name] ~= nil
                    )),
                }, ",")
            end
        end
    end
    local signature = table.concat(rows, "|")
    if hero_runtime_trace_by_unit[unit_key] == signature then return end
    hero_runtime_trace_by_unit[unit_key] = signature
    print(string.format(
        "[SURVIVAL_TOOLTIP_RUNTIME] unit=%s player=%s hero=%s engine_count=%s abilities=%s",
        tostring(unit_key),
        tostring(state.player_id),
        tostring(unit:GetUnitName()),
        tostring(count),
        signature
    ))
end

local function publish(state)
    local unit = state.unit
    if not valid_entity(unit) then
        return
    end

    reconcile_authoritative_unit_state(state)

    local unit_key = unit:entindex()
    state_by_unit[unit_key] = state
    local resource_state = resources(state.team)
    local current = {}
    local tower_transitions = 0

    ability_utils.for_each(unit, function(ability)
        local ability_name = ability:GetAbilityName()
        local runtime = builder.build(
            ability_name,
            state,
            resource_state
        )
        local hero_skill = hero_skill_by_ability[ability_name]
        local passive = hero_skill and (
            hero_skill.skill_id == "proto_flame_burst"
                or hero_skill.skill_id == "proto_ice_cone"
                or hero_skill.skill_id == "proto_magic_slingshot"
                or hero_skill.skill_id == "proto_holy_pulse"
                or hero_skill.skill_id == "proto_meteor"
                or hero_skill.skill_id == "proto_frost_nova"
                or hero_skill.skill_id == "proto_poison_cloud"
                or hero_skill.skill_id == "proto_blade_nova"
                or hero_skill.skill_id == "proto_echo_slash"
                or hero_skill.skill_id == "proto_earth_line"
                or hero_skill.skill_id == "proto_void_pulse"
        )
            and hero_passive_definitions.by_id[hero_skill.skill_id] or nil
        if passive then
            local current_level = math.max(1, math.min(
                tonumber(passive.max_level) or 1,
                tonumber(ability:GetLevel()) or 1
            ))
            runtime.current_level = current_level
            runtime.fields = runtime.fields or {}
            for _, row in ipairs(hero_skill_tooltip.level_rows(
                passive, tonumber(passive.max_level) or current_level
            )) do
                runtime.fields[#runtime.fields + 1] = {
                    label = "LV" .. tostring(row.level),
                    value = row.effect,
                }
            end
        end
        runtime.ability_name = ability_name
        runtime.owner_entindex = unit_key
        runtime.ability_entindex = ability:entindex()
        runtime.resource_version =
            resource_state and resource_state.version or 0
        if is_tower_upgrade(ability_name) then
            ensure_tower_upgrade_active(ability, runtime)
            local trace_key = ability:entindex()
            local signature = table.concat({
                tostring(state.level),
                tostring(runtime.available),
                tostring(runtime.can_afford),
                tostring(runtime.cost_wood or 0),
                tostring(runtime.cost_gold or 0),
            }, ":")
            local previous = tower_trace_by_ability[trace_key]
            if previous ~= signature then
                tower_transitions = tower_transitions + 1
                tower_trace_by_ability[trace_key] = signature
                print(string.format(
                    "[TOWER_UPGRADE_RUNTIME] unit=%s ability=%s ability_entindex=%s level=%s resource_version=%s wood=%s gold=%s cost_wood=%s cost_gold=%s available=%s can_afford=%s engine_level=%s engine_activated=%s previous=%s reason=state_transition",
                    tostring(unit_key),
                    tostring(ability_name),
                    tostring(trace_key),
                    tostring(state.level),
                    tostring(runtime.resource_version),
                    tostring(resource_state and resource_state.wood or "nil"),
                    tostring(resource_state and resource_state.gold or "nil"),
                    tostring(runtime.cost_wood or 0),
                    tostring(runtime.cost_gold or 0),
                    tostring(runtime.available),
                    tostring(runtime.can_afford),
                    tostring(runtime.engine_level or 0),
                    tostring(runtime.engine_activated or 0),
                    tostring(previous or "none")
                ))
            end
        end
        CustomNetTables:SetTableValue(
            "survival_ability_runtime",
            tostring(ability:entindex()),
            runtime
        )
        current[ability:entindex()] = true
    end)

    clear_removed(unit_key, current)
    ability_keys_by_unit[unit_key] = current
    trace_combat_hero_runtime(state)
    return tower_transitions
end

local function publish_unit(payload)
    local unit = unit_from_payload(payload)
    if unit then
        publish(normalize(payload, unit))
    end
end

local function clear_unit(payload)
    local entindex = payload.entindex
    local keys = entindex and ability_keys_by_unit[entindex]
        or nil
    for ability_entindex, _ in pairs(keys or {}) do
        CustomNetTables:SetTableValue(
            "survival_ability_runtime",
            tostring(ability_entindex),
            { removed = 1 }
        )
    end
    ability_keys_by_unit[entindex] = nil
    state_by_unit[entindex] = nil
    hero_runtime_trace_by_unit[entindex] = nil
    for ability_entindex, _ in pairs(keys or {}) do
        tower_trace_by_ability[ability_entindex] = nil
    end
end

local function on_resources(payload)
    local refreshed = 0
    local tower_transitions = 0
    for _, state in pairs(state_by_unit) do
        if state.team == payload.team then
            tower_transitions = tower_transitions + (publish(state) or 0)
            refreshed = refreshed + 1
        end
    end
    if tower_transitions > 0 then
        print(string.format(
            "[ABILITY_RUNTIME_RESOURCE_REFRESH] team=%s version=%s wood=%s gold=%s reason=%s units=%s tower_transitions=%s",
            tostring(payload.team),
            tostring(payload.version or 0),
            tostring(payload.wood or 0),
            tostring(payload.gold or 0),
            tostring(payload.reason or "unknown"),
            tostring(refreshed),
            tostring(tower_transitions)
        ))
    end
end

local function on_worker_changed(payload)
    for _, state in pairs(state_by_unit) do
        if state.team == payload.team and (
            state.building_id == "main_city"
                or state.building_id == "building_farm"
        ) then
            publish(state)
        end
    end
end

local function on_hero_summon_state(payload)
    local player_id = tonumber(payload.player_id)
    if player_id == nil or player_id < 0 then
        return
    end
    local team = PlayerResource:GetTeam(player_id)
    for _, state in pairs(state_by_unit) do
        if state.team == team then
            state.hero_summoned =
                tonumber(payload.hero_summoned) or 0
            publish(state)
        end
    end
end

local function on_hero_progression_changed(payload)
    local player_id = tonumber(payload.player_id)
    if player_id == nil or player_id < 0 then return end
    for _, state in pairs(state_by_unit) do
        if tonumber(state.player_id) == player_id then publish(state) end
    end
end


local function on_hero_skill_changed(payload)
    local entindex = tonumber(payload.unit_entindex)
    if not entindex or entindex < 0 then
        return
    end
    publish_unit({
        entindex = entindex,
        building_id = "combat_hero",
        level = 1,
    })
end

local function on_builder_ready(payload)
    publish_unit({
        unit = payload.builder,
        team = payload.team,
        level = 1,
        building_id = "builder",
    })
end

function M.init()
    state_by_unit = {}
    ability_keys_by_unit = {}
    tower_trace_by_ability = {}
    hero_runtime_trace_by_unit = {}
    event_bus.subscribe(events.BUILDER_READY, on_builder_ready)
    event_bus.subscribe(events.BUILDING_CREATED, publish_unit)
    event_bus.subscribe(events.BUILDING_CHANGED, publish_unit)
    event_bus.subscribe(events.BUILDING_DESTROYED, clear_unit)
    event_bus.subscribe(events.BUILDER_UNLOCK_CHANGED, publish_unit)
    event_bus.subscribe(events.BUILDER_STAGE_CHANGED, publish_unit)
    event_bus.subscribe(
        events.HERO_SUMMON_STATE_CHANGED,
        on_hero_summon_state
    )
    event_bus.subscribe(events.GOLD_MINE_CHANGED, publish_unit)
    event_bus.subscribe(
        events.HERO_SKILL_CHANGED,
        on_hero_skill_changed
    )
    event_bus.subscribe(events.RESOURCE_CHANGED, on_resources)
    event_bus.subscribe(events.WORKER_CHANGED, on_worker_changed)
    event_bus.subscribe(
        events.HERO_PROGRESSION_CHANGED,
        on_hero_progression_changed
    )
end

return M
