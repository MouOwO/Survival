LinkLuaModifier("modifier_tower_auto_attack", "modifiers/modifier_tower_auto_attack", LUA_MODIFIER_MOTION_NONE)
modifier_tower_auto_attack = class({})
_G.modifier_tower_auto_attack = modifier_tower_auto_attack

function modifier_tower_auto_attack:IsHidden() return true end
function modifier_tower_auto_attack:IsPurgable() return false end
function modifier_tower_auto_attack:GetAttributes() return MODIFIER_ATTRIBUTE_PERMANENT end

local function valid(unit)
    return unit and not unit:IsNull() and unit:IsAlive()
end

local function find_target(tower)
    local attack_range = tower.GetAttackRange and tower:GetAttackRange() or 600
    local radius = math.max(attack_range + 64, 700)
    local units = FindUnitsInRadius(
        tower:GetTeamNumber(), tower:GetAbsOrigin(), nil, radius,
        DOTA_UNIT_TARGET_TEAM_ENEMY,
        DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC,
        DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES,
        FIND_CLOSEST, false)
    return units and units[1] or nil
end

function modifier_tower_auto_attack:OnCreated()
    if not IsServer() then return end
    self:StartIntervalThink(0.25)
end

function modifier_tower_auto_attack:ResetTarget()
    if not IsServer() then return end
    local tower = self:GetParent()
    if valid(tower) then tower:SetForceAttackTarget(nil) end
end

function modifier_tower_auto_attack:OnIntervalThink()
    if not IsServer() then return end
    local tower = self:GetParent()
    if not valid(tower) then return end

    local current = tower:GetAttackTarget()
    local target = current
    local distance = target and (target:GetAbsOrigin() - tower:GetAbsOrigin()):Length2D() or 99999
    local attack_range = tower.GetAttackRange and tower:GetAttackRange() or 600
    if not valid(target) or target:GetTeamNumber() == tower:GetTeamNumber()
        or distance > attack_range + 96 then
        target = find_target(tower)
    end
    if not valid(target) then
        tower:SetForceAttackTarget(nil)
        return
    end

    tower:SetForceAttackTarget(target)
    if current ~= target then
        ExecuteOrderFromTable({
            UnitIndex = tower:entindex(),
            OrderType = DOTA_UNIT_ORDER_ATTACK_TARGET,
            TargetIndex = target:entindex(),
            Queue = false,
        })
    end
end

function modifier_tower_auto_attack:OnDestroy()
    if IsServer() then
        local tower = self:GetParent()
        if valid(tower) then tower:SetForceAttackTarget(nil) end
    end
end

return modifier_tower_auto_attack
