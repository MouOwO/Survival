local scheduler = require("core/scheduler")
local armor_balance = require("config/armor_balance")

local M = {}

local ARMOR_VALUES = { 0, 25, 50, 100, 150, 200, 224, 225, 250 }
local DAMAGE_CASES = {
    { name = "physical", damage_type = DAMAGE_TYPE_PHYSICAL },
    { name = "magical", damage_type = DAMAGE_TYPE_MAGICAL },
    { name = "pure", damage_type = DAMAGE_TYPE_PURE },
}
local TEST_DAMAGE = 1000
local TEST_HEALTH = 100000
local active_units = {}
local generation = 0

local function valid(unit)
    return unit and not unit:IsNull()
end

local function remove(unit)
    if not valid(unit) then return end
    if UTIL_Remove then
        UTIL_Remove(unit)
    elseif unit.ForceKill then
        unit:ForceKill(false)
    end
end

local function clear()
    generation = generation + 1
    for _, unit in ipairs(active_units) do remove(unit) end
    active_units = {}
end

local function create_unit(origin, team)
    local unit = CreateUnitByName(
        "npc_survival_wave_monster",
        origin,
        true,
        nil,
        nil,
        team
    )
    if not valid(unit) then return nil end
    active_units[#active_units + 1] = unit
    FindClearSpaceForUnit(unit, origin, true)
    unit:SetBaseMaxHealth(TEST_HEALTH)
    unit:SetMaxHealth(TEST_HEALTH)
    unit:SetHealth(TEST_HEALTH)
    unit:SetBaseDamageMin(0)
    unit:SetBaseDamageMax(0)
    unit:SetBaseMoveSpeed(0)
    unit:SetMoveCapability(DOTA_UNIT_CAP_MOVE_NONE)
    unit:SetAttackCapability(DOTA_UNIT_CAP_NO_ATTACK)
    if unit.SetBaseMagicalResistanceValue then
        unit:SetBaseMagicalResistanceValue(0)
    end
    return unit
end

local function run_case(token, attacker, target, requested_armor, damage_case)
    if token ~= generation or not valid(attacker) or not valid(target) then return end
    target:SetHealth(TEST_HEALTH)
    local base_armor = tonumber(target:GetPhysicalArmorBaseValue())
    local effective_armor = tonumber(target:GetPhysicalArmorValue(false))
    local before = tonumber(target:GetHealth()) or TEST_HEALTH
    local returned = ApplyDamage({
        attacker = attacker,
        victim = target,
        damage = TEST_DAMAGE,
        damage_type = damage_case.damage_type,
        damage_flags = 0,
    })
    local after = tonumber(target:GetHealth()) or before
    local health_loss = math.max(0, before - after)
    print(string.format(
        "[ARMOR_ENGINE_DIAGNOSTIC] requested_armor=%s base_armor=%s "
            .. "effective_armor=%s damage_type=%s submitted=%s "
            .. "apply_return=%s health_loss=%s candidate_reduction_pct=%s",
        tostring(requested_armor),
        tostring(base_armor),
        tostring(effective_armor),
        damage_case.name,
        tostring(TEST_DAMAGE),
        tostring(returned),
        tostring(health_loss),
        tostring(armor_balance.modern_physical_reduction_pct(
            effective_armor
        ))
    ))
end

function M.run(options)
    options = options or {}
    clear()
    local token = generation
    local origin = options.origin or Vector(-1280, 1088, 64)
    local attacker = create_unit(origin + Vector(-300, 0, 0), DOTA_TEAM_GOODGUYS)
    if not attacker then return false, "diagnostic_attacker_create_failed" end

    local targets = {}
    for index, armor in ipairs(ARMOR_VALUES) do
        local row = math.floor((index - 1) / 3)
        local column = (index - 1) % 3
        local target = create_unit(
            origin + Vector(column * 180, row * 180, 0),
            DOTA_TEAM_BADGUYS
        )
        if not target then
            clear()
            return false, "diagnostic_target_create_failed"
        end
        target:SetPhysicalArmorBaseValue(armor)
        targets[#targets + 1] = { unit = target, armor = armor }
    end

    local sequence = 0
    for _, target in ipairs(targets) do
        for _, damage_case in ipairs(DAMAGE_CASES) do
            sequence = sequence + 1
            scheduler.after(0.2 + sequence * 0.08, function()
                run_case(token, attacker, target.unit, target.armor, damage_case)
            end, "armor_engine_diagnostic:" .. tostring(sequence))
        end
    end
    scheduler.after(0.5 + sequence * 0.08, function()
        if token ~= generation then return end
        print("[ARMOR_ENGINE_DIAGNOSTIC] complete=true cases="
            .. tostring(sequence))
        clear()
    end, "armor_engine_diagnostic:cleanup")
    return true, { armor_count = #targets, case_count = sequence }
end

function M.clear()
    clear()
end

return M