-- Visual-only Q carrier. Deliberately does not silence, mute, or restrict
-- commands: the native Overwhelming Odds order must still be able to execute.
modifier_blademaster_q_visual = class({})
local M = modifier_blademaster_q_visual
function M:IsHidden() return true end
function M:IsPurgable() return false end
function M:RemoveOnDeath() return false end
function M:CheckState()
    local states = {}
    for _, name in ipairs({
        "MODIFIER_STATE_INVULNERABLE", "MODIFIER_STATE_UNSELECTABLE",
        "MODIFIER_STATE_NO_HEALTH_BAR", "MODIFIER_STATE_NO_UNIT_COLLISION",
        "MODIFIER_STATE_NOT_ON_MINIMAP", "MODIFIER_STATE_DISARMED",
    }) do
        local key = rawget(_G, name)
        if key ~= nil then states[key] = true end
    end
    return states
end
return M
