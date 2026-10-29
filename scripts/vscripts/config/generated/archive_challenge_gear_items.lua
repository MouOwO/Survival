-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: archive_challenge_gear_items.csv
local M = {}
M.rows = {
    { item_id = "archive_gear_n_blade", display_name = "守望短刃", quality = "N", max_owned = 30, description = "英雄初始属性+100（每件），无尽与通天塔装备", effect_ids = {"hero_initial_attributes"}, effect_values = {"100"}, enabled = true },
    { item_id = "archive_gear_n_guard", display_name = "守望护符", quality = "N", max_owned = 30, description = "城墙初始生命+1000（每件），无尽与通天塔装备", effect_ids = {"wall_initial_health"}, effect_values = {"1000"}, enabled = true },
    { item_id = "archive_gear_r_blade", display_name = "远征长刃", quality = "R", max_owned = 30, description = "英雄初始属性+300（每件），无尽与通天塔装备", effect_ids = {"hero_initial_attributes"}, effect_values = {"300"}, enabled = true },
    { item_id = "archive_gear_r_guard", display_name = "远征护符", quality = "R", max_owned = 30, description = "城墙初始生命+3000（每件），无尽与通天塔装备", effect_ids = {"wall_initial_health"}, effect_values = {"3000"}, enabled = true },
    { item_id = "archive_gear_sr_blade", display_name = "星辉长刃", quality = "SR", max_owned = 30, description = "英雄初始属性+1000（每件），无尽与通天塔装备", effect_ids = {"hero_initial_attributes"}, effect_values = {"1000"}, enabled = true },
    { item_id = "archive_gear_sr_guard", display_name = "星辉护符", quality = "SR", max_owned = 30, description = "城墙初始生命+10000（每件），无尽与通天塔装备", effect_ids = {"wall_initial_health"}, effect_values = {"10000"}, enabled = true },
    { item_id = "archive_gear_ssr_blade", display_name = "黎明圣刃", quality = "SSR", max_owned = 30, description = "英雄初始属性+3000（每件），无尽与通天塔装备", effect_ids = {"hero_initial_attributes"}, effect_values = {"3000"}, enabled = true },
    { item_id = "archive_gear_ssr_guard", display_name = "黎明圣徽", quality = "SSR", max_owned = 30, description = "城墙初始生命+30000（每件），无尽与通天塔装备", effect_ids = {"wall_initial_health"}, effect_values = {"30000"}, enabled = true },
    { item_id = "archive_gear_ur_blade", display_name = "永昼圣刃", quality = "UR", max_owned = 30, description = "英雄初始属性+8000（每件），无尽与通天塔装备", effect_ids = {"hero_initial_attributes"}, effect_values = {"8000"}, enabled = true },
    { item_id = "archive_gear_ur_guard", display_name = "永昼圣徽", quality = "UR", max_owned = 30, description = "城墙初始生命+80000（每件），无尽与通天塔装备", effect_ids = {"wall_initial_health"}, effect_values = {"80000"}, enabled = true },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["item_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
