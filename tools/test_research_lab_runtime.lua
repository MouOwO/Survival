package.path = table.concat({
    "scripts/vscripts/?.lua",
    "scripts/vscripts/?/init.lua",
    package.path,
}, ";")

package.preload["core/event_bus"] = function()
    return { request = function() return nil end }
end

local builder = require("ui/ability_runtime_builder")
local config = require("config/research_technology_config")

local function check(value, message)
    if not value then error(message, 2) end
end

local state = {
    research_levels = {},
    research_transaction = { researching = 0 },
}
local rich = { wood = 999999, gold = 999999, population = 0, max_population = 100 }

local city = builder.build("ability_upgrade_city", { level = 1 }, rich)
check(city ~= nil and city.fields ~= nil, "CITY_UPGRADE_RUNTIME_MISSING")
for _, field in ipairs(city.fields) do
    check(field.label ~= "生命" and field.label ~= "护甲",
        "CITY_UPGRADE_HIDDEN_FIELD_PRESENT")
end

local wall_upgrade = builder.build("ability_upgrade_wall", { level = 1 }, rich)
local wall_fields = {}
for _, field in ipairs(wall_upgrade.fields or {}) do wall_fields[field.label] = true end
check(wall_fields["生命"] == true and wall_fields["护甲"] == true,
    "BUILDING_UPGRADE_DEFAULT_FIELDS_MISSING")

local speed = builder.build("ability_research_lumberjack_speed", state, rich)
check(speed.research_upgrade == 1, "RESEARCH_RUNTIME_IDENTITY_MISSING")
check(speed.display_name == "研究伐木工攻速",
    "RESEARCH_RUNTIME_DISPLAY_NAME_INVALID")
check(speed.current_level == 0 and speed.next_level == 1 and speed.max_level == 10,
    "RESEARCH_RUNTIME_LEVELS_INVALID")
check(speed.cost_wood == 200 and speed.cost_gold == 0,
    "RESEARCH_RUNTIME_LEVEL1_COST_INVALID")
check(speed.research_effect_current == 0 and speed.research_effect_next == 0.05,
    "RESEARCH_RUNTIME_EFFECT_INVALID")
check(speed.available == 1 and speed.can_afford == 1,
    "RESEARCH_RUNTIME_AVAILABLE_INVALID")
check(speed.fields[1].label == "等级上限"
        and speed.fields[2].label == "当前累计"
        and speed.fields[3].label == "升级后累计"
        and speed.fields[4].label == "前置条件",
    "RESEARCH_RUNTIME_TOOLTIP_FIELDS_INVALID")
for _, field in ipairs(speed.fields) do
    check(field.label ~= "科技编号", "RESEARCH_RUNTIME_TECHNOLOGY_ID_VISIBLE")
end

state.research_levels.lumberjack_speed = 4
speed = builder.build("ability_research_lumberjack_speed", state, rich)
check(speed.next_level == 5 and speed.cost_wood == 1800,
    "RESEARCH_RUNTIME_NEXT_COST_INVALID")
check(speed.research_effect_current == 0.20 and speed.research_effect_next == 0.25,
    "RESEARCH_RUNTIME_CUMULATIVE_EFFECT_INVALID")

local poor = { wood = 1799, gold = 0, population = 0, max_population = 100 }
speed = builder.build("ability_research_lumberjack_speed", state, poor)
check(speed.available == 1 and speed.can_afford == 0,
    "RESEARCH_RUNTIME_RESOURCE_STATE_INVALID")

state.research_transaction = {
    researching = 1,
    research_group = "lumberjack_speed",
    research_target_level = 5,
}
speed = builder.build("ability_research_lumberjack_speed", state, rich)
check(speed.available == 0 and speed.research_status_code == "researching_current",
    "RESEARCH_RUNTIME_CURRENT_LOCK_INVALID")
local wall = builder.build("ability_research_wall_health", state, rich)
check(wall.available == 0 and wall.research_status_code == "researching_other",
    "RESEARCH_RUNTIME_TEAM_LOCK_INVALID")

state.research_transaction = { researching = 0 }
state.research_levels.lumberjack_speed = config.by_legacy_group.lumberjack_speed.max_level
speed = builder.build("ability_research_lumberjack_speed", state, rich)
check(speed.available == 0 and speed.can_afford == 0
        and speed.research_status_code == "max_level",
    "RESEARCH_RUNTIME_MAX_LEVEL_INVALID")
check(speed.cost_wood == 0 and speed.cost_gold == 0,
    "RESEARCH_RUNTIME_MAX_LEVEL_COST_PRESENT")
check(speed.display_name == "研究伐木工攻速" and speed.fields ~= nil,
    "RESEARCH_RUNTIME_MAX_LEVEL_TOOLTIP_INVALID")
check(speed.research_slot_order == 1
        and speed.research_building_id == "building_research_lab"
        and speed.technology_group == "lumberjack_speed",
    "RESEARCH_RUNTIME_MAX_LEVEL_SLOT_IDENTITY_INVALID")

print("RESEARCH_LAB_RUNTIME_LUA51_PASS")