-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: lottery_pool_updates.csv
local M = {}
M.rows = {
    { pool_id = "map", title = "地图宝箱奖励更新公告", summary = "地图宝箱按图鉴调整为30种奖励：SSR10种、SR5种、R5种、N10种；十连保底SSR。", updated_at = 1790698669, single_draw_probabilities = "SSR：1.5%　 SR：4%　 R：25%　 N：69.5%" },
    { pool_id = "cultivation", title = "修仙宝箱概率更新公告", effective_date = "2026-11-11", summary = "修仙宝箱现有26种奖励：UR7种、SSR9种、SR5种、R5种；UR基础概率3%；一次十连必出SSR而UR不保底。", updated_at = 1794354588, single_draw_probabilities = "UR：3%　 SSR：1.5%　 SR：4%　 R：91.5%" },
    { pool_id = "dragon_knight", title = "龙骑宝箱概率更新公告", effective_date = "2026-11-11", summary = "龙骑宝箱当前开放26种奖励：UR6种、SSR10种、SR5种、R5种；UR基础概率3%；一次十连必出SSR而UR不保底。", updated_at = 1794354588, single_draw_probabilities = "UR：3%　 SSR：1.5%　 SR：4%　 R：91.5%" },
    { pool_id = "summer", title = "暑期宝箱概率更新公告", effective_date = "2026-11-11", summary = "暑期宝箱现有23种奖励：UR5种、SSR8种、SR5种、R5种；UR基础概率3%；一次十连必出SSR而UR不保底。", updated_at = 1794354588, single_draw_probabilities = "UR：3%　 SSR：1.5%　 SR：4%　 R：91.5%" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["pool_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
