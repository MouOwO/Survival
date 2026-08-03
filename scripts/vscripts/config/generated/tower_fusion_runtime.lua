-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: tower_fusion_runtime.csv
local M = {}
M.rows = {
    { config_id = "ultimate_tower", route_ids = {"class_1", "class_2", "class_3", "class_4", "class_5", "class_6", "class_7"}, unit_name = "building_arrow_tower", display_name = "终极塔", target_scan_interval = 0.05, projectile_expire_time = 10, enabled = true },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["config_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
