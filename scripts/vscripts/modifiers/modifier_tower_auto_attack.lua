LinkLuaModifier("modifier_tower_auto_attack", "modifiers/modifier_tower_auto_attack", LUA_MODIFIER_MOTION_NONE)
local global_rules = require("config/global_rules")
local tree_damage_rules = require("systems/tree_damage_rules")
local anti_air_rules = require("systems/anti_air_rules")
modifier_tower_auto_attack = class({})
_G.modifier_tower_auto_attack = modifier_tower_auto_attack

function modifier_tower_auto_attack:IsHidden() return true end
function modifier_tower_auto_attack:IsPurgable() return false end
function modifier_tower_auto_attack:GetAttributes() return MODIFIER_ATTRIBUTE_PERMANENT end

function modifier_tower_auto_attack:DeclareFunctions()
    return { MODIFIER_EVENT_ON_ATTACK_START }
end

local function valid(unit)
    return unit and not unit:IsNull() and unit:IsAlive()
end

local function current_attack_range(tower)
    if tower and tower.GetAttackRange then
        local attack_range = tonumber(tower:GetAttackRange())
        if attack_range and attack_range > 0 then return attack_range end
    end
    return global_rules.tower_attack_range
end

local function is_training_dummy(unit)
    return unit and unit.survival_is_training_dummy == true
end

local function find_target(tower)
    local attack_range = current_attack_range(tower)
    local radius = math.max(attack_range + 64, 700)
    local units = FindUnitsInRadius(
        tower:GetTeamNumber(), tower:GetAbsOrigin(), nil, radius,
        DOTA_UNIT_TARGET_TEAM_ENEMY,
        DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC,
        DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES,
        FIND_CLOSEST, false)
    local training_dummy = nil
    for _, unit in ipairs(units or {}) do
        local distance = valid(unit)
            and (unit:GetAbsOrigin() - tower:GetAbsOrigin()):Length2D()
            or 99999
        if valid(unit) and is_training_dummy(unit)
            and anti_air_rules.can_attack(tower, unit)
            and distance <= attack_range + 64 and not training_dummy then
            training_dummy = unit
        elseif valid(unit) and not tree_damage_rules.is_tree(unit)
            and anti_air_rules.can_attack(tower, unit)
            and distance <= attack_range + 64 then
            return unit
        end
    end
    return training_dummy
end

function modifier_tower_auto_attack:OnAttackStart(params)
    if not IsServer() or params.attacker ~= self:GetParent() then
        return
    end
    local tower = self:GetParent()
    local target = params.target
    if not tree_damage_rules.is_tree(target)
        and anti_air_rules.can_attack(tower, target)
        and (not is_training_dummy(target) or find_target(tower) == target) then
        return
    end
    tower:SetForceAttackTarget(nil)
    self.forced_target = nil
    self.manual_target = nil
    if tower.Stop then tower:Stop() end
end

function modifier_tower_auto_attack:OnCreated()
    if not IsServer() then return end
    self.forced_target = nil
    local tower = self:GetParent()
    if valid(tower) then
        if tower.SetAcquisitionRange then
            tower:SetAcquisitionRange(math.max(
                global_rules.tower_acquisition_range,
                current_attack_range(tower)
            ))
        end
    end
    self:StartIntervalThink(0.25)
end

function modifier_tower_auto_attack:ResetTarget()
    if not IsServer() then return end
    local tower = self:GetParent()
    self.forced_target = nil
    self.manual_target = nil
    if valid(tower) then tower:SetForceAttackTarget(nil) end
end

function modifier_tower_auto_attack:SetManualTarget(target)
    if not IsServer() then return end
    local tower = self:GetParent()
    if not valid(tower) or not valid(target)
        or tree_damage_rules.is_tree(target)
        or not anti_air_rules.can_attack(tower, target)
        or target:GetTeamNumber() == tower:GetTeamNumber() then
        return
    end
    self.manual_target = target
    self.forced_target = nil
    tower:SetForceAttackTarget(target)
    self.forced_target = target
    print(string.format("[TOWER_MANUAL_TARGET] tower=%s target=%s action=set",
        tostring(tower:entindex()), tostring(target:entindex())))
end
function modifier_tower_auto_attack:OnIntervalThink()
    if not IsServer() then return end
    local tower = self:GetParent()
    if not valid(tower) then return end

    local target = self.manual_target
    local manual_distance = valid(target)
        and (target:GetAbsOrigin() - tower:GetAbsOrigin()):Length2D()
        or 99999
    local attack_range = current_attack_range(tower)
    if target and (not valid(target) or tree_damage_rules.is_tree(target)
        or target.IsAlive and not target:IsAlive()
        or not anti_air_rules.can_attack(tower, target)
        or target:GetTeamNumber() == tower:GetTeamNumber()
        or manual_distance > attack_range + 96) then
        self.manual_target = nil
        target = nil
    end
    -- A player-selected target has priority over the engine's acquisition
    -- target until it becomes invalid or leaves attack range.
    if not target then target = tower:GetAttackTarget() end
    local distance = valid(target)
        and (target:GetAbsOrigin() - tower:GetAbsOrigin()):Length2D()
        or 99999
    if not self.manual_target and tree_damage_rules.is_tree(target)
        or is_training_dummy(target) and find_target(tower) ~= target
        or not anti_air_rules.can_attack(tower, target) then
        tower:SetForceAttackTarget(nil)
        self.forced_target = nil
    end
    if not valid(target) or not self.manual_target and tree_damage_rules.is_tree(target)
        or is_training_dummy(target) and find_target(tower) ~= target
        or not anti_air_rules.can_attack(tower, target)
        or target:GetTeamNumber() == tower:GetTeamNumber()
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
        self.manual_target = nil
    end
end

modifier_tower_auto_attack._find_target_for_test = find_target
modifier_tower_auto_attack._is_tree_for_test = tree_damage_rules.is_tree

return modifier_tower_auto_attack
