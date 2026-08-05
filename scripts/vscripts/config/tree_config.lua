local armor_balance = require("config/armor_balance")
local global_rules = require("config/global_rules")
local world_visuals = require("config/generated/world_visual_definitions")

local tree_asset = assert(
    (world_visuals.by_id or {}).world_resource_tree,
    "world_visual_definitions.csv must define world_resource_tree"
)

local source_levels = {
    { level = 1, health = 100000, war3_armor = -2, war3_minimum_armor = -2 },
    { level = 2, health = 103000, war3_armor = 5, war3_minimum_armor = 5 },
    { level = 3, health = 203000, war3_armor = 10, war3_minimum_armor = 10 },
    { level = 4, health = 303000, war3_armor = 15, war3_minimum_armor = 15 },
    { level = 5, health = 403000, war3_armor = 20, war3_minimum_armor = 20 },
    { level = 6, health = 503000, war3_armor = 25, war3_minimum_armor = 25 },
    { level = 7, health = 603000, war3_armor = 30, war3_minimum_armor = 30 },
    { level = 8, health = 703000, war3_armor = 35, war3_minimum_armor = 35 },
    { level = 9, health = 803000, war3_armor = 40, war3_minimum_armor = 40 },
    { level = 10, health = 906000, war3_armor = 90, war3_minimum_armor = 90 },
    { level = 11, health = 2806000, war3_armor = 95, war3_minimum_armor = 95 },
    { level = 12, health = 3006000, war3_armor = 100, war3_minimum_armor = 99 },
    { level = 13, health = 4906000, war3_armor = 105, war3_minimum_armor = 99 },
    { level = 14, health = 5806000, war3_armor = 110, war3_minimum_armor = 99 },
    { level = 15, health = 6806000, war3_armor = 115, war3_minimum_armor = 99 },
    { level = 16, health = 7806000, war3_armor = 120, war3_minimum_armor = 99 },
    { level = 17, health = 8806000, war3_armor = 125, war3_minimum_armor = 99 },
    { level = 18, health = 9806000, war3_armor = 130, war3_minimum_armor = 99 },
    { level = 19, health = 10806000, war3_armor = 135, war3_minimum_armor = 99 },
    { level = 20, health = 32612000, war3_armor = 280, war3_minimum_armor = 99 },
    { level = 21, health = 32612000, war3_armor = 285, war3_minimum_armor = 99 },
    { level = 22, health = 43612000, war3_armor = 290, war3_minimum_armor = 99 },
    { level = 23, health = 63612000, war3_armor = 295, war3_minimum_armor = 99 },
    { level = 24, health = 63612000, war3_armor = 300, war3_minimum_armor = 99 },
    { level = 25, health = 73612000, war3_armor = 305, war3_minimum_armor = 99 },
    { level = 26, health = 83612000, war3_armor = 310, war3_minimum_armor = 99 },
    { level = 27, health = 93612000, war3_armor = 315, war3_minimum_armor = 99 },
    { level = 28, health = 103600000, war3_armor = 320, war3_minimum_armor = 99 },
    { level = 29, health = 113600000, war3_armor = 325, war3_minimum_armor = 99 },
    { level = 30, health = 247200000, war3_armor = 660, war3_minimum_armor = 99 },
}

local levels = {}
for _, row in ipairs(source_levels) do
    levels[row.level] = {
        level = row.level,
        health = row.health,
        war3_armor = row.war3_armor,
        armor = armor_balance.from_war3(row.war3_armor),
        war3_minimum_armor = row.war3_minimum_armor,
        minimum_armor = armor_balance.from_war3(row.war3_minimum_armor),
    }
end

local M = {
    unit_name = "enemy_tree",
    model_name = tree_asset.model_name,
    model_scale = tree_asset.model_scale,
    spawn_point = {
        x = tree_asset.spawn_x,
        y = tree_asset.spawn_y,
        z = tree_asset.spawn_z,
    },
    footprint = { x = 2, y = 2 },
    grid_cell_size = 64,
    max_level = #source_levels,
    levels = levels,
    lumber_efficiency_buff_per_level = global_rules.number(
        "tree_lumber_efficiency_buff_per_level",
        1
    ),
    hero_base_lumber_efficiency = global_rules.number(
        "hero_base_lumber_efficiency",
        13
    ),
}

return M
