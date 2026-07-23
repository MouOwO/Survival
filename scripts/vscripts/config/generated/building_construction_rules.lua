-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: building_construction_rules.csv
local M = {}
M.rows = {
    { building_id = "wall", build_cast_range = 200, build_time = 3, build_particle = "particles/items_fx/repair_kit.vpcf", enabled = true, notes = "Undying走到200范围内施法；完成前不可选择。" },
    { building_id = "main_city", build_cast_range = 200, build_time = 3, build_particle = "particles/items_fx/repair_kit.vpcf", enabled = true, notes = "Undying走到200范围内施法；完成前不可选择。" },
    { building_id = "arrow_tower", build_cast_range = 200, build_time = 3, build_particle = "particles/items_fx/repair_kit.vpcf", enabled = true, notes = "Undying走到200范围内施法；完成前不可选择。" },
    { building_id = "building_farm", build_cast_range = 200, build_time = 3, build_particle = "particles/items_fx/repair_kit.vpcf", enabled = true, notes = "主城建成后可重复建造；完成前不可选择，完成后恢复模型与选择。" },
    { building_id = "building_research_lab", build_cast_range = 200, build_time = 3, build_particle = "particles/items_fx/repair_kit.vpcf", enabled = true, notes = "主城建成后Undying通过W建造；费用读取building_levels.csv；完成前不可选择。" },
    { building_id = "gold_mine", build_cast_range = 200, build_time = 3, build_particle = "particles/items_fx/repair_kit.vpcf", enabled = true, notes = "Undying走到200范围内施法；完成前不可选择。" },
    { building_id = "hero_altar", build_cast_range = 200, build_time = 3, build_particle = "particles/items_fx/repair_kit.vpcf", enabled = true, notes = "Undying走到200范围内施法；完成前不可选择。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["building_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
