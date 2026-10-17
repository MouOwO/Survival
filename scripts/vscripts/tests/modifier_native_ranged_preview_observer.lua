-- Tools-only short observation carrier, attached only during the bounded
-- owned demo shot test. Unconditional declarations are stable in native order.
modifier_native_ranged_preview_observer = class({})
local M = modifier_native_ranged_preview_observer
function M:IsHidden() return true end
function M:IsPurgable() return false end
function M:RemoveOnDeath() return true end
function M:DeclareFunctions()
    return {MODIFIER_EVENT_ON_ATTACK_RECORD, MODIFIER_EVENT_ON_ATTACK,
        MODIFIER_EVENT_ON_ATTACK_LANDED, MODIFIER_EVENT_ON_ATTACK_RECORD_DESTROY}
end
local function forward(self, kind, params)
    if not IsServer() then return end
    require('tests/manual_native_ranged_visual_probe').on_native_event(self, kind, params)
end
function M:OnAttackRecord(params) forward(self, 'record', params) end
function M:OnAttack(params) forward(self, 'launch', params) end
function M:OnAttackLanded(params) forward(self, 'landed', params) end
function M:OnAttackRecordDestroy(params) forward(self, 'destroy', params) end
return M
