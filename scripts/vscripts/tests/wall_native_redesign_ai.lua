-- Isolated native acceptance adapter. Formal gameplay never links this name.
-- Each temporary actor carries the private implementation captured by the
-- payload, so loading this adapter cannot replace a live gameplay modifier.
modifier_wall_native_redesign_ai = class({})
local M = modifier_wall_native_redesign_ai
_G.modifier_wall_native_redesign_ai = M

local function implementation(self)
    local parent = self:GetParent()
    return parent and not parent:IsNull() and parent.survival_native_ai_impl
end
local function invoke(self, name, ...)
    local methods = implementation(self)
    local method = methods and methods[name]
    if method then return method(self, ...) end
end

function M:IsHidden() return true end
function M:IsPurgable() return false end
function M:GetAttributes() return MODIFIER_ATTRIBUTE_PERMANENT end
function M:DeclareFunctions()
    local methods = implementation(self)
    if methods then return methods.DeclareFunctions(self) end
    return {MODIFIER_EVENT_ON_ATTACK_START, MODIFIER_EVENT_ON_ATTACK_LANDED,
        MODIFIER_EVENT_ON_DEATH, MODIFIER_PROPERTY_ATTACK_RANGE_BONUS}
end
function M:CheckState()
    if IsServer() and implementation(self) then return invoke(self, 'CheckState') end
    local mode, states = self:GetStackCount(), {}
    -- Match the server contract even without the private implementation:
    -- native approach and retreat retain unit collision on both VMs.
    if mode == 1 or mode == 3 or mode == 4 or mode == 5 then states[MODIFIER_STATE_DISARMED] = true end
    if mode == 2 or mode == 6 then states[MODIFIER_STATE_ROOTED] = true end
    return states
end
function M:GetModifierAttackRangeBonus() return self.contact_range_delta or 0 end
function M:AddCustomTransmitterData() return {contact_range_delta = self.contact_range_delta or 0} end
function M:HandleCustomTransmitterData(data) self.contact_range_delta = tonumber(data.contact_range_delta) or 0 end
function M:OnAttackLanded(event)
    if IsServer() and event and event.attacker == self:GetParent() then
        local probe = event.attacker.survival_native_probe
        if probe and event.target == probe.wall and probe.record_hit then probe.record_hit(self, event) end
    end
    return invoke(self, 'OnAttackLanded', event)
end

-- Every production helper is dispatched, including calls made through self.
-- Keep this list explicit so Source 2 discovers callbacks when it links us.
local forwarded = {
    'OnAttackStart', 'ObserveRangedStationary', 'ReleaseRangedStationary',
    'HandleAttackStart', 'HandleAttackFired', 'OnDeath', 'HandleDeath',
    'HandleAttackLanded', 'OnCreated', 'OnRefresh', 'UpdateContactRange',
    'SetContactMode', 'SetWallEntIndex', 'InvalidateWallTarget', 'RefreshWallTarget',
    'IssueStateOrder', 'EnterState', 'MonitorState', 'OnIntervalThink', 'OnDestroy',
}
for _, name in ipairs(forwarded) do
    local method_name = name
    M[method_name] = function(self, ...) return invoke(self, method_name, ...) end
end
return M
