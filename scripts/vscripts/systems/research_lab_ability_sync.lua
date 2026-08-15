local mappings = require("config/generated/research_lab_abilities")
local research_config = require("config/research_technology_config")
local event_bus = require("core/event_bus")
local events = require("core/events")
local research_events = require("research/research_event_names")

local M = {}

local rows_by_building = {}
local managed_by_building = {}

for _, row in ipairs(mappings.rows or {}) do
    if row.enabled ~= false and row.building_id and row.ability_name then
        rows_by_building[row.building_id] = rows_by_building[row.building_id] or {}
        managed_by_building[row.building_id] = managed_by_building[row.building_id] or {}
        rows_by_building[row.building_id][#rows_by_building[row.building_id] + 1] = row
        managed_by_building[row.building_id][row.ability_name] = true
    end
end

for _, rows in pairs(rows_by_building) do
    table.sort(rows, function(left, right)
        local left_slot = tonumber(left.slot_order) or 0
        local right_slot = tonumber(right.slot_order) or 0
        if left_slot ~= right_slot then return left_slot < right_slot end
        return (tonumber(left.chain_order) or 0) < (tonumber(right.chain_order) or 0)
    end)
end

local function valid_entity(entity)
    return entity and not entity:IsNull()
end

local function maximum(row)
    local definition = research_config.by_legacy_group[row.technology_group]
    return tonumber(definition and definition.max_level) or 0
end

local function prerequisite_met(row, levels, reincarnation_level)
    local definition = research_config.by_legacy_group[row.technology_group]
    local required = definition and definition.prerequisite or {}
    if required.tech_id then
        local prerequisite = research_config.by_id[required.tech_id]
        if not prerequisite or (tonumber(levels[prerequisite.legacy_group]) or 0)
            < (tonumber(required.required_level) or 0) then
            return false
        end
    end
    return (tonumber(reincarnation_level) or 0)
        >= (tonumber(required.reincarnation_level) or 0)
end

local function desired_rows(building_id, levels)
    local rows = rows_by_building[building_id] or {}
    local desired = {}
    if building_id ~= "building_research_lab" then
        for _, row in ipairs(rows) do desired[#desired + 1] = row end
        return desired
    end
    local chains = {}
    local chain_order = {}
    for _, row in ipairs(rows) do
        local chain_id = tostring(row.chain_id or row.technology_group)
        if not chains[chain_id] then
            chains[chain_id] = {}
            chain_order[#chain_order + 1] = chain_id
        end
        chains[chain_id][#chains[chain_id] + 1] = row
    end
    for _, chain_id in ipairs(chain_order) do
        local selected = chains[chain_id][1]
        for index = 2, #chains[chain_id] do
            local previous = chains[chain_id][index - 1]
            if (tonumber(levels[previous.technology_group]) or 0)
                >= maximum(previous) then
                selected = chains[chain_id][index]
            else
                break
            end
        end
        desired[#desired + 1] = selected
    end
    return desired
end

function M.initial_abilities(building_id)
    local result = {}
    for _, row in ipairs(desired_rows(building_id, {})) do
        result[#result + 1] = row.ability_name
    end
    return result
end

function M.sync(unit, building_id, levels, transaction, reincarnation_level)
    if not valid_entity(unit) then return {} end
    levels = levels or {}
    local desired = desired_rows(building_id, levels)
    local desired_by_name = {}
    for _, row in ipairs(desired) do desired_by_name[row.ability_name] = row end

    for ability_name, _ in pairs(managed_by_building[building_id] or {}) do
        if not desired_by_name[ability_name]
            and unit:FindAbilityByName(ability_name) then
            unit:RemoveAbility(ability_name)
        end
    end

    local researching = transaction and transaction.researching == 1
    for _, row in ipairs(desired) do
        local ability = unit:FindAbilityByName(row.ability_name)
            or unit:AddAbility(row.ability_name)
        if ability then
            local current = tonumber(levels[row.technology_group]) or 0
            ability:SetLevel(1)
            ability:SetHidden(false)
            ability:SetActivated(not researching
                and current < maximum(row)
                and prerequisite_met(row, levels, reincarnation_level))
            if ability.SetAbilityIndex then
                ability:SetAbilityIndex(math.max(0, (tonumber(row.slot_order) or 1) - 1))
            end
        end
    end
    return desired
end

function M.rows_for_building(building_id)
    return rows_by_building[building_id] or {}
end

local function is_research_building(building_id)
    return building_id == "building_research_lab"
        or building_id == "building_advanced_research_lab"
end

local function reincarnation_level(player_id)
    local result = event_bus.request(events.HERO_PROGRESSION_GET_REQUEST, {
        player_id = player_id,
    })
    return tonumber(result and result.snapshot
        and result.snapshot.rebirth_level) or 0
end

local function research_levels(player_id)
    local result = event_bus.request(research_events.STATE_GET_REQUESTED, {
        player_id = player_id,
    })
    return result and result.ok == true and result.legacy_levels or {}
end

local function sync_building(building, transaction)
    if not building or not is_research_building(building.building_id) then return end
    M.sync(
        building.unit,
        building.building_id,
        research_levels(building.player_id),
        transaction,
        reincarnation_level(building.player_id)
    )
end

local function sync_team(team, transaction)
    local result = event_bus.request(events.BUILDING_LIST_REQUEST, {})
    for _, building in ipairs(result and result.buildings or {}) do
        if tonumber(building.team) == tonumber(team) then
            sync_building(building, transaction)
        end
    end
end

function M.init()
    event_bus.subscribe(events.BUILDING_CREATED, function(payload)
        sync_building(payload, { researching = 0 })
    end)
    event_bus.subscribe(events.TECHNOLOGY_RESEARCH_STATE_CHANGED, function(payload)
        sync_team(payload.team, payload)
    end)
    event_bus.subscribe(research_events.LEVEL_CHANGED, function(payload)
        local player_id = tonumber(payload and payload.player_id)
        local team = player_id ~= nil and PlayerResource:GetTeam(player_id) or nil
        if team ~= nil then sync_team(team, { researching = 0 }) end
    end)
    event_bus.subscribe(events.HERO_PROGRESSION_CHANGED, function(payload)
        local player_id = tonumber(payload and payload.player_id)
        local team = player_id ~= nil and PlayerResource:GetTeam(player_id) or nil
        if team ~= nil then sync_team(team, { researching = 0 }) end
    end)
end

return M