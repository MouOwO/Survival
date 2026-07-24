-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: content_effects.csv
local M = {}
M.rows = {
    { effect_id = "effect_0001", content_id = "weapon_growth_sword_01", effect_type = "ADD_ATK_PER_ATK", value = "1", value_type = "number", target = "owner_hero", trigger = "always", enabled = true, source = "武器合成/行2" },
    { effect_id = "effect_0002", content_id = "weapon_growth_sword_02", effect_type = "ADD_ATK_PER_ATK", value = "2", value_type = "number", target = "owner_hero", trigger = "always", enabled = true, source = "武器合成/行3" },
    { effect_id = "effect_0003", content_id = "weapon_growth_sword_03", effect_type = "ADD_ATK_PER_ATK", value = "3", value_type = "number", target = "owner_hero", trigger = "always", enabled = true, source = "武器合成/行4" },
    { effect_id = "effect_0004", content_id = "weapon_growth_sword_04", effect_type = "ADD_ATK_PER_ATK", value = "4", value_type = "number", target = "owner_hero", trigger = "always", enabled = true, source = "武器合成/行5" },
    { effect_id = "effect_0005", content_id = "weapon_growth_sword_max", effect_type = "ADD_ATK_PER_ATK", value = "5", value_type = "number", target = "owner_hero", trigger = "always", enabled = true, source = "武器合成/行6" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["effect_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
