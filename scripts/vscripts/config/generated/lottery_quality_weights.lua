-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: lottery_quality_weights.csv
local M = {}
M.rows = {
    { weight_id = "map_n", pool_id = "map", quality = "n", weight = 6950, enabled = true, review_status = "ok", notes = "用户2026-09-30概率截图确认：N69.5%。" },
    { weight_id = "map_r", pool_id = "map", quality = "r", weight = 2500, enabled = true, review_status = "ok", notes = "用户2026-09-30概率截图确认：R25%。" },
    { weight_id = "map_sr", pool_id = "map", quality = "sr", weight = 400, enabled = true, review_status = "ok", notes = "用户2026-09-30概率截图确认：SR4%。" },
    { weight_id = "map_ssr", pool_id = "map", quality = "ssr", weight = 150, enabled = true, review_status = "ok", notes = "用户2026-09-30概率截图确认：SSR1.5%。" },
    { weight_id = "map_ur", pool_id = "map", quality = "ur", weight = 0, enabled = false, review_status = "ok", notes = "2026-09-29截图地图奖池仅N/R/SR/SSR，无UR成员。" },
    { weight_id = "cultivation_n", pool_id = "cultivation", quality = "n", weight = 0, enabled = false, review_status = "needs_confirmation", notes = "截图修仙奖池无N成员；正式概率待用户提供。" },
    { weight_id = "cultivation_r", pool_id = "cultivation", quality = "r", weight = 8450, enabled = true, review_status = "needs_confirmation", notes = "仅本地联调临时值84.5%；原N权重暂并入R，以保持SR/SSR/UR原临时权重。正式概率待用户提供，暂不发布。" },
    { weight_id = "cultivation_sr", pool_id = "cultivation", quality = "sr", weight = 400, enabled = true, review_status = "needs_confirmation", notes = "特殊池临时联调概率4%。" },
    { weight_id = "cultivation_ssr", pool_id = "cultivation", quality = "ssr", weight = 150, enabled = true, review_status = "needs_confirmation", notes = "特殊池临时联调概率1.5%。" },
    { weight_id = "cultivation_ur", pool_id = "cultivation", quality = "ur", weight = 1000, enabled = true, review_status = "needs_confirmation", notes = "特殊池临时联调概率10%；正式数值待确认。" },
    { weight_id = "dragon_knight_n", pool_id = "dragon_knight", quality = "n", weight = 0, enabled = false, review_status = "needs_confirmation", notes = "截图第三宝箱无N成员；正式概率待用户提供。" },
    { weight_id = "dragon_knight_r", pool_id = "dragon_knight", quality = "r", weight = 8450, enabled = true, review_status = "needs_confirmation", notes = "仅本地联调临时值84.5%；原N权重暂并入R，保留SR/SSR/UR原临时权重。正式概率待用户提供，暂不发布。" },
    { weight_id = "dragon_knight_sr", pool_id = "dragon_knight", quality = "sr", weight = 400, enabled = true, review_status = "needs_confirmation", notes = "特殊池临时联调概率4%。" },
    { weight_id = "dragon_knight_ssr", pool_id = "dragon_knight", quality = "ssr", weight = 150, enabled = true, review_status = "needs_confirmation", notes = "特殊池临时联调概率1.5%。" },
    { weight_id = "dragon_knight_ur", pool_id = "dragon_knight", quality = "ur", weight = 1000, enabled = true, review_status = "needs_confirmation", notes = "特殊池临时联调概率10%；正式数值待确认。" },
    { weight_id = "summer_n", pool_id = "summer", quality = "n", weight = 0, enabled = false, review_status = "needs_confirmation", notes = "截图第四宝箱无N；沿用其他特殊池联调规则，N临时权重并入R。正式概率待用户确认，暂不发布。" },
    { weight_id = "summer_r", pool_id = "summer", quality = "r", weight = 8450, enabled = true, review_status = "needs_confirmation", notes = "截图第四宝箱无N；沿用其他特殊池联调规则，N临时权重并入R。正式概率待用户确认，暂不发布。" },
    { weight_id = "summer_sr", pool_id = "summer", quality = "sr", weight = 400, enabled = true, review_status = "needs_confirmation", notes = "特殊池临时联调概率4%。" },
    { weight_id = "summer_ssr", pool_id = "summer", quality = "ssr", weight = 150, enabled = true, review_status = "needs_confirmation", notes = "特殊池临时联调概率1.5%。" },
    { weight_id = "summer_ur", pool_id = "summer", quality = "ur", weight = 1000, enabled = true, review_status = "needs_confirmation", notes = "特殊池临时联调概率10%；正式数值待确认。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["weight_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
