modifier_native_wearable_visual_carrier = class({})

function modifier_native_wearable_visual_carrier:IsHidden() return true end
function modifier_native_wearable_visual_carrier:IsPurgable() return false end
function modifier_native_wearable_visual_carrier:RemoveOnDeath() return false end

function modifier_native_wearable_visual_carrier:CheckState()
    local states = {}
    local function enabled(name)
        local state = rawget(_G, name)
        if state ~= nil then states[state] = true end
    end
    enabled("MODIFIER_STATE_INVULNERABLE")
    enabled("MODIFIER_STATE_UNSELECTABLE")
    enabled("MODIFIER_STATE_NO_HEALTH_BAR")
    enabled("MODIFIER_STATE_NO_UNIT_COLLISION")
    enabled("MODIFIER_STATE_NOT_ON_MINIMAP")
    enabled("MODIFIER_STATE_COMMAND_RESTRICTED")
    enabled("MODIFIER_STATE_DISARMED")
    enabled("MODIFIER_STATE_SILENCED")
    enabled("MODIFIER_STATE_MUTED")
    enabled("MODIFIER_STATE_ROOTED")
    return states
end

return modifier_native_wearable_visual_carrier