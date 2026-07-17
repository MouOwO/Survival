local event_bus = require("core/event_bus")
local events = require("core/events")

local M = class({})
_G.modifier_lumberjack_ai = M

function M:IsHidden() return true end
function M:IsPurgable() return false end
function M:GetAttributes() return MODIFIER_ATTRIBUTE_PERMANENT end

function M:OnCreated(params)
    if not IsServer() then return end
    self.tree_entindex = tonumber(params.tree_entindex) or -1
    self:StartIntervalThink(0.5)
end

function M:SetTreeEntIndex(entindex)
    self.tree_entindex = tonumber(entindex) or -1
end

function M:OnIntervalThink()
    if not IsServer() then return end
    local parent = self:GetParent()
    if not parent or parent:IsNull() or not parent:IsAlive() then return end
    if self.tree_entindex < 0 then return end

    local tree = EntIndexToHScript(self.tree_entindex)
    if not tree or tree:IsNull() or not tree:IsAlive() then return end
    if parent:GetAttackTarget() == tree then return end

    ExecuteOrderFromTable({
        UnitIndex = parent:entindex(),
        OrderType = DOTA_UNIT_ORDER_ATTACK_TARGET,
        TargetIndex = tree:entindex(),
        Queue = false,
    })
end

function M:DeclareFunctions()
    return { MODIFIER_EVENT_ON_ATTACK_LANDED }
end

function M:OnAttackLanded(keys)
    if not IsServer() then return end
    local parent = self:GetParent()
    if keys.attacker ~= parent then return end
    local target = keys.target
    if not target or target:IsNull() then return end
    if target:entindex() ~= self.tree_entindex then return end

    event_bus.emit(events.TREE_HIT, {
        worker = parent,
        target = target,
        team = parent:GetTeamNumber(),
    })
end

return M
