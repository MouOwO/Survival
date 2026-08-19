-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: global_rules.csv
local M = {}
M.rows = {
    { rule_id = "tower_attack_range", value = 1000, description = "所有防御塔统一基础攻击距离", enabled = true },
    { rule_id = "tower_acquisition_range", value = 1000, description = "所有防御塔统一基础索敌距离", enabled = true },
    { rule_id = "tower_base_projectile_speed", value = 5000, description = "基础箭塔原始弹道速度", enabled = true },
    { rule_id = "tower_route_default_projectile_speed", value = 1250, description = "无独立配置转职塔的原始弹道速度", enabled = true },
    { rule_id = "tower_class_max_count", value = 5, description = "每条箭塔转职路线允许同时存在的最大数量", enabled = true },
    { rule_id = "tower_projectile_speed_multiplier", value = 1, description = "所有防御塔弹道速度倍率", enabled = true },
    { rule_id = "base_arrow_tower_cannot_miss", value = 1, description = "未转职基础箭塔普通攻击必中（0关闭1开启）", enabled = true },
    { rule_id = "monster_war3_armor_damage_enabled", value = 0, description = "废弃兼容字段；怪物物理伤害固定使用项目War3护甲公式", enabled = false },
    { rule_id = "wave_monster_round_robin_enabled", value = 1, description = "每波普通怪按类型循环；地面飞行混合时按两地面一飞行（0关闭1开启）", enabled = true },
    { rule_id = "wave_ground_monster_hull_radius", value = 32, description = "正式波次及默认地面怪统一基础碰撞半径", enabled = true },
    { rule_id = "practice_monster_hull_radius", value = 12, description = "练功房怪物统一基础碰撞半径", enabled = true },
    { rule_id = "repair_detection_range", value = 99999, description = "修理师自动感知受损建筑的范围", enabled = true },
    { rule_id = "building_challenge_hull_radius", value = 0, description = "所有挑战怪的基础碰撞半径", enabled = true },
    { rule_id = "building_challenge_lifetime_seconds", value = 60, description = "挑战怪存活达到该秒数时挑战失败", enabled = true },
    { rule_id = "building_challenge_wall_failure_health_pct", value = 50, description = "挑战期间城墙生命低于该百分比时挑战失败", enabled = true },
    { rule_id = "building_challenge_failure_check_interval_seconds", value = 0.1, description = "挑战期间检查城墙生命的间隔秒数", enabled = true },
    { rule_id = "initial_gold", value = 0, description = "队伍开局金币", enabled = true },
    { rule_id = "initial_wood", value = 10, description = "队伍开局木材", enabled = true },
    { rule_id = "initial_population", value = 0, description = "队伍开局已用人口", enabled = true },
    { rule_id = "initial_max_population", value = 0, description = "队伍开局人口上限", enabled = true },
    { rule_id = "tree_lumber_efficiency_buff_per_level", value = 1, description = "资源树从LV2起每级增加的伐木效率", enabled = true },
    { rule_id = "hero_base_lumber_efficiency", value = 13, description = "英雄每次攻击资源树的基础木材收益", enabled = true },
    { rule_id = "hero_meta_all_attributes_bonus", value = 0, description = "全体英雄局外全属性加成", enabled = true },
    { rule_id = "hero_meta_damage_multiplier", value = 1, description = "全体英雄局外伤害倍率", enabled = true },
    { rule_id = "hero_meta_max_health_multiplier", value = 1, description = "全体英雄局外最大生命倍率", enabled = true },
    { rule_id = "hero_meta_max_mana_multiplier", value = 1, description = "全体英雄局外最大魔法倍率", enabled = true },
    { rule_id = "hero_meta_move_speed_bonus", value = 0, description = "全体英雄局外移动速度加成", enabled = true },
    { rule_id = "monster_corpse_hold_seconds", value = 0.6, description = "怪物死亡后在原地保留死亡表现的秒数", enabled = true },
    { rule_id = "monster_corpse_sink_seconds", value = 0.8, description = "怪物尸体平滑下沉所需秒数", enabled = true },
    { rule_id = "monster_corpse_sink_depth", value = 160, description = "怪物尸体下沉的垂直距离", enabled = true },
    { rule_id = "monster_corpse_update_interval", value = 0.05, description = "全部怪物尸体共享更新任务的间隔秒数", enabled = true },
    { rule_id = "monster_corpse_remove_delay_seconds", value = 0.05, description = "尸体隐藏后安全移除实体的延迟秒数", enabled = true },
    { rule_id = "runtime_detailed_diagnostics", value = 0, description = "运行时攻击与技能成功路径详细日志开关（0关闭1开启）", enabled = true },
    { rule_id = "dev_wall_health", value = 100000000, description = "输入dev后城墙的开发模式最大生命和当前生命", enabled = true },
    { rule_id = "dev_wall_war3_armor", value = 100000, description = "输入dev后城墙的开发模式War3护甲", enabled = true },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["rule_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
