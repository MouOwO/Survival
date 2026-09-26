-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: build_forbidden_regions.csv
local M = {}
M.rows = {
    { region_id = "main_stair_east", region_type = "building_forbidden", shape = "quadrilateral", p1_x = 960, p1_y = 3872, p2_x = 1600, p2_y = 3872, p3_x = 1600, p3_y = 5216, p4_x = 960, p4_y = 5216, map_name = "template_map", enabled = true, notes = "主岛东侧楼梯及转角禁建" },
    { region_id = "main_stair_south", region_type = "building_forbidden", shape = "quadrilateral", p1_x = -1248, p1_y = 1472, p2_x = 96, p2_y = 1472, p3_x = 96, p3_y = 2112, p4_x = -1248, p4_y = 2112, map_name = "template_map", enabled = true, notes = "主岛南侧楼梯及转角禁建" },
    { region_id = "main_stair_west", region_type = "building_forbidden", shape = "quadrilateral", p1_x = -3648, p1_y = 2976, p2_x = -3008, p2_y = 2976, p3_x = -3008, p3_y = 4320, p4_x = -3648, p4_y = 4320, map_name = "template_map", enabled = true, notes = "主岛西侧楼梯及转角禁建" },
    { region_id = "main_stair_north", region_type = "building_forbidden", shape = "quadrilateral", p1_x = -2144, p1_y = 6080, p2_x = -800, p2_y = 6080, p3_x = -800, p3_y = 6720, p4_x = -2144, p4_y = 6720, map_name = "template_map", enabled = true, notes = "主岛北侧楼梯及转角禁建" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["region_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
