modifier_lumberjack_attack_observer = class({})
local M = modifier_lumberjack_attack_observer
local observer = require("systems/lumberjack_attack_observer")

function M:IsHidden() return true end
function M:IsPurgable() return false end
function M:RemoveOnDeath() return false end
function M:DeclareFunctions() return {MODIFIER_EVENT_ON_ATTACK_LANDED} end
function M:CheckState()
    return {[MODIFIER_STATE_INVULNERABLE] = true, [MODIFIER_STATE_UNSELECTABLE] = true,
        [MODIFIER_STATE_NO_HEALTH_BAR] = true, [MODIFIER_STATE_OUT_OF_GAME] = true}
end

function M:OnAttackLanded(params)
    if not IsServer() or not params then return end
    local attacker = params.attacker
    if not attacker or attacker:IsNull() then return end
    local owner = attacker.survival_lumberjack_attack_owner
    if not owner or (owner.IsNull and owner:IsNull()) or not owner.shared_attack_observer then return end
    if not observer.is_authoritative(self:GetParent()) then return end
    local methods = _G.modifier_lumberjack_ai
    if methods and methods.OnHarvestLanded then methods.OnHarvestLanded(owner, params) end
end

return M
