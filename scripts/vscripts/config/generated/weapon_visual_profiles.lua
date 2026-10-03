-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: weapon_visual_profiles.csv
local M = {}
M.rows = {
    { series_id = "growth_sword", enabled = true, primary_rgb = {"185", "215", "255"}, secondary_rgb = {"140", "180", "255"}, glow_radius_min = 6, glow_radius_max = 10, trail_radius_min = 1.2, trail_radius_max = 2.2, emission_min = 6, emission_max = 10, alpha_min = 0.2, alpha_max = 0.35, shards = false, impact_cooldown = 0.8, notes = "仅主手；轻量银蓝光晕与短尾迹。" },
    { series_id = "frost_blade", enabled = true, primary_rgb = {"90", "175", "255"}, secondary_rgb = {"165", "225", "255"}, glow_radius_min = 10, glow_radius_max = 15, trail_radius_min = 2, trail_radius_max = 3.5, emission_min = 10, emission_max = 15, alpha_min = 0.3, alpha_max = 0.45, shards = false, impact_particle = "particles/items2_fx/skadi_projectile_explosion.vpcf", impact_cooldown = 0.65, notes = "霜之剑刃；只加视觉不改变攻击弹道或伤害。" },
    { series_id = "ice_blade", enabled = true, primary_rgb = {"75", "200", "255"}, secondary_rgb = {"210", "240", "255"}, glow_radius_min = 15, glow_radius_max = 20, trail_radius_min = 3, trail_radius_max = 4.5, emission_min = 14, emission_max = 20, alpha_min = 0.35, alpha_max = 0.5, shards = true, impact_particle = "particles/items2_fx/skadi_projectile_explosion.vpcf", impact_cooldown = 0.55, notes = "极寒之刃；增加低频冰晶碎片。" },
    { series_id = "epic_icefire", enabled = true, primary_rgb = {"255", "135", "45"}, secondary_rgb = {"70", "195", "255"}, glow_radius_min = 20, glow_radius_max = 25, trail_radius_min = 4, trail_radius_max = 5.5, emission_min = 20, emission_max = 26, alpha_min = 0.4, alpha_max = 0.55, shards = true, impact_particle = "particles/units/heroes/hero_jakiro/jakiro_liquid_fire_explosion.vpcf", impact_cooldown = 0.45, notes = "冰火双配色；暖色核心与冰蓝尾迹。" },
    { series_id = "legend_abyss", enabled = true, primary_rgb = {"195", "90", "255"}, secondary_rgb = {"95", "190", "255"}, glow_radius_min = 25, glow_radius_max = 30, trail_radius_min = 5, trail_radius_max = 7, emission_min = 24, emission_max = 32, alpha_min = 0.45, alpha_max = 0.6, shards = true, impact_particle = "particles/items_fx/desolator_projectile_explosion.vpcf", impact_cooldown = 0.4, notes = "深渊紫色核心与蓝色尾迹；三个主手常驻根加一个库存持有神杖脚底根（含原生子层）。", owned_particle = "particles/items4_fx/scepter_aura.vpcf" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["series_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
