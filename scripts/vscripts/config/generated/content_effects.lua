-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: content_effects.csv
local M = {}
M.rows = {
    { effect_id = "effect_0001", content_id = "weapon_growth_sword_01", effect_type = "ADD_ATK_PER_ATK", value = "1", value_type = "number", target = "owner_hero", trigger = "always", enabled = true, source = "武器合成/行2" },
    { effect_id = "effect_0002", content_id = "weapon_growth_sword_02", effect_type = "ADD_ATK_PER_ATK", value = "2", value_type = "number", target = "owner_hero", trigger = "always", enabled = true, source = "武器合成/行3" },
    { effect_id = "effect_0003", content_id = "weapon_growth_sword_03", effect_type = "ADD_ATK_PER_ATK", value = "3", value_type = "number", target = "owner_hero", trigger = "always", enabled = true, source = "武器合成/行4" },
    { effect_id = "effect_0004", content_id = "weapon_growth_sword_04", effect_type = "ADD_ATK_PER_ATK", value = "4", value_type = "number", target = "owner_hero", trigger = "always", enabled = true, source = "武器合成/行5" },
    { effect_id = "effect_0005", content_id = "weapon_growth_sword_max", effect_type = "ADD_ATK_PER_ATK", value = "5", value_type = "number", target = "owner_hero", trigger = "always", enabled = true, source = "武器合成/行6" },
    { effect_id = "effect_0006", content_id = "tech_gold_mine_efficiency_01", effect_type = "mine_efficiency_level", value = "1", value_type = "number", target = "player_gold_mine", trigger = "technology_level", enabled = true, source = "设计需求" },
    { effect_id = "effect_0007", content_id = "tech_gold_mine_crit_01", effect_type = "mine_crit_percent", value = "2", value_type = "percent", target = "player_gold_mine", trigger = "technology_level", enabled = true, source = "设计需求" },
    { effect_id = "effect_0008", content_id = "tech_gold_mine_efficiency_02", effect_type = "mine_efficiency_level", value = "2", value_type = "number", target = "player_gold_mine", trigger = "technology_level", enabled = true, source = "设计需求" },
    { effect_id = "effect_0009", content_id = "tech_gold_mine_crit_02", effect_type = "mine_crit_percent", value = "4", value_type = "percent", target = "player_gold_mine", trigger = "technology_level", enabled = true, source = "设计需求" },
    { effect_id = "effect_0010", content_id = "tech_gold_mine_efficiency_03", effect_type = "mine_efficiency_level", value = "3", value_type = "number", target = "player_gold_mine", trigger = "technology_level", enabled = true, source = "设计需求" },
    { effect_id = "effect_0011", content_id = "tech_gold_mine_crit_03", effect_type = "mine_crit_percent", value = "6", value_type = "percent", target = "player_gold_mine", trigger = "technology_level", enabled = true, source = "设计需求" },
    { effect_id = "effect_0012", content_id = "tech_gold_mine_efficiency_04", effect_type = "mine_efficiency_level", value = "4", value_type = "number", target = "player_gold_mine", trigger = "technology_level", enabled = true, source = "设计需求" },
    { effect_id = "effect_0013", content_id = "tech_gold_mine_crit_04", effect_type = "mine_crit_percent", value = "8", value_type = "percent", target = "player_gold_mine", trigger = "technology_level", enabled = true, source = "设计需求" },
    { effect_id = "effect_0014", content_id = "tech_gold_mine_efficiency_05", effect_type = "mine_efficiency_level", value = "5", value_type = "number", target = "player_gold_mine", trigger = "technology_level", enabled = true, source = "设计需求" },
    { effect_id = "effect_0015", content_id = "tech_gold_mine_crit_05", effect_type = "mine_crit_percent", value = "10", value_type = "percent", target = "player_gold_mine", trigger = "technology_level", enabled = true, source = "设计需求" },
    { effect_id = "effect_0016", content_id = "tech_gold_mine_efficiency_06", effect_type = "mine_efficiency_level", value = "6", value_type = "number", target = "player_gold_mine", trigger = "technology_level", enabled = true, source = "设计需求" },
    { effect_id = "effect_0017", content_id = "tech_gold_mine_crit_06", effect_type = "mine_crit_percent", value = "12", value_type = "percent", target = "player_gold_mine", trigger = "technology_level", enabled = true, source = "设计需求" },
    { effect_id = "effect_0018", content_id = "tech_gold_mine_efficiency_07", effect_type = "mine_efficiency_level", value = "7", value_type = "number", target = "player_gold_mine", trigger = "technology_level", enabled = true, source = "设计需求" },
    { effect_id = "effect_0019", content_id = "tech_gold_mine_crit_07", effect_type = "mine_crit_percent", value = "14", value_type = "percent", target = "player_gold_mine", trigger = "technology_level", enabled = true, source = "设计需求" },
    { effect_id = "effect_0020", content_id = "tech_gold_mine_efficiency_08", effect_type = "mine_efficiency_level", value = "8", value_type = "number", target = "player_gold_mine", trigger = "technology_level", enabled = true, source = "设计需求" },
    { effect_id = "effect_0021", content_id = "tech_gold_mine_crit_08", effect_type = "mine_crit_percent", value = "16", value_type = "percent", target = "player_gold_mine", trigger = "technology_level", enabled = true, source = "设计需求" },
    { effect_id = "effect_0022", content_id = "tech_gold_mine_efficiency_09", effect_type = "mine_efficiency_level", value = "9", value_type = "number", target = "player_gold_mine", trigger = "technology_level", enabled = true, source = "设计需求" },
    { effect_id = "effect_0023", content_id = "tech_gold_mine_crit_09", effect_type = "mine_crit_percent", value = "18", value_type = "percent", target = "player_gold_mine", trigger = "technology_level", enabled = true, source = "设计需求" },
    { effect_id = "effect_0024", content_id = "tech_gold_mine_efficiency_10", effect_type = "mine_efficiency_level", value = "10", value_type = "number", target = "player_gold_mine", trigger = "technology_level", enabled = true, source = "设计需求" },
    { effect_id = "effect_0025", content_id = "tech_gold_mine_crit_10", effect_type = "mine_crit_percent", value = "20", value_type = "percent", target = "player_gold_mine", trigger = "technology_level", enabled = true, source = "设计需求" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["effect_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
