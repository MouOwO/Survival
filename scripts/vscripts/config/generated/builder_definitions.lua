-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: builder_definitions.csv
local M = {}
M.rows = {
    { builder_id = "default_builder", unit_name = "npc_survival_builder_proxy", display_name = "建造者", model_name = "models/items/io/io_ti7/io_ti7.vmdl", model_scale = 1, move_speed = 500, spawn_x = 0, spawn_y = 0, spawn_z = 256, enabled = true, notes = "独立建造代理；艾欧仁爱之友至宝ItemDef9235；地面寻路/无碰撞/修理身份不变。", visual_asset_id = "builder_io_benevolent_companion", construction_activity = "ACT_DOTA_TAUNT", construction_particle = "particles/econ/items/wisp/wisp_overcharge_ti7.vpcf" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["builder_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
