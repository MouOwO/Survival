-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: lottery_quality_weights.csv
local M = {}
M.rows = {
    { weight_id = "map_n", pool_id = "map", quality = "n", weight = 6950, enabled = true, review_status = "ok", notes = "用户2026-09-30概率截图确认：N69.5%。" },
    { weight_id = "map_r", pool_id = "map", quality = "r", weight = 2500, enabled = true, review_status = "ok", notes = "用户2026-09-30概率截图确认：R25%。" },
    { weight_id = "map_sr", pool_id = "map", quality = "sr", weight = 400, enabled = true, review_status = "ok", notes = "用户2026-09-30概率截图确认：SR4%。" },
    { weight_id = "map_ssr", pool_id = "map", quality = "ssr", weight = 150, enabled = true, review_status = "ok", notes = "用户2026-09-30概率截图确认：SSR1.5%。" },
    { weight_id = "map_ur", pool_id = "map", quality = "ur", weight = 0, enabled = false, review_status = "ok", notes = "2026-09-29截图地图奖池仅N/R/SR/SSR，无UR成员。" },
    { weight_id = "cultivation_n", pool_id = "cultivation", quality = "n", weight = 0, enabled = false, review_status = "ok", notes = "修仙宝箱无N成员。" },
    { weight_id = "cultivation_r", pool_id = "cultivation", quality = "r", weight = 9350, enabled = true, review_status = "ok", notes = "2026-11-11 金券池：R93.5%。" },
    { weight_id = "cultivation_sr", pool_id = "cultivation", quality = "sr", weight = 400, enabled = true, review_status = "ok", notes = "2026-11-11 金券池分配：SR4%。" },
    { weight_id = "cultivation_ssr", pool_id = "cultivation", quality = "ssr", weight = 150, enabled = true, review_status = "ok", notes = "2026-11-11 金券池分配：SSR1.5%；一次十连固定至少一件SSR。" },
    { weight_id = "cultivation_ur", pool_id = "cultivation", quality = "ur", weight = 100, enabled = true, review_status = "ok", notes = "2026-11-11 用户指定：UR基础1%，每池最多50抽必出UR。" },
    { weight_id = "dragon_knight_n", pool_id = "dragon_knight", quality = "n", weight = 0, enabled = false, review_status = "ok", notes = "龙骑宝箱无N成员。" },
    { weight_id = "dragon_knight_r", pool_id = "dragon_knight", quality = "r", weight = 9350, enabled = true, review_status = "ok", notes = "2026-11-11 金券池：R93.5%。" },
    { weight_id = "dragon_knight_sr", pool_id = "dragon_knight", quality = "sr", weight = 400, enabled = true, review_status = "ok", notes = "2026-11-11 金券池分配：SR4%。" },
    { weight_id = "dragon_knight_ssr", pool_id = "dragon_knight", quality = "ssr", weight = 150, enabled = true, review_status = "ok", notes = "2026-11-11 金券池分配：SSR1.5%；一次十连固定至少一件SSR。" },
    { weight_id = "dragon_knight_ur", pool_id = "dragon_knight", quality = "ur", weight = 100, enabled = true, review_status = "ok", notes = "2026-11-11 用户指定：UR基础1%，每池最多50抽必出UR。" },
    { weight_id = "summer_n", pool_id = "summer", quality = "n", weight = 0, enabled = false, review_status = "ok", notes = "暑期宝箱无N成员。" },
    { weight_id = "summer_r", pool_id = "summer", quality = "r", weight = 9350, enabled = true, review_status = "ok", notes = "2026-11-11 金券池：R93.5%。" },
    { weight_id = "summer_sr", pool_id = "summer", quality = "sr", weight = 400, enabled = true, review_status = "ok", notes = "2026-11-11 金券池分配：SR4%。" },
    { weight_id = "summer_ssr", pool_id = "summer", quality = "ssr", weight = 150, enabled = true, review_status = "ok", notes = "2026-11-11 金券池分配：SSR1.5%；一次十连固定至少一件SSR。" },
    { weight_id = "summer_ur", pool_id = "summer", quality = "ur", weight = 100, enabled = true, review_status = "ok", notes = "2026-11-11 用户指定：UR基础1%，每池最多50抽必出UR。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["weight_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
