local event_bus = require("core/event_bus")
local events = require("core/events")
local stages = require("config/generated/builder_ability_stages")
local training = require("config/generated/training_definitions")

local M = {}
local BUILDER_BLINK_ABILITY = "ability_survival_builder_blink"
local BUILDER_SLOT_COUNT = 6

local state_by_team = {}
local managed_abilities = {}

local function placeholder_name(slot_order)
    return "ability_survival_builder_slot_" .. tostring(slot_order)
        .. "_placeholder"
end

local function is_managed_ability(name)
    return managed_abilities[name] == true
        or name == BUILDER_BLINK_ABILITY
        or string.match(
            name,
            "^ability_survival_builder_slot_[1-6]_placeholder$"
        ) ~= nil
end

local function valid_entity(entity)
    return entity and not entity:IsNull()
end

local function create_state()
    return {
        builder = nil,
        player_id = -1,
        team = -1,
        stage_id = "",
        wall_built_once = false,
        city_level = 0,
        hero_summoned = false,
        counts = {},
        tower_class_by_entindex = {},
    }
end

local function ensure(team)
    if not state_by_team[team] then
        state_by_team[team] = create_state()
        state_by_team[team].team = team
    end
    return state_by_team[team]
end

local function count(state, building_id)
    return state.counts[building_id] or 0
end

local function stage_for(state)
    if not state.wall_built_once then
        return "wall_pending"
    end
    if count(state, "main_city") < 1 then
        return "city_pending"
    end
    return "city_built"
end

local function rows_for(stage_id)
    local rows = {}
    for _, row in ipairs(stages.rows or {}) do
        if row.enabled ~= false and row.stage_id == stage_id then
            table.insert(rows, row)
            managed_abilities[row.ability_name] = true
        end
    end
    table.sort(rows, function(a, b)
        return (a.slot_order or 0) < (b.slot_order or 0)
    end)
    return rows
end

local function can_activate(state, row)
    if row.building_id == "building_research_lab"
        and count(state, "building_research_lab") >= 1 then
        return false
    end
    if row.building_id == "building_challenge"
        and count(state, "building_research_lab") < 1 then
        return false
    end
    if state.city_level < (tonumber(row.required_city_level) or 0) then
        return false
    end
    local maximum = tonumber(row.max_building_count) or 0
    if maximum > 0 and count(state, row.building_id) >= maximum then
        return false
    end
    local prerequisite = tostring(row.requires_building_id or "")
    if prerequisite ~= "" and count(state, prerequisite) < 1 then
        return false
    end
    if row.disable_after_hero_summoned == true
        and state.hero_summoned then
        return false
    end
    return true
end

local function count_limit_reached(state, row)
    local maximum = tonumber(row.max_building_count) or 0
    return maximum > 0 and count(state, row.building_id) >= maximum
end

local function should_show(state, row)
    if count_limit_reached(state, row) then return false end
    local prerequisite = tostring(row.requires_building_id or "")
    return prerequisite == "" or count(state, prerequisite) > 0
end

local function valid_tower_class(value)
    return type(value) == "string"
        and string.match(value, "^class_[1-7]$") ~= nil
end

local function count_key_for_tower(tower_class)
    return valid_tower_class(tower_class) and tower_class or "arrow_tower"
end

local function change_count(state, building_id, delta)
    state.counts[building_id] = math.max(
        0,
        (state.counts[building_id] or 0) + delta
    )
end

local function apply_tower_identity(state, payload, delta)
    if payload.building_id ~= "arrow_tower" then return end
    local entindex = tonumber(payload.entindex)
    if not entindex then return end
    local previous = state.tower_class_by_entindex[entindex]
    local next_class = valid_tower_class(payload.tower_class)
        and payload.tower_class or nil
    local previous_key = count_key_for_tower(previous)
    local next_key = count_key_for_tower(next_class)
    if delta > 0 then
        state.tower_class_by_entindex[entindex] = next_class
        change_count(state, next_key, 1)
    elseif delta < 0 then
        change_count(state, previous_key, -1)
        state.tower_class_by_entindex[entindex] = nil
    elseif previous_key ~= next_key then
        change_count(state, previous_key, -1)
        change_count(state, next_key, 1)
        state.tower_class_by_entindex[entindex] = next_class
    end
end

local function rebuild_building_counts(state)
    state.counts = {}
    state.tower_class_by_entindex = {}
    state.city_level = 0
    local result = event_bus.request(events.BUILDING_LIST_REQUEST, {
        player_id = state.player_id,
    }) or {}
    for _, building in ipairs(result.buildings or {}) do
        local building_id = tostring(building.building_id or "")
        if building_id == "arrow_tower" then
            apply_tower_identity(state, building, 1)
        elseif building_id ~= "" then
            change_count(state, building_id, 1)
        end
        if building_id == "wall" then state.wall_built_once = true end
        if building_id == "main_city" then
            state.city_level = math.max(
                state.city_level,
                tonumber(building.level) or 1
            )
        end
    end
end

