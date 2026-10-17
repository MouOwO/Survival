-- Tools-only observer. Fixed declarations apply to every fresh test actor.
modifier_wall_native_attack_record_audit=class({})
local M=modifier_wall_native_attack_record_audit
function M:IsHidden() return true end
function M:IsPurgable() return false end
function M:RemoveOnDeath() return false end
function M:DeclareFunctions()
    return {MODIFIER_EVENT_ON_ATTACK_RECORD,MODIFIER_EVENT_ON_ATTACK_RECORD_DESTROY,
        MODIFIER_PROPERTY_ATTACK_RANGE_BASE_OVERRIDE}
end
function M:GetModifierAttackRangeOverride()
    local row=self:GetParent().survival_native_attack_record_lifecycle
    return row and row.test_attack_range or nil
end
function M:CheckState()
    if self:GetStackCount()==1 then
        return {[MODIFIER_STATE_DISARMED]=true,[MODIFIER_STATE_COMMAND_RESTRICTED]=true,
            [MODIFIER_STATE_ROOTED]=true}
    end
    -- The separate attack-record stress fixture holds actors at known native
    -- positions; this neither phases nor changes their solid collision body.
    if self:GetStackCount()==2 then return {[MODIFIER_STATE_ROOTED]=true} end
    return {}
end
local function forward(self,method,event)
    if not IsServer() then return end
    local unit=self:GetParent()
    local row=unit and unit.survival_native_attack_record_lifecycle
    if row and row.owner and row.owner[method] then row.owner[method](row.owner,unit,event) end
end
function M:OnAttackRecord(event) forward(self,'on_record',event) end
function M:OnAttackRecordDestroy(event) forward(self,'on_record_destroy',event) end
function M:OnDestroy() forward(self,'on_modifier_destroyed') end
return M
