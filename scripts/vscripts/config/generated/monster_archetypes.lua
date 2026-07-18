-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: monster_archetypes.csv
local M = {}
M.rows = {
    { archetype_id = "wild_boss_common", unit_name = "zombie_boss", display_group = "野外Boss通用模板", rank = "boss", base_stats_profile = "zombie_boss", model_source = "npc_units_custom", model_path = "models/heroes/undying/undying_flesh_golem.vmdl", team_name = "DOTA_TEAM_BADGUYS", considered_boss = true, enabled = true, notes = "11个出生位置共用此模板。模型和基础数值集中在zombie_boss单位/野外Boss配置中，不在每个遭遇重复填写。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["archetype_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
