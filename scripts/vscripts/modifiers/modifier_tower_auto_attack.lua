LinkLuaModifier("modifier_tower_auto_attack", "modifiers/modifier_tower_auto_attack", LUA_MODIFIER_MOTION_NONE)
local tower_combat_rules = require("config/tower_combat_rules")
local tree_damage_rules = require("systems/tree_damage_rules")
local anti_air_rules = require("systems/anti_air_rules")
modifier_tower_auto_attack = class({})
_G.modifier_tower_auto_attack = modifier_tower_auto_attack

function modifier_tower_auto_attack:IsHidden() return true end
function modifier_tower_auto_attack:IsPurgable() return false end
function modifier_tower_auto_attack:GetAttributes() return MODIFIER_ATTRIBUTE_PERMANENT end

function modifier_tower_auto_attack:DeclareFunctions()
    return { MODIFIER_EVENT_ON_ATTACK_START, MODIFIER_EVENT_ON_DEATH,
        MODIFIER_PROPERTY_DISABLE_AUTOATTACK }
end

-- Replicated modifier stacks keep the server and client in the same state:
-- idle (0) cannot even start an attack; only an approved target unlocks it (1).
function modifier_tower_auto_attack:CheckState()
    if self:GetStackCount() == 0 then return { [MODIFIER_STATE_DISARMED] = true } end
    return {}
end

function modifier_tower_auto_attack:GetDisableAutoAttack()
    return self:GetStackCount() == 0 and 1 or 0
end

function modifier_tower_auto_attack:SetAttackEnabled(enabled)
    local count = enabled and 1 or 0
    if self:GetStackCount() == count then return end
    self:SetStackCount(count)
    self:ForceRefresh()
end

local function valid(unit)
    return unit and not unit:IsNull() and unit:IsAlive()
end

local current_attack_range = tower_combat_rules.current_attack_range
local THINK_INTERVAL = 0.25
local ATTACK_ORDER_RETRY_SECONDS = 1

local function disable_native_acquisition(tower)
    if tower.SetIdleAcquire then tower:SetIdleAcquire(false) end
    if tower.SetAcquisitionRange then tower:SetAcquisitionRange(0) end
end

local function clear_attack_gestures(tower)
    if not tower.FadeGesture then return end
    for _, name in ipairs({ "ACT_DOTA_ATTACK", "ACT_DOTA_ATTACK2", "ACT_DOTA_ATTACK_EVENT" }) do
        local activity = rawget(_G, name)
        if activity ~= nil then tower:FadeGesture(activity) end
    end
end

function modifier_tower_auto_attack:EnterIdle(force_stop)
    local tower = self:GetParent()
    local needs_stop = force_stop or not self.idle_initialized
        or self:GetStackCount() ~= 0 or self.forced_target ~= nil or self.manual_target ~= nil
        or (valid(tower) and tower:GetAttackTarget() ~= nil)
    -- Close the gate before clearing orders, so the engine cannot acquire a
    -- nearby hostile tree between the previous target and the next AI update.
    self:SetAttackEnabled(false)
    self.forced_target, self.manual_target = nil, nil
    self.attack_order_wait = 0
    if valid(tower) and needs_stop then
        tower:SetForceAttackTarget(nil)
        if tower.Stop then tower:Stop() end
        clear_attack_gestures(tower)
    end
    self.idle_initialized = true
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
        if valid(unit) and not tree_damage_rules.is_tree(unit)
            and unit:GetTeamNumber() ~= tower:GetTeamNumber()
            and anti_air_rules.can_attack(tower, unit)
            and distance <= attack_range + 64 then
            if is_training_dummy(unit) then
                training_dummy = training_dummy or unit
            else
                return unit
            end
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
    if valid(target) and target:GetTeamNumber() ~= tower:GetTeamNumber()
        and self:GetStackCount() ~= 0 and not tree_damage_rules.is_tree(target)
        and anti_air_rules.can_attack(tower, target)
        and (not is_training_dummy(target) or find_target(tower) == target) then
        return
    end
    self:EnterIdle(true)
end

function modifier_tower_auto_attack:OnDeath(params)
    if not IsServer() then return end
    local tower = self:GetParent()
    if params.unit and (params.unit == self.forced_target or params.unit == self.manual_target
        or (valid(tower) and params.unit == tower:GetAttackTarget())) then
        self:EnterIdle()
    end
end

function modifier_tower_auto_attack:OnCreated()
    if not IsServer() then return end
    self.forced_target, self.manual_target = nil, nil
    self.idle_initialized = false
    local tower = self:GetParent()
    if valid(tower) then
        disable_native_acquisition(tower)
    end
    self:EnterIdle(true)
    self:StartIntervalThink(THINK_INTERVAL)
