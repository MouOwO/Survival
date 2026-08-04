-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: builder_definitions.csv
local M = {}
M.rows = {
    { builder_id = "default_builder", unit_name = "npc_survival_builder_proxy", display_name = "建造者", model_name = "models/heroes/undying/undying.vmdl", model_scale = 1, move_speed = 300, spawn_x = 0, spawn_y = 0, spawn_z = 256, enabled = true, notes = "独立建造代理；首版使用普通可控单位验证身份解耦，不声明为真实信使类型。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["builder_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
