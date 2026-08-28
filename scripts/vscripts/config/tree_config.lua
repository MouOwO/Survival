local armor_balance = require("config/armor_balance")
local global_rules = require("config/global_rules")
local world_visuals = require("config/generated/world_visual_definitions")
local progression = require("config/generated/tree_progression")

local tree_asset = assert(
    (world_visuals.by_id or {}).world_resource_tree,
    "world_visual_definitions.csv must define world_resource_tree"
)

local source_levels = progression.rows

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
