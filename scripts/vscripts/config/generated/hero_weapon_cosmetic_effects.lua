-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: hero_weapon_cosmetic_effects.csv
local M = {}
M.rows = {
    { effect_id = "hero_monkey_king:frost_blade:ambient_1", cosmetic_id = "hero_monkey_king:frost_blade", path = "particles/econ/items/monkey_king/mk_ti9_immortal/mk_ti9_immortal_weapon_ambient.vpcf", attach_type = "PATTACH_ABSORIGIN_FOLLOW", enabled = true },
    { effect_id = "hero_monkey_king:ice_blade:ambient_1", cosmetic_id = "hero_monkey_king:ice_blade", path = "particles/econ/items/monkey_king/ti7_weapon/mk_ti7_immortal_weapon_ambient.vpcf", attach_type = "PATTACH_ABSORIGIN_FOLLOW", enabled = true },
    { effect_id = "hero_monkey_king:epic_icefire:ambient_1", cosmetic_id = "hero_monkey_king:epic_icefire", path = "particles/econ/items/monkey_king/ti7_weapon/mk_ti7_golden_immortal_weapon_ambient.vpcf", attach_type = "PATTACH_ABSORIGIN_FOLLOW", enabled = true },
    { effect_id = "hero_monkey_king:legend_abyss:ambient_1", cosmetic_id = "hero_monkey_king:legend_abyss", path = "particles/econ/items/monkey_king/ti7_weapon/mk_10th_anniversary_weapon_ambient.vpcf", attach_type = "PATTACH_ABSORIGIN_FOLLOW", enabled = true },
    { effect_id = "hero_blademaster:default:ambient_1", cosmetic_id = "hero_blademaster:default", path = "particles/units/heroes/hero_juggernaut/juggernaut_blade_generic.vpcf", attach_type = "PATTACH_ABSORIGIN_FOLLOW", enabled = true },
    { effect_id = "hero_blademaster:ice_blade:ambient_1", cosmetic_id = "hero_blademaster:ice_blade", path = "particles/econ/items/juggernaut/jugg_ti10_cache/jugg_ti10_cache_weapon.vpcf", attach_type = "PATTACH_ABSORIGIN_FOLLOW", enabled = true },
    { effect_id = "hero_blademaster:epic_icefire:ambient_1", cosmetic_id = "hero_blademaster:epic_icefire", path = "particles/econ/items/juggernaut/jugg_ti8_sword/jugg_ti8_sword_ambient.vpcf", attach_type = "PATTACH_ABSORIGIN_FOLLOW", enabled = true },
    { effect_id = "hero_blademaster:legend_abyss:ambient_1", cosmetic_id = "hero_blademaster:legend_abyss", path = "particles/econ/items/juggernaut/jugg_ti8_sword/jugg_ti8_crimson_sword_ambient.vpcf", attach_type = "PATTACH_ABSORIGIN_FOLLOW", enabled = true },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["effect_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
