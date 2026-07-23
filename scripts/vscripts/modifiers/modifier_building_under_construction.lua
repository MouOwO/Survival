modifier_building_under_construction = class({})
local M = modifier_building_under_construction

function M:IsHidden() return true end
function M:IsPurgable() return false end

function M:CheckState()
    return {
        [MODIFIER_STATE_INVULNERABLE] = true,
        [MODIFIER_STATE_UNSELECTABLE] = true,
        [MODIFIER_STATE_NO_UNIT_COLLISION] = true,
        [MODIFIER_STATE_DISARMED] = true,
    }
end

return M