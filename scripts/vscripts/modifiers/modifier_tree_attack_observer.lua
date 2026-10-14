-- This carrier is created only by the explicit Tools probe. A native creation
-- version proves that all four required event declarations actually exist.
modifier_tree_attack_observer=class({})
local M=modifier_tree_attack_observer
local observer=require('systems/tree_attack_observer')
function M:IsHidden() return true end
function M:IsPurgable() return false end
function M:RemoveOnDeath() return false end
function M:DeclareFunctions()
    return {MODIFIER_EVENT_ON_ATTACK_START,MODIFIER_EVENT_ON_ATTACK_FAIL,
        MODIFIER_EVENT_ON_ATTACK_RECORD_DESTROY,MODIFIER_EVENT_ON_TAKEDAMAGE}
end
function M:OnCreated()
    if not IsServer() then return end
    self:GetParent().survival_tree_attack_observer_native_version=1
end
function M:CheckState()
    return {[MODIFIER_STATE_INVULNERABLE]=true,[MODIFIER_STATE_UNSELECTABLE]=true,
        [MODIFIER_STATE_NO_HEALTH_BAR]=true,[MODIFIER_STATE_OUT_OF_GAME]=true}
end
function M:OnAttackStart(p) observer.dispatch(self:GetParent(),'HandleAttackStart',p) end
function M:OnAttackFail(p) observer.dispatch(self:GetParent(),'HandleAttackFail',p) end
function M:OnAttackRecordDestroy(p) observer.dispatch(self:GetParent(),'HandleAttackRecordDestroy',p) end
function M:OnTakeDamage(p) observer.dispatch(self:GetParent(),'HandleTakeDamage',p) end
return M
