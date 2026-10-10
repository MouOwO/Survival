-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: builder_definitions.csv
local M = {}
M.rows = {
    { builder_id = "default_builder", unit_name = "npc_survival_builder_proxy", display_name = "建造者", model_name = "models/heroes/wisp/wisp.vmdl", model_scale = 1, move_speed = 500, spawn_x = 0, spawn_y = 0, spawn_z = 256, enabled = true, notes = "独立建造代理；艾欧本体保留原生拾取hitbox；仁爱之友9235作可渲染父子挂载，失败回退原版光球；地面/无碰撞/修理不变。", visual_asset_id = "builder_io_benevolent_companion", construction_activity = "ACT_DOTA_ATTACK", construction_sequence = "attack" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["builder_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
