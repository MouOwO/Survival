LinkLuaModifier("modifier_building_stationary", "modifiers/modifier_building_stationary", LUA_MODIFIER_MOTION_NONE)
modifier_building_stationary = class({})
local M = modifier_building_stationary
_G.modifier_building_stationary = M
function M:IsHidden() return true end
function M:IsPurgable() return false end
function M:GetAttributes() return MODIFIER_ATTRIBUTE_PERMANENT end
function M:OnCreated()
    if not IsServer() then return end
    local unit = self:GetParent()
    if not unit.survival_fixed_position then
        local origin = unit:GetAbsOrigin()
        unit.survival_fixed_position = Vector(origin.x, origin.y, origin.z)
    end
    self:StartIntervalThink(0.1)
end
function M:OnIntervalThink()
    local unit = self:GetParent()
    local anchor = unit and unit.survival_fixed_position or nil
    if not unit or unit:IsNull() or not anchor then return end
    local origin = unit:GetAbsOrigin()
    local dx = origin.x - anchor.x
    local dy = origin.y - anchor.y
    local dz = origin.z - anchor.z
    if dx * dx + dy * dy + dz * dz > 0.01 then
        unit:SetAbsOrigin(anchor)
        unit:Stop()
    end
end
function M:CheckState()
    return { [MODIFIER_STATE_ROOTED] = true }
end
return M
