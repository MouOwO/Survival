modifier_tower_fixed_facing = class({})
local M = modifier_tower_fixed_facing

function M:IsHidden() return true end
function M:IsPurgable() return false end
function M:RemoveOnDeath() return false end
function M:GetAttributes() return MODIFIER_ATTRIBUTE_PERMANENT end

function M:DeclareFunctions()
    return {MODIFIER_PROPERTY_DISABLE_TURNING, MODIFIER_PROPERTY_IGNORE_CAST_ANGLE}
end

-- A stationary arrow tower can fire in every direction without rotating its
-- model. Both properties are replicated by the modifier, without a timer.
function M:GetModifierDisableTurning() return 1 end
function M:GetModifierIgnoreCastAngle() return 1 end

return M
