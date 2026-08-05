-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: asset_activity_modifiers.csv
local M = {}
M.rows = {
    { modifier_key = "challenge_monster_primal_beast_svarog:less_brow", asset_id = "challenge_monster_primal_beast_svarog", modifier_name = "less_brow", sort_order = 1, enabled = true, notes = "Svarog头部官方动作修饰。" },
    { modifier_key = "challenge_monster_terrorblade_fractal_horns:abysm", asset_id = "challenge_monster_terrorblade_fractal_horns", modifier_name = "abysm", sort_order = 1, enabled = true, notes = "Fractal Horns官方Arcana动作修饰。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["modifier_key"]
    if key ~= nil then M.by_id[key] = row end
end
return M
