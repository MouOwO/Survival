local tree_damage_rules = require("systems/tree_damage_rules")
local repair_order_service = require("systems/repair_order_service")
local lumberjack_order_service = require("systems/lumberjack_order_service")
local destination_validation = require("systems/destination_validation_service")
local anti_air_rules = require("systems/anti_air_rules")
local player_context = require("systems/player_context_service")

local M = {}
local registered = false

local function entity(entindex)
    entindex = tonumber(entindex)
    if not entindex or not EntIndexToHScript then return nil end
    return EntIndexToHScript(entindex)
end

local function ordered_units(keys)
    local result = {}
    for _, entindex in pairs(keys.units or {}) do
        local unit = entity(entindex)
        if unit then result[#result + 1] = unit end
    end
    return result
end

local function filter(_, keys)
    local issuer = tonumber(keys.issuer_player_id_const)
        or tonumber(keys.issuer_player_id)
        or tonumber(keys.player_id)
    local units = ordered_units(keys)
    if issuer ~= nil and issuer >= 0 then
        for _, unit in ipairs(units) do
            local owner = player_context.owner_player_id(unit)
            if owner == nil or owner ~= issuer then return false end
        end
    end
    lumberjack_order_service.process(keys)
    if repair_order_service.process(keys) then return false end
    local order_type = tonumber(keys.order_type)
    if order_type == tonumber(DOTA_UNIT_ORDER_MOVE_TO_POSITION)
        or order_type == tonumber(DOTA_UNIT_ORDER_ATTACK_MOVE) then
        local position = Vector(
            tonumber(keys.position_x) or 0,
            tonumber(keys.position_y) or 0,
            tonumber(keys.position_z) or 0
        )
        for _, unit in ipairs(units) do
            if tree_damage_rules.is_arrow_tower(unit) then
                return false
            end
            if destination_validation.is_constrained_hero(unit) then
                local allowed = destination_validation.validate(position, unit)
                if not allowed then return false end
            end
        end
        return true
    end
    if order_type ~= tonumber(DOTA_UNIT_ORDER_ATTACK_TARGET) then return true end
    local target = entity(keys.entindex_target)
    for _, unit in ipairs(units) do
        if tree_damage_rules.is_arrow_tower(unit) then
            local owner = player_context.owner_player_id(unit)
            if issuer ~= nil and issuer >= 0 and owner ~= nil
                and issuer ~= owner then
                return false
            end
        end
        if tree_damage_rules.is_tree(target)
            and not tree_damage_rules.is_allowed_tree_attacker(unit) then
            return false
        end
        if anti_air_rules.is_anti_air_tower(unit)
            and not anti_air_rules.is_flying(target) then
            return false
        end
        if tree_damage_rules.is_arrow_tower(unit)
            and target and not tree_damage_rules.is_tree(target)
            and anti_air_rules.can_attack(unit, target)
            and target:GetTeamNumber() ~= unit:GetTeamNumber() then
            local modifier = unit:FindModifierByName("modifier_tower_auto_attack")
            if modifier and modifier.SetManualTarget then
                modifier:SetManualTarget(target)
            end
        end
    end
    return true
end

function M.register()
    if registered then return true end
    local mode = GameRules:GetGameModeEntity()
    if not mode or not mode.SetExecuteOrderFilter then return false end
    mode:SetExecuteOrderFilter(filter, M)
    registered = true
    return true
end

function M.reset_for_test()
    registered = false
end

M._filter_for_test = filter
M._ordered_units_for_test = ordered_units

return M
