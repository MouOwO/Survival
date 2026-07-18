local logger = require("core/logger")

local M = {}

local registered = false

local modifiers = {
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
    logger.info(
        "ModifierRegistry",
        "registered " .. tostring(#modifiers) .. " modifiers"
    )
end

return M
