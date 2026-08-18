if LinkLuaModifier then
    LinkLuaModifier(
        "modifier_wall_collision_barrier",
        "modifiers/modifier_wall_collision_barrier",
        LUA_MODIFIER_MOTION_NONE
    )
end

modifier_wall_collision_barrier = class({})
_G.modifier_wall_collision_barrier = modifier_wall_collision_barrier
local M = modifier_wall_collision_barrier

function M:IsHidden() return true end
function M:IsPurgable() return false end
function M:RemoveOnDeath() return false end

function M:CheckState()
    return {
        [MODIFIER_STATE_INVULNERABLE] = true,
        [MODIFIER_STATE_UNSELECTABLE] = true,
        [MODIFIER_STATE_NO_HEALTH_BAR] = true,
        [MODIFIER_STATE_NOT_ON_MINIMAP] = true,
    }
end
