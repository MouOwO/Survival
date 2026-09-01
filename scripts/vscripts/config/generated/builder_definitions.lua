-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: builder_definitions.csv
local M = {}
M.rows = {
    { builder_id = "default_builder", unit_name = "npc_survival_builder_proxy", display_name = "建造者", model_name = "models/courier/courier_mech/courier_mech.vmdl", model_scale = 1, move_speed = 500, spawn_x = 0, spawn_y = 0, spawn_z = 256, enabled = true, notes = "独立建造代理；使用courier_mech外观，不声明为真实信使类型。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["builder_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
