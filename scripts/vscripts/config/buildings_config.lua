local building_levels = require("config/generated/building_levels")
local building_definitions = require("config/generated/building_definitions")
local construction_rules = require(
    "config/generated/building_construction_rules"
)

local M = {}

local function definition_row(building_id)
    return (building_definitions.by_id or {})[building_id] or {}
end

local function configured_name(building_id, fallback)
    local row = definition_row(building_id)
    return row.name or fallback
end

local function configured_unit_name(building_id, fallback)
    local row = definition_row(building_id)
    local value = row.unit_name
    if type(value) == "string" and string.match(value, "^[%a_][%w_]*$") then
        return value
    end
    return fallback
end

local function apply_construction(definition, source_id)
    local row = (construction_rules.by_id or {})[source_id]
        or definition_row(source_id)
    definition.build_time = tonumber(row.build_time) or 3
    definition.build_particle = row.build_particle
        or "particles/items_fx/repair_kit.vpcf"
    definition.build_cast_range = tonumber(row.build_cast_range) or 200
    return definition
end

local function level_rows(building_id)
    local result = {}
    for _, row in ipairs(building_levels.rows or {}) do
        if row.enabled ~= false and row.building_id == building_id then
            result[row.level] = {
                level = row.level,
                display_name = row.display_name,
                health = row.health,
                armor = row.armor,
                requires_city_level = row.requires_city_level,
                prerequisite_text = row.prerequisite_text,
                model_name = row.model_name,
                add_population = row.population_add,
                wood_cost = row.wood_cost or 0,
                gold_cost = row.gold_cost or 0,
                upgrade_cost = row.level > 1 and {
                    wood = row.wood_cost or 0,
                    gold = row.gold_cost or 0,
                } or nil,
            }
        end
    end
    return result
end

local function build_cost(building_id, fallback_wood, fallback_gold)
    local level_one = level_rows(building_id)[1] or {}
    return {
        wood = level_one.wood_cost or fallback_wood or 0,
        gold = level_one.gold_cost or fallback_gold or 0,
    }
end

local wall_levels = level_rows("building_wall")
M.wall = {
    id = "wall", display_name = configured_name("wall", "城墙"),
    unit_name = configured_unit_name("wall", "building_wall"),
    build_cost = build_cost("building_wall", 100, 0),
    footprint = { x = 2, y = 2 }, max_count = 1, build_once = true,
    show_health_bar = true, selectable = true,
    abilities = { "ability_upgrade_wall" }, levels = wall_levels,
}

M.main_city = {
    id = "main_city", display_name = configured_name("main_city", "主城"),
    unit_name = configured_unit_name("main_city", "building_main_city"),
    build_cost = build_cost("building_main_city", 100, 50),
    footprint = { x = 2, y = 2 },
    max_count = 1, show_health_bar = false, selectable = true,
    abilities = {
        "ability_upgrade_city",
        "ability_train_lumberjack",
        "ability_train_repairer",
    },
    levels = level_rows("building_main_city"),
}

local farm_levels = level_rows("building_farm")
farm_levels[1] = farm_levels[1] or {}
farm_levels[1].health = farm_levels[1].health or 2500
farm_levels[1].armor = farm_levels[1].armor or 5
M.building_farm = {
    id = "building_farm", display_name = configured_name("building_farm", "人口农场"),
    unit_name = configured_unit_name("building_farm", "building_farm"),
    build_cost = build_cost("building_farm", 100, 0),
    footprint = { x = 2, y = 2 }, max_count = 0,
    unlock_city_level = 1, show_health_bar = true, selectable = true,
    abilities = {
        "ability_upgrade_farm",
        "ability_train_population",
    },
    levels = farm_levels,
}

