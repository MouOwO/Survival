-- Loaded only by the explicitly invoked Tools fixture hold command.
modifier_manual_real_game_stress_hold=class({})
_G.modifier_manual_real_game_stress_hold=modifier_manual_real_game_stress_hold
local M=modifier_manual_real_game_stress_hold
function M:IsHidden() return true end
function M:IsPurgable() return false end
function M:IsPurgeException() return false end
function M:OnCreated(options)
    if not IsServer() then return end
    self.original_capability=tonumber(options.original_capability)
    self.scene=_G.SURVIVAL_REAL_GAME_STRESS
    self:SetStackCount(1)
end
function M:RestoreCapability()
    if self.restored then return end
    self.restored=true
    local parent=self:GetParent()
    if parent and not parent:IsNull() and self.original_capability~=nil then
        parent:SetAttackCapability(self.original_capability)
    end
end
function M:CheckState()
    if IsServer() and (not self.scene or self.scene~=_G.SURVIVAL_REAL_GAME_STRESS
        or self.scene.mode~=GameRules:GetGameModeEntity() or self.scene.status~='ready') then
        self:RestoreCapability()
        self:SetStackCount(0)
    end
    return self:GetStackCount()==1 and {[MODIFIER_STATE_DISARMED]=true} or {}
end
function M:OnDestroy()
    if IsServer() then self:RestoreCapability() end
end
return M
