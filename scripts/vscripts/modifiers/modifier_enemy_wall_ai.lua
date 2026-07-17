local M = class({})
_G.modifier_enemy_wall_ai = M

function M:IsHidden() return true end
function M:IsPurgable() return false end
function M:GetAttributes() return MODIFIER_ATTRIBUTE_PERMANENT end

function M:OnCreated(params)
    if not IsServer() then return end
    self.wall_entindex = tonumber(params.wall_entindex) or -1
    self:StartIntervalThink(0.5)
end

function M:SetWallEntIndex(entindex)
    self.wall_entindex = tonumber(entindex) or -1
    local parent = self:GetParent()
    if parent and not parent:IsNull() and self.wall_entindex < 0 then
        parent:SetForceAttackTarget(nil)
        parent:Stop()
    end
end

function M:OnIntervalThink()
    if not IsServer() then return end
    local parent = self:GetParent()
    if not parent or parent:IsNull() or not parent:IsAlive() then return end

    if self.wall_entindex < 0 then
        parent:SetForceAttackTarget(nil)
        return
    end

    local wall = EntIndexToHScript(self.wall_entindex)
    if not wall or wall:IsNull() or not wall:IsAlive() then
        self:SetWallEntIndex(-1)
        return
    end

    parent:SetForceAttackTarget(wall)
    if parent:GetAttackTarget() ~= wall then
        ExecuteOrderFromTable({
            UnitIndex = parent:entindex(),
            OrderType = DOTA_UNIT_ORDER_ATTACK_TARGET,
            TargetIndex = wall:entindex(),
            Queue = false,
        })
    end
end

function M:OnDestroy()
    if not IsServer() then return end
    local parent = self:GetParent()
    if parent and not parent:IsNull() then
        parent:SetForceAttackTarget(nil)
    end
end

return M
