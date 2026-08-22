package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

function class(definition) return definition or {} end
function IsServer() return true end
MODIFIER_PROPERTY_PHYSICAL_ARMOR_BONUS = 1

local callbacks = {}
package.loaded["core/scheduler"] = {
    after = function(_, callback) callbacks[#callbacks + 1] = callback end,
}
package.loaded["core/event_bus"] = { emit = function() end }
package.loaded["core/events"] = { UNIT_COMBAT_STATS_CHANGED = "changed" }

local armor_balance = require("config/armor_balance")
local definition = require("modifiers/modifier_hero_poison_cloud_armor")

local parent = {
    survival_armor_mapping_version = armor_balance.CUSTOM_WAR3_MAPPING_VERSION,
    survival_war3_armor = 117,
    survival_effective_war3_armor = 117,
    survival_war3_armor_reduction = 0,
}
function parent:IsNull() return false end
function parent:entindex() return 42 end
function parent:GetPhysicalArmorValue() return 0 end

local modifier = setmetatable({ stack = 0 }, { __index = definition })
function modifier:GetParent() return parent end
function modifier:GetStackCount() return self.stack end
function modifier:SetStackCount(value) self.stack = value end

local function close(actual, expected, label)
    assert(math.abs((tonumber(actual) or 0) - expected) < 0.0001,
        string.format("%s: expected %.6f, got %s", label, expected, tostring(actual)))
end

modifier:OnCreated({ armor_per_stack_pct = 20, poison_stacks = 1 })
close(parent.survival_effective_war3_armor, 93.6, "one stack")
close(modifier:GetModifierPhysicalArmorBonus(), 0, "engine armor remains zero")

parent.survival_war3_armor_reduction = 17
modifier:OnRefresh({ armor_per_stack_pct = 20, poison_stacks = 3 })
close(parent.survival_effective_war3_armor, 40, "fixed reduction plus three stacks")

parent.survival_war3_armor_reduction = 130
modifier:OnRefresh({ armor_per_stack_pct = 20, poison_stacks = 3 })
close(parent.survival_effective_war3_armor, -20.8, "negative armor state")

modifier:OnDestroy()
close(parent.survival_effective_war3_armor, -13, "removal preserves fixed reduction")
assert(parent.survival_poison_cloud_armor_reduction_pct == nil,
    "poison percentage state was not cleared")

print("CUSTOM_MONSTER_POISON_ARMOR_PASS")