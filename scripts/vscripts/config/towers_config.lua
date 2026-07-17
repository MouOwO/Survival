-- ============================================================================
-- Towers Config - 箭塔转职配置
-- ============================================================================
TOWERS_CONFIG = {
    -- 转职选项（箭塔5级后可转职）
    class_change = {
        { name = "暴击塔", kv_name = "building_tower_crit", desc = "攻击有暴击效果", bonus = "crit" },
        { name = "冰冻塔", kv_name = "building_tower_frost", desc = "攻击减速敌人", bonus = "frost" },
        { name = "机枪塔", kv_name = "building_tower_mg", desc = "高攻速", bonus = "mg" },
        { name = "防空塔", kv_name = "building_tower_air", desc = "对空中单位伤害加成", bonus = "air" },
        { name = "雷电塔", kv_name = "building_tower_lightning", desc = "AOE伤害", bonus = "aoe" },
    },

    -- 转职后继续升级5级
    post_class_levels = 5,
    post_class_upgrade_wood = 50,
    post_class_upgrade_gold = 20,

    -- 暴击塔参数
    crit = {
        crit_chance = 0.2,
        crit_multiplier = 2.0,
    },

    -- 冰冻塔参数
    frost = {
        slow_percent = 0.3,
        slow_duration = 3.0,
    },

    -- 机枪塔参数
    mg = {
        attack_speed_bonus = 2.0,
    },

    -- 防空塔参数
    air = {
        air_bonus_multiplier = 2.5,
    },

    -- 雷电塔参数
    aoe = {
        aoe_radius = 200,
        aoe_multiplier = 0.6,
    },
}
