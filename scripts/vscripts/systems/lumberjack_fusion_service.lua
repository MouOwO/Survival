local event_bus = require("core/event_bus")
local events = require("core/events")
local definitions = require("config/generated/lumberjack_fusion_definitions")
local personality_definitions = require("config/generated/lumberjack_personality_definitions")
local training_definitions = require("config/generated/training_definitions")
local worker_system = require("systems/worker_system")
local armor_balance = require("config/armor_balance")

local M = {}
local pending_by_caster = {}

local function valid(unit)
    return unit and not unit:IsNull() and unit:IsAlive()
end

local function row_for_ability(ability_name)
    for _, row in ipairs(definitions.rows or {}) do
        if row.enabled ~= false and row.ability_id == ability_name then return row end
    end
    return nil
end

local function source_training(row)
    return training_definitions.by_id["train_lumberjack_"
        .. string.format("%02d", tonumber(row.level) or 0)]
end

local function ability_names(row)
    local pool = {}
    for _, skill_id in ipairs(row.super_skill_ids or {}) do
        local definition = personality_definitions.by_id[skill_id]
        if definition and definition.enabled ~= false then
            pool[#pool + 1] = definition
        end
    end
    if #pool == 0 then return {} end
    local index = RandomInt(1, #pool)
    return { pool[index].ability_name, skill_id = pool[index].skill_id }
end

local function collect_materials(caster, row)
    local player_id = tonumber(caster.survival_player_id)
    if player_id == nil then return {} end
    local listed = event_bus.request(events.WORKER_LIST_REQUEST, {
        player_id = player_id,
    }) or {}
    local result = { caster }
    local caster_entindex = caster:entindex()
    for _, state in ipairs(listed) do
        local unit = state.unit
        if valid(unit) and unit:entindex() ~= caster_entindex
            and state.team == caster:GetTeamNumber()
            and tonumber(state.player_id) == player_id
            and state.worker_type == "lumberjack"
            and unit.survival_super_lumberjack ~= true
            and tonumber(unit.survival_lumberjack_level) == tonumber(row.level)
            and not unit.survival_lumberjack_fusion_pending then
            result[#result + 1] = unit
            if #result >= tonumber(row.required_count) then break end
        end
    end
    return result
end

local function main_city_level(player_id)
    local listed = event_bus.request(events.BUILDING_LIST_REQUEST, {
        player_id = player_id,
    })
    for _, building in ipairs((listed and listed.buildings) or {}) do
        if building.building_id == "main_city" then
            return tonumber(building.level) or 0
        end
    end
    return 0
end

local function fusion_cost(row)
    return {
        wood = math.max(0, tonumber(row.wood_cost) or 0),
        gold = math.max(0, tonumber(row.gold_cost) or 0),
    }
end

local function refund_cost(player_id, team, cost)
    if cost.wood <= 0 and cost.gold <= 0 then return end
    event_bus.request(events.RESOURCE_ADD_REQUEST, {
        player_id = player_id,
        team = team,
        wood = cost.wood,
        gold = cost.gold,
        reason = "lumberjack_fusion_refund",
    })
end

local function target_data(row, materials, fusion_ability_name)
    local source = source_training(row)
    if not source then return { ok = false, error = "source_training_missing" } end
    local attack = 0
    local wood_per_hit = 0
    local player_id = tonumber(materials[1].survival_player_id)
    for _, material in ipairs(materials) do
        local current_attack = tonumber(material.survival_attack_min)
            or tonumber(material.survival_base_attack) or 0
        -- Keep the attack snapshot including the technology already applied to
        -- each material. The worker registry splits the aggregate snapshot
        -- before reapplying the current technology for all fused materials.
        attack = attack + math.max(0, current_attack)
        wood_per_hit = wood_per_hit
            + (tonumber(material.survival_base_wood_per_hit) or 0)
    end
    return {
        ok = true,
        level = row.level,
        team = materials[1]:GetTeamNumber(),
        player_id = materials[1].survival_player_id,
        fusion_count = #materials,
        base_attack = attack,
        wood_per_hit = wood_per_hit,
        attack_speed = tonumber(source.attack_rate) or 0.5,
        fusion_interval_reduction = 0.5,
        attack_range = tonumber(source.attack_range) or 400,
        move_speed = tonumber(source.move_speed) or 300,
        health = tonumber(source.health) or 300,
        engine_armor = armor_balance.from_war3(
            tonumber(source.war3_armor or source.armor) or 0
        ),
        ability_names = ability_names(row),
        fusion_ability_name = fusion_ability_name,
        model_name = source.model_name,
        model_scale = 1.5,
    }
end

local function fuse(payload)
    local caster = payload and payload.caster
    local ability = payload and payload.ability
    if not valid(caster) or not ability
        or caster.survival_worker_type ~= "lumberjack"
        or caster.survival_super_lumberjack
        or caster.survival_lumberjack_fusion_pending
        or tonumber(caster.survival_player_id) == nil then
        return { ok = false, error = "invalid_caster" }
    end
    local row = row_for_ability(ability:GetAbilityName())
    if not row then return { ok = false, error = "fusion_definition_invalid" } end
    if tonumber(caster.survival_lumberjack_level) ~= tonumber(row.level) then
        return { ok = false, error = "fusion_caster_level_mismatch" }
    end
    local caster_key = caster:entindex()
    if pending_by_caster[caster_key] then
        return { ok = false, error = "fusion_pending" }
    end
    pending_by_caster[caster_key] = true
    local player_id = tonumber(caster.survival_player_id)
    local required_city_level = tonumber(row.required_city_level) or 0
    if main_city_level(player_id) < required_city_level then
        pending_by_caster[caster_key] = nil
        return { ok = false, error = "fusion_city_level_not_enough" }
    end
    local materials = collect_materials(caster, row)
    if #materials < tonumber(row.required_count) then
        pending_by_caster[caster_key] = nil
        return { ok = false, error = "fusion_material_not_enough" }
    end
    for _, material in ipairs(materials) do
        material.survival_lumberjack_fusion_pending = true
    end
    local cost = fusion_cost(row)
    local spent = event_bus.request(events.RESOURCE_TRY_SPEND_REQUEST, {
        player_id = player_id,
        team = caster:GetTeamNumber(),
        wood = cost.wood,
        gold = cost.gold,
        reason = "lumberjack_fusion",
    })
    if not spent or not spent.ok then
        for _, material in ipairs(materials) do
            material.survival_lumberjack_fusion_pending = nil
        end
        pending_by_caster[caster_key] = nil
        return spent or { ok = false, error = "fusion_resource_not_enough" }
    end
    local target = caster
    local data = target_data(row, materials, ability:GetAbilityName())
    if not data or not data.ok then
        for _, material in ipairs(materials) do
            material.survival_lumberjack_fusion_pending = nil
        end
        refund_cost(player_id, caster:GetTeamNumber(), cost)
        pending_by_caster[caster_key] = nil
        return data or { ok = false, error = "fusion_target_config_failed" }
    end
    local committed = worker_system.commit_lumberjack_fusion(materials, target, data)
    if not committed or not committed.ok then
        refund_cost(player_id, caster:GetTeamNumber(), cost)
        for _, material in ipairs(materials) do
            material.survival_lumberjack_fusion_pending = nil
        end
        pending_by_caster[caster_key] = nil
        return committed or { ok = false, error = "fusion_commit_failed" }
    end
    pending_by_caster[caster_key] = nil
    return { ok = true, entindex = target:entindex(), fusion_id = row.fusion_id }
end

function M.init()
    pending_by_caster = {}
    event_bus.handle_request(events.LUMBERJACK_FUSION_REQUEST, fuse)
end

M._fuse_for_test = fuse
M._row_for_ability_for_test = row_for_ability
return M