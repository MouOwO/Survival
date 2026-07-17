-- ============================================================================
-- Modifier: lumberjack - 伐木工专用
-- ============================================================================
modifier_lumberjack = class({})

function modifier_lumberjack:IsHidden()
    return false
end

function modifier_lumberjack:IsPurgable()
    return false
end

function modifier_lumberjack:GetAttributes()
    return MODIFIER_ATTRIBUTE_PERMANENT
end

function modifier_lumberjack:OnCreated()
    self.woodPerHit = 1
    if IsServer() then
        local parent = self:GetParent()
        if parent and parent._woodPerHit then
            self.woodPerHit = parent._woodPerHit
        end
        self:StartIntervalThink(1.0)
    end
end

function modifier_lumberjack:IntervalThink()
    if not IsServer() then return end
    local parent = self:GetParent()
    if not parent or parent:IsNull() or not parent:IsAlive() then return end

    local currentTarget = parent:GetAttackTarget()
    if currentTarget and not currentTarget:IsNull() and currentTarget:IsAlive()
       and currentTarget._isEnemyTree then
        return
    end

    if EnemyTreeSystem.tree and not EnemyTreeSystem.tree:IsNull()
       and EnemyTreeSystem.tree:IsAlive() then
        local tree = EnemyTreeSystem.tree
        local dist = (tree:GetAbsOrigin() - parent:GetAbsOrigin()):Length2D()

        if dist > 200 then
            ExecuteOrderFromTable({
                UnitIndex = parent:entindex(),
                OrderType = DOTA_UNIT_ORDER_MOVE_TO_POSITION,
                Position = tree:GetAbsOrigin(),
            })
        else
            ExecuteOrderFromTable({
                UnitIndex = parent:entindex(),
                OrderType = DOTA_UNIT_ORDER_ATTACK_TARGET,
                TargetIndex = tree:entindex(),
            })
        end
    end
end

function modifier_lumberjack:DeclareFunctions()
    return {
        MODIFIER_EVENT_ON_ATTACK_LANDED,
    }
end

function modifier_lumberjack:OnAttackLanded(kv)
    if not IsServer() then return end
    local parent = self:GetParent()
    if kv.attacker == parent then
        local target = kv.target
        if target and target._isEnemyTree then
            ResourceSystem:AddWood(parent:GetTeamNumber(), self.woodPerHit)
        end
    end
end
