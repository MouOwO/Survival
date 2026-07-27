local M = {}

local function skill(row)
    row.max_level = 3
    row.passive = true
    row.hidden = true
    row.trigger_type = row.trigger_type or "main_attack_landed"
    return row
end

M.rows = {
    skill({
        skill_id = "proto_flame_burst", display_name = "炎爆震击", icon_name = "lina_dragon_slave",
        trigger_chance = { 0.10, 0.16, 0.24 }, damage_multiplier = { 0.40, 0.65, 1.00 },
        radius = { 260, 300, 360 },
        level_effects = {
            [2] = { effect_id = "burn", duration = 3.0, interval = 1.0, dot_multiplier = 0.08 },
            [3] = { effect_id = "burn_then_explode", duration = 5.0, interval = 1.0,
                dot_multiplier = 0.12, secondary_multiplier = 0.35 },
        },
        level_text = {
            "普通攻击命中时，对目标周围260范围造成三围总和×0.40伤害。",
            "范围提高至300；附加3秒灼烧，每秒造成三围快照×0.08伤害。",
            "范围提高至360；灼烧5秒，每秒×0.12，结束时爆炸造成×0.35伤害。",
        },
    }),
    skill({
        skill_id = "proto_frost_nova", display_name = "冰霜新星", icon_name = "crystal_maiden_crystal_nova",
        trigger_chance = { 0.10, 0.16, 0.24 }, damage_multiplier = { 0.35, 0.60, 0.95 },
        radius = { 260, 300, 360 },
        level_effects = {
            [2] = { effect_id = "move_slow", move_slow_pct = 30, duration = 2.0 },
            [3] = { effect_id = "freeze_then_slow", freeze_duration = 1.0,
                move_slow_pct = 45, slow_duration = 3.0 },
        },
        level_text = {
            "普通攻击命中时，对目标周围260范围造成三围总和×0.35伤害。",
            "范围提高至300；降低敌人30%移动速度，持续2秒。",
            "范围提高至360；冰冻1秒，随后降低45%移动速度3秒。",
        },
    }),
    skill({
        skill_id = "proto_chain_lightning", display_name = "雷霆连锁", icon_name = "zuus_arc_lightning",
        trigger_chance = { 0.11, 0.17, 0.25 }, damage_multiplier = { 0.25, 0.40, 0.62 },
        max_targets = { 4, 6, 8 }, chain_radius = { 500, 550, 600 },
        level_effects = {
            [2] = { effect_id = "attack_slow", attack_slow_pct = 20, duration = 2.0 },
            [3] = { effect_id = "attack_slow_last_stun", attack_slow_pct = 40,
                duration = 3.0, stun_duration = 0.8 },
        },
        level_text = {
            "普通攻击命中时，连锁最多4个不同目标，每个受到三围总和×0.25伤害。",
            "目标提高至6个；降低20%攻击速度2秒。",
            "目标提高至8个；降低40%攻击速度3秒，最后目标眩晕0.8秒。",
        },
    }),
    skill({
        skill_id = "proto_poison_cloud", display_name = "毒云", icon_name = "viper_nethertoxin",
        trigger_chance = { 0.09, 0.14, 0.21 }, damage_multiplier = { 0.10, 0.17, 0.27 },
        radius = { 260, 310, 360 }, duration = { 4.0, 5.0, 6.0 }, interval = { 1.0, 1.0, 1.0 },
        level_effects = {
            [2] = { effect_id = "cloud_attack_slow", attack_slow_pct = 20, linger_duration = 0 },
            [3] = { effect_id = "cloud_attack_slow", attack_slow_pct = 35, linger_duration = 2.0 },
        },
        level_text = {
            "生成260范围毒云4秒，每秒造成三围快照×0.10伤害。",
            "范围310、持续5秒、每秒×0.17；区域内降低20%攻击速度。",
            "范围360、持续6秒、每秒×0.27；降低35%攻击速度，离开后保留2秒。",
        },
    }),
    skill({
        skill_id = "proto_blade_nova", display_name = "剑刃震荡", icon_name = "juggernaut_blade_fury",
        trigger_chance = { 0.10, 0.16, 0.24 }, damage_multiplier = { 0.45, 0.72, 1.08 },
        radius = { 280, 330, 380 },
        level_effects = {
            [2] = { effect_id = "bleed", duration = 3.0, interval = 1.0, dot_multiplier = 0.07 },
            [3] = { effect_id = "bleed_refresh", duration = 5.0, interval = 1.0, dot_multiplier = 0.12 },
        },
        level_text = {
            "普通攻击命中时，对英雄周围280范围造成三围总和×0.45伤害。",
            "范围330、伤害×0.72；流血3秒，每秒三围快照×0.07。",
            "范围380、伤害×1.08；流血5秒，每秒×0.12，再次命中刷新持续时间。",
        },
    }),
    skill({
        skill_id = "proto_earth_line", display_name = "地裂冲击", icon_name = "earthshaker_fissure",
        trigger_chance = { 0.10, 0.16, 0.23 }, damage_multiplier = { 0.42, 0.70, 1.05 },
        length = { 700, 800, 900 }, width = { 180, 210, 240 },
        level_effects = {
            [2] = { effect_id = "stun", stun_duration = 0.5 },
            [3] = { effect_id = "stun_then_second_line", stun_duration = 1.0,
                secondary_delay = 0.5, secondary_multiplier = 0.45 },
        },
        level_text = {
            "向攻击方向产生700×180地裂，造成三围总和×0.42伤害。",
            "长度800、宽210、伤害×0.70；眩晕0.5秒。",
            "长度900、宽240、伤害×1.05；眩晕1秒，0.5秒后同路径二次造成×0.45伤害。",
        },
    }),
    skill({
        skill_id = "proto_meteor", display_name = "陨石坠落", icon_name = "invoker_chaos_meteor",
        trigger_chance = { 0.08, 0.13, 0.20 }, damage_multiplier = { 0.55, 0.88, 1.30 },
        radius = { 280, 330, 380 }, delay = { 0.8, 0.8, 0.8 },
        level_effects = {
            [2] = { effect_id = "burning_ground", duration = 3.0, interval = 1.0, dot_multiplier = 0.08 },
            [3] = { effect_id = "stun_burning_ground", center_radius_pct = 0.5,
                stun_duration = 1.0, duration = 5.0, interval = 1.0, dot_multiplier = 0.14 },
        },
        level_text = {
            "0.8秒后轰击记录位置，280范围造成三围总和×0.55伤害。",
            "范围330、伤害×0.88；生成3秒灼烧地面，每秒×0.08。",
            "范围380、伤害×1.30；中心眩晕1秒，灼烧地面5秒，每秒×0.14。",
        },
    }),
    skill({
        skill_id = "proto_arcane_barrage", display_name = "奥术弹幕", icon_name = "skywrath_mage_arcane_bolt",
        trigger_chance = { 0.11, 0.17, 0.25 }, damage_multiplier = { 0.22, 0.36, 0.55 },
        max_targets = { 3, 5, 7 }, search_radius = { 700, 800, 900 },
        level_effects = {
            [2] = { effect_id = "skill_vulnerability", vulnerability_pct = 5, duration = 3.0 },
            [3] = { effect_id = "skill_vulnerability", vulnerability_pct = 12, duration = 5.0 },
        },
        level_text = {
            "攻击最多3个不同目标，每个受到三围总和×0.22伤害。",
            "目标提高至5个、伤害×0.36；随机被动技能易伤5%，持续3秒。",
            "目标提高至7个、伤害×0.55；随机被动技能易伤12%，持续5秒。",
        },
    }),
    skill({
        skill_id = "proto_shadow_blast", display_name = "暗影爆裂", icon_name = "nevermore_shadowraze1",
        trigger_type = "main_attack_direct_kill",
        trigger_chance = { 0.20, 0.32, 0.45 }, damage_multiplier = { 0.40, 0.68, 1.00 },
        radius = { 260, 310, 360 },
        level_effects = {
            [2] = { effect_id = "move_slow", move_slow_pct = 25, duration = 2.0 },
            [3] = { effect_id = "move_slow_shadow_pulse", move_slow_pct = 40,
                duration = 3.0, minimum_targets = 3, secondary_multiplier = 0.40 },
        },
        level_text = {
            "英雄主攻击直接击杀后，对周围260范围造成三围总和×0.40伤害。",
            "范围310、伤害×0.68；降低25%移动速度2秒。",
            "范围360、伤害×1.00；降低40%移动速度3秒，命中至少3人时追加×0.40暗影脉冲。",
        },
    }),
    skill({
        skill_id = "proto_holy_pulse", display_name = "圣光震荡", icon_name = "omniknight_purification",
        trigger_chance = { 0.10, 0.16, 0.24 }, damage_multiplier = { 0.38, 0.64, 0.98 },
        radius = { 300, 350, 400 },
        level_effects = {
            [2] = { effect_id = "attack_slow", attack_slow_pct = 20, duration = 2.0 },
            [3] = { effect_id = "attack_slow_second_pulse", attack_slow_pct = 35,
                duration = 3.0, secondary_delay = 0.6, secondary_multiplier = 0.40 },
        },
        level_text = {
            "普通攻击命中时，对英雄周围300范围造成三围总和×0.38伤害。",
            "范围350、伤害×0.64；降低20%攻击速度2秒。",
            "范围400、伤害×0.98；降低35%攻击速度3秒，0.6秒后追加×0.40脉冲。",
        },
    }),
    skill({
        skill_id = "proto_ice_cone", display_name = "寒冰锥", icon_name = "drow_ranger_wave_of_silence",
        trigger_chance = { 0.10, 0.16, 0.24 }, damage_multiplier = { 0.38, 0.65, 1.00 },
        distance = { 600, 680, 750 }, angle = { 70, 78, 85 },
        level_effects = {
            [2] = { effect_id = "move_slow", move_slow_pct = 30, duration = 2.0 },
            [3] = { effect_id = "center_freeze_else_slow", center_angle_pct = 0.4,
                freeze_duration = 1.2, move_slow_pct = 45, duration = 3.0 },
        },
        level_text = {
            "向攻击方向释放600距离、70度冰锥，造成三围总和×0.38伤害。",
            "距离680、角度78、伤害×0.65；降低30%移动速度2秒。",
            "距离750、角度85、伤害×1.00；中心冰冻1.2秒，其他区域减速45%共3秒。",
        },
    }),
    skill({
        skill_id = "proto_void_pulse", display_name = "虚空震爆", icon_name = "faceless_void_time_dilation",
        trigger_chance = { 0.09, 0.15, 0.22 }, damage_multiplier = { 0.45, 0.72, 1.10 },
        radius = { 300, 350, 400 }, center_radius_pct = { 0.5, 0.5, 0.5 },
        center_bonus_pct = { 0.50, 0.50, 0.50 },
        level_effects = {
            [2] = { effect_id = "attack_slow", attack_slow_pct = 25, duration = 2.0 },
            [3] = { effect_id = "attack_slow_aftershock", attack_slow_pct = 40,
                duration = 3.0, secondary_delay = 0.7, secondary_multiplier = 0.45 },
        },
        level_text = {
            "对目标周围300范围造成三围总和×0.45伤害；中心区域同一次结算额外提高50%。",
            "范围350、伤害×0.72；降低25%攻击速度2秒。",
            "范围400、伤害×1.10；降低40%攻击速度3秒，0.7秒后中心位置余震×0.45。",
        },
    }),
}

