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
}

function M.register()
    if registered then return end
    registered = true

    for _, definition in ipairs(modifiers) do
        -- Force the engine adapter class to exist before any AddNewModifier call.
        require(definition.path)
        LinkLuaModifier(
            definition.name,
            definition.path,
            LUA_MODIFIER_MOTION_NONE
        )
    end
end

return M
