-- Only fresh ordinary training may omit the Lua cap. Nonzero native IAS or
-- fusion permanently revokes that birth contract before changing gameplay.
local contracts = require("systems/wave_native_attack_cap")
local training_definitions = require("config/generated/training_definitions")
local M = {}
local CAP, FLAG = "modifier_debug_attack_cap", "survival_worker_native_cap_omitted"
local ability_kv
local allowed = {}
for level = 1, 8 do
    local suffix = string.format("%02d", level)
    allowed["train_lumberjack_" .. suffix] = "ability_fuse_lumberjack_" .. suffix
end
function M.init() ability_kv = nil end
local function fusion_kv(kv)
    return type(kv) == "table" and kv.BaseClass == "ability_lua"
        and kv.ScriptFile == "abilities/ability_fuse_lumberjack"
        and kv.AbilityBehavior == "DOTA_ABILITY_BEHAVIOR_NO_TARGET"
        and tonumber(kv.MaxLevel) == 1 and kv.Modifiers == nil
        and kv.AbilitySpecial == nil and kv.AbilityValues == nil
        and kv.AttackSpeed == nil and kv.BaseAttackSpeed == nil
end
local function custom_abilities()
    if ability_kv == nil then
        local ok, kv = pcall(LoadKeyValues, "scripts/npc/npc_abilities_custom.txt")
        ability_kv = ok and type(kv) == "table" and (kv.DOTAAbilities or kv) or false
    end
    return ability_kv
end
function M.is_training_candidate(id, row, unit_name)
    local expected = allowed[id]
    if not expected or type(row) ~= "table" or row ~= training_definitions.by_id[id]
        or row.training_id ~= id or row.training_type ~= "unit" or row.enabled ~= true
        or row.building_id ~= "building_main_city" or unit_name ~= "npc_survival_lumberjack"
        or row.unit_name ~= nil and row.unit_name ~= unit_name
        or row.unit_id ~= "unit_lumberjack_" .. id:sub(-2)
        or tonumber(row.level) ~= tonumber(id:sub(-2))
        or type(row.active_skill_ids) ~= "table" or row.active_skill_ids[1] ~= expected
        then return false end
    for key in pairs(row.active_skill_ids) do if key ~= 1 then return false end end
    if row.passive_skill_ids ~= nil and (type(row.passive_skill_ids) ~= "table"
        or next(row.passive_skill_ids) ~= nil) then return false end
    local ok, result = pcall(function()
        local kv = custom_abilities()
        return contracts.is_bare_creature(unit_name) and kv and fusion_kv(kv[expected])
    end)
    return ok and result == true
end
function M.omit_new(unit, id, row, fresh_training)
    if fresh_training ~= true or not M.is_training_candidate(id, row, "npc_survival_lumberjack") then
        return false
    end
    local ok, result = pcall(function()
        if not unit or unit:IsNull() ~= false or unit:GetUnitName() ~= "npc_survival_lumberjack"
            or unit:GetClassname() ~= "npc_dota_creature" or unit:IsRealHero() ~= false
            or unit.survival_super_lumberjack or unit.survival_commerce_immortal
            or unit.survival_worker_type ~= nil or unit[FLAG] ~= nil
            or unit:HasModifier(CAP) ~= false then return false end
        local maximum = GameRules:GetGameModeEntity():GetMaximumAttackSpeed()
        if type(maximum) ~= "number" or maximum ~= maximum
            or maximum < 7 or maximum == math.huge then return false end
        -- Reject unknown spawn auras/intrinsics, including an already present IAS buff.
        local modifiers = unit:FindAllModifiers()
        if type(modifiers) ~= "table" or #modifiers > 64 then return false end
        for _, modifier in pairs(modifiers) do
            if not modifier or modifier:IsNull()
                or modifier:GetName() ~= "modifier_single_health_bar" then return false end
        end
        local count, seen = unit:GetAbilityCount(), false
        if type(count) ~= "number" or count ~= count or count < 1
            or count > 64 or count ~= math.floor(count) then return false end
        for slot = 0, count - 1 do
            local ability = unit:GetAbilityByIndex(slot)
            if ability and not ability:IsNull() then
                if ability:GetAbilityName() == allowed[id] then
                    if seen or ability:IsPassive() ~= false or ability:GetLevel() ~= 1
                        or ability:GetIntrinsicModifierName() ~= nil
                        or not fusion_kv(ability:GetAbilityKeyValues()) then return false end
                    seen = true
                elseif not contracts.is_inert_native_warp(ability, slot) then return false end
            end
        end
        return seen
    end)
    if ok and result == true then unit[FLAG] = true; return true end
    return false
end
-- Old/unknown/immortal entities never gain a new cap through this helper.
-- Leave the marker on failure so a later genuine application may retry.
function M.restore(unit)
    if not unit or unit[FLAG] ~= true then return true end
    if unit:IsNull() then return false end
    if not unit:HasModifier(CAP) then unit:AddNewModifier(unit, nil, CAP, {}) end
    if not unit:HasModifier(CAP) then return false end
    unit[FLAG] = nil
    return true
end
function M.restore_or_error(unit)
    if not M.restore(unit) then error("worker_attack_cap_restore_failed", 2) end
end
return M
