LinkLuaModifier("modifier_tower_auto_attack", "modifiers/modifier_tower_auto_attack", LUA_MODIFIER_MOTION_NONE)
local global_rules = require("config/global_rules")
modifier_tower_auto_attack = class({})
_G.modifier_tower_auto_attack = modifier_tower_auto_attack

function modifier_tower_auto_attack:IsHidden() return true end
function modifier_tower_auto_attack:IsPurgable() return false end
function modifier_tower_auto_attack:GetAttributes() return MODIFIER_ATTRIBUTE_PERMANENT end

local function valid(unit)
    return unit and not unit:IsNull() and unit:IsAlive()
end

local function find_target(tower)
    local attack_range = global_rules.tower_attack_range
    local radius = math.max(attack_range + 64, 700)
    local units = FindUnitsInRadius(
        tower:GetTeamNumber(), tower:GetAbsOrigin(), nil, radius,
        DOTA_UNIT_TARGET_TEAM_ENEMY,
        DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC,
        DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES,
        FIND_CLOSEST, false)
    for _, unit in ipairs(units or {}) do
        local distance = valid(unit)
            and (unit:GetAbsOrigin() - tower:GetAbsOrigin()):Length2D()
            or 99999
        if valid(unit) and distance <= attack_range + 64 then
            return unit
        end
    end
    return nil
end

function modifier_tower_auto_attack:OnCreated()
    if not IsServer() then return end
    self.forced_target = nil
    local tower = self:GetParent()
    if valid(tower) then
        if tower.Script_SetAttackRange then
            tower:Script_SetAttackRange(global_rules.tower_attack_range)
        elseif tower.SetAttackRange then
            tower:SetAttackRange(global_rules.tower_attack_range)
        end
        if tower.SetAcquisitionRange then
            tower:SetAcquisitionRange(global_rules.tower_acquisition_range)
        end
    end
    self:StartIntervalThink(0.25)
end

function modifier_tower_auto_attack:ResetTarget()
    if not IsServer() then return end
    local tower = self:GetParent()
    self.forced_target = nil
    if valid(tower) then tower:SetForceAttackTarget(nil) end
end

function modifier_tower_auto_attack:OnIntervalThink()
    if not IsServer() then return end
    local tower = self:GetParent()
    if not valid(tower) then return end

    local target = tower:GetAttackTarget()
    local distance = valid(target)
        and (target:GetAbsOrigin() - tower:GetAbsOrigin()):Length2D()
        or 99999
    local attack_range = global_rules.tower_attack_range
    if not valid(target) or target:GetTeamNumber() == tower:GetTeamNumber()
        or distance > attack_range + 96 then
        if self.forced_target ~= nil then
            tower:SetForceAttackTarget(nil)
            self.forced_target = nil
        end
        target = find_target(tower)
    end
    if not valid(target) then
        if self.forced_target ~= nil then
            tower:SetForceAttackTarget(nil)
            self.forced_target = nil
        end
        return
    end

    -- SetForceAttackTarget generates an engine attack order. Reissuing it
    -- every interval races with a target dying and produces invalid order 19.
    -- Only issue an order when the selected live target actually changes.
    if self.forced_target ~= target and valid(target) then
        tower:SetForceAttackTarget(target)
        self.forced_target = target
    end
end

function modifier_tower_auto_attack:OnDestroy()
    if IsServer() then
        local tower = self:GetParent()
        if valid(tower) then tower:SetForceAttackTarget(nil) end
        self.forced_target = nil
    end
end

return modifier_tower_auto_attack