local function ability_name(ability)
    if not ability or not ability.GetAbilityName then return "" end
    return tostring(ability:GetAbilityName() or "")
end

local function enumerate_abilities(builder)
    local result = {}
    local reported_count = builder.GetAbilityCount
        and (tonumber(builder:GetAbilityCount()) or 0) or 0
    reported_count = math.max(0, math.floor(reported_count))
    for index = 0, reported_count - 1 do
        local ability = builder:GetAbilityByIndex(index)
        if ability then
            table.insert(result, {
                ability = ability,
                name = ability_name(ability),
                index = index,
            })
        end
    end
    return result, reported_count
end

local function management_domain_start(entries, reported_count)
    local first_managed = nil
    for _, entry in ipairs(entries or {}) do
        if is_managed_ability(entry.name)
            and (first_managed == nil or entry.index < first_managed) then
            first_managed = entry.index
        end
    end
    if first_managed ~= nil then return first_managed end
    return math.max(0, tonumber(reported_count) or 0)
end

local function desired_layout(state, stage_rows, domain_start)
    local result = {}
    local target_by_index = {}
    domain_start = math.max(0, tonumber(domain_start) or 0)
    for _, row in ipairs(stage_rows) do
        if should_show(state, row) then
            local relative_index = math.max(
                0,
                (tonumber(row.slot_order) or 1) - 1
            )
            local target = {
                name = row.ability_name,
                index = domain_start + relative_index,
                row = row,
            }
            target_by_index[relative_index] = target
        end
    end
    for relative_index = 0, BUILDER_SLOT_COUNT - 1 do
        table.insert(result, target_by_index[relative_index] or {
            name = placeholder_name(relative_index + 1),
            index = domain_start + relative_index,
            row = nil,
            placeholder = true,
        })
    end
    table.sort(result, function(a, b) return a.index < b.index end)
    table.insert(result, {
        name = BUILDER_BLINK_ABILITY,
        index = domain_start + BUILDER_SLOT_COUNT,
        row = nil,
    })
    return result
end

local function layout_is_valid(builder, desired, entries)
    entries = entries or enumerate_abilities(builder)
    local expected_by_index = {}
    local actual_by_index = {}
    local expected_count = 0
    for _, target in ipairs(desired) do
        if expected_by_index[target.index] then return false end
        expected_by_index[target.index] = target.name
        expected_count = expected_count + 1
    end

    local managed_count = 0
    for _, entry in ipairs(entries) do
        actual_by_index[entry.index] = entry.name
        if is_managed_ability(entry.name) then
            managed_count = managed_count + 1
            if expected_by_index[entry.index] ~= entry.name then return false end
        end
    end
    if managed_count ~= expected_count then return false end

    for _, target in ipairs(desired) do
        if actual_by_index[target.index] ~= target.name then
            return false
        end
    end
    return true
end

local function capture_cooldowns(builder, entries)
    local result = {}
    entries = entries or enumerate_abilities(builder)
    for _, entry in ipairs(entries) do
        if is_managed_ability(entry.name) then
            local remaining = 0
            if entry.ability.GetCooldownTimeRemaining then
                remaining = math.max(
                    0,
                    tonumber(entry.ability:GetCooldownTimeRemaining()) or 0
                )
            end
            result[entry.name] = math.max(result[entry.name] or 0, remaining)
        end
    end
    return result
end

local function remove_managed_instances(builder, entries)
    local counts = {}
    entries = entries or enumerate_abilities(builder)
    for _, entry in ipairs(entries) do
        if is_managed_ability(entry.name) then
            counts[entry.name] = (counts[entry.name] or 0) + 1
        end
    end
    for name, ability_count in pairs(counts) do
        for _ = 1, ability_count do builder:RemoveAbility(name) end
    end
end

local function restore_cooldown(ability, remaining)
    remaining = math.max(0, tonumber(remaining) or 0)
    if remaining <= 0 or not ability.StartCooldown then return end
    if ability.EndCooldown then ability:EndCooldown() end
    ability:StartCooldown(remaining)
end

local function configure_ability(state, target, ability)
    if not ability then return end
    ability:SetLevel(1)
    ability:SetHidden(target.placeholder == true)
    ability:SetActivated(target.placeholder ~= true
        and (target.row == nil or can_activate(state, target.row)))
end

local function rebuild_layout(state, builder, desired, entries)
    local cooldowns = capture_cooldowns(builder, entries)
    remove_managed_instances(builder, entries)
    local rebuilt = {}
    for _, target in ipairs(desired) do
        local ability = builder:AddAbility(target.name)
        rebuilt[target.name] = ability
        if ability then
            restore_cooldown(ability, cooldowns[target.name])
            configure_ability(state, target, ability)
        end
    end
    local rebuilt_entries, reported_count = enumerate_abilities(builder)
    return layout_is_valid(builder, desired, rebuilt_entries), rebuilt,
        rebuilt_entries, reported_count
end

local function layout_description(entries)
    local parts = {}
    for _, entry in ipairs(entries or {}) do
        table.insert(parts, tostring(entry.index) .. ":" .. entry.name)
    end
    return table.concat(parts, ",")
