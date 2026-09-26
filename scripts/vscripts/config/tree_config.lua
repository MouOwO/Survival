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
        10
    ),
}

local layout
if GetMapName and GetMapName() == "survival_c6" then
    layout = require("config/map_layouts/survival_c6")
elseif GetMapName and GetMapName() == "template_map" then
    layout = require("config/map_layouts/template_map")
end
if layout then M.spawn_point = layout.resource_tree end

local bounds = layout and layout.build_bounds
M.region_center = {
    x = bounds and (bounds.min_x + bounds.max_x) / 2 or 0,
    y = bounds and (bounds.min_y + bounds.max_y) / 2 or 0,
}
-- Rotate the existing northeast tree location with the four island courts.
-- Reserve four separate fixed sockets per court for players sharing a base.
M.spawn_regions = {}
local region_ids = { "northeast", "southeast", "southwest", "northwest" }
local offsets = { {0, 0}, {-192, 0}, {0, -192}, {-192, -192} }
for rotation, region_id in ipairs(region_ids) do
    local points = {}
    for _, offset in ipairs(offsets) do
        local x = M.spawn_point.x - M.region_center.x + offset[1]
        local y = M.spawn_point.y - M.region_center.y + offset[2]
        for _ = 2, rotation do x, y = y, -x end
        points[#points + 1] = {
            x = M.region_center.x + x, y = M.region_center.y + y,
            z = M.spawn_point.z,
        }
    end
    M.spawn_regions[region_id] = points
end

return M
