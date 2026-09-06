-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: archive_shadow_items.csv
local M = {}
M.rows = {
    { item_id = "shadow_01", display_name = "幻象树枝", quality = "white", max_owned = 430, description = "木材+10", effect_ids = {"initial_wood"}, effect_values = {"10"}, icon_style = "shard", enabled = true, source_row = 5, source_boss_difficulty = "n1" },
    { item_id = "shadow_02", display_name = "贪婪金币", quality = "white", max_owned = 430, description = "金币+1", effect_ids = {"initial_gold"}, effect_values = {"1"}, icon_style = "shard", enabled = true, source_row = 6, source_boss_difficulty = "n1" },
    { item_id = "shadow_03", display_name = "虚无模块", quality = "white", max_owned = 430, description = "墙生命+100", effect_ids = {"wall_initial_health"}, effect_values = {"100"}, icon_style = "shard", enabled = true, source_row = 7, source_boss_difficulty = "n1" },
    { item_id = "shadow_04", display_name = "粘稠之泥", quality = "white", max_owned = 430, description = "墙每秒生命+1", effect_ids = {"wall_health_per_second"}, effect_values = {"1"}, icon_style = "shard", enabled = true, source_row = 8, source_boss_difficulty = "n1" },
    { item_id = "shadow_05", display_name = "虚空箭头", quality = "white", max_owned = 430, description = "箭塔攻击+50", effect_ids = {"tower_attack_flat"}, effect_values = {"50"}, icon_style = "shard", enabled = true, source_row = 9, source_boss_difficulty = "n1" },
    { item_id = "shadow_06", display_name = "阴暗附着", quality = "blue", max_owned = 440, description = "英雄初始属性+30", effect_ids = {"hero_initial_attributes"}, effect_values = {"30"}, icon_style = "shard", enabled = true, source_row = 10, source_boss_difficulty = "n2" },
    { item_id = "shadow_07", display_name = "阴影碎布", quality = "blue", max_owned = 440, description = "英雄生命加成+0.5%", effect_ids = {"hero_health_bonus_pct"}, effect_values = {"0.5"}, icon_style = "shard", enabled = true, source_row = 11, source_boss_difficulty = "n2" },
    { item_id = "shadow_08", display_name = "空明碎甲", quality = "blue", max_owned = 440, description = "英雄护甲加成+0.5%", effect_ids = {"hero_armor_bonus_pct"}, effect_values = {"0.5"}, icon_style = "shard", enabled = true, source_row = 12, source_boss_difficulty = "n2" },
    { item_id = "shadow_09", display_name = "虚空护罩", quality = "blue", max_owned = 440, description = "墙伤害格挡+30", effect_ids = {"wall_damage_block"}, effect_values = {"30"}, icon_style = "shard", enabled = true, source_row = 13, source_boss_difficulty = "n2" },
    { item_id = "shadow_10", display_name = "大虚之锤", quality = "blue", max_owned = 440, description = "墙每秒生命+2", effect_ids = {"wall_health_per_second"}, effect_values = {"2"}, icon_style = "shard", enabled = true, source_row = 14, source_boss_difficulty = "n2" },
    { item_id = "shadow_11", display_name = "虚无之盾", quality = "blue", max_owned = 440, description = "墙护甲加成+0.5%", effect_ids = {"wall_armor_bonus_pct"}, effect_values = {"0.5"}, icon_style = "shard", enabled = true, source_row = 15, source_boss_difficulty = "n2" },
    { item_id = "shadow_12", display_name = "坚韧甲壳", quality = "purple", max_owned = 450, description = "墙护甲+0.5", effect_ids = {"wall_armor"}, effect_values = {"0.5"}, icon_style = "shard", enabled = true, source_row = 16, source_boss_difficulty = "n3" },
    { item_id = "shadow_13", display_name = "动力齿轮", quality = "purple", max_owned = 450, description = "箭塔攻速+0.5%", effect_ids = {"tower_attack_speed_bonus_pct"}, effect_values = {"0.5"}, icon_style = "shard", enabled = true, source_row = 17, source_boss_difficulty = "n3" },
    { item_id = "shadow_14", display_name = "无形之斧", quality = "purple", max_owned = 450, description = "每秒木材+1", effect_ids = {"wood_per_second"}, effect_values = {"1"}, icon_style = "shard", enabled = true, source_row = 18, source_boss_difficulty = "n3" },
    { item_id = "shadow_15", display_name = "弹匣之弦", quality = "purple", max_owned = 225, description = "箭塔攻击加成+0.5%", effect_ids = {"tower_attack_bonus_pct"}, effect_values = {"0.5"}, icon_style = "shard", enabled = true, source_row = 19, source_boss_difficulty = "n3" },
    { item_id = "shadow_16", display_name = "魔魇之能", quality = "purple", max_owned = 180, description = "伐木工攻速+0.2", effect_ids = {"lumberjack_attack_speed_bonus_pct"}, effect_values = {"0.2"}, icon_style = "shard", enabled = true, source_row = 20, source_boss_difficulty = "n3" },
    { item_id = "shadow_17", display_name = "相位之力", quality = "purple", max_owned = 180, description = "墙减伤+0.5%", effect_ids = {"wall_damage_reduction_pct"}, effect_values = {"0.5"}, icon_style = "shard", enabled = true, source_row = 21, source_boss_difficulty = "n3" },
    { item_id = "shadow_18", display_name = "虚空炼金", quality = "green", max_owned = 430, description = "金矿效率+0.5%", effect_ids = {"gold_mine_efficiency_pct"}, effect_values = {"0.5"}, icon_style = "shard", enabled = true, source_row = 22, source_boss_difficulty = "n4" },
    { item_id = "shadow_19", display_name = "腐蚀魔能", quality = "green", max_owned = 300, description = "英雄攻击减甲+0.2", effect_ids = {"hero_attack_armor_reduction"}, effect_values = {"0.2"}, icon_style = "shard", enabled = true, source_row = 23, source_boss_difficulty = "n4" },
    { item_id = "shadow_20", display_name = "膨胀药剂", quality = "green", max_owned = 430, description = "英雄三维加成+0.3%", effect_ids = {"hero_attribute_bonus_pct"}, effect_values = {"0.3"}, icon_style = "shard", enabled = true, source_row = 24, source_boss_difficulty = "n4" },
    { item_id = "shadow_21", display_name = "梦魔狂飙", quality = "green", max_owned = 430, description = "英雄攻击加成+0.3%", effect_ids = {"hero_attack_bonus_pct"}, effect_values = {"0.3"}, icon_style = "shard", enabled = true, source_row = 25, source_boss_difficulty = "n4" },
    { item_id = "shadow_22", display_name = "虚无之锋", quality = "green", max_owned = 430, description = "英雄最终伤害+0.3%", effect_ids = {"hero_final_damage_bonus_pct"}, effect_values = {"0.3"}, icon_style = "shard", enabled = true, source_row = 26, source_boss_difficulty = "n4" },
    { item_id = "shadow_23", display_name = "虚无之眼", quality = "green", max_owned = 430, description = "箭塔攻击加成+0.3%", effect_ids = {"tower_attack_bonus_pct"}, effect_values = {"0.3"}, icon_style = "shard", enabled = true, source_row = 27, source_boss_difficulty = "n4" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["item_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
