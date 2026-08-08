-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: wave_timing_rules.csv
local M = {}
M.rows = {
    { timing_rule_id = "default", initial_delay_seconds = 150, early_wave_last_number = 9, early_interval_seconds = 90, late_interval_seconds = 90, enabled = true, notes = "选择难度后150秒出第一波；第1至9波首怪到下一波首怪间隔90秒；第10波起首怪到下一波首怪间隔150秒" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["timing_rule_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
