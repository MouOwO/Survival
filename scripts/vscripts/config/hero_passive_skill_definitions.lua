local M = {}

local function skill(row)
    row.max_level = tonumber(row.max_level) or 3
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
        skill_id = "proto_chain_lightning", display_name = "怒雷", icon_name = "zuus_lightning_bolt",
        max_level = 5,
        trigger_chance = { 0.20, 0.20, 0.45, 0.45, 0.45 },
        damage_multiplier = { 3.00, 3.00, 3.00, 3.00, 3.00 },
        radius = { 400, 400, 400, 400, 400 },
        splash_multiplier = { 0.50, 0.50, 0.50, 0.50, 0.50 },
        mark_duration = { 3.0, 3.0, 3.0, 3.0, 3.0 },
        mark_bonus_multiplier = { 0, 1.50, 1.50, 1.50, 1.50 },
        mark_attack_reduction_pct = { 0, 0, 15, 15, 15 },
        strike_count = { 1, 1, 1, 1, 3 },
        level_effects = {
            [2] = { effect_id = "mark", duration = 3.0, bonus_multiplier = 1.50 },
            [3] = { effect_id = "mark_attack_reduction", duration = 3.0,
                bonus_multiplier = 1.50, attack_reduction_pct = 15 },
            [4] = { effect_id = "mark_attack_reduction", duration = 3.0,
                bonus_multiplier = 1.50, attack_reduction_pct = 15 },
            [5] = { effect_id = "triple_strike", duration = 3.0,
                bonus_multiplier = 1.50, attack_reduction_pct = 15, strike_count = 3 },
        },
        level_text = {
            "普通攻击命中时，20%概率对目标落雷，造成全属性总和×3伤害，并对400范围内其他敌人造成50%伤害。",
            "怒雷命中目标施加3秒标记；标记期间再次被怒雷命中，额外受到全属性总和×1.5伤害。每次命中都会刷新标记。",
            "触发概率提高至45%；被标记的敌人攻击力降低15%，持续至标记结束。",
            "完整继承等级3效果，无额外变化。",
            "怒雷连续释放3道；同一目标重复被落雷命中时，该目标从第二道起每道伤害减半。每道雷都会触发标记效果。",
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
        max_level = 5,
        trigger_chance = { 0.10, 0.10, 0.10, 0.10, 0.10 },
        damage_multiplier = { 2.00, 2.00, 2.00, 2.00, 2.00 },
        landing_radius = { 500, 200, 200, 200, 200 },
        missile_count = { 5, 5, 7, 7, 7 },
        explosion_radius = { 150, 150, 150, 150, 150 },
        barrage_count = { 1, 1, 1, 1, 3 },
        barrage_interval = { 1.0, 1.0, 1.0, 1.0, 1.0 },
        missile_window = { 1.0, 1.0, 1.0, 1.0, 1.0 },
        level_effects = {
            [2] = { effect_id = "concentrated_barrage", landing_radius = 200 },
            [3] = { effect_id = "additional_missiles", missile_count = 7 },
            [4] = { effect_id = "inherit_level_three", missile_count = 7 },
            [5] = { effect_id = "sustained_barrage", barrage_count = 3, total_missiles = 21 },
        },
        level_text = {
            "普通攻击命中时有10%概率触发：以目标位置为中心，在500范围内于1秒内随机落下5颗飞弹。每颗飞弹对落点150范围造成全属性总和×2纯粹伤害。施法结束前不能再次触发。",
            "飞弹落点区域半径缩小至200，其他效果不变。",
            "每轮飞弹数量增加至7颗，其他效果不变。",
            "完整继承等级3效果，无额外变化。",
            "炮击区域持续3秒，每秒释放一轮7颗飞弹，共3轮、总计21颗飞弹。施法结束前不能再次触发。",
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
        local maximum = math.max(1, tonumber(row.max_level) or 1)
        for _, field in ipairs({ "trigger_chance", "damage_multiplier" }) do
            if array_size(row[field]) ~= maximum then
                fail(row.skill_id, field, "must_have_" .. tostring(maximum) .. "_items")
            end
        end
        if array_size(row.level_text) ~= maximum then
            fail(row.skill_id, "level_text", "must_have_" .. tostring(maximum) .. "_items")
        end
        for level = 2, maximum do
            if tonumber(row.trigger_chance[level]) < tonumber(row.trigger_chance[level - 1]) then
                fail(row.skill_id, "trigger_chance", "must_not_decrease")
            end
            if tonumber(row.damage_multiplier[level]) < tonumber(row.damage_multiplier[level - 1]) then
                fail(row.skill_id, "damage_multiplier", "must_not_decrease")
            end
        end
        for level, _ in pairs(row.level_effects or {}) do
            if type(level) ~= "number" or level < 1 or level > maximum then
                fail(row.skill_id, "level_effects", "level_out_of_range:" .. tostring(level))
            end
        end
        for field, values in pairs(row) do
            if type(values) == "table" and field ~= "level_effects" and field ~= "level_text"
                and array_size(values) > 0 and array_size(values) ~= maximum then
                fail(row.skill_id, field, "level_array_must_have_max_level_items")
            end
        end
    end
    if #errors > 0 then error("invalid hero passive skill config: " .. table.concat(errors, "; ")) end
    print(string.format("[HeroPassiveSkillConfig] validated skills=%d", #M.rows))
    return true
end

return M