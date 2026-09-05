-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: map_level_effect_rules.csv
local M = {}
M.rows = {
    { rule_id = "map_level_wall_health_bonus_pct", source_field_id = "map_level", target_field_id = "wall_health_bonus_pct", value_per_level = 1, stacking_rule = "add", enabled = true, notes = "每1级地图等级使城墙生命加成增加1%。" },
    { rule_id = "map_level_wall_health_per_second", source_field_id = "map_level", target_field_id = "wall_health_per_second", value_per_level = 5, stacking_rule = "add", enabled = true, notes = "每1级地图等级使城墙每秒生命增加5。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["rule_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
