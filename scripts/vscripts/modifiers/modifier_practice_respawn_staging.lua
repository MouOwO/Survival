-- A freshly prepared replacement is not a live room participant until its
-- authored respawn deadline. This state is identical in server/client VMs.
modifier_practice_respawn_staging = class({})
local M = modifier_practice_respawn_staging
function M:IsHidden() return true end
function M:IsPurgable() return false end
function M:RemoveOnDeath() return false end
function M:OnCreated()
    if not IsServer() then return end
    self.preparation_world = GameRules:GetGameModeEntity()
    local unit = self:GetParent()
    unit.survival_challenge_staging_health_bar_paused = true
    unit.survival_challenge_staging_pause_modifier = self
    unit.survival_challenge_staging_pause_mode = GameRules:GetGameModeEntity()
    local bar = unit.FindModifierByName and unit:FindModifierByName("modifier_single_health_bar")
    if bar and not bar:IsNull() and bar.PauseForChallengeStaging then bar:PauseForChallengeStaging() end
end
function M:OnDestroy()
    if not IsServer() then return end
    if GameRules:GetGameModeEntity() ~= self.preparation_world then return end
    local unit = self:GetParent()
    if not unit or unit:IsNull() or unit.survival_challenge_staging_pause_modifier ~= self then return end
    unit.survival_challenge_staging_health_bar_paused = nil
    unit.survival_challenge_staging_pause_modifier = nil
    unit.survival_challenge_staging_pause_mode = nil
    local bar = unit.FindModifierByName and unit:FindModifierByName("modifier_single_health_bar")
    if unit.survival_challenge_teardown ~= true and bar and not bar:IsNull()
        and bar.ResumeAfterChallengeStaging then bar:ResumeAfterChallengeStaging() end
end
function M:CheckState()
    local result = {}
    for _, name in ipairs({"MODIFIER_STATE_INVULNERABLE", "MODIFIER_STATE_UNSELECTABLE",
        "MODIFIER_STATE_NO_HEALTH_BAR", "MODIFIER_STATE_NO_UNIT_COLLISION",
        "MODIFIER_STATE_NOT_ON_MINIMAP", "MODIFIER_STATE_DISARMED",
        "MODIFIER_STATE_SILENCED", "MODIFIER_STATE_MUTED", "MODIFIER_STATE_ROOTED",
        "MODIFIER_STATE_COMMAND_RESTRICTED", "MODIFIER_STATE_OUT_OF_GAME"}) do
        local key = rawget(_G, name)
        if key ~= nil then result[key] = true end
    end
    return result
end
return M
