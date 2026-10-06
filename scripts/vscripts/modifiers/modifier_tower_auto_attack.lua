LinkLuaModifier("modifier_tower_auto_attack", "modifiers/modifier_tower_auto_attack", LUA_MODIFIER_MOTION_NONE)
local tree_damage_rules = require("systems/tree_damage_rules")
local anti_air_rules = require("systems/anti_air_rules")
local targeting = require("systems/tower_targeting")
modifier_tower_auto_attack = class({})
_G.modifier_tower_auto_attack = modifier_tower_auto_attack

function modifier_tower_auto_attack:IsHidden() return true end
function modifier_tower_auto_attack:IsPurgable() return false end
function modifier_tower_auto_attack:GetAttributes() return MODIFIER_ATTRIBUTE_PERMANENT end

function modifier_tower_auto_attack:DeclareFunctions()
    return { MODIFIER_EVENT_ON_ATTACK_START, MODIFIER_EVENT_ON_ATTACK, MODIFIER_EVENT_ON_DEATH,
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
    self.windup_target = nil
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
    return targeting.select(tower, excluded_target)
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
        if params.no_attack_cooldown ~= true and params.no_attack_cooldown ~= 1 then
            self.windup_target = target
        end
        return
    end
    self:EnterIdle(true)
end

-- Releasing a shot clears its windup, but does not release the combat target.
function modifier_tower_auto_attack:OnAttack(params)
    if not IsServer() or params.attacker ~= self:GetParent() then return end
    if params.no_attack_cooldown == true or params.no_attack_cooldown == 1 then return end
    if self.windup_target == params.target then self.windup_target = nil end
end

function modifier_tower_auto_attack:VerifyTargetNextFrame(target)
    local tower = self:GetParent()
    if not tower.SetContextThink then return end
    tower:SetContextThink("SurvivalTowerVerifyTarget", function()
        if self.destroyed or not valid(tower) or self.forced_target ~= target then return nil end
        -- The engine may clear its old attack order after dispatching OnDeath.
        -- Recheck once next frame, without waiting for the 0.25s idle scan.
        if targeting.valid(tower, target) and tower:GetAttackTarget() ~= target then
            self:IssueAttackTarget(target, true)
        end
        return nil
    end, 0)
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
        if self.windup_target == params.unit then self.windup_target = nil end
        -- A kill is a target change, not an idle transition. Disarming/Stop here
        -- interrupted the next attack, then a forced-target hint could spend a
        -- whole second waiting for the retry while native acquisition was off.
        local target = self:SelectTarget(params.unit)
        if target then
            self:SetAttackEnabled(true)
            if self.forced_target ~= target or tower:GetAttackTarget() ~= target then
                self:IssueAttackTarget(target, tower:GetAttackTarget() ~= target)
            end
            self:VerifyTargetNextFrame(target)
        else
            self:EnterIdle()
        end
    end
end

function modifier_tower_auto_attack:OnCreated()
    if not IsServer() then return end
    self.forced_target, self.manual_target = nil, nil
    self.windup_target, self.destroyed = nil, false
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
        or not targeting.in_range(tower, target) then
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
        -- These are stationary towers. Face the next victim immediately so a
        -- hero model's turn animation cannot add a separate targeting delay.
        if tower.SetForwardVector then
            local direction = target:GetAbsOrigin()-tower:GetAbsOrigin()
            direction.z = 0
            if direction.x*direction.x + direction.y*direction.y > 0 and direction.Normalized then
                tower:SetForwardVector(direction:Normalized())
            end
        end
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
    local function legal(target)
        return targeting.valid(tower, target, excluded_target)
    end
    if not legal(self.manual_target) then self.manual_target = nil end
    if self.manual_target and not is_training_dummy(self.manual_target) then return self.manual_target end
    -- A living in-range combat victim remains locked across attack cycles.
    -- Training dummies still yield to real enemies instead of pinning the tower.
    if legal(self.forced_target) and not is_training_dummy(self.forced_target) then
        return self.forced_target
    end
    if legal(self.windup_target) and tower:GetAttackTarget() == self.windup_target
        and not is_training_dummy(self.windup_target) then return self.windup_target end
    self.windup_target = nil
    return find_target(tower, excluded_target)
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
        self.destroyed = true
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
