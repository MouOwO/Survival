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
    self.attack_enabled = enabled == true
    if self:GetStackCount() == count then return end
    self:SetStackCount(count)
    self:ForceRefresh()
end

local function valid(unit)
    return unit and not unit:IsNull() and unit:IsAlive()
end

local current_attack_range = tower_combat_rules.current_attack_range
local THINK_INTERVAL = 0.25
local ATTACK_ORDER_RETRY_SECONDS = THINK_INTERVAL

local function disable_native_acquisition(tower, modifier, force)
    if not force and modifier.native_acquisition_disabled
        and (not tower.GetAcquisitionRange or tower:GetAcquisitionRange() == 0) then return end
    if tower.SetIdleAcquire then tower:SetIdleAcquire(false) end
    if tower.SetAcquisitionRange then tower:SetAcquisitionRange(0) end
    modifier.native_acquisition_disabled = true
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

local function find_target(tower, excluded_target)
    local attack_range = current_attack_range(tower)
    local origin, team = tower:GetAbsOrigin(), tower:GetTeamNumber()
    local radius = math.max(attack_range + 64, 700)
    local units = FindUnitsInRadius(
        team, origin, nil, radius,
        DOTA_UNIT_TARGET_TEAM_ENEMY,
        DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC,
        DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES,
        FIND_CLOSEST, false)
    local training_dummy = nil
    for _, unit in ipairs(units or {}) do
        if unit ~= excluded_target and valid(unit) and not tree_damage_rules.is_tree(unit)
            and unit:GetTeamNumber() ~= team
            and anti_air_rules.can_attack(tower, unit)
            and (unit:GetAbsOrigin() - origin):Length2D() <= attack_range + 64 then
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
        and (not is_training_dummy(target) or self.forced_target == target) then
        return
    end
    self:EnterIdle(true)
end

function modifier_tower_auto_attack:OnDeath(params)
    if not IsServer() or not params or not params.unit then return end
    if self.attack_enabled == false and self.forced_target == nil and self.manual_target == nil then
        return
    end
    local tower = self:GetParent()
    if params.unit and (params.unit == self.forced_target or params.unit == self.manual_target
        or (valid(tower) and params.unit == tower:GetAttackTarget())) then
        if not valid(tower) then return end
        -- A kill is a target change, not an idle transition. Disarming/Stop here
        -- interrupted the next attack, then a forced-target hint could spend a
        -- whole second waiting for the retry while native acquisition was off.
        local target = self:SelectTarget(params.unit)
        if target then
            self:SetAttackEnabled(true)
            if self.forced_target ~= target or tower:GetAttackTarget() ~= target then
                self:IssueAttackTarget(target, tower:GetAttackTarget() ~= target)
            end
        else
            self:EnterIdle()
        end
    end
end

function modifier_tower_auto_attack:OnCreated()
    if not IsServer() then return end
    self.forced_target, self.manual_target = nil, nil
    self.idle_initialized = false
    local tower = self:GetParent()
    if valid(tower) then
        disable_native_acquisition(tower, self, true)
    end
    self:EnterIdle(true)
    self:StartIntervalThink(THINK_INTERVAL)
end

function modifier_tower_auto_attack:ResetTarget()
    if not IsServer() then return end
    local tower = self:GetParent()
    if valid(tower) then
        disable_native_acquisition(tower, self, true)
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

function modifier_tower_auto_attack:IssueAttackTarget(target, issue_order)
    local tower = self:GetParent()
    if not valid(tower) or not valid(target) or tree_damage_rules.is_tree(target) then return end
    self.forced_target, self.attack_order_wait = target, 0
    self.issuing_attack_order = true
    local ok = pcall(function()
        tower:SetForceAttackTarget(target)
        -- Idle acquisition is disabled. On a new automatic target, issue the
        -- actual order immediately instead of waiting for a forced-target hint
        -- to turn into an attack. Manual targeting already has an engine order.
        if issue_order and tower.MoveToTargetToAttack and valid(target) then
            tower:MoveToTargetToAttack(target)
        end
    end)
    self.issuing_attack_order = false
    if not ok then self.forced_target = nil end
end

function modifier_tower_auto_attack:SelectTarget(excluded_target)
    local tower = self:GetParent()
    local attack_range = current_attack_range(tower)
    local function legal(target)
        return target ~= excluded_target and valid(target) and not tree_damage_rules.is_tree(target)
            and anti_air_rules.can_attack(tower, target)
            and target:GetTeamNumber() ~= tower:GetTeamNumber()
            and (target:GetAbsOrigin() - tower:GetAbsOrigin()):Length2D() <= attack_range + 96
    end
    if not legal(self.manual_target) then self.manual_target = nil end
    -- Keep a legal player selection or ongoing engine target. Training dummies
    -- still yield to real enemies; no target leaves the tower explicitly idle.
    local target = self.manual_target or tower:GetAttackTarget()
    if not legal(target) then target = nil end
    if not target and legal(self.forced_target) then target = self.forced_target end
    if target and is_training_dummy(target) then
        local preferred = find_target(tower, excluded_target)
        if preferred ~= target then
            self.manual_target = nil
        end
        return preferred
    end
    if not target then target = find_target(tower, excluded_target) end
    return target
end

function modifier_tower_auto_attack:OnIntervalThink()
    if not IsServer() then return end
    local tower = self:GetParent()
    if not valid(tower) then return end

    -- Idle acquisition is distinct from acquisition radius. Disable both;
    -- approved combat targets below are still attacked explicitly.
    disable_native_acquisition(tower, self)
    if tree_damage_rules.is_tree(tower:GetAttackTarget()) then
        self:EnterIdle(true)
    end

    local target = self:SelectTarget()
    if not valid(target) then
        self:EnterIdle()
        return
    end

    -- Never repeat a healthy attack each think. But Lua's remembered target
    -- alone does not prove that the engine accepted it: disarm transitions,
    -- another Stop(), or an interrupted initial order can leave the tower idle.
    self:SetAttackEnabled(true)
    if self.forced_target ~= target then
        self:IssueAttackTarget(target, tower:GetAttackTarget() ~= target)
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
