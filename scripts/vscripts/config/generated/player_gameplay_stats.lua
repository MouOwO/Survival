-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: player_gameplay_stats.csv
local M = {}
M.rows = {
    { field_id = "initial_wood", storage_type = "integer", default_value = 10, unit = "wood", min_value = 0, enabled = true, notes = "玩家初始木材数量。" },
    { field_id = "initial_gold", storage_type = "integer", default_value = 0, unit = "gold", min_value = 0, enabled = true, notes = "玩家初始金币数量。" },
    { field_id = "wood_per_second", storage_type = "decimal", default_value = 1, unit = "wood_per_second", min_value = 0, enabled = true, notes = "玩家每秒木材增加量。" },
    { field_id = "lumberjack_attack_efficiency", storage_type = "integer", default_value = 13, unit = "wood_per_attack", min_value = 0, enabled = true, notes = "伐木工每次攻击的基础采集值。" },
    { field_id = "gold_per_second", storage_type = "decimal", default_value = 0, unit = "gold_per_second", min_value = 0, enabled = true, notes = "玩家每秒金币增加量。" },
    { field_id = "gold_mine_efficiency_pct", storage_type = "percentage", default_value = 0, unit = "percent", min_value = 0, max_value = 10000, enabled = true, notes = "金矿收益百分比；15表示15%。" },
    { field_id = "initial_population_cap", storage_type = "integer", default_value = 0, unit = "population", min_value = 0, enabled = true, notes = "玩家初始人口上限。" },
    { field_id = "starjoy_points", storage_type = "integer", default_value = 0, unit = "points", min_value = 0, enabled = true, notes = "星悦积分。" },
    { field_id = "hero_initial_attack", storage_type = "integer", default_value = 100, unit = "attack", min_value = 0, enabled = true, notes = "英雄初始攻击力。" },
    { field_id = "hero_damage_attack_growth", storage_type = "decimal", default_value = 1, unit = "attack_per_damage", min_value = 0, enabled = true, notes = "英雄每次造成伤害后的攻击力增加量。" },
    { field_id = "hero_basic_attack_growth", storage_type = "decimal", default_value = 1, unit = "attack_per_attack", min_value = 0, enabled = true, notes = "英雄每次普通攻击后的攻击力增加量。" },
    { field_id = "hero_final_damage_bonus_pct", storage_type = "percentage", default_value = 0, unit = "percent", min_value = 0, max_value = 10000, enabled = true, notes = "英雄最终伤害增加百分比；15表示15%。" },
    { field_id = "hero_attack_armor_reduction", storage_type = "decimal", default_value = 0, unit = "armor", min_value = 0, enabled = true, notes = "英雄攻击附带的初始减甲量。" },
    { field_id = "hero_attribute_growth", storage_type = "decimal", default_value = 1, unit = "attribute_per_growth", min_value = 0, enabled = true, notes = "英雄攻击三围成长量。" },
    { field_id = "hero_attributes_per_second", storage_type = "decimal", default_value = 0, unit = "attributes_per_second", min_value = 0, enabled = true, notes = "星之庇佑每秒增加的英雄全属性。" },
    { field_id = "hero_critical_damage_bonus_pct", storage_type = "percentage", default_value = 0, unit = "percent", min_value = 0, max_value = 10000, enabled = true, notes = "英雄暴击伤害增加百分比；25表示25%。" },
    { field_id = "hero_attack_bonus_pct", storage_type = "percentage", default_value = 0, unit = "percent", min_value = 0, max_value = 10000, enabled = true, notes = "英雄攻击力加成百分比；20表示20%。" },
    { field_id = "hero_health_bonus_pct", storage_type = "percentage", default_value = 0, unit = "percent", min_value = 0, max_value = 10000, enabled = true, notes = "英雄生命值加成百分比；20表示20%。" },
    { field_id = "hero_armor_bonus_pct", storage_type = "percentage", default_value = 0, unit = "percent", min_value = 0, max_value = 10000, enabled = true, notes = "英雄护甲加成百分比；20表示20%。" },
    { field_id = "hero_damage_reduction_pct", storage_type = "percentage", default_value = 0, unit = "percent", min_value = 0, max_value = 100, enabled = true, notes = "英雄伤害减免百分比；10表示10%。" },
    { field_id = "tower_attack_bonus_pct", storage_type = "percentage", default_value = 0, unit = "percent", min_value = 0, max_value = 10000, enabled = true, notes = "防御塔攻击力加成百分比；20表示20%。" },
    { field_id = "tower_attack_speed_bonus_pct", storage_type = "percentage", default_value = 0, unit = "percent", min_value = 0, max_value = 10000, enabled = true, notes = "防御塔攻速加成百分比；20表示20%。" },
    { field_id = "tower_attack_armor_reduction", storage_type = "decimal", default_value = 0, unit = "armor", min_value = 0, enabled = true, notes = "防御塔攻击附带的减甲数量。" },
    { field_id = "tower_critical_chance_pct", storage_type = "percentage", default_value = 0, unit = "percent", min_value = 0, max_value = 100, enabled = true, notes = "防御塔暴击几率百分比；15表示15%。" },
    { field_id = "tower_attack_interval", storage_type = "decimal", default_value = 1.7, unit = "seconds", min_value = 0.01, enabled = true, notes = "防御塔攻击间隔，单位为秒。" },
    { field_id = "tower_final_damage_bonus_pct", storage_type = "percentage", default_value = 0, unit = "percent", min_value = 0, max_value = 10000, enabled = true, notes = "防御塔最终伤害增加百分比；15表示15%。" },
    { field_id = "tower_attack_per_second", storage_type = "decimal", default_value = 0, unit = "attack_per_second", min_value = 0, enabled = true, notes = "星之庇佑每秒增加的防御塔攻击力。" },
    { field_id = "wall_damage_block", storage_type = "decimal", default_value = 0, unit = "damage", min_value = 0, enabled = true, notes = "城墙每次抵挡的固定伤害。" },
    { field_id = "wall_damage_reduction_pct", storage_type = "percentage", default_value = 0, unit = "percent", min_value = 0, max_value = 100, enabled = true, notes = "城墙伤害减免百分比；20表示20%。" },
    { field_id = "wall_armor_bonus_pct", storage_type = "percentage", default_value = 0, unit = "percent", min_value = 0, max_value = 10000, enabled = true, notes = "城墙防御力加成百分比；20表示20%。" },
    { field_id = "wall_health_regen_per_second", storage_type = "decimal", default_value = 0, unit = "health_per_second", min_value = 0, enabled = true, notes = "城墙每秒回血增加量。" },
    { field_id = "wall_initial_health", storage_type = "integer", default_value = 1000, unit = "health", min_value = 0, enabled = true, notes = "城墙初始生命值。" },
    { field_id = "wall_armor", storage_type = "decimal", default_value = 0, unit = "armor", min_value = 0, enabled = true, notes = "城墙初始护甲值。" },
    { field_id = "wall_health_bonus_pct", storage_type = "percentage", default_value = 0, unit = "percent", min_value = 0, max_value = 10000, enabled = true, notes = "城墙生命值加成百分比；20表示20%。" },
    { field_id = "wall_health_per_second", storage_type = "decimal", default_value = 0, unit = "health_per_second", min_value = 0, enabled = true, notes = "城墙每秒生命值增加量。" },
    { field_id = "lumberjack_attack_growth", storage_type = "decimal", default_value = 1, unit = "attack_per_growth", min_value = 0, enabled = true, notes = "伐木工每次攻击后的攻击力成长量。" },
    { field_id = "lumberjack_attack_speed_bonus_pct", storage_type = "percentage", default_value = 0, unit = "percent", min_value = 0, max_value = 10000, enabled = true, notes = "伐木工攻速加成百分比；20表示20%。" },
    { field_id = "online_seconds_total", storage_type = "integer", default_value = 0, unit = "seconds", min_value = 0, enabled = true, notes = "玩家永久累计在线时长；只累计同一session租约内的有效相邻心跳秒数，不计算掉线间隔。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["field_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
