-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: hero_summon_rules.csv
local M = {}
M.rows = {
    { rule_id = "default_hero_summon", altar_building_id = "hero_altar", open_ability_name = "ability_open_hero_altar", max_summoned_heroes = 1, shop_unlock_after_summon = true, requires_city_level = 3, selection_once = true, default_vip_unlocked = false, enabled = true, notes = "每位玩家只能召唤一个战斗英雄；召唤完成后祭坛仅保留为建筑，并解锁商店UI。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["rule_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
