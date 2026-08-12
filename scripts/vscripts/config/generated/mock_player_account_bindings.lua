-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: mock_player_account_bindings.csv
local M = {}
M.rows = {
    { binding_id = "mock_player_0", player_id = 0, account_id = "mock_account_10001", enabled = true, notes = "仅用于本地假数据Provider；正式环境不得把player_id作为永久账号主键。" },
    { binding_id = "mock_player_1", player_id = 1, account_id = "mock_account_10002", enabled = true, notes = "仅用于双人联机假数据验证。" },
    { binding_id = "mock_player_2", player_id = 2, account_id = "mock_account_10003", enabled = true, notes = "预留第三名玩家假账号。" },
    { binding_id = "mock_player_3", player_id = 3, account_id = "mock_account_10004", enabled = true, notes = "预留第四名玩家假账号。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["binding_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
