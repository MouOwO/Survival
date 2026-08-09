-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: wave_timing_rules.csv
local M = {}
M.rows = {
    { timing_rule_id = "default", initial_delay_seconds = 150, early_wave_last_number = 9, early_interval_seconds = 90, late_interval_seconds = 90, enabled = true, dev_wave_preload_timeout_seconds = 3, formal_wave_preload_lead_seconds = 4, notes = "选择难度后150秒出第一波；第1至9波使用短间隔；第10波起使用长间隔；开发跳波最多等待3秒资源加载；后续正式波次在首只敌人出现前4秒异步加载目标波资源" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["timing_rule_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
