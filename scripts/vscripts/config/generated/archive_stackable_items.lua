-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: archive_stackable_items.csv
local M = {}
M.rows = {
    { rule_id = "zongzi_base", item_id = "welfare_zongzi", display_name = "粽子", max_owned = 150, threshold = 0, effect_id = "hero_basic_attack_growth", effect_value = 0.05, mode = "per_copy", enabled = true, notes = "每份普攻攻击力成长叠加；薪火无游戏数量上限，粽子上限150", quality = "r", description = "每个粽子：每次普攻攻击力成长+0.05，可叠加，最多150个；数量>10：英雄每秒属性+100；>20：英雄攻击全属性+1；>30：伐木效率+1；>40：英雄攻击加成+3%；>50：英雄全属性加成+3%；>60：英雄攻击减甲+2；>70：英雄攻击全属性改为+2；>80：英雄最终伤害+2%；>90：英雄攻击减甲改为+3；>100：英雄攻击全属性改为+3；同属性只生效已达最高档，严格大于门槛生效；满150后仅接收剩余额度，超额不转积分" },
    { rule_id = "ember_base", item_id = "lottery_ember_of_legacy", display_name = "薪火余烬", max_owned = 0, threshold = 0, effect_id = "hero_basic_attack_growth", effect_value = 0.1, mode = "per_copy", enabled = true, notes = "每份普攻攻击力成长叠加；薪火无游戏数量上限，粽子上限150", quality = "ur", description = "每个薪火余烬：每次普攻攻击力成长+0.1，可叠加，无持有上限；数量>10：英雄每秒属性+100；>50：英雄攻击全属性+100；>100：英雄最终伤害+10%；>200：英雄攻击加成+30%；>300：英雄全属性加成+30%；>400：英雄攻击减甲+30；>600：英雄攻击全属性改为+40；>800：英雄最终伤害改为+120%；>1000：英雄攻击减甲改为+50；>1500：英雄攻击全属性改为+60；同属性只生效已达最高档，严格大于门槛生效；不会转化为积分" },
    { rule_id = "zongzi_10", item_id = "welfare_zongzi", display_name = "粽子", max_owned = 150, threshold = 10, effect_id = "hero_attributes_per_second", effect_value = 100, mode = "threshold", enabled = true, notes = "数量严格大于门槛；同属性仅生效已达最高档", quality = "r" },
    { rule_id = "zongzi_20", item_id = "welfare_zongzi", display_name = "粽子", max_owned = 150, threshold = 20, effect_id = "hero_attribute_growth", effect_value = 1, mode = "threshold", enabled = true, notes = "数量严格大于门槛；同属性仅生效已达最高档", quality = "r" },
    { rule_id = "zongzi_30", item_id = "welfare_zongzi", display_name = "粽子", max_owned = 150, threshold = 30, effect_id = "lumberjack_efficiency", effect_value = 1, mode = "threshold", enabled = true, notes = "数量严格大于门槛；同属性仅生效已达最高档", quality = "r" },
    { rule_id = "zongzi_40", item_id = "welfare_zongzi", display_name = "粽子", max_owned = 150, threshold = 40, effect_id = "hero_attack_bonus_pct", effect_value = 3, mode = "threshold", enabled = true, notes = "数量严格大于门槛；同属性仅生效已达最高档", quality = "r" },
    { rule_id = "zongzi_50", item_id = "welfare_zongzi", display_name = "粽子", max_owned = 150, threshold = 50, effect_id = "hero_attribute_bonus_pct", effect_value = 3, mode = "threshold", enabled = true, notes = "数量严格大于门槛；同属性仅生效已达最高档", quality = "r" },
    { rule_id = "zongzi_60", item_id = "welfare_zongzi", display_name = "粽子", max_owned = 150, threshold = 60, effect_id = "hero_attack_armor_reduction", effect_value = 2, mode = "threshold", enabled = true, notes = "数量严格大于门槛；同属性仅生效已达最高档", quality = "r" },
    { rule_id = "zongzi_70", item_id = "welfare_zongzi", display_name = "粽子", max_owned = 150, threshold = 70, effect_id = "hero_attribute_growth", effect_value = 2, mode = "threshold", enabled = true, notes = "数量严格大于门槛；同属性仅生效已达最高档", quality = "r" },
    { rule_id = "zongzi_80", item_id = "welfare_zongzi", display_name = "粽子", max_owned = 150, threshold = 80, effect_id = "hero_final_damage_bonus_pct", effect_value = 2, mode = "threshold", enabled = true, notes = "数量严格大于门槛；同属性仅生效已达最高档", quality = "r" },
    { rule_id = "zongzi_90", item_id = "welfare_zongzi", display_name = "粽子", max_owned = 150, threshold = 90, effect_id = "hero_attack_armor_reduction", effect_value = 3, mode = "threshold", enabled = true, notes = "数量严格大于门槛；同属性仅生效已达最高档", quality = "r" },
    { rule_id = "zongzi_100", item_id = "welfare_zongzi", display_name = "粽子", max_owned = 150, threshold = 100, effect_id = "hero_attribute_growth", effect_value = 3, mode = "threshold", enabled = true, notes = "数量严格大于门槛；同属性仅生效已达最高档", quality = "r" },
    { rule_id = "ember_10", item_id = "lottery_ember_of_legacy", display_name = "薪火余烬", max_owned = 0, threshold = 10, effect_id = "hero_attributes_per_second", effect_value = 100, mode = "threshold", enabled = true, notes = "数量严格大于门槛；同属性仅生效已达最高档", quality = "ur" },
    { rule_id = "ember_50", item_id = "lottery_ember_of_legacy", display_name = "薪火余烬", max_owned = 0, threshold = 50, effect_id = "hero_attribute_growth", effect_value = 100, mode = "threshold", enabled = true, notes = "数量严格大于门槛；同属性仅生效已达最高档", quality = "ur" },
    { rule_id = "ember_100", item_id = "lottery_ember_of_legacy", display_name = "薪火余烬", max_owned = 0, threshold = 100, effect_id = "hero_final_damage_bonus_pct", effect_value = 10, mode = "threshold", enabled = true, notes = "数量严格大于门槛；同属性仅生效已达最高档", quality = "ur" },
    { rule_id = "ember_200", item_id = "lottery_ember_of_legacy", display_name = "薪火余烬", max_owned = 0, threshold = 200, effect_id = "hero_attack_bonus_pct", effect_value = 30, mode = "threshold", enabled = true, notes = "数量严格大于门槛；同属性仅生效已达最高档", quality = "ur" },
    { rule_id = "ember_300", item_id = "lottery_ember_of_legacy", display_name = "薪火余烬", max_owned = 0, threshold = 300, effect_id = "hero_attribute_bonus_pct", effect_value = 30, mode = "threshold", enabled = true, notes = "数量严格大于门槛；同属性仅生效已达最高档", quality = "ur" },
    { rule_id = "ember_400", item_id = "lottery_ember_of_legacy", display_name = "薪火余烬", max_owned = 0, threshold = 400, effect_id = "hero_attack_armor_reduction", effect_value = 30, mode = "threshold", enabled = true, notes = "数量严格大于门槛；同属性仅生效已达最高档", quality = "ur" },
    { rule_id = "ember_600", item_id = "lottery_ember_of_legacy", display_name = "薪火余烬", max_owned = 0, threshold = 600, effect_id = "hero_attribute_growth", effect_value = 40, mode = "threshold", enabled = true, notes = "数量严格大于门槛；同属性仅生效已达最高档", quality = "ur" },
    { rule_id = "ember_800", item_id = "lottery_ember_of_legacy", display_name = "薪火余烬", max_owned = 0, threshold = 800, effect_id = "hero_final_damage_bonus_pct", effect_value = 120, mode = "threshold", enabled = true, notes = "数量严格大于门槛；同属性仅生效已达最高档", quality = "ur" },
    { rule_id = "ember_1000", item_id = "lottery_ember_of_legacy", display_name = "薪火余烬", max_owned = 0, threshold = 1000, effect_id = "hero_attack_armor_reduction", effect_value = 50, mode = "threshold", enabled = true, notes = "数量严格大于门槛；同属性仅生效已达最高档", quality = "ur" },
    { rule_id = "ember_1500", item_id = "lottery_ember_of_legacy", display_name = "薪火余烬", max_owned = 0, threshold = 1500, effect_id = "hero_attribute_growth", effect_value = 60, mode = "threshold", enabled = true, notes = "数量严格大于门槛；同属性仅生效已达最高档", quality = "ur" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["rule_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
