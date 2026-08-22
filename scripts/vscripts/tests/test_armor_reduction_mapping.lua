package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;"
    .. package.path

function class(definition) return definition or {} end
function IsServer() return true end
MODIFIER_ATTRIBUTE_PERMANENT = 1
MODIFIER_PROPERTY_PHYSICAL_ARMOR_BONUS = 2

package.loaded["core/scheduler"] = {
    after = function() return "test_task" end,
}
package.loaded["core/event_bus"] = {
    emit = function() end,
}

local armor_balance = require("config/armor_balance")
require("modifiers/modifier_research_technology")

local function close(actual, expected, label, epsilon)
    assert(math.abs((tonumber(actual) or 0) - expected) < (epsilon or 0.011),
        string.format("%s: expected %.6f, got %s",
            label, expected, tostring(actual)))
end

local function fixture(options)
    options = options or {}
    local modifier = setmetatable({ stack = 0 }, {
        __index = modifier_research_armor_reduction,
    })
    local parent = {
        survival_armor_mapping_version = options.mapping_version,
        survival_war3_armor = options.war3_armor,
        survival_minimum_war3_armor = options.minimum_war3_armor,
        survival_minimum_armor = options.minimum_armor,
    }
    local base_runtime = options.runtime_armor
        or armor_balance.from_war3_modern(options.war3_armor or 0)
    function parent:IsNull() return false end
    function parent:entindex() return 42 end
    function parent:GetPhysicalArmorValue()
        return base_runtime - modifier.stack / 100
    end
    function modifier:GetParent() return parent end
    function modifier:GetStackCount() return self.stack end
    function modifier:SetStackCount(value) self.stack = value end
    return modifier, parent, base_runtime
end

local modern, modern_parent, modern_base = fixture({
    mapping_version = armor_balance.MODERN_MAPPING_VERSION,
    war3_armor = 675,
})
modern:OnCreated({ armor_reduction_per_attack = 1 })
close(modern.war3_armor_reduction, 3,
    "one runtime point becomes three War3 reduction", 0.0001)
close(modern_parent.survival_effective_war3_armor, 672,
    "modern effective War3 armor", 0.0001)
close(modern:GetModifierPhysicalArmorBonus(),
    armor_balance.from_war3_modern(672) - modern_base,
    "modern modifier exposes remapped Dota delta")
modern:OnRefresh({ armor_reduction_per_attack = 1 })
close(modern.war3_armor_reduction, 6,
    "modern reduction accumulates in War3 domain", 0.0001)
close(modern_parent.survival_effective_war3_armor, 669,
    "modern repeated effective War3 armor", 0.0001)

local unrestricted, unrestricted_parent = fixture({
    mapping_version = armor_balance.MODERN_MAPPING_VERSION,
    war3_armor = 3,
})
unrestricted:OnCreated({ armor_reduction_per_attack = 1 })
unrestricted:OnRefresh({ armor_reduction_per_attack = 1 })
close(unrestricted_parent.survival_effective_war3_armor, -3,
    "modern monster without floor can reach negative armor", 0.0001)
assert(unrestricted:GetModifierPhysicalArmorBonus() < -1,
    "negative effective armor did not produce sufficient runtime reduction")

local floored, floored_parent = fixture({
    mapping_version = armor_balance.MODERN_MAPPING_VERSION,
    war3_armor = 105,
    minimum_war3_armor = 100,
})
floored:OnCreated({ armor_reduction_per_attack = 1 })
floored:OnRefresh({ armor_reduction_per_attack = 1 })
close(floored.war3_armor_reduction, 5,
    "modern reduction stops at explicit War3 floor", 0.0001)
close(floored_parent.survival_effective_war3_armor, 100,
    "modern explicit War3 floor", 0.0001)

local custom, custom_parent = fixture({
    mapping_version = armor_balance.CUSTOM_WAR3_MAPPING_VERSION,
    war3_armor = 3,
    runtime_armor = 0,
})
custom:OnCreated({ armor_reduction_per_attack = 1 })
custom:OnRefresh({ armor_reduction_per_attack = 1 })
close(custom_parent.survival_effective_war3_armor, -3,
    "custom monster keeps negative War3 state", 0.0001)
close(custom:GetModifierPhysicalArmorBonus(), 0,
    "custom monster never projects reduction to Dota armor", 0.0001)

local legacy = fixture({
    mapping_version = 1,
    runtime_armor = 10,
})
legacy:OnCreated({ armor_reduction_per_attack = 1 })
legacy:OnRefresh({ armor_reduction_per_attack = 1 })
close(legacy:GetModifierPhysicalArmorBonus(), -2,
    "legacy units keep additive runtime reduction", 0.0001)

print("ARMOR_REDUCTION_MAPPING_PASS")