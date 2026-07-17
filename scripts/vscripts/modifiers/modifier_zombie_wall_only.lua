-- ============================================================================
-- Modifier: zombie_wall_only - 僵尸只攻击城墙
-- ============================================================================
modifier_zombie_wall_only = class({})

function modifier_zombie_wall_only:IsHidden()
    return true
end

function modifier_zombie_wall_only:IsPurgable()
    return false
end

function modifier_zombie_wall_only:GetAttributes()
    return MODIFIER_ATTRIBUTE_PERMANENT
end

function modifier_zombie_wall_only:OnCreated()
    if IsServer() then
        self:StartIntervalThink(0.5)
    end
end

function modifier_zombie_wall_only:IntervalThink()
    if not IsServer() then return end
    local parent = self:GetParent()
    if not parent or parent:IsNull() or not parent:IsAlive() then return end

    -- 检查当前目标是否是城墙
    local currentTarget = parent:GetAttackTarget()
    if currentTarget and not currentTarget:IsNull()
       and currentTarget._buildingType == "wall" then
        return -- 已经在攻击城墙
    end

    -- 寻找最近的城墙
    local walls = GridSystem:GetAllWalls()
    if #walls > 0 then
        local closest = nil
        local closestDist = 99999
        local parentPos = parent:GetAbsOrigin()

        for _, wall in ipairs(walls) do
            if wall and not wall:IsNull() and wall:IsAlive() then
                local dist = (wall:GetAbsOrigin() - parentPos):Length2D()
                if dist < closestDist then
                    closestDist = dist
                    closest = wall
                end
            end
        end

        if closest then
            if closestDist > parent:GetAttackRange() then
                ExecuteOrderFromTable({
                    UnitIndex = parent:entindex(),
                    OrderType = DOTA_UNIT_ORDER_MOVE_TO_POSITION,
                    Position = closest:GetAbsOrigin(),
                })
            else
                ExecuteOrderFromTable({
                    UnitIndex = parent:entindex(),
                    OrderType = DOTA_UNIT_ORDER_ATTACK_TARGET,
                    TargetIndex = closest:entindex(),
                })
            end
        end
    end
end
