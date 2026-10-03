package.path = "scripts/vscripts/?.lua;" .. package.path
class = function(value) return value end
IsServer = function() return true end
local published, attaches = {}, 0
CustomNetTables = {SetTableValue = function(_, _, key, value) published[key] = value end}
package.loaded["combat/endless_stat_projection"] = {for_ui = function(_, value) return value end}
package.loaded["core/modifier_registry"] = {ensure = function(unit)
    attaches = attaches + 1; unit.bar = true; return {}
end}
local service = require("systems/unit_health_bar_service")
local bar_class = require("modifiers/modifier_single_health_bar")
local function unit(index)
    return {
        entindex = function() return index end, IsNull = function() return false end,
        IsBaseNPC = function() return true end, AddNewModifier = function() end,
        GetClassname = function() return "npc_dota_hero_monkey_king" end,
        GetUnitName = function() return "npc_dota_hero_monkey_king" end,
        GetHealth = function() return 100 end, GetMaxHealth = function() return 100 end,
        IsAlive = function() return true end, GetTeamNumber = function() return 2 end,
        HasModifier = function(self, name)
            return (name == "modifier_single_health_bar" and self.bar)
                or (name == "modifier_native_wearable_visual_carrier" and self.visual_modifier)
        end,
        RemoveModifierByName = function(self) self.bar = nil end,
    }
end
local hero, carrier = unit(1), unit(2)
assert(service._attach_for_test(hero))
-- Spawn event arrives before the caller of CreateUnitByName marks the carrier.
assert(service._attach_for_test(carrier))
carrier.survival_is_native_wearable_visual = true
local bar = setmetatable({GetParent = function() return carrier end}, {__index = bar_class})
bar:publish_state()
assert(published.unit_2.removed == 1, "visual-only carrier published a health bar")
assert(service._clear_excluded_for_test(carrier))
assert(not carrier.bar and carrier.survival_hide_custom_health_bar)
assert(not service._attach_for_test(carrier), "respawn reattached the visual carrier bar")
assert(hero.bar and not published.unit_1, "combat hero bar must be retained")
local recovered = unit(3); recovered.visual_modifier = true
assert(service._clear_excluded_for_test(recovered))
assert(published.unit_3.removed == 1, "existing carrier modifier must also be excluded")
assert(attaches == 2)
print("VISUAL_CARRIER_HEALTH_BAR_PASS: spawn race, explicit cleanup, respawn, recovered carrier, hero retained")

-- Existing building projections must be cleared without affecting actual health
-- or the overhead bars on combat units and unrequested building types.
package.loaded["core/modifier_registry"].ensure = function(u, name)
    if name == "modifier_single_health_bar" then u.bar = true
    elseif name == "modifier_building_no_health_bar" then u.native_hidden = true
    else error("unexpected modifier: " .. name) end
    return {}
end
for index, name in ipairs({"building_main_city", "building_gold_mine",
    "building_challenge", "building_research_lab", "building_advanced_research_lab",
    "building_hero_altar", "building_farm"}) do
    local u = unit(10 + index)
    u.GetUnitName = function() return name end
    assert(not service._attach_for_test(u), "new building must not receive a custom bar")
    u.bar = true -- Existing published bar before applying the change.
    assert(service._clear_excluded_for_test(u))
    assert(not u.bar and u.native_hidden and u.survival_hide_custom_health_bar)
    assert(published["unit_" .. (10 + index)].removed == 1)
    assert(u:GetHealth() == 100 and u:GetMaxHealth() == 100)
    assert(not service._attach_for_test(u), "respawn must keep the bar hidden")
end
for index, name in ipairs({"building_wall", "building_arrow_tower",
    "npc_dota_hero_monkey_king", "npc_survival_worker", "npc_survival_monster"}) do
    local u = unit(30 + index)
    u.GetUnitName = function() return name end
    assert(not service._clear_excluded_for_test(u))
    assert(service._attach_for_test(u) and u.bar and not u.native_hidden)
end
print("BUILDING_HEALTH_BAR_SCOPE_PASS: seven hidden building types including farms; walls/towers/hero/workers/monsters retained")
