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
        skill_id = "proto_flame_burst", display_name = "爆炎弹", icon_name = "lina_dragon_slave",
        max_level = 5,
        trigger_chance = { 0.15, 0.15, 0.15, 0.15, 0.15 },
        damage_multiplier = { 4.00, 4.00, 4.00, 4.00, 4.00 },
        radius = { 500, 500, 500, 500, 500 },
        burn_total_multiplier = { 0, 2.20, 2.20, 2.20, 2.20 },
        burn_duration = { 0, 3.0, 3.0, 3.0, 3.0 },
        burn_interval = { 0, 1.0, 1.0, 1.0, 1.0 },
        burn_max_stacks = { 0, 1, 5, 5, 5 },
        small_fireball_count = { 0, 0, 0, 0, 3 },
        small_fireball_landing_radius = { 0, 0, 0, 0, 200 },
        small_fireball_explosion_radius = { 0, 0, 0, 0, 250 },
        small_fireball_damage_multiplier = { 0, 0, 0, 0, 3.00 },
        small_fireball_flight_time = { 0, 0, 0, 0, 0.5 },
        level_text = {
            "攻击命中时有15%概率引爆目标位置，对500范围造成全属性×4纯粹伤害。",
            "主爆炸命中的敌人被点燃，在3秒内总计受到全属性×2.2额外伤害。再次点燃会替换旧点燃并重新持续3秒。",
            "点燃最多叠加5层；每层拥有独立的3秒持续时间和属性快照，超过5层时替换最早到期的一层。",
            "完整继承等级3效果，无额外变化。",
            "主爆炸后同时喷射3颗小火球，0.5秒后落在主爆炸中心200范围内的随机位置。每颗对250范围造成全属性×3伤害，并分别施加1层点燃。",
        },
    }),
    skill({
        skill_id = "proto_frost_nova", display_name = "移动冰球", icon_name = "crystal_maiden_crystal_nova",
        max_level = 5,
        trigger_chance = { 0.12, 0.12, 0.12, 0.12, 0.12 },
        damage_multiplier = { 2.00, 2.00, 2.00, 2.00, 2.00 },
        radius = { 300, 300, 350, 350, 350 },
        move_speed = { 360, 540, 540, 540, 540 },
        damage_interval = { 0.5, 0.5, 0.5, 0.5, 0.5 },
        collision_bonus_pct = { 0, 5, 5, 5, 5 },
        collision_max_stacks = { 0, 10, 10, 10, 10 },
        explosion_multiplier = { 0, 0, 3.00, 3.00, 3.00 },
        max_distance_multiplier = { 1.00, 1.00, 1.00, 1.00, 1.50 },
        homing = { 0, 0, 0, 0, 1 },
        distance_bonus_pct_per_100 = { 0, 0, 0, 0, 10 },
        collision_width = { 128, 128, 128, 128, 128 },
        level_text = {
            "攻击命中时有12%概率向目标方向释放冰球。冰球以360速度直线移动，每0.5秒对300范围造成全属性×2伤害。",
            "冰球速度提高50%至540；每碰撞一个不同敌人，周期基础伤害提高5%，最多10次。",
            "冰球影响半径扩大至350；飞行结束时爆炸，对350范围造成一次全属性×3伤害。",
            "完整继承等级3效果，无额外变化。",
            "冰球自动追踪最大移动距离内的随机敌人；最大移动距离提高50%，每移动100码周期基础伤害提高10%。目标死亡后直线飞向其死亡位置并爆炸。",
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
        max_level = 5,
        trigger_chance = { 0.12, 0.12, 0.20, 0.20, 0.20 },
        damage_multiplier = { 1.00, 1.00, 1.00, 1.00, 1.00 },
        radius = { 400, 400, 400, 400, 400 },
        duration = { 5.0, 5.0, 7.0, 7.0, 7.0 },
        interval = { 1.0, 1.0, 1.0, 1.0, 1.0 },
        armor_reduction_per_stack_pct = { 0, 20, 20, 20, 20 },
        armor_max_stacks = { 0, 3, 3, 3, 3 },
        death_explosion_radius = { 0, 0, 0, 0, 300 },
        death_explosion_multiplier = { 0, 0, 0, 0, 3.00 },
        level_effects = {
            [2] = { effect_id = "stacking_armor_reduction", armor_per_stack_pct = 20, max_stacks = 3 },
            [3] = { effect_id = "long_cloud", duration = 7.0, trigger_chance = 0.20 },
            [4] = { effect_id = "inherit_level_three", duration = 7.0, trigger_chance = 0.20 },
            [5] = { effect_id = "death_explosion", radius = 300, damage_multiplier = 3.00 },
        },
        level_text = {
            "普通攻击命中时，12%概率在目标位置生成400范围毒云，持续5秒；第1至第5秒各造成一次触发时全属性总和×1纯粹伤害。毒云活动期间同一英雄不会再次触发毒云。",
            "毒云每次整秒伤害命中使敌人的实时总护甲降低20%，最多3层（60%）；离开毒云或毒云消失时立即恢复毒云降低的护甲。",
            "触发概率提高至20%，毒云持续时间增加至7秒，因此第1至第7秒各造成一次伤害。",
            "完整继承等级3效果，无额外变化。",
            "毒云中的敌人死亡时，以死亡位置为中心对300范围造成一次触发时全属性总和×3纯粹伤害；死亡爆炸可继续引发毒云内敌人的连锁爆炸。",
        },
    }),
    skill({
        skill_id = "proto_blade_nova", display_name = "剑刃震荡", icon_name = "juggernaut_blade_fury",
        max_level = 5,
        trigger_chance = { 0.15, 0.15, 0.15, 0.15, 0.15 },
        damage_multiplier = { 4.00, 4.00, 4.00, 4.00, 4.00 },
        pulse_width = { 200, 200, 200, 200, 200 },
        range_multiplier = { 1.00, 1.00, 1.00, 1.00, 1.50 },
        first_target_multiplier = { 1.00, 2.00, 2.00, 2.00, 2.00 },
        maximum_distance_multiplier = { 1.00, 1.00, 2.00, 2.00, 2.00 },
        triple_pulse_chance = { 0, 0, 0, 0, 0.30 },
        triple_pulse_count = { 1, 1, 1, 1, 3 },
        pulse_duration = { 1.00, 1.00, 1.00, 1.00, 1.00 },
        level_effects = {
            [2] = { effect_id = "first_target_double", first_target_multiplier = 2.00 },
            [3] = { effect_id = "distance_scaling", maximum_distance_multiplier = 2.00 },
            [4] = { effect_id = "inherit_level_three", maximum_distance_multiplier = 2.00 },
            [5] = { effect_id = "triple_pulse", range_multiplier = 1.50,
                trigger_chance = 0.30, pulse_count = 3 },
        },
        level_text = {
            "普通攻击命中时有15%概率沿英雄面向发射脉冲。脉冲总宽度200，长度等于英雄攻击射程，对路径内所有敌人造成触发时全属性总和×4纯粹伤害。",
            "每道脉冲最先命中的目标受到双倍伤害。",
            "伤害随目标沿脉冲方向的距离线性提高：英雄近端为全属性×4，射程末端最高为全属性×8；首个目标仍会受到双倍伤害。",
            "完整继承等级3效果，无额外变化。",
            "脉冲射程提高50%；每次触发有30%概率沿同一路径同时发射3道脉冲。三道分别造成完整伤害，同一敌人可被三道分别命中。",
        },
    }),
    skill({
        skill_id = "proto_holy_pulse", display_name = "元气弹", icon_name = "keeper_of_the_light_illuminate",
        max_level = 5,
        trigger_chance = { 0.12, 0.12, 0.12, 0.12, 0.12 },
        damage_multiplier = { 4.00, 4.00, 4.00, 4.00, 4.00 },
        target_count = { 5, 5, 7, 7, 7 },
        bonus_target_chance = { 0, 0, 0.10, 0.10, 0.10 },
        bonus_target_count = { 0, 0, 2, 2, 2 },
        heal_max_health_pct = { 0, 5, 5, 5, 5 },
        projectile_speed = { 1000, 1000, 1000, 1000, 1000 },
        explosion_chance = { 0, 0, 0, 0, 0.20 },
        explosion_radius = { 0, 0, 0, 0, 250 },
        explosion_damage_pct = { 0, 0, 0, 0, 60 },
        level_text = {
            "攻击命中时有12%概率向英雄攻击射程内最近的最多5个敌人发射追踪元气弹。每颗命中造成触发时全属性×4纯粹伤害。",
            "每颗元气弹命中时恢复英雄5%最大生命值，按实际命中数量分别恢复。",
            "基础目标上限提高至7个；每次触发另有10%概率将本次目标上限提高至9个。",
            "完整继承等级3效果，无额外变化。",
            "每颗元气弹命中时独立有20%概率爆炸，对目标中心250范围内所有敌人额外造成该颗基础伤害60%的纯粹伤害；原目标也会重复承受爆炸伤害。",
        },
    }),
    skill({
        skill_id = "proto_meteor", display_name = "陨石坠落", icon_name = "invoker_chaos_meteor",
        max_level = 5,
        trigger_chance = { 0.12, 0.12, 0.12, 0.12, 0.12 },
        damage_multiplier = { 3.00, 3.00, 3.00, 3.00, 3.00 },
        radius = { 500, 500, 500, 500, 500 },
        fall_duration = { 0.8, 0.8, 0.8, 0.8, 0.8 },
        lava_duration = { 0, 3.0, 3.0, 3.0, 3.0 },
        lava_interval = { 0, 1.0, 1.0, 1.0, 1.0 },
        lava_damage_multiplier = { 0, 1.00, 1.00, 1.00, 1.00 },
        lava_move_slow_pct = { 0, 0, 30, 30, 30 },
        meteor_count = { 1, 1, 1, 1, 2 },
        second_meteor_delay = { 0, 0, 0, 0, 0.5 },
        second_meteor_damage_pct = { 0, 0, 0, 0, 80 },
        level_text = {
            "普通攻击命中时有12%概率在目标当时的位置坠落一颗陨石。落地后原地爆炸，不会滚动，对500范围造成触发时全属性×3纯粹伤害。陨石活动期间不能再次触发。",
            "陨石落地后留下500范围熔岩区域，持续3秒；落地后的第1、2、3秒各造成一次触发时全属性×1纯粹伤害。",
            "熔岩区域内的敌人降低30%移动速度；多个区域的减速不叠加，离开所有区域立即移除。",
            "完整继承等级3效果，无额外变化。",
            "第一颗陨石落地0.5秒后，在同一位置落下第二颗陨石。第二颗爆炸和熔岩伤害均为第一颗的80%；两片熔岩独立造成伤害。",
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
        skill_id = "proto_magic_slingshot", display_name = "魔法弹弓", icon_name = "tiny_toss",
        max_level = 5,
        trigger_chance = { 0.10, 0.10, 0.10, 0.10, 0.10 },
        damage_multiplier = { 3.00, 3.00, 3.00, 3.00, 3.00 },
        stunned_damage_multiplier = { 3.00, 3.00, 6.00, 6.00, 6.00 },
        target_count = { 5, 5, 5, 5, 5 },
        stun_duration = { 0.1, 1.0, 1.0, 1.0, 1.0 },
        prefer_unstunned = { 0, 1, 1, 1, 1 },
        projectile_speed = { 1000, 1000, 1000, 1000, 1000 },
        rubble_radius = { 0, 0, 0, 0, 200 },
        rubble_duration = { 0, 0, 0, 0, 3.0 },
        rubble_interval = { 0, 0, 0, 0, 1.0 },
        rubble_damage_multiplier = { 0, 0, 0, 0, 1.20 },
        rubble_move_slow_pct = { 0, 0, 0, 0, 30 },
        level_effects = {
            [2] = { effect_id = "prefer_unstunned", stun_duration = 1.0 },
            [3] = { effect_id = "stunned_bonus_damage", stunned_damage_multiplier = 6.00 },
            [4] = { effect_id = "inherit_level_three", stunned_damage_multiplier = 6.00 },
            [5] = { effect_id = "rubble_field", radius = 200, duration = 3.0,
                interval = 1.0, damage_multiplier = 1.20, move_slow_pct = 30 },
        },
        level_text = {
            "普通攻击命中时有10%概率触发：向英雄当前攻击射程内最近的5名敌人各发射一颗石弹。石弹命中造成全属性总和×3纯粹伤害并眩晕0.1秒。",
            "眩晕时间延长至1秒；选敌时优先选择当前未被眩晕的敌人，不足5名时再由已眩晕敌人补足。",
            "石弹命中瞬间若目标已处于眩晕状态，本颗石弹伤害提高至全属性总和×6；先结算旧眩晕增伤，再施加本次眩晕。",
            "完整继承等级3效果，无额外变化。",
            "石弹命中后尝试在目标位置生成半径200的碎石区，持续3秒。区域每秒造成全属性总和×1.2纯粹伤害，区域内敌人移动速度降低30%；多个区域减速不叠加，离开全部区域立即恢复。仍处于已有碎石区内的目标不会重复生成新区。",
        },
    }),
    skill({
        skill_id = "proto_ice_cone", display_name = "寒冰锥", icon_name = "crystal_maiden_freezing_field",
        max_level = 5,
        trigger_chance = { 0.15, 0.15, 0.15, 0.15, 0.15 },
        damage_multiplier = { 1.00, 1.00, 1.00, 1.00, 1.00 },
        radius = { 500, 500, 500, 500, 500 },
        impact_count = { 3, 3, 3, 3, 5 },
        impact_interval = { 1.0, 1.0, 1.0, 1.0, 1.0 },
        cast_duration = { 3.0, 3.0, 3.0, 3.0, 5.0 },
        attack_slow_pct = { 0, 20, 20, 20, 40 },
        attack_slow_duration = { 0, 3.0, 3.0, 3.0, 3.0 },
        freeze_chance = { 0, 0, 0.20, 0.20, 0.20 },
        freeze_duration = { 0, 0, 1.0, 1.0, 1.0 },
        level_effects = {
            [2] = { effect_id = "blizzard_attack_slow", attack_slow_pct = 20, duration = 3.0 },
            [3] = { effect_id = "blizzard_freeze", attack_slow_pct = 20,
                duration = 3.0, freeze_chance = 0.20, freeze_duration = 1.0 },
            [4] = { effect_id = "inherit_level_three", attack_slow_pct = 20,
                duration = 3.0, freeze_chance = 0.20, freeze_duration = 1.0 },
            [5] = { effect_id = "extended_blizzard", impact_count = 5,
                attack_slow_pct = 40, duration = 3.0,
                freeze_chance = 0.20, freeze_duration = 1.0 },
        },
        level_text = {
            "普通攻击命中时有15%概率触发：以目标位置为中心，在500范围内立即落下冰锥，之后每秒落下1次，共3次。每次造成触发时全属性总和×1纯粹伤害。暴风雪结束前不能再次触发。",
            "每次落冰使命中的敌人攻击速度降低20%，持续3秒；不可叠加，再次命中刷新持续时间。",
            "每次落冰对每个命中的敌人独立进行判定，有20%概率冻结1秒；保留20%攻击速度降低。",
            "完整继承等级3效果，无额外变化。",
            "落冰次数增加至5次，暴风雪持续时间增加至5秒；攻击速度降低提高至40%，其他效果不变。",
        },
    }),
    skill({
        skill_id = "proto_void_pulse", display_name = "虚空震爆", icon_name = "invoker_tornado",
        max_level = 5,
        trigger_chance = { 0.15, 0.15, 0.15, 0.15, 0.15 },
        damage_multiplier = { 2.00, 2.00, 2.00, 2.00, 2.00 },
        move_speed = { 500, 500, 500, 500, 500 },
        duration = { 3.0, 3.0, 3.0, 3.0, 3.0 },
        damage_interval = { 1.0, 1.0, 1.0, 1.0, 1.0 },
        hit_radius = { 300, 300, 300, 300, 300 },
        effect_radius = { 600, 600, 600, 600, 600 },
        area_slow_pct = { 0, 0, 20, 20, 20 },
        hit_slow_pct = { 0, 0, 15, 15, 15 },
        small_tornado_duration = { 0, 0, 0, 0, 2.0 },
        small_tornado_damage_pct = { 0, 0, 0, 0, 60 },
        level_text = {
            "普通攻击命中时有15%概率从攻击者位置释放龙卷风。龙卷风以500速度追踪原攻击目标，第一次到达后附着跟随目标；目标死亡则停在死亡位置。持续3秒，在生成时及第1、2秒实时读取全属性，对中心300范围造成全属性×2纯粹伤害。",
            "完整继承等级1效果，无额外变化。",
            "龙卷风中心600范围内的敌人持续降低20%移动速度；被主龙卷伤害命中的敌人在仍处于该范围时额外降低15%，总计35%，离开范围立即移除。",
            "完整继承等级3效果，无额外变化。",
            "主龙卷结束时，按仍存活的已命中不同目标数量在结束位置生成小龙卷。小龙卷随机选择这些目标的方向，以相同速度移动2秒，每秒造成主龙卷60%的实时属性伤害，并仅施加20%范围减速。",
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