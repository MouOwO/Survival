-- Linked only after the isolated Q pool probe is explicitly enabled.
modifier_blademaster_q_caster_idle = class({})
local M = modifier_blademaster_q_caster_idle
function M:IsHidden() return true end
function M:IsPurgable() return false end
function M:RemoveOnDeath() return false end
function M:CheckState()
    local result = {}
    for _, name in ipairs({
        "MODIFIER_STATE_INVULNERABLE", "MODIFIER_STATE_UNSELECTABLE",
        "MODIFIER_STATE_NO_HEALTH_BAR", "MODIFIER_STATE_NO_UNIT_COLLISION",
        "MODIFIER_STATE_NOT_ON_MINIMAP", "MODIFIER_STATE_COMMAND_RESTRICTED",
        "MODIFIER_STATE_DISARMED", "MODIFIER_STATE_SILENCED",
        "MODIFIER_STATE_MUTED", "MODIFIER_STATE_ROOTED", "MODIFIER_STATE_OUT_OF_GAME",
    }) do
        local value = rawget(_G, name)
        if value ~= nil then result[value] = true end
    end
    return result
end
return M
