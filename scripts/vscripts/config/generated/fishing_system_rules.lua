-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: fishing_system_rules.csv
local M = {}
M.rows = {
    { fishing_rule_id = "default_fishing", api_base_url = "http://127.0.0.1:8765", heartbeat_interval_seconds = 5, heartbeat_lease_seconds = 15, online_time_checkpoint_interval_seconds = 60, online_time_lease_seconds = 180, reward_interval_min_seconds = 600, reward_interval_max_seconds = 600, match_reward_interval_seconds = 480, definition_version = 3, profile_schema_version = 1, enabled = true, notes = "在线奖励每10分钟派发；每分钟检查并在正常断开或对局结束时立即结算；租约超时用于恢复异常退出；断线只结算对应玩家session；共享令牌仅从服务端ConVar读取。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["fishing_rule_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
