modifier_building_stationary = class({})
local M = modifier_building_stationary

function M:IsHidden() return true end
function M:IsPurgable() return false end
function M:GetAttributes() return MODIFIER_ATTRIBUTE_PERMANENT end

function M:CheckState()
    return { [MODIFIER_STATE_ROOTED] = true }
end

return M
