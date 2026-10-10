-- BAT-only formal waves have no positive native-AS sources. Unknown contracts
-- keep the Lua cap. A future native-AS buff must revoke this contract or add
-- the cap before applying the buff; current attack speed is not this proof.
local M = {}
local unit_kv, bare_units, custom_warp_absent = nil, {}, nil
function M.init()
    bare_units = {}
    custom_warp_absent = nil
    local ok, values = pcall(LoadKeyValues, "scripts/npc/npc_units_custom.txt")
    unit_kv = ok and type(values) == "table" and (values.DOTAUnits or values) or false
end

-- Valve injects this native channelled teleport in slot zero. It has no
-- passive/intrinsic or attack-speed effects. Never generalize hidden/level1.
local WARP = "twin_gate_portal_warp"
local WARP_BEHAVIOR = "DOTA_ABILITY_BEHAVIOR_UNIT_TARGET | DOTA_ABILITY_BEHAVIOR_CHANNELLED | DOTA_ABILITY_BEHAVIOR_DONT_RESUME_ATTACK | DOTA_ABILITY_BEHAVIOR_DONT_CANCEL_CHANNEL | DOTA_ABILITY_BEHAVIOR_HIDDEN | DOTA_ABILITY_BEHAVIOR_IGNORE_SILENCE | DOTA_ABILITY_BEHAVIOR_ROOT_DISABLES | DOTA_ABILITY_BEHAVIOR_NOT_LEARNABLE"
local function native_warp(ability, slot)
    if slot ~= 0 or ability:GetAbilityName() ~= WARP or ability:GetClassname() ~= WARP
        or ability:GetAbilityType() ~= 0 or ability:IsPassive() ~= false
        or ability:IsHidden() ~= true or ability:GetLevel() ~= 1
        or ability:GetIntrinsicModifierName() ~= nil then return false end
    local kv = ability:GetAbilityKeyValues()
    if type(kv) ~= "table" or tonumber(kv.ID) ~= 8873 or tonumber(kv.MaxLevel) ~= 1
        or kv.AbilityBehavior ~= WARP_BEHAVIOR or kv.AbilityType ~= "ABILITY_TYPE_BASIC"
        or kv.ScriptFile ~= nil or kv.BaseClass ~= nil or kv.Modifiers ~= nil
        or kv.AbilitySpecial ~= nil or kv.AttackSpeed ~= nil or kv.BaseAttackSpeed ~= nil
        or type(kv.AbilityValues) ~= "table" then return false end
    local values = kv.AbilityValues
    if tonumber(values.animation_rate) ~= 0.8 or tonumber(values.stop_distance) ~= 500 then return false end
    for key in pairs(values) do
        if key ~= "animation_rate" and key ~= "stop_distance" then return false end
    end
    if custom_warp_absent == nil then
        local ok, custom = pcall(LoadKeyValues, "scripts/npc/npc_abilities_custom.txt")
        if not ok then custom = false end
        if type(custom) == "table" and custom.DOTAAbilities ~= nil then custom = custom.DOTAAbilities end
        custom_warp_absent = type(custom) == "table" and custom[WARP] == nil
    end
    return custom_warp_absent == true
end
local function bare_unit(name)
    if bare_units[name] ~= nil then return bare_units[name] end
    if unit_kv == nil then M.init() end
    local kv = unit_kv and unit_kv[name]
    local bare = type(kv) == "table" and kv.BaseClass == "npc_dota_creature"
        and tonumber(kv.ConsideredHero) == 0 and tonumber(kv.HasInventory) == 0
        and kv.BaseAttackSpeed == nil and kv.AttackSpeed == nil
    if bare then
        for key, value in pairs(kv) do
            if type(key) == "string" and key:match("^Ability%d+$") and value ~= "" then
                bare = false
                break
            end
        end
    end
    bare_units[name] = bare == true
    return bare_units[name]
end

-- Call once, only for a fresh formal spawn, after appearance and before AI.
-- Never remove an existing cap or use this for challenge/encounter creation.
function M.can_omit(unit, definition, fresh_formal_wave)
    if fresh_formal_wave ~= true or type(definition) ~= "table"
        or definition.native_attack_speed_policy ~= "bat_only_v1"
        or definition.enabled == false
        or (definition.passive_skill_ids ~= nil and
            (type(definition.passive_skill_ids) ~= "table" or next(definition.passive_skill_ids))) then
        return false
    end
    local ok, eligible = pcall(function()
        if not unit or unit:IsNull() ~= false or unit:GetUnitName() ~= definition.unit_name
            or unit:GetClassname() ~= "npc_dota_creature" or unit:IsRealHero() ~= false
            or unit:GetTeamNumber() ~= DOTA_TEAM_BADGUYS
            or unit:HasModifier("modifier_debug_attack_cap") ~= false then return false end
        local maximum = GameRules:GetGameModeEntity():GetMaximumAttackSpeed()
        -- Getter returns the native multiplier (7), not setter units (700).
        if type(maximum) ~= "number" or maximum ~= maximum
            or maximum < 7 or maximum == math.huge or not bare_unit(definition.unit_name) then return false end
        local count = unit:GetAbilityCount()
        if type(count) ~= "number" or count ~= count or count < 0 or count > 64
            or count ~= math.floor(count) then return false end
        for slot = 0, count - 1 do
            local ability = unit:GetAbilityByIndex(slot)
            if ability and not ability:IsNull() and not native_warp(ability, slot) then return false end
        end
        return true
    end)
    return ok and eligible == true
end
-- Shared pure checks; callers still own their separate birth/lifecycle contract.
M.is_bare_creature = bare_unit
M.is_inert_native_warp = native_warp
return M
