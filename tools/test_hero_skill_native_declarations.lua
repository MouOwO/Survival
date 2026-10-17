-- Pure Lua 5.1 regression. No game, native binding, timers or account writes.
package.path = "scripts/vscripts/?.lua;" .. package.path
local checks = 0
local function check(condition, message)
    checks = checks + 1
    assert(condition, message)
end
class = function() local result = {}; result.__index = result; return result end
MODIFIER_ATTRIBUTE_MULTIPLE = 2
local properties = {
    {"pre_attack_damage", "MODIFIER_PROPERTY_PREATTACK_BONUS_DAMAGE", "GetModifierPreAttack_BonusDamage"},
    {"health_bonus", "MODIFIER_PROPERTY_HEALTH_BONUS", "GetModifierHealthBonus"},
    {"strength_bonus", "MODIFIER_PROPERTY_STATS_STRENGTH_BONUS", "GetModifierBonusStats_Strength"},
    {"agility_bonus", "MODIFIER_PROPERTY_STATS_AGILITY_BONUS", "GetModifierBonusStats_Agility"},
    {"intellect_bonus", "MODIFIER_PROPERTY_STATS_INTELLECT_BONUS", "GetModifierBonusStats_Intellect"},
    {"armor_bonus", "MODIFIER_PROPERTY_PHYSICAL_ARMOR_BONUS", "GetModifierPhysicalArmorBonus"},
    {"attack_speed_bonus", "MODIFIER_PROPERTY_ATTACKSPEED_BONUS_CONSTANT", "GetModifierAttackSpeedBonus_Constant"},
    {"move_speed_bonus", "MODIFIER_PROPERTY_MOVESPEED_BONUS_CONSTANT", "GetModifierMoveSpeedBonus_Constant"},
    {"attack_range_bonus", "MODIFIER_PROPERTY_ATTACK_RANGE_BONUS", "GetModifierAttackRangeBonus"},
    {"health_regen", "MODIFIER_PROPERTY_HEALTH_REGEN_CONSTANT", "GetModifierConstantHealthRegen"},
    {"mana_regen", "MODIFIER_PROPERTY_MANA_REGEN_CONSTANT", "GetModifierConstantManaRegen"},
}
for index, entry in ipairs(properties) do _G[entry[2]] = 100 + index end
local original_definitions = require("config/generated/hero_skill_definitions")
local actual_rows, rows = {}, {}
for _, row in ipairs(original_definitions.rows) do
    rows[#rows + 1] = row
    if row.enabled ~= false and type(row.ability_name) == "string" and row.ability_name ~= "" then
        actual_rows[#actual_rows + 1] = row
    end
end
for _, entry in ipairs(properties) do
    rows[#rows + 1] = {ability_name = "test_stat_" .. entry[1], enabled = true,
        effect_type = entry[1], effect_value_per_level = 2.75}
end
rows[#rows + 1] = {ability_name = "test_disabled", enabled = false,
    effect_type = "pre_attack_damage", effect_value_per_level = 999}
rows[#rows + 1] = {ability_name = "test_future_effect", enabled = true,
    effect_type = "future_scripted_effect", effect_value_per_level = 999}
rows[#rows + 1] = {ability_name = "test_missing_effect", enabled = true}
package.loaded["config/generated/hero_skill_definitions"] = {rows = rows}
local modifier = require("modifiers/modifier_survival_hero_skill")
local function ability(name)
    local result = {name = name, level = 1, active = true, null = false,
        level_reads = 0, activation_reads = 0}
    function result:GetAbilityName() return self.name end
    function result:IsNull() return self.null end
    function result:GetLevel() self.level_reads = self.level_reads + 1; return self.level end
    function result:IsActivated() self.activation_reads = self.activation_reads + 1; return self.active end
    function result:SetLevel(value) self.level = value end
    function result:SetActivated(value) self.active = value end
    return result
end
local function instance(attached)
    local result = setmetatable({ability = attached}, modifier)
    function result:GetParent() return {} end
    function result:GetAbility() return self.ability end
    return result
end
local function legacy(result, label)
    check(#result == 11, label .. ": legacy declaration count")
    for index, entry in ipairs(properties) do
        check(result[index] == _G[entry[2]], label .. ": legacy property " .. entry[1])
    end
end

-- Real authored skills, including all proc and VIP exclusive paths, have no
-- contribution from any stat getter. Exercise activated and locked levels.
check(#actual_rows == 25, "review new authored skills before expanding the zero-stat proof")
for _, row in ipairs(actual_rows) do
    local attached = ability(row.ability_name)
    local unit = instance(attached)
    local declared = unit:DeclareFunctions() -- First native query, before OnCreated.
    check(#declared == 0, row.ability_name .. ": unnecessary native stat properties")
    check(attached.level_reads == 0 and attached.activation_reads == 0,
        "declaration used current skill level/activation")
    for _, state in ipairs({{0, true}, {1, true}, {5, true}, {50, true}, {1, false}}) do
        attached:SetLevel(state[1]); attached:SetActivated(state[2])
        for _, entry in ipairs(properties) do
            check(unit[entry[3]](unit) == 0, row.ability_name .. ": nonzero stat " .. entry[1])
        end
        check(unit:DeclareFunctions() == declared, "native declaration changed with skill level/activation")
    end
end

-- Future stat definitions still expose their actual effect and preserve the
-- existing level floor, immediate level updates, lock and activation behavior.
for index, entry in ipairs(properties) do
    local attached = ability("test_stat_" .. entry[1])
    attached:SetActivated(false)
    local unit = instance(attached)
    local declared = unit:DeclareFunctions()
    check(#declared == 1 and declared[1] == _G[entry[2]], "missing native property " .. entry[1])
    check(attached.level_reads == 0 and attached.activation_reads == 0, "declaration inspected dynamic values")
    check(unit[entry[3]](unit) == 0, "locked stat skill became active")
    attached:SetActivated(true)
    for _, level in ipairs({1, 4, 2, 0}) do
        attached:SetLevel(level)
        check(unit[entry[3]](unit) == 2.75 * math.max(1, level), "live stat level changed semantics")
        check(unit:DeclareFunctions() == declared, "level update changed native declaration")
    end
    for other_index, other in ipairs(properties) do
        if other_index ~= index then check(unit[other[3]](unit) == 0, "stat leaked across property types") end
    end
    attached:SetActivated(false)
    check(unit[entry[3]](unit) == 0, "deactivation retained cached stat value")
end

-- Native binding fallbacks commit on the instance, including a first query
-- made while GetAbility is not ready. A later valid ability cannot switch it.
for _, name in ipairs({"test_disabled", "test_future_effect", "test_missing_effect", "unknown_ability", ""}) do
    local unit = instance(ability(name))
    local declared = unit:DeclareFunctions(); legacy(declared, name)
    unit.ability = ability(actual_rows[1].ability_name)
    check(unit:DeclareFunctions() == declared, "unknown first declaration was upgraded later")
end
local unavailable = instance(nil)
local unavailable_declarations = unavailable:DeclareFunctions()
legacy(unavailable_declarations, "GetAbility not ready")
unavailable.ability = ability("test_stat_health_bonus")
check(unavailable:DeclareFunctions() == unavailable_declarations, "nil first declaration changed later")
local missing_method = instance(nil)
missing_method.GetAbility = false
legacy(missing_method:DeclareFunctions(), "GetAbility unavailable")
missing_method.GetAbility = function() return ability(actual_rows[1].ability_name) end
legacy(missing_method:DeclareFunctions(), "GetAbility restored after commitment")
for _, malformed in ipairs({false, 123, {}, {IsNull = function() return true end},
        {IsNull = function() error("stale native handle") end}}) do
    legacy(instance(malformed):DeclareFunctions(), "invalid native ability")
end
local invalid_name = ability(actual_rows[1].ability_name)
invalid_name.GetAbilityName = function() error("native name unavailable") end
legacy(instance(invalid_name):DeclareFunctions(), "invalid native ability name")
local throwing = instance(nil)
throwing.GetAbility = function() error("native GetAbility unavailable") end
legacy(throwing:DeclareFunctions(), "throwing native GetAbility")

-- MULTIPLE intrinsic modifiers share this class but never one decision/table.
local first, second = instance(ability("test_stat_attack_speed_bonus")), instance(ability("test_stat_health_bonus"))
local first_decl, second_decl = first:DeclareFunctions(), second:DeclareFunctions()
check(first_decl ~= second_decl and first_decl[1] ~= second_decl[1], "intrinsic instances share one declaration")
check(first:GetAttributes() == MODIFIER_ATTRIBUTE_MULTIPLE, "multiple intrinsic modifier contract changed")
modifier.GetParent = function() return {} end -- Engine-like methods visible on the class.
modifier.GetAbility = function() error("class declaration must not inspect an ability") end
legacy(modifier:DeclareFunctions(), "class-level diagnostic")
legacy(modifier:DeclareFunctions(), "repeated class-level diagnostic")
check(rawget(modifier, "survival_skill_declaration_decided") == nil,
    "class-level query contaminated every native instance")
check(rawget(modifier, "survival_skill_native_declarations") == nil, "shared class retained instance state")
check(first:DeclareFunctions() == first_decl and second:DeclareFunctions() == second_decl,
    "class query changed an existing instance")
print("hero_skill_native_declarations PASS checks=" .. checks .. " authored_zero_stat_skills=" .. #actual_rows)
