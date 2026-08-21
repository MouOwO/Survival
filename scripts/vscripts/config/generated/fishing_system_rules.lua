-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: fishing_system_rules.csv
local M = {}
M.rows = {
    { fishing_rule_id = "default_fishing", api_base_url = "http://127.0.0.1:8765", heartbeat_interval_seconds = 5, heartbeat_lease_seconds = 15, online_time_checkpoint_interval_seconds = 60, online_time_lease_seconds = 90, reward_interval_min_seconds = 60, reward_interval_max_seconds = 600, match_reward_interval_seconds = 480, definition_version = 1, profile_schema_version = 1, enabled = true, notes = "局内钓鱼从首次难度选择成功开始计时；共享令牌仅从服务端ConVar读取。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["fishing_rule_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
