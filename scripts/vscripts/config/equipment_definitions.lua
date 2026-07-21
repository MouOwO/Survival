-- 装备系列元数据；content_id 与 config/generated/content_catalog.lua 对齐。
local M = {}

M.aliases = {
    death_mask = {
        source_name = "死亡面罩",
        canonical_name = "吸血面罩",
        content_id = "item_death_mask",
        reason = "需求指定映射；保留生成表 ID，避免破坏配方引用。",
    },
}

M.series = {
    growth_sword = {
        slot = "main_hand", stages = 5, first_id = "weapon_growth_sword_01",
        progression = "normal_attack_count", source_priority = "excel_then_explicit_override",
    },
    frost_blade = {
        slot = "main_hand", stages = 5, first_id = "weapon_frost_blade_01",
        progression = "normal_attack_count", source_priority = "explicit_override",
    },
    ice_blade = {
        slot = "main_hand", stages = 5, first_id = "weapon_ice_blade_01",
        progression = "valid_kill_count", valid_kill_policy = "server_validated_enemy_kill",
    },
    attack_gloves = { slot = "accessory", stages = 5, first_id = "equipment_attack_gloves_01" },
    burning_blade = { slot = "accessory", stages = 5, first_id = "equipment_burning_blade_01" },
    iron_armor = { slot = "armor", stages = 5, first_id = "equipment_iron_armor_01" },
    infernal_armor = { slot = "armor", stages = 5, first_id = "equipment_infernal_armor_01" },
    epic_icefire = { slot = "main_hand", stages = 8, first_id = "weapon_epic_icefire_00", progression = "sin_stage" },
    legend_abyss = { slot = "main_hand", stages = 11, first_id = "weapon_legend_abyss_00", progression = "戒_stage" },
}

M.by_content_id = {}
local ids = {
    growth_sword = { "weapon_growth_sword_01", "weapon_growth_sword_02", "weapon_growth_sword_03", "weapon_growth_sword_04", "weapon_growth_sword_max" },
    frost_blade = { "weapon_frost_blade_01", "weapon_frost_blade_02", "weapon_frost_blade_03", "weapon_frost_blade_04", "weapon_frost_blade_max" },
    ice_blade = { "weapon_ice_blade_01", "weapon_ice_blade_02", "weapon_ice_blade_03", "weapon_ice_blade_04", "weapon_ice_blade_max" },
    attack_gloves = { "equipment_attack_gloves_01", "equipment_attack_gloves_02", "equipment_attack_gloves_03", "equipment_attack_gloves_04", "equipment_attack_gloves_max" },
    burning_blade = { "equipment_burning_blade_01", "equipment_burning_blade_02", "equipment_burning_blade_03", "equipment_burning_blade_04", "equipment_burning_blade_max" },
    iron_armor = { "equipment_iron_armor_01", "equipment_iron_armor_02", "equipment_iron_armor_03", "equipment_iron_armor_04", "equipment_iron_armor_max" },
    infernal_armor = { "equipment_infernal_armor_01", "equipment_infernal_armor_02", "equipment_infernal_armor_03", "equipment_infernal_armor_04", "equipment_infernal_armor_max" },
    epic_icefire = { "weapon_epic_icefire_00", "weapon_epic_icefire_01", "weapon_epic_icefire_02", "weapon_epic_icefire_03", "weapon_epic_icefire_04", "weapon_epic_icefire_05", "weapon_epic_icefire_06", "weapon_epic_icefire_07" },
    legend_abyss = { "weapon_legend_abyss_00", "weapon_legend_abyss_01", "weapon_legend_abyss_02", "weapon_legend_abyss_03", "weapon_legend_abyss_04", "weapon_legend_abyss_05", "weapon_legend_abyss_06", "weapon_legend_abyss_07", "weapon_legend_abyss_08", "weapon_legend_abyss_09", "weapon_legend_abyss_10" },
}
for series_id, content_ids in pairs(ids) do
    for index, content_id in ipairs(content_ids) do
        M.by_content_id[content_id] = { series_id = series_id, level = index, slot = M.series[series_id].slot }
    end
end

return M
