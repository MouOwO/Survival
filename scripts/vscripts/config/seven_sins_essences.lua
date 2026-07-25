local M = {}

M.challenge_id = "challenge_10"
M.encounter_id = "encounter_challenge_10"
M.drop_chance_pct = 40
M.drop_radius = 360
M.attack_interval_floor = 0.1

M.rows = {
    {
        legacy_id = "I03C",
        content_id = "item_seven_sins_wrath_essence",
        engine_item_name = "item_survival_wrath_essence",
        display_name = "暴怒精华",
        description = "点击使用强化冰火裁决+1，并且最终伤害+5%。",
        effect_type = "final_damage_pct",
        effect_value = 5,
        drop_weight = 12,
        icon_name = "item_demon_edge",
    },
    {
        legacy_id = "I03D",
        content_id = "item_seven_sins_gluttony_essence",
        engine_item_name = "item_survival_gluttony_essence",
        display_name = "暴食精华",
        description = "点击使用强化冰火裁决+1，并且攻击间隔-0.05秒。",
        effect_type = "attack_interval_flat",
        effect_value = 0.05,
        drop_weight = 14,
        icon_name = "item_gloves",
    },
    {
        legacy_id = "I03E",
        content_id = "item_seven_sins_sloth_essence",
        engine_item_name = "item_survival_sloth_essence",
        display_name = "懒惰精华",
        description = "点击使用强化冰火裁决+1，并且杀敌全属性+5。",
        effect_type = "attributes_per_kill",
        effect_value = 5,
        drop_weight = 14,
        icon_name = "item_ultimate_orb",
    },
    {
        legacy_id = "I03F",
        content_id = "item_seven_sins_envy_essence",
        engine_item_name = "item_survival_envy_essence",
        display_name = "妒忌精华",
        description = "点击使用强化冰火裁决+1，并且全属性加成+5%。",
        effect_type = "all_attributes_pct",
        effect_value = 5,
        drop_weight = 14,
        icon_name = "item_skadi",
    },
    {
        legacy_id = "I03G",
        content_id = "item_seven_sins_pride_essence",
        engine_item_name = "item_survival_pride_essence",
        display_name = "傲慢精华",
        description = "点击使用强化冰火裁决+1，并且攻击加成+20%。",
        effect_type = "attack_bonus_pct",
        effect_value = 20,
        drop_weight = 14,
        icon_name = "item_reaver",
    },
    {
        legacy_id = "I03H",
        content_id = "item_seven_sins_greed_essence",
        engine_item_name = "item_survival_greed_essence",
        display_name = "贪婪精华",
        description = "点击使用强化冰火裁决+1，并且每次攻击全属性+3。",
        effect_type = "attributes_per_attack",
        effect_value = 3,
        drop_weight = 16,
        icon_name = "item_eagle",
    },
    {
        legacy_id = "I03I",
        content_id = "item_seven_sins_lust_essence",
        engine_item_name = "item_survival_lust_essence",
        display_name = "色欲精华",
        description = "点击使用强化冰火裁决+1，并且每次攻击减甲+3。",
        effect_type = "armor_reduction_per_attack",
        effect_value = 3,
        drop_weight = 12,
        icon_name = "item_blades_of_attack",
    },
}

M.by_content_id = {}
M.by_engine_item_name = {}
for index, row in ipairs(M.rows) do
    row.sequence_index = index
    M.by_content_id[row.content_id] = row
    M.by_engine_item_name[row.engine_item_name] = row
end

return M