-- Load the real ability classes: passive skills retain their intrinsic effects
-- and provide no Lua cast entry point, including Monkey King's fourth skill.
package.path = "scripts/vscripts/?.lua;" .. package.path

local definitions = require("config/generated/hero_skill_definitions")
class = function(methods) return methods end
package.preload["systems/tower_fusion_service"] = function()
    error("passive hero ability classes must not load the old teleport action")
end
require("abilities/survival_hero_skill")

local count = 0
for _, definition in ipairs(definitions.rows) do
    if definition.enabled ~= false and definition.skill_type == "passive" then
        local ability_class = assert(_G[definition.ability_name],
            "missing ability class: " .. definition.ability_name)
        assert(ability_class:GetIntrinsicModifierName() == "modifier_survival_hero_skill",
            "passive intrinsic effects must remain installed: " .. definition.ability_name)
        assert(ability_class.OnSpellStart == nil,
            "passive hero skill must not expose a cast action: " .. definition.ability_name)
        count = count + 1
    end
end

local monkey_r = assert(definitions.by_id.skill_monkey_king_agility)
assert(monkey_r.skill_type == "passive", "Monkey King's fourth skill must be passive")
assert(_G[monkey_r.ability_name].OnSpellStart == nil,
    "Monkey King's fourth skill must not trigger tower teleportation")
assert(package.loaded["systems/tower_fusion_service"] == nil,
    "passive hero abilities must leave the old teleport action unloaded")
assert(count > 0, "expected enabled passive hero ability classes")
print("HERO_PASSIVE_ABILITY_CLASS_PASS: " .. count
    .. " passive classes preserve intrinsic effects and expose no cast action")
