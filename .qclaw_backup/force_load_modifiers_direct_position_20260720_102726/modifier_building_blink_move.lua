modifier_building_blink_move = class({})
local M = modifier_building_blink_move
_G.modifier_building_blink_move = M
function M:IsHidden() return true end
function M:IsPurgable() return false end
function M:OnCreated(params)
    self.target = Vector(tonumber(params.x) or 0, tonumber(params.y) or 0, tonumber(params.z) or 0)
    if not IsServer() then return end
    self:StartIntervalThink(0.03)
    self:ApplyPosition()
end
function M:ApplyPosition()
    local unit = self:GetParent()
    if unit and not unit:IsNull() then unit:SetAbsOrigin(self.target) end
end
function M:OnIntervalThink()
    self:ApplyPosition()
    self:StartIntervalThink(-1)
    self:Destroy()
end
function M:OnDestroy()
    if not IsServer() then return end
    local unit = self:GetParent()
    if unit and not unit:IsNull() then
        self:ApplyPosition()
        unit:AddNewModifier(unit, nil, "modifier_building_stationary", {})
    end
end
return M
