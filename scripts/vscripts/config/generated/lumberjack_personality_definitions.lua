-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: lumberjack_personality_definitions.csv
local M = {}
M.rows = {
    { skill_id = "lumberjack_personality_self_pua", ability_name = "ability_lumberjack_personality_self_pua", name = "自我PUA", description = "每次采集后伐木工攻击力成长5点", effect_type = "attack_growth", effect_value = 5, enabled = true, source = "伐木工超级合成", notes = "超级伐木工LV1" },
    { skill_id = "lumberjack_personality_leader", ability_name = "ability_lumberjack_personality_leader", name = "领袖气质", description = "除自身之外的其他伐木工攻速提高20%", effect_type = "other_lumberjack_attack_speed_pct", effect_value = 20, enabled = true, source = "伐木工超级合成", notes = "超级伐木工LV2" },
    { skill_id = "lumberjack_personality_study", ability_name = "ability_lumberjack_personality_study", name = "喜欢钻研", description = "每次采集量增加20", effect_type = "wood_per_hit_flat", effect_value = 20, enabled = true, source = "伐木工超级合成", notes = "超级伐木工LV3" },
    { skill_id = "lumberjack_personality_heavy_hand", ability_name = "ability_lumberjack_personality_heavy_hand", name = "手很重", description = "每次采集有1%概率直接减少资源树生命值1点", effect_type = "tree_damage_chance_pct", effect_value = 1, enabled = true, source = "伐木工超级合成", notes = "超级伐木工LV4" },
    { skill_id = "lumberjack_personality_cheer", ability_name = "ability_lumberjack_personality_cheer", name = "啦啦队", description = "为所属玩家英雄和防御塔增加10%攻速，多个可叠加", effect_type = "owner_attack_speed_pct", effect_value = 10, enabled = true, source = "伐木工超级合成", notes = "超级伐木工LV5" },
    { skill_id = "lumberjack_personality_high_pressure", ability_name = "ability_lumberjack_personality_high_pressure", name = "血压高", description = "伐木工攻击力增加20%", effect_type = "lumberjack_attack_pct", effect_value = 20, enabled = true, source = "伐木工超级合成", notes = "超级伐木工LV6" },
    { skill_id = "lumberjack_personality_efficiency", ability_name = "ability_lumberjack_personality_efficiency", name = "效率", description = "伐木工攻击间隔减少30%", effect_type = "lumberjack_attack_speed_pct", effect_value = 30, enabled = true, source = "伐木工超级合成", notes = "超级伐木工LV7" },
    { skill_id = "lumberjack_personality_chosen", ability_name = "ability_lumberjack_personality_chosen", name = "天选之子", description = "每次采集有1%概率获得10倍木材", effect_type = "wood_multiplier_chance_pct", effect_value = 1, enabled = true, source = "伐木工超级合成", notes = "技能池备用" },
    { skill_id = "lumberjack_personality_workaholic", ability_name = "ability_lumberjack_personality_workaholic", name = "工作狂", description = "攻击间隔减少0.03秒", effect_type = "attack_interval_flat", effect_value = 0.03, enabled = true, source = "伐木工超级合成", notes = "技能池备用" },
    { skill_id = "lumberjack_personality_discoverer", ability_name = "ability_lumberjack_personality_discoverer", name = "善于发现", description = "每次采集获得10金币", effect_type = "gold_per_hit_flat", effect_value = 10, enabled = true, source = "伐木工超级合成", notes = "技能池备用" },
    { skill_id = "lumberjack_personality_scavenger", ability_name = "ability_lumberjack_personality_scavenger", name = "喜欢捡漏", description = "每次砍死资源树有10%概率获得当前木材总数10%，最多3次", effect_type = "tree_death_wood_pct", effect_value = 10, enabled = true, source = "伐木工超级合成", notes = "技能池备用" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["skill_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
