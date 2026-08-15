package.path = table.concat({
    "scripts/vscripts/?.lua",
    "scripts/vscripts/?/init.lua",
    package.path,
}, ";")

local sync = require("systems/research_lab_ability_sync")
local config = require("config/research_technology_config")

local function check(value, message)
    if not value then error(message, 2) end
end

local function ability(name)
    local instance = {
        name = name,
        level = 0,
        hidden = true,
        activated = false,
        index = -1,
    }
    function instance:SetLevel(value) self.level = value end
    function instance:SetHidden(value) self.hidden = value end
    function instance:SetActivated(value) self.activated = value end
    function instance:SetAbilityIndex(value) self.index = value end
    return instance
end

local function unit()
    local instance = { abilities = {} }
    function instance:IsNull() return false end
    function instance:FindAbilityByName(name) return self.abilities[name] end
    function instance:AddAbility(name)
        self.abilities[name] = ability(name)
        return self.abilities[name]
    end
    function instance:RemoveAbility(name) self.abilities[name] = nil end
    return instance
end

local standard = unit()
sync.sync(standard, "building_research_lab", {}, { researching = 0 }, 0)
local initial = {
    "ability_research_lumberjack_speed",
    "ability_research_lumberjack_efficiency",
    "ability_research_tower_attack",
    "ability_research_wall_health",
    "ability_research_advanced_lumberjack_efficiency",
    "ability_research_lumberjack_crit",
}
for index, name in ipairs(initial) do
    local current = standard.abilities[name]
    local expected_active = name ~= "ability_research_advanced_lumberjack_efficiency"
    check(current and current.index == index - 1
            and current.activated == expected_active,
        "STANDARD_INITIAL_SLOT_INVALID_" .. tostring(index))
end

local levels = {
    lumberjack_speed = config.by_legacy_group.lumberjack_speed.max_level,
    lumberjack_efficiency = config.by_legacy_group.lumberjack_efficiency.max_level,
    tower_attack = config.by_legacy_group.tower_attack.max_level,
    wall_health = config.by_legacy_group.wall_health.max_level,
}
sync.sync(standard, "building_research_lab", levels, { researching = 0 }, 0)
local replacements = {
    [1] = "ability_research_advanced_lumberjack_speed",
    [3] = "ability_research_advanced_tower_attack",
    [4] = "ability_research_advanced_wall_health",
}
for slot, name in pairs(replacements) do
    local current = standard.abilities[name]
    check(current and current.index == slot - 1 and current.activated,
        "STANDARD_CHAIN_REPLACEMENT_INVALID_" .. tostring(slot))
end
check(standard.abilities.ability_research_lumberjack_speed == nil,
    "STANDARD_COMPLETED_BASE_ABILITY_PRESENT")
check(standard.abilities.ability_research_advanced_lumberjack_efficiency.activated,
    "STANDARD_FIXED_ADVANCED_EFFICIENCY_NOT_RELEASED")

levels.advanced_lumberjack_speed =
    config.by_legacy_group.advanced_lumberjack_speed.max_level
sync.sync(standard, "building_research_lab", levels, { researching = 0 }, 0)
check(standard.abilities.ability_research_advanced_lumberjack_speed ~= nil
        and not standard.abilities.ability_research_advanced_lumberjack_speed.activated,
    "STANDARD_COMPLETED_CHAIN_NOT_RETAINED_DISABLED")

sync.sync(standard, "building_research_lab", levels, { researching = 1 }, 0)
for _, current in pairs(standard.abilities) do
    check(current.activated == false, "STANDARD_RESEARCH_LOCK_NOT_APPLIED")
end

local advanced = unit()
sync.sync(advanced, "building_advanced_research_lab", {}, { researching = 0 }, 0)
for index = 1, 10 do
    local name = string.format("ability_research_ars_%02d", index)
    local current = advanced.abilities[name]
    check(current and current.index == index - 1,
        "ADVANCED_SLOT_INVALID_" .. tostring(index))
end
check(advanced.abilities.ability_research_ars_01.activated,
    "ADVANCED_AVAILABLE_ABILITY_DISABLED")
check(not advanced.abilities.ability_research_ars_03.activated,
    "ADVANCED_TECH_PREREQUISITE_IGNORED")
check(not advanced.abilities.ability_research_ars_08.activated,
    "ADVANCED_REBIRTH_PREREQUISITE_IGNORED")

local advanced_levels = {
    advanced_wall_health = 10,
    advanced_tower_attack = 10,
    researcher_lumberjack_attack_growth =
        config.by_legacy_group.researcher_lumberjack_attack_growth.max_level,
}
sync.sync(advanced, "building_advanced_research_lab", advanced_levels,
    { researching = 0 }, 3)
check(advanced.abilities.ability_research_ars_01 ~= nil
        and not advanced.abilities.ability_research_ars_01.activated,
    "ADVANCED_COMPLETED_ABILITY_NOT_RETAINED_DISABLED")
check(advanced.abilities.ability_research_ars_03.activated,
    "ADVANCED_TECH_PREREQUISITE_NOT_RELEASED")
check(advanced.abilities.ability_research_ars_08.activated,
    "ADVANCED_REBIRTH_PREREQUISITE_NOT_RELEASED")

print("RESEARCH_LAB_ABILITY_SYNC_LUA51_PASS")