M.arrow_tower = {
    id = "arrow_tower", display_name = configured_name("arrow_tower", "防御塔"),
    unit_name = configured_unit_name("arrow_tower", "building_arrow_tower"),
    build_cost = build_cost("building_arrow_tower", 80, 20),
    footprint = { x = 2, y = 2 }, max_count = 0,
    show_health_bar = false, selectable = true, abilities = {
        "ability_upgrade_tower_lv01",
        "ability_upgrade_tower_max",
    },
    pre_class_levels = {
        [1] = { health = 1500, armor = 5, damage = 172, attack_range = 600, attack_rate = 1.0, upgrade_cost = { wood = 50, gold = 0 } },
        [2] = { health = 2000, armor = 6, damage = 251, attack_range = 600, attack_rate = 1.0, upgrade_cost = { wood = 100, gold = 0 } },
        [3] = { health = 2500, armor = 7, damage = 301, attack_range = 625, attack_rate = 1.0, upgrade_cost = { wood = 200, gold = 0 } },
        [4] = { health = 3000, armor = 8, damage = 401, attack_range = 650, attack_rate = 0.95, upgrade_cost = { wood = 250, gold = 0 } },
        [5] = { health = 3500, armor = 9, damage = 501, attack_range = 675, attack_rate = 0.9, upgrade_cost = { wood = 300, gold = 0 } },
    },
    class_change_cost = { wood = 100, gold = 50 },
    class_options = {
        [1] = { id = "class_1", display_name = "【N】死亡之塔", ability = "ability_tower_class_1" },
        [2] = { id = "class_2", display_name = "【N】神秘之塔", ability = "ability_tower_class_2" },
        [3] = { id = "class_3", display_name = "【N】闪电塔", ability = "ability_tower_class_3" },
        [4] = { id = "class_4", display_name = "【N】机枪塔", ability = "ability_tower_class_4" },
        [5] = { id = "class_5", display_name = "【N】多重塔", ability = "ability_tower_class_5" },
        [6] = { id = "class_6", display_name = "【N】冰霜之塔", ability = "ability_tower_class_6" },
    [7] = { id = "class_7", display_name = "【N】魔法塔", ability = "ability_tower_class_7" },
    },
}

local research_lab_levels = level_rows("building_research_lab")
research_lab_levels[1] = research_lab_levels[1] or {}
research_lab_levels[1].health = research_lab_levels[1].health or 2500
research_lab_levels[1].armor = research_lab_levels[1].armor or 8
M.building_research_lab = {
    id = "building_research_lab",
    display_name = configured_name("building_research_lab", "研究所"),
    unit_name = configured_unit_name(
        "building_research_lab",
        "building_research_lab"
    ),
    build_cost = build_cost("building_research_lab", 0, 0),
    footprint = { x = 2, y = 2 },
    max_count = 1,
    unlock_city_level = 1,
    show_health_bar = false,
    selectable = true,
    abilities = {},
    levels = research_lab_levels,
}

M.gold_mine = { id = "gold_mine", display_name = configured_name("gold_mine", "金矿"), unit_name = configured_unit_name("gold_mine", "building_gold_mine"), build_cost = build_cost("building_gold_mine", 2000, 0), footprint = { x = 2, y = 2 }, max_count = 5, population_cost = 2, unlock_city_level = 3, show_health_bar = true, selectable = true, abilities = { "ability_upgrade_gold_mine", "ability_upgrade_gold_mine_efficiency", "ability_upgrade_gold_mine_crit", "ability_gold_mine_auto_upgrade", "ability_gold_mine_stop_auto_upgrade" }, levels = level_rows("building_gold_mine") }
M.hero_altar = { id = "hero_altar", display_name = configured_name("hero_altar", "英雄祭坛"), unit_name = configured_unit_name("hero_altar", "building_hero_altar"), build_cost = build_cost("building_hero_altar", 300, 100), footprint = { x = 2, y = 2 }, max_count = 1, unlock_city_level = 3, show_health_bar = false, selectable = true, abilities = { "ability_summon_axe", "ability_summon_slark", "ability_summon_juggernaut", "ability_summon_monkey_king", "ability_summon_blademaster", "ability_enter_endless_training", "ability_enter_shadow_realm" }, levels = { [1] = { health = 2500, armor = 8 } } }

M.wall = apply_construction(M.wall, "wall")
M.main_city = apply_construction(M.main_city, "main_city")
M.building_farm = apply_construction(M.building_farm, "building_farm")
-- 兼容仍持有旧模块缓存或旧建造请求的测试会话；新代码统一使用 building_farm。
M.farm = M.building_farm
M.arrow_tower = apply_construction(M.arrow_tower, "arrow_tower")
M.building_research_lab = apply_construction(
    M.building_research_lab,
    "building_research_lab"
)
M.gold_mine = apply_construction(M.gold_mine, "gold_mine")
M.hero_altar = apply_construction(M.hero_altar, "hero_altar")
return M
