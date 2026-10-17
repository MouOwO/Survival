-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: archive_social_rules.csv
local M = {}
M.rows = {
    { pool_id = "friend", display_name = "我的好基友", currency_id = "yitie", currency_name = "义帖", daily_limit = 10, draw_cost = 1, unlock_count = 100, enabled = true, quality_weight_n = 6000, quality_weight_r = 2500, quality_weight_sr = 1000, quality_weight_ssr = 450, quality_weight_ur = 50 },
    { pool_id = "ex", display_name = "我的前女友", currency_id = "invitation", currency_name = "邀请函", daily_limit = 10, draw_cost = 1, unlock_count = 0, enabled = true, quality_weight_n = 6000, quality_weight_r = 2500, quality_weight_sr = 1000, quality_weight_ssr = 450, quality_weight_ur = 50 },
    { pool_id = "beast", display_name = "瑞兽赐福", currency_id = "blessing_ticket", currency_name = "福签", daily_limit = 10, draw_cost = 1, unlock_count = 100, enabled = true, quality_weight_n = 6000, quality_weight_r = 2500, quality_weight_sr = 1000, quality_weight_ssr = 450, quality_weight_ur = 50 },
    { pool_id = "wife", display_name = "我的老婆", currency_id = "rose", currency_name = "玫瑰", daily_limit = 10, draw_cost = 1, unlock_count = 0, enabled = true, quality_weight_n = 6000, quality_weight_r = 2500, quality_weight_sr = 1000, quality_weight_ssr = 450, quality_weight_ur = 50 },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["pool_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
