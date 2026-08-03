-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: world_visual_definitions.csv
local M = {}
M.rows = {
    { visual_id = "world_resource_tree", model_name = "models/props_tree/mango_tree.vmdl", model_scale = 3, spawn_x = 448, spawn_y = 64, spawn_z = 128, enabled = true, notes = "资源树模型、运行缩放与初始位置" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["visual_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
