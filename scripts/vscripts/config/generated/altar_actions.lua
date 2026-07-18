-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: altar_actions.csv
local M = {}
M.rows = {
    { action_id = "altar_endless_training", name = "无尽练功房", wood_cost = 0, gold_cost = 50000, prerequisite_text = "英雄6转", visible_condition = "altar_used==true", description = "每秒收费5W金币/该练功房拥有无限血量与15倍属性成长效率。", enabled = true, source = "英雄相关建筑/行3" },
    { action_id = "altar_shadow_realm", name = "暗影界", wood_cost = 0, gold_cost = 50000, prerequisite_text = "英雄10转", visible_condition = "altar_used==true", description = "进入暗影界击杀各种BOSS与精英怪/掉落魔道器与图纸进行合成装备。", enabled = true, source = "英雄相关建筑/行4" },
    { action_id = "altar_select_hero", name = "选择英雄", wood_cost = 0, gold_cost = 0, visible_condition = "altar_used==true", description = "根据设置的英雄，一个英雄一个选项框", enabled = true, source = "英雄相关建筑/行5" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["action_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
