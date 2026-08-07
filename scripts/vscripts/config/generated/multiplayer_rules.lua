-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: multiplayer_rules.csv
local M = {}
M.rows = {
    { rule_id = "default_multiplayer", max_players = 4, initial_slice_players = 2, shared_wave_clock = true, allow_cross_lane_hero_support = true, player_zero_legacy_fallback = true, enabled = true, notes = "最多4名玩家；先完成2人纵向切片。服务端权威结算，客户端只提交操作意图。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["rule_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
