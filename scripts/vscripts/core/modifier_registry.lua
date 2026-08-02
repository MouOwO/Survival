require("modifiers/modifier_building_blink_move")
local logger = require("core/logger")

local M = {}

local modifiers = {
    {
        name = "modifier_building_blink_move",
        path = "modifiers/modifier_building_blink_move",
    },
    {
        name = "modifier_building_stationary",
        path = "modifiers/modifier_building_stationary",
    },
    {
        name = "modifier_building_no_health_bar",
        path = "modifiers/modifier_building_no_health_bar",
    },
    {
        name = "modifier_building_under_construction",
        path = "modifiers/modifier_building_under_construction",
    },
    {
        name = "modifier_grid_building_preview",
        path = "modifiers/modifier_grid_building_preview",
    },
    {
        name = "modifier_lumberjack_ai",
        path = "modifiers/modifier_lumberjack_ai",
    },
    {
        name = "modifier_tree_progression",
        path = "modifiers/modifier_tree_progression",
    },
    {
        name = "modifier_repair_worker_ai",
        path = "modifiers/modifier_repair_worker_ai",
    },
    {
        name = "modifier_enemy_wall_ai",
        path = "modifiers/modifier_enemy_wall_ai",
    },
    {
        name = "modifier_survival_hero_skill",
        path = "modifiers/modifier_survival_hero_skill",
    },
    {
        name = "modifier_hero_passive_skill_effect",
        path = "modifiers/modifier_hero_passive_skill_effects",
    },
    {
        name = "modifier_hero_poison_cloud_armor",
        path = "modifiers/modifier_hero_poison_cloud_armor",
    },
    {
        name = "modifier_weapon_attack_tracker",
        path = "modifiers/modifier_weapon_attack_tracker",
    },
    {
        name = "modifier_weapon_stat_projection",
        path = "modifiers/modifier_weapon_stat_projection",
    },
    {
        name = "modifier_equipment_effects",
        path = "modifiers/modifier_equipment_effects",
    },
    {
        name = "modifier_survival_hero_base_health",
        path = "modifiers/modifier_survival_hero_base_health",
    },
    {
        name = "modifier_debug_fixed_attack_rate",
        path = "modifiers/modifier_debug_fixed_attack_rate",
    },
    {
        name = "modifier_debug_attack_cap",
        path = "modifiers/modifier_debug_attack_cap",
    },
    {
        name = "modifier_debug_move_speed_cap",
        path = "modifiers/modifier_debug_move_speed_cap",
    },
    {
        name = "modifier_debug_attack_bonus",
        path = "modifiers/modifier_debug_combat_bonus",
    },
    {
        name = "modifier_debug_armor_bonus",
        path = "modifiers/modifier_debug_combat_bonus",
    },
    {
        name = "modifier_tower_auto_attack",
        path = "modifiers/modifier_tower_auto_attack",
    },
    {
        name = "modifier_tower_attack_effects",
        path = "modifiers/modifier_tower_attack_effects",
    },
    {
        name = "modifier_survival_managed_buff",
        path = "modifiers/modifier_survival_managed_buff",
    },
    {
        name = "modifier_survival_managed_aura",
        path = "modifiers/modifier_survival_managed_buff",
    },
    {
        name = "modifier_practice_monster_ai",
        path = "modifiers/modifier_practice_monster_ai",
    },
    {
        name = "modifier_endless_training_target",
        path = "modifiers/modifier_endless_training_target",
    },
    {
        name = "modifier_research_technology",
        path = "modifiers/modifier_research_technology",
    },
    {
        name = "modifier_research_armor_reduction",
        path = "modifiers/modifier_research_technology",
    },
    {
        name = "modifier_single_health_bar",
        path = "modifiers/modifier_single_health_bar",
    },
}

local function link(definition)
    LinkLuaModifier(
        definition.name,
        definition.path,
        LUA_MODIFIER_MOTION_NONE
    )
    require(definition.path)

    if _G[definition.name] == nil then
        error(
            "modifier class was not created: "
            .. definition.name
            .. " from "
            .. definition.path
        )
    end
end

function M.register()
    for _, definition in ipairs(modifiers) do
        link(definition)
    end
    print("[ModifierRegistry] LinkLuaModifier refreshed count=" .. tostring(#modifiers))
    logger.info(
        "ModifierRegistry",
        "refreshed " .. tostring(#modifiers) .. " modifiers"
    )
    return M.validate()
end

function M.validate()
    local missing = {}
    for _, definition in ipairs(modifiers) do
        if _G[definition.name] == nil then
            missing[#missing + 1] = definition.name
        end
    end
    if #missing > 0 then
        return false, table.concat(missing, ",")
    end
    return true, #modifiers
end

return M