end

function modifier_tower_auto_attack:ResetTarget()
    if not IsServer() then return end
    local tower = self:GetParent()
    if valid(tower) then
        disable_native_acquisition(tower)
    end
    self:EnterIdle()
end

function modifier_tower_auto_attack:SetManualTarget(target)
    if not IsServer() then return end
    -- The execute-order filter also observes Lua-generated attack commands.
    -- Those must not recurse or turn automatic selection into a manual lock.
    if self.issuing_attack_order then return end
    local tower = self:GetParent()
    if not valid(tower) or not valid(target)
        or tree_damage_rules.is_tree(target)
        or not anti_air_rules.can_attack(tower, target)
        or target:GetTeamNumber() == tower:GetTeamNumber()
        or (target:GetAbsOrigin() - tower:GetAbsOrigin()):Length2D()
            > current_attack_range(tower) + 96 then
        return
    end
    self.manual_target = target
    self:SetAttackEnabled(true)
    self:IssueAttackTarget(target, false)
    print(string.format("[TOWER_MANUAL_TARGET] tower=%s target=%s action=set",
        tostring(tower:entindex()), tostring(target:entindex())))
end

function modifier_tower_auto_attack:IssueAttackTarget(target, recover)
    local tower = self:GetParent()
    if not valid(tower) or not valid(target) or tree_damage_rules.is_tree(target) then return end
    self.forced_target, self.attack_order_wait = target, 0
    self.issuing_attack_order = true
    local ok = pcall(function()
        tower:SetForceAttackTarget(target)
        -- SetForceAttackTarget can leave only a forced-target hint when the
        -- engine has just rejected/cleared an attack. Idle acquisition is off,
        -- so restart that stalled target with an explicit single-target order.
        if recover and tower.MoveToTargetToAttack and valid(target) then
            tower:MoveToTargetToAttack(target)
        end
    end)
    self.issuing_attack_order = false
    if not ok then self.forced_target = nil end
end

function modifier_tower_auto_attack:OnIntervalThink()
    if not IsServer() then return end
    local tower = self:GetParent()
    if not valid(tower) then return end

    -- Idle acquisition is distinct from acquisition radius. Disable both;
    -- approved combat targets below are still attacked explicitly.
    disable_native_acquisition(tower)
    if tree_damage_rules.is_tree(tower:GetAttackTarget()) then
        self:EnterIdle(true)
    end

    local attack_range = current_attack_range(tower)
    local function legal(target)
        return valid(target) and not tree_damage_rules.is_tree(target)
            and anti_air_rules.can_attack(tower, target)
            and target:GetTeamNumber() ~= tower:GetTeamNumber()
            and (target:GetAbsOrigin() - tower:GetAbsOrigin()):Length2D() <= attack_range + 96
    end
    if not legal(self.manual_target) then self.manual_target = nil end
    -- Keep a legal player selection or ongoing engine target. Training dummies
    -- still yield to real enemies; no target leaves the tower explicitly idle.
    local target = self.manual_target or tower:GetAttackTarget()
    if not legal(target) then target = nil end
    if target and is_training_dummy(target) then
        local preferred = find_target(tower)
        if preferred ~= target then
            self.manual_target = nil
            target = preferred
        end
    end
    if not target then target = find_target(tower) end
    if not valid(target) then
        self:EnterIdle()
        return
    end

    -- Never repeat a healthy attack each think. But Lua's remembered target
    -- alone does not prove that the engine accepted it: disarm transitions,
    -- another Stop(), or an interrupted initial order can leave the tower idle.
    self:SetAttackEnabled(true)
    if self.forced_target ~= target then
        self:IssueAttackTarget(target, false)
    elseif tower:GetAttackTarget() == target then
        self.attack_order_wait = 0
    else
        self.attack_order_wait = (self.attack_order_wait or 0) + THINK_INTERVAL
        if self.attack_order_wait >= ATTACK_ORDER_RETRY_SECONDS then
            self:IssueAttackTarget(target, true)
        end
    end
end

function modifier_tower_auto_attack:OnDestroy()
    if IsServer() then
        local tower = self:GetParent()
        if valid(tower) then
            tower:SetForceAttackTarget(nil)
            if tower.Stop then tower:Stop() end
            clear_attack_gestures(tower)
        end
        self.forced_target = nil
        self.manual_target = nil
    end
end

modifier_tower_auto_attack._find_target_for_test = find_target
modifier_tower_auto_attack._is_tree_for_test = tree_damage_rules.is_tree

return modifier_tower_auto_attack
