-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: lottery_pool_updates.csv
local M = {}
M.rows = {
    { pool_id = "map", title = "地图宝箱奖励更新公告", summary = "地图宝箱按图鉴调整为30种奖励：SSR10种、SR5种、R5种、N10种；十连保底SSR。", updated_at = 1790698669, single_draw_probabilities = "SSR：1.5%　 SR：4%　 R：25%　 N：69.5%" },
    { pool_id = "cultivation", title = "修仙宝箱奖励更新公告", summary = "修仙宝箱按图鉴调整为26种奖励：UR7种、SSR9种、SR5种、R5种；十连保底SSR。", updated_at = 1790697756 },
    { pool_id = "dragon_knight", title = "龙骑宝箱奖励更新公告", summary = "第三宝箱按图鉴登记27种：UR7种、SSR10种、SR5种、R5种；龙骑尖兵01型效果待补，暂不开放；十连保底UR。", updated_at = 1790697997 },
    { pool_id = "summer", title = "暑期宝箱奖励更新公告", summary = "二次元宝箱现有23种奖励：UR5种、SSR8种、SR5种、R5种。王之财宝按地图等级增加全属性加成；妖刀村正按持有UR种数增加最终伤害；朗基努斯枪最终伤害合计+32%；十连保底UR。", updated_at = 1790985602 },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["pool_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
