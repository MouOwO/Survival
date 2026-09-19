-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: lottery_pool_updates.csv
local M = {}
M.rows = {
    { pool_id = "map", title = "地图宝箱奖励更新公告", summary = "本次奖池内容已更新，以下为当前可获得的奖励。", updated_at = 1789370604 },
    { pool_id = "cultivation", title = "修仙宝箱奖励更新公告", summary = "本次奖池内容已更新，以下为当前可获得的奖励。", updated_at = 1789370604 },
    { pool_id = "dragon_knight", title = "龙骑宝箱奖励更新公告", summary = "本次奖池内容已更新，以下为当前可获得的奖励。", updated_at = 1789370604 },
    { pool_id = "summer", title = "暑期宝箱奖励更新公告", summary = "本次奖池内容已更新，以下为当前可获得的奖励。", updated_at = 1789370604 },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["pool_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
