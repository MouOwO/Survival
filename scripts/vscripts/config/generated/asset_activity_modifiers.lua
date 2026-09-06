-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: asset_activity_modifiers.csv
local M = {}
M.rows = {
    { modifier_key = "challenge_monster_primal_beast_svarog:less_brow", asset_id = "challenge_monster_primal_beast_svarog", modifier_name = "less_brow", sort_order = 1, enabled = true, notes = "Svarog头部官方动作修饰。" },
    { modifier_key = "challenge_monster_terrorblade_fractal_horns:abysm", asset_id = "challenge_monster_terrorblade_fractal_horns", modifier_name = "abysm", sort_order = 1, enabled = true, notes = "Fractal Horns官方Arcana动作修饰。" },
    { modifier_key = "hero_permanent_hero_blademaster:arcana", asset_id = "hero_permanent_hero_blademaster", modifier_name = "arcana", sort_order = 1, enabled = true, notes = "剑心之遗官方动作修饰。" },
    { modifier_key = "hero_permanent_hero_blademaster:arcana_style", asset_id = "hero_permanent_hero_blademaster", modifier_name = "arcana_style", sort_order = 2, enabled = true, notes = "剑心之遗官方样式动作修饰。" },
    { modifier_key = "hero_permanent_hero_blademaster:red", asset_id = "hero_permanent_hero_blademaster", modifier_name = "red", sort_order = 3, enabled = true, notes = "剑心之遗起源红色样式动作修饰。" },
    { modifier_key = "monster_wave_golem_gray_small:tactician", asset_id = "monster_wave_golem_gray_small", modifier_name = "tactician", sort_order = 1, enabled = true, notes = "维齐尔流犯著作官方动作修饰" },
    { modifier_key = "monster_wave_armored_horned_large:tier_2", asset_id = "monster_wave_armored_horned_large", modifier_name = "tier_2", sort_order = 1, enabled = true, notes = "金辉暴君官方动作修饰" },
    { modifier_key = "monster_wave_stitcher_large:aberrant_observer", asset_id = "monster_wave_stitcher_large", modifier_name = "aberrant_observer", sort_order = 1, enabled = true, notes = "畸变观察者官方动作修饰" },
    { modifier_key = "monster_wave_golem_green_fire:necro_plague_doctor", asset_id = "monster_wave_golem_green_fire", modifier_name = "necro_plague_doctor", sort_order = 1, enabled = true, notes = "腐铁开膛手官方动作修饰" },
    { modifier_key = "monster_wave_boss_twinblade_demon:abysm", asset_id = "monster_wave_boss_twinblade_demon", modifier_name = "abysm", sort_order = 1, enabled = true, notes = "心渊魔角官方动作修饰" },
    { modifier_key = "monster_archive_shadow_1:cc_2024", asset_id = "monster_archive_shadow_1", modifier_name = "cc_2024", sort_order = 1, enabled = true, notes = "邪魔之器官方动作修饰" },
    { modifier_key = "monster_archive_shadow_2:cc_2024", asset_id = "monster_archive_shadow_2", modifier_name = "cc_2024", sort_order = 1, enabled = true, notes = "邪魔之器官方动作修饰" },
    { modifier_key = "monster_archive_shadow_3:cc_2024", asset_id = "monster_archive_shadow_3", modifier_name = "cc_2024", sort_order = 1, enabled = true, notes = "邪魔之器官方动作修饰" },
    { modifier_key = "monster_archive_shadow_4:cc_2024", asset_id = "monster_archive_shadow_4", modifier_name = "cc_2024", sort_order = 1, enabled = true, notes = "邪魔之器官方动作修饰" },
    { modifier_key = "monster_archive_hunt_02:spear", asset_id = "monster_archive_hunt_02", modifier_name = "spear", sort_order = 1, enabled = true, notes = "绝世官方动作修饰" },
    { modifier_key = "monster_archive_hunt_02:tier_2", asset_id = "monster_archive_hunt_02", modifier_name = "tier_2", sort_order = 2, enabled = true, notes = "绝世官方动作修饰" },
    { modifier_key = "monster_archive_hunt_06:basher", asset_id = "monster_archive_hunt_06", modifier_name = "basher", sort_order = 1, enabled = true, notes = "收割者烙印官方动作修饰" },
    { modifier_key = "monster_archive_hunt_06:offhand_basher", asset_id = "monster_archive_hunt_06", modifier_name = "offhand_basher", sort_order = 2, enabled = true, notes = "收割者烙印官方动作修饰" },
    { modifier_key = "monster_archive_hunt_08:arcana", asset_id = "monster_archive_hunt_08", modifier_name = "arcana", sort_order = 1, enabled = true, notes = "千劫神屠捆绑包官方动作修饰" },
    { modifier_key = "monster_archive_hunt_08:green", asset_id = "monster_archive_hunt_08", modifier_name = "green", sort_order = 2, enabled = true, notes = "千劫神屠捆绑包官方动作修饰" },
    { modifier_key = "monster_archive_hunt_08:arcana_back", asset_id = "monster_archive_hunt_08", modifier_name = "arcana_back", sort_order = 3, enabled = true, notes = "千劫神屠捆绑包官方动作修饰" },
    { modifier_key = "monster_archive_hunt_09:weaver_ti7_immortal", asset_id = "monster_archive_hunt_09", modifier_name = "weaver_ti7_immortal", sort_order = 1, enabled = true, notes = "维度穿梭者官方动作修饰" },
    { modifier_key = "monster_archive_hunt_10:dualwield", asset_id = "monster_archive_hunt_10", modifier_name = "dualwield", sort_order = 1, enabled = true, notes = "孽龙之怒官方动作修饰" },
    { modifier_key = "monster_archive_hunt_10:arcana", asset_id = "monster_archive_hunt_10", modifier_name = "arcana", sort_order = 2, enabled = true, notes = "孽龙之怒官方动作修饰" },
    { modifier_key = "monster_archive_hunt_10:apostle2", asset_id = "monster_archive_hunt_10", modifier_name = "apostle2", sort_order = 3, enabled = true, notes = "孽龙之怒官方动作修饰" },
    { modifier_key = "monster_archive_hunt_12:force", asset_id = "monster_archive_hunt_12", modifier_name = "force", sort_order = 1, enabled = true, notes = "法出谁手官方动作修饰" },
    { modifier_key = "monster_archive_hunt_12:cc_2024", asset_id = "monster_archive_hunt_12", modifier_name = "cc_2024", sort_order = 2, enabled = true, notes = "法出谁手官方动作修饰" },
    { modifier_key = "monster_archive_social_friend:arcana", asset_id = "monster_archive_social_friend", modifier_name = "arcana", sort_order = 1, enabled = true, notes = "金鹏之幸捆绑包官方动作修饰" },
    { modifier_key = "monster_archive_social_ex:arcana", asset_id = "monster_archive_social_ex", modifier_name = "arcana", sort_order = 1, enabled = true, notes = "金鹏之幸捆绑包官方动作修饰" },
    { modifier_key = "monster_archive_social_beast:arcana", asset_id = "monster_archive_social_beast", modifier_name = "arcana", sort_order = 1, enabled = true, notes = "金鹏之幸捆绑包官方动作修饰" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["modifier_key"]
    if key ~= nil then M.by_id[key] = row end
end
return M