end

local function expected_description(desired)
    local parts = {}
    for _, target in ipairs(desired or {}) do
        table.insert(parts, tostring(target.index) .. ":" .. target.name)
    end
    return table.concat(parts, ",")
end

local function configure_layout(state, stage_rows)
    local builder = state.builder
    if not valid_entity(builder) then return end
    local entries, reported_count = enumerate_abilities(builder)
    local domain_start = management_domain_start(entries, reported_count)
    local desired = desired_layout(state, stage_rows, domain_start)
    local layout_valid = layout_is_valid(builder, desired, entries)
    local rebuilt = {}
    if not layout_valid then
        layout_valid, rebuilt, entries, reported_count = rebuild_layout(
            state,
            builder,
            desired,
            entries
        )
    end
    if not layout_valid then
        print("[BuilderProgression] failed to rebuild authoritative ability layout"
            .. " ability_count=" .. tostring(reported_count)
            .. " domain_start=" .. tostring(domain_start)
            .. " valid_slots=[" .. layout_description(entries) .. "]"
            .. " expected=[" .. expected_description(desired) .. "]")
    end
    local ability_by_index = {}
    for _, entry in ipairs(entries) do
        ability_by_index[entry.index] = entry.ability
    end
    for _, target in ipairs(desired) do
        local ability = rebuilt[target.name]
            or ability_by_index[target.index]
        if ability_name(ability) == target.name then
            configure_ability(state, target, ability)
        end
    end
end

local function public_counts(state)
    local result = {}
    for building_id, value in pairs(state.counts) do
        result[building_id] = value
    end
    return result
end

local function publish(state)
    if not valid_entity(state.builder) then
        return
    end
    local payload = {
        unit = state.builder,
        entindex = state.builder:entindex(),
        player_id = state.player_id,
        team = state.team,
        building_id = "builder",
        level = 1,
        city_level = state.city_level,
        builder_stage = state.stage_id,
        hero_summoned = state.hero_summoned and 1 or 0,
        building_counts = public_counts(state),
    }
    event_bus.emit(events.BUILDER_STAGE_CHANGED, payload)
    event_bus.emit(events.BUILDER_UNLOCK_CHANGED, payload)
end

local function sync(state)
    local next_stage = stage_for(state)
    state.stage_id = next_stage
    local rows = rows_for(next_stage)
    configure_layout(state, rows)
    publish(state)
end

local function on_builder_ready(payload)
    local state = ensure(payload.team)
    state.builder = payload.builder
    state.player_id = payload.player_id
    rebuild_building_counts(state)
    local repair = (training.by_id or {}).train_repairer_01 or {}
    if valid_entity(payload.builder)
        and not payload.builder:HasModifier("modifier_repair_worker_ai") then
        payload.builder:AddNewModifier(
            payload.builder,
            nil,
            "modifier_repair_worker_ai",
            {
                repair_max_health_pct_per_second = tonumber(
                    repair.repair_max_health_pct_per_second
                ) or 2,
                repair_range = tonumber(repair.repair_range) or 200,
            }
        )
    end
    managed_abilities = {}
    for _, row in ipairs(stages.rows or {}) do
        managed_abilities[row.ability_name] = true
    end
    sync(state)
end

local function on_building_created(payload)
    local state = ensure(payload.team)
    local building_id = tostring(payload.building_id or "")
    if building_id == "arrow_tower" then
        apply_tower_identity(state, payload, 1)
        sync(state)
        return
    end
    state.counts[building_id] = count(state, building_id) + 1
    if building_id == "wall" then
        state.wall_built_once = true
    end
    if building_id == "main_city" then
        state.city_level = tonumber(payload.level) or 1
    end
    sync(state)
end

local function on_building_changed(payload)
    local state = ensure(payload.team)
    if payload.building_id == "arrow_tower" then
        apply_tower_identity(state, payload, 0)
        sync(state)
        return
    end
    if payload.building_id == "main_city" then
        state.city_level = tonumber(payload.level) or state.city_level
        sync(state)
    end
end

local function on_building_destroyed(payload)
    local state = ensure(payload.team)
    local building_id = tostring(payload.building_id or "")
    if building_id == "arrow_tower" then
        apply_tower_identity(state, payload, -1)
        sync(state)
        return
    end
    state.counts[building_id] = math.max(0, count(state, building_id) - 1)
    if building_id == "main_city" then
        state.city_level = 0
    end
    sync(state)
end

local function on_hero_summoned(payload)
    local state = ensure(payload.team)
    state.hero_summoned = true
    sync(state)
end

function M.init()
    state_by_team = {}
    managed_abilities = {}
    event_bus.subscribe(events.BUILDER_READY, on_builder_ready)
    event_bus.subscribe(events.BUILDING_CREATED, on_building_created)
    event_bus.subscribe(events.BUILDING_CHANGED, on_building_changed)
    event_bus.subscribe(events.BUILDING_DESTROYED, on_building_destroyed)
    event_bus.subscribe(events.HERO_SUMMONED, on_hero_summoned)
end

return M
