if LinkLuaModifier then
    LinkLuaModifier("modifier_enemy_wall_ai", "modifiers/modifier_enemy_wall_ai", LUA_MODIFIER_MOTION_NONE)
end
modifier_enemy_wall_ai = class({})
_G.modifier_enemy_wall_ai = modifier_enemy_wall_ai
local M = modifier_enemy_wall_ai
local team_alignment = require("core/team_alignment")

function M:IsHidden() return true end
function M:IsPurgable() return false end
function M:GetAttributes() return MODIFIER_ATTRIBUTE_PERMANENT end

function M:OnCreated(params)
    self.no_unit_collision = tonumber(params.no_unit_collision) == 1
    if not IsServer() then return end
    self.wall_entindex = tonumber(params.wall_entindex) or -1
    self:StartIntervalThink(0.5)
end

function M:CheckState()
    if not self.no_unit_collision then return {} end
    return {
        [MODIFIER_STATE_NO_UNIT_COLLISION] = true,
    }
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

    team_alignment.enforce(parent, DOTA_TEAM_BADGUYS, "wave_enemy_ai")
    if not team_alignment.are_enemies(parent, wall) then
        team_alignment.enforce(wall, DOTA_TEAM_GOODGUYS, "wall_target")
    end
    if not team_alignment.are_enemies(parent, wall) then return end

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
