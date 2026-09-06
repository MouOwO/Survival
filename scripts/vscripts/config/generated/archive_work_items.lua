-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: archive_work_items.csv
local M = {}
M.rows = {
    { item_id = "work_01", display_name = "老板凝视", cost = 600, max_level = 1, description = "伐木工攻速+2%", effect_ids = {"lumberjack_attack_speed_bonus_pct"}, effect_values = {"2"}, enabled = true },
    { item_id = "work_02", display_name = "996lv1", cost = 800, max_level = 1, description = "箭塔攻击+100", effect_ids = {"tower_attack_flat"}, effect_values = {"100"}, enabled = true },
    { item_id = "work_03", display_name = "继续努力", cost = 1000, max_level = 1, description = "英雄攻速+2%", effect_ids = {"hero_attack_speed_bonus_pct"}, effect_values = {"2"}, enabled = true },
    { item_id = "work_04", display_name = "不要猝死", cost = 1200, max_level = 1, description = "墙生命+1000", effect_ids = {"wall_initial_health"}, effect_values = {"1000"}, enabled = true },
    { item_id = "work_05", display_name = "老板买车", cost = 1400, max_level = 1, description = "墙护甲+5", effect_ids = {"wall_armor"}, effect_values = {"5"}, enabled = true },
    { item_id = "work_06", display_name = "带薪拉屎", cost = 1600, max_level = 1, description = "金矿收益+1%", effect_ids = {"gold_mine_efficiency_pct"}, effect_values = {"1"}, enabled = true },
    { item_id = "work_07", display_name = "今晚加班", cost = 1800, max_level = 1, description = "墙每秒生命+5", effect_ids = {"wall_health_per_second"}, effect_values = {"5"}, enabled = true },
    { item_id = "work_08", display_name = "拼好饭", cost = 2000, max_level = 1, description = "金矿收益+1%", effect_ids = {"gold_mine_efficiency_pct"}, effect_values = {"1"}, enabled = true },
    { item_id = "work_09", display_name = "脂肪肝", cost = 2500, max_level = 1, description = "英雄生命加成+2%", effect_ids = {"hero_health_bonus_pct"}, effect_values = {"2"}, enabled = true },
    { item_id = "work_10", display_name = "胃结石", cost = 3000, max_level = 1, description = "英雄护甲加成+2%", effect_ids = {"hero_armor_bonus_pct"}, effect_values = {"2"}, enabled = true },
    { item_id = "work_11", display_name = "高血压", cost = 3500, max_level = 1, description = "英雄攻击间隔-0.02", effect_ids = {"hero_attack_interval_reduction"}, effect_values = {"0.02"}, enabled = true },
    { item_id = "work_12", display_name = "鸡汤", cost = 4000, max_level = 1, description = "练功房收益+5%", effect_ids = {"training_room_income_bonus_pct"}, effect_values = {"5"}, enabled = true },
    { item_id = "work_13", display_name = "画饼", cost = 4500, max_level = 1, description = "箭塔攻速+2%", effect_ids = {"tower_attack_speed_bonus_pct"}, effect_values = {"2"}, enabled = true },
    { item_id = "work_14", display_name = "摸鱼", cost = 5000, max_level = 1, description = "每秒木材+1", effect_ids = {"wood_per_second"}, effect_values = {"1"}, enabled = true },
    { item_id = "work_15", display_name = "咖啡", cost = 5500, max_level = 1, description = "英雄造成伤害+1", effect_ids = {"hero_damage_bonus_flat"}, effect_values = {"1"}, enabled = true },
    { item_id = "work_16", display_name = "健身房", cost = 6000, max_level = 1, description = "英雄每秒全属性+2", effect_ids = {"hero_attributes_per_second"}, effect_values = {"2"}, enabled = true },
    { item_id = "work_17", display_name = "内卷", cost = 7000, max_level = 1, description = "伐木效率+1", effect_ids = {"lumberjack_attack_efficiency"}, effect_values = {"1"}, enabled = true },
    { item_id = "work_18", display_name = "老板凝视", cost = 8000, max_level = 1, description = "伐木工攻速+5%", effect_ids = {"lumberjack_attack_speed_bonus_pct"}, effect_values = {"5"}, enabled = true },
    { item_id = "work_19", display_name = "996lv2", cost = 9000, max_level = 1, description = "箭塔攻击+1000", effect_ids = {"tower_attack_flat"}, effect_values = {"1000"}, enabled = true },
    { item_id = "work_20", display_name = "继续努力", cost = 10000, max_level = 1, description = "英雄攻速+5%", effect_ids = {"hero_attack_speed_bonus_pct"}, effect_values = {"5"}, enabled = true },
    { item_id = "work_21", display_name = "不要猝死", cost = 11000, max_level = 1, description = "墙生命+2000", effect_ids = {"wall_initial_health"}, effect_values = {"2000"}, enabled = true },
    { item_id = "work_22", display_name = "老板买车", cost = 12000, max_level = 1, description = "墙护甲+20", effect_ids = {"wall_armor"}, effect_values = {"20"}, enabled = true },
    { item_id = "work_23", display_name = "带薪拉屎", cost = 13000, max_level = 1, description = "金矿收益+3%", effect_ids = {"gold_mine_efficiency_pct"}, effect_values = {"3"}, enabled = true },
    { item_id = "work_24", display_name = "今晚加个班", cost = 14000, max_level = 1, description = "墙每秒生命+10", effect_ids = {"wall_health_per_second"}, effect_values = {"10"}, enabled = true },
    { item_id = "work_25", display_name = "拼好饭", cost = 15000, max_level = 1, description = "英雄攻击加成+5%", effect_ids = {"hero_attack_bonus_pct"}, effect_values = {"5"}, enabled = true },
    { item_id = "work_26", display_name = "脂肪肝", cost = 16000, max_level = 1, description = "英雄生命加成+5%", effect_ids = {"hero_health_bonus_pct"}, effect_values = {"5"}, enabled = true },
    { item_id = "work_27", display_name = "胃结石", cost = 17000, max_level = 1, description = "英雄护甲加成+5%", effect_ids = {"hero_armor_bonus_pct"}, effect_values = {"5"}, enabled = true },
    { item_id = "work_28", display_name = "高血压", cost = 18000, max_level = 1, description = "英雄攻击间隔-0.05", effect_ids = {"hero_attack_interval_reduction"}, effect_values = {"0.05"}, enabled = true },
    { item_id = "work_29", display_name = "鸡汤", cost = 19000, max_level = 1, description = "练功房收益+8%", effect_ids = {"training_room_income_bonus_pct"}, effect_values = {"8"}, enabled = true },
    { item_id = "work_30", display_name = "画饼", cost = 20000, max_level = 1, description = "箭塔攻速+5%", effect_ids = {"tower_attack_speed_bonus_pct"}, effect_values = {"5"}, enabled = true },
    { item_id = "work_31", display_name = "摸鱼", cost = 21000, max_level = 1, description = "每秒木材+4", effect_ids = {"wood_per_second"}, effect_values = {"4"}, enabled = true },
    { item_id = "work_32", display_name = "咖啡", cost = 22000, max_level = 1, description = "英雄造成伤害+3", effect_ids = {"hero_damage_bonus_flat"}, effect_values = {"3"}, enabled = true },
    { item_id = "work_33", display_name = "健身房", cost = 23000, max_level = 1, description = "英雄每秒全属性+3", effect_ids = {"hero_attributes_per_second"}, effect_values = {"3"}, enabled = true },
    { item_id = "work_34", display_name = "内卷", cost = 24000, max_level = 1, description = "伐木效率+3", effect_ids = {"lumberjack_attack_efficiency"}, effect_values = {"3"}, enabled = true },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["item_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
