package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local levels = require("config/generated/wall_visual_levels")
local assets = require("config/generated/asset_catalog")
local buildings = require("config/buildings_config")

local expected_assets = {
    "wall_reference_wall_lv01", "wall_reference_wall_lv02",
    "wall_reference_wall_lv03", "wall_reference_wall_lv04",
    "wall_reference_wall_lv05", "wall_reference_wall_lv06",
    "wall_reference_wall_lv07", "wall_reference_wall_lv08",
    "wall_reference_wall_lv09", "wall_reference_wall_lv10",
}
local names={"原木","木石","青石","青铜","苍蓝","碧玉","赤铜","紫晶","白金","天辉晶冠"}
local romans={"Ⅰ","Ⅱ","Ⅲ"}
local shells=require("config/generated/building_white_shells")

assert(#levels.rows == 30, "wall visual configuration must contain levels 1-30")
assert(buildings.wall.footprint.x == 4 and buildings.wall.footprint.y == 4,
    "wall footprint must occupy a 4x4 grid")
for level = 1, 30 do
    local row = levels.rows[level]
    local stage=math.floor((level-1)/3)+1
    local expected_asset_id = expected_assets[stage]
    assert(row and row.level == level,
        "wall visual level order mismatch at level " .. tostring(level))
    assert(row.model_asset_id == expected_asset_id,
        "wall visual asset mismatch at level " .. tostring(level))
    assert(row.model_scale == 1,
        "wall meshes already fit four cells; do not enlarge them again")
    assert(row.model_yaw == 180,
        "wall visual yaw must be 180 degrees at level " .. tostring(level))
    local asset = assert(assets.by_id[row.model_asset_id],
        "wall visual asset is missing at level " .. tostring(level))
    assert(type(asset.primary_model) == "string" and asset.primary_model ~= "",
        "wall visual model path is missing at level " .. tostring(level))
    assert(not asset.environment_particles or #asset.environment_particles==0,
        "old Tiny ambient effects must not attach to reference walls")
    local model=string.format("models/survival_buildings/wall_lv%02d.vmdl",stage)
    assert(asset.enabled~=false and asset.primary_model==model)
    assert(shells[model]==model:gsub("%.vmdl$","_white_shell.vmdl"),"wall reveal mesh is missing")
    local runtime=buildings.wall.levels[level]
    assert(runtime.model_name==model and runtime.model_asset_id==expected_asset_id)
    assert(runtime.display_name==names[stage].."城墙·"..romans[(level-1)%3+1])
end

for level = 1, 30 do
    local runtime = assert(buildings.wall.levels[level],
        "wall runtime level is missing at level " .. tostring(level))
    assert(runtime.model_scale == 1 and runtime.model_yaw == 180,
        "wall runtime transform mismatch at level " .. tostring(level))
end

print("WALL_VISUAL_CONFIG_PASS models=10 levels=30 names=30 footprint=4x4 yaw=preserved flow_shells=10")
