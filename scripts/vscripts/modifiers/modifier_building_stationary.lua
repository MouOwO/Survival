LinkLuaModifier("modifier_building_stationary", "modifiers/modifier_building_stationary", LUA_MODIFIER_MOTION_NONE)
modifier_building_stationary = class({})
local M = modifier_building_stationary
_G.modifier_building_stationary = M
function M:IsHidden() return true end
function M:IsPurgable() return false end
function M:GetAttributes() return MODIFIER_ATTRIBUTE_PERMANENT end
function M:CheckState()
    return { [MODIFIER_STATE_ROOTED] = true }
end
return M