M.by_id = {}
for _, row in ipairs(M.rows) do M.by_id[row.skill_id] = row end

local function array_size(value)
    if type(value) ~= "table" then return 0 end
    local count = 0
    for index, _ in ipairs(value) do count = index end
    return count
end

function M.validate()
    local errors = {}
    local function fail(skill_id, field, detail)
        local message = string.format("skill_id=%s field=%s %s", skill_id, field, detail)
        errors[#errors + 1] = message
        print("[HeroPassiveSkillConfig] ERROR " .. message)
    end
    for _, row in ipairs(M.rows) do
        if row.max_level ~= 3 then fail(row.skill_id, "max_level", "must_equal_3") end
        for _, field in ipairs({ "trigger_chance", "damage_multiplier" }) do
            if array_size(row[field]) ~= 3 then fail(row.skill_id, field, "must_have_3_items") end
        end
        for level = 2, 3 do
            if tonumber(row.trigger_chance[level]) <= tonumber(row.trigger_chance[level - 1]) then
                fail(row.skill_id, "trigger_chance", "must_strictly_increase")
            end
            if tonumber(row.damage_multiplier[level]) < tonumber(row.damage_multiplier[level - 1]) then
                fail(row.skill_id, "damage_multiplier", "must_not_decrease")
            end
        end
        for level, _ in pairs(row.level_effects or {}) do
            if type(level) ~= "number" or level < 1 or level > 3 then
                fail(row.skill_id, "level_effects", "level_out_of_range:" .. tostring(level))
            end
        end
        for field, values in pairs(row) do
            if type(values) == "table" and field ~= "level_effects" and field ~= "level_text"
                and array_size(values) > 0 and array_size(values) ~= 3 then
                fail(row.skill_id, field, "level_array_must_have_3_items")
            end
        end
    end
    if #errors > 0 then error("invalid hero passive skill config: " .. table.concat(errors, "; ")) end
    print(string.format("[HeroPassiveSkillConfig] validated skills=%d max_level=3", #M.rows))
    return true
end

return M