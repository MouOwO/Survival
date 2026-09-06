-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: lottery_quality_weights.csv
local M = {}
M.rows = {
    { weight_id = "map_n", pool_id = "map", quality = "n", weight = 6940, enabled = true, review_status = "ok", notes = "69.4%；地图池UR下调至0.1%，差额回补N。" },
    { weight_id = "map_r", pool_id = "map", quality = "r", weight = 2500, enabled = true, review_status = "ok", notes = "25%。" },
    { weight_id = "map_sr", pool_id = "map", quality = "sr", weight = 400, enabled = true, review_status = "ok", notes = "4%。" },
    { weight_id = "map_ssr", pool_id = "map", quality = "ssr", weight = 150, enabled = true, review_status = "ok", notes = "1.5%。" },
    { weight_id = "map_ur", pool_id = "map", quality = "ur", weight = 10, enabled = true, review_status = "ok", notes = "0.1%；仅按正常概率产出，不参与SR保底补位。" },
    { weight_id = "cultivation_n", pool_id = "cultivation", quality = "n", weight = 5950, enabled = true, review_status = "needs_confirmation", notes = "特殊池临时联调概率59.5%。" },
    { weight_id = "cultivation_r", pool_id = "cultivation", quality = "r", weight = 2500, enabled = true, review_status = "needs_confirmation", notes = "特殊池临时联调概率25%。" },
    { weight_id = "cultivation_sr", pool_id = "cultivation", quality = "sr", weight = 400, enabled = true, review_status = "needs_confirmation", notes = "特殊池临时联调概率4%。" },
    { weight_id = "cultivation_ssr", pool_id = "cultivation", quality = "ssr", weight = 150, enabled = true, review_status = "needs_confirmation", notes = "特殊池临时联调概率1.5%。" },
    { weight_id = "cultivation_ur", pool_id = "cultivation", quality = "ur", weight = 1000, enabled = true, review_status = "needs_confirmation", notes = "特殊池临时联调概率10%；正式数值待确认。" },
    { weight_id = "dragon_knight_n", pool_id = "dragon_knight", quality = "n", weight = 5950, enabled = true, review_status = "needs_confirmation", notes = "特殊池临时联调概率59.5%。" },
    { weight_id = "dragon_knight_r", pool_id = "dragon_knight", quality = "r", weight = 2500, enabled = true, review_status = "needs_confirmation", notes = "特殊池临时联调概率25%。" },
    { weight_id = "dragon_knight_sr", pool_id = "dragon_knight", quality = "sr", weight = 400, enabled = true, review_status = "needs_confirmation", notes = "特殊池临时联调概率4%。" },
    { weight_id = "dragon_knight_ssr", pool_id = "dragon_knight", quality = "ssr", weight = 150, enabled = true, review_status = "needs_confirmation", notes = "特殊池临时联调概率1.5%。" },
    { weight_id = "dragon_knight_ur", pool_id = "dragon_knight", quality = "ur", weight = 1000, enabled = true, review_status = "needs_confirmation", notes = "特殊池临时联调概率10%；正式数值待确认。" },
    { weight_id = "summer_n", pool_id = "summer", quality = "n", weight = 5950, enabled = true, review_status = "needs_confirmation", notes = "特殊池临时联调概率59.5%。" },
    { weight_id = "summer_r", pool_id = "summer", quality = "r", weight = 2500, enabled = true, review_status = "needs_confirmation", notes = "特殊池临时联调概率25%。" },
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
