-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: achievement_definitions.csv
local M = {}
M.rows = {
    { achievement_id = "first_wave_clear", display_name = "初次守住一波", default_progress = 0, target = 1, public_badge = true, enabled = true, notes = "首版假数据成就；后续写回接口不得改变ID。" },
    { achievement_id = "clear_n2", display_name = "通关难度N2", default_progress = 0, target = 1, public_badge = true, enabled = true, notes = "首版假数据成就；当前只读加载和增量更新。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["achievement_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
