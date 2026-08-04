LinkLuaModifier(
    "modifier_survival_placeholder_anchor",
    "modifiers/modifier_survival_placeholder_anchor",
    LUA_MODIFIER_MOTION_NONE
)

modifier_survival_placeholder_anchor = class({})
local M = modifier_survival_placeholder_anchor
_G.modifier_survival_placeholder_anchor = M

function M:IsHidden() return true end
function M:IsPurgable() return false end
function M:RemoveOnDeath() return false end
function M:GetAttributes() return MODIFIER_ATTRIBUTE_PERMANENT end

function M:CheckState()
    local states = {
        [MODIFIER_STATE_INVULNERABLE] = true,
        [MODIFIER_STATE_UNSELECTABLE] = true,
        [MODIFIER_STATE_COMMAND_RESTRICTED] = true,
        [MODIFIER_STATE_DISARMED] = true,
        [MODIFIER_STATE_NO_UNIT_COLLISION] = true,
        [MODIFIER_STATE_ROOTED] = true,
    }
    if MODIFIER_STATE_NO_HEALTH_BAR ~= nil then
        states[MODIFIER_STATE_NO_HEALTH_BAR] = true
    end
    if MODIFIER_STATE_NOT_ON_MINIMAP ~= nil then
        states[MODIFIER_STATE_NOT_ON_MINIMAP] = true
    end
    return states
end

return M