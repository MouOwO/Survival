-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: archive_vip_levels.csv
local M = {}
M.rows = {
    { level_id = "vip_level_01", level = 1, required_recharge_fen = 5000, required_recharge_yuan = 50 },
    { level_id = "vip_level_02", level = 2, required_recharge_fen = 10000, required_recharge_yuan = 100 },
    { level_id = "vip_level_03", level = 3, required_recharge_fen = 25000, required_recharge_yuan = 250 },
    { level_id = "vip_level_04", level = 4, required_recharge_fen = 50000, required_recharge_yuan = 500 },
    { level_id = "vip_level_05", level = 5, required_recharge_fen = 100000, required_recharge_yuan = 1000 },
    { level_id = "vip_level_06", level = 6, required_recharge_fen = 150000, required_recharge_yuan = 1500 },
    { level_id = "vip_level_07", level = 7, required_recharge_fen = 250000, required_recharge_yuan = 2500 },
    { level_id = "vip_level_08", level = 8, required_recharge_fen = 400000, required_recharge_yuan = 4000 },
    { level_id = "vip_level_09", level = 9, required_recharge_fen = 600000, required_recharge_yuan = 6000 },
    { level_id = "vip_level_10", level = 10, required_recharge_fen = 750000, required_recharge_yuan = 7500 },
    { level_id = "vip_level_11", level = 11, required_recharge_fen = 1000000, required_recharge_yuan = 10000 },
    { level_id = "vip_level_12", level = 12, required_recharge_fen = 1250000, required_recharge_yuan = 12500 },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["level_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
