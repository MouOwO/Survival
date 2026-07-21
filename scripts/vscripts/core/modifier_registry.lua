require("modifiers/modifier_building_blink_move")
local logger = require("core/logger")

local M = {}

local registered = false

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
        name = "modifier_lumberjack_ai",
        path = "modifiers/modifier_lumberjack_ai",
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
        name = "modifier_debug_fixed_attack_rate",
        path = "modifiers/modifier_debug_fixed_attack_rate",
    },
    {
        name = "modifier_debug_attack_cap",
        path = "modifiers/modifier_debug_attack_cap",
    },
    {
        name = "modifier_tower_auto_attack",
        path = "modifiers/modifier_tower_auto_attack",
    },
    {
        name = "modifier_tower_attack_effects",
        path = "modifiers/modifier_tower_attack_effects",
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
    if registered then
        return
    end
    for _, definition in ipairs(modifiers) do
        link(definition)
    end
    registered = true
    print("[ModifierRegistry] LinkLuaModifier complete count=" .. tostring(#modifiers))
    logger.info(
        "ModifierRegistry",
        "registered " .. tostring(#modifiers) .. " modifiers"
    )
end

return M
