modifier_building_no_health_bar = class({})
local M = modifier_building_no_health_bar
_G.modifier_building_no_health_bar = M

function M:IsHidden() return true end
function M:IsPurgable() return false end
function M:GetAttributes() return MODIFIER_ATTRIBUTE_PERMANENT end

function M:CheckState()
    local states = {}
    if MODIFIER_STATE_NO_HEALTH_BAR ~= nil then
        states[MODIFIER_STATE_NO_HEALTH_BAR] = true
    end
    return states
end

return M
