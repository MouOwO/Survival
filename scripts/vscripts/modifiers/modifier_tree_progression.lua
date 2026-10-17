local scheduler = require("core/scheduler")
local tree_damage_rules = require("systems/tree_damage_rules")
local tree_observer = require("systems/tree_attack_observer")

modifier_tree_progression = class({})
local M = modifier_tree_progression

function M:IsHidden() return true end
function M:IsPurgable() return false end
function M:RemoveOnDeath() return false end
function M:GetAttributes() return MODIFIER_ATTRIBUTE_PERMANENT end

-- Source 2 first reads declarations before OnCreated. Lock the decision at
-- that FIRST read, using only an already confirmed formal tree and native
-- carrier. Later OnCreated/refresh/global flag changes never alter its cache.
local function sample_tree_events(self)
    if self.survival_tree_event_decl_sampled == true then return end
    self.survival_tree_event_decl_sampled = true
    self.shared_tree_observer = false
    local ok, shared = pcall(function()
        if not tree_observer.can_register_new() then return false end
        -- Explicit probe only; counters include manual declaration queries as
        -- well as engine calls. Census reads these fields without invoking this
        -- function, so it does not manufacture another native lifecycle call.
        self.survival_tree_probe_declaration_counted = true
        self.survival_tree_declaration_calls = 0
        self.survival_tree_declaration_calls_before_created = 0
        self.survival_tree_declaration_calls_after_created = 0
        local parent = self:GetParent()
        local id = tonumber(parent and parent.survival_tree_owner_id)
        if not tree_damage_rules.is_tree(parent) or parent:IsRealHero() ~= false
            or parent:GetClassname() ~= "npc_dota_creature" or not id or id < 0 or id ~= math.floor(id)
            or type(parent.survival_tree_depleted_callback) ~= "function" then return false end
        return tree_observer.register(parent,self,{
            HandleAttackStart=M.HandleAttackStart,HandleAttackFail=M.HandleAttackFail,
            HandleAttackRecordDestroy=M.HandleAttackRecordDestroy,HandleTakeDamage=M.HandleTakeDamage})
    end)
    self.shared_tree_observer = ok and shared == true
    self.survival_tree_event_decl_reason = self.shared_tree_observer and "tools_shared_formal_tree"
        or ok and "probe_disabled_or_unknown_tree_identity" or "tree_role_or_registration_exception"
end
function M:OnCreated()
    if type(self.GetParent) == "function" then
        if self.survival_tree_created ~= true then self.survival_tree_created = true end
        sample_tree_events(self)
    end
end
function M:DeclareFunctions()
    -- A class-level query has no native parent and must not poison later
    -- instances through inherited class fields. An instance with an unknown
    -- or unavailable parent permanently takes the guarded legacy path.
    if type(self.GetParent) == "function" and self.survival_tree_event_decl_sampled ~= true then sample_tree_events(self) end
    if self.survival_tree_probe_declaration_counted == true then
        self.survival_tree_declaration_calls = (self.survival_tree_declaration_calls or 0) + 1
        local key = self.survival_tree_created == true and "survival_tree_declaration_calls_after_created"
            or "survival_tree_declaration_calls_before_created"
        self[key] = (self[key] or 0) + 1
    end
    local functions = {
        MODIFIER_PROPERTY_MIN_HEALTH,
        MODIFIER_PROPERTY_INCOMING_DAMAGE_PERCENTAGE,
    }
    if self.shared_tree_observer ~= true then
        functions[#functions+1]=MODIFIER_EVENT_ON_ATTACK_START
        functions[#functions+1]=MODIFIER_EVENT_ON_ATTACK_FAIL
        functions[#functions+1]=MODIFIER_EVENT_ON_ATTACK_RECORD_DESTROY
        functions[#functions+1]=MODIFIER_EVENT_ON_TAKEDAMAGE
    end
    return functions
end

function M:OnAttackStart(params)
    if self.shared_tree_observer == true then return end
    return self:HandleAttackStart(params)
end
function M:HandleAttackStart(params)
    if not IsServer() or not params or params.target ~= self:GetParent() then return end
    local marked, token = tree_damage_rules.mark_basic_attack(
        params.attacker,
        self:GetParent(),
        params.record
    )
    if marked then
        self.tree_attackers = self.tree_attackers or {}
        self.tree_attackers[params.attacker] = token
    end
end

function M:OnAttackFail(params)
    if self.shared_tree_observer == true then return end
    return self:HandleAttackFail(params)
end
function M:HandleAttackFail(params)
    if not IsServer() or not params or params.target ~= self:GetParent() then return end
    local token = self.tree_attackers and self.tree_attackers[params.attacker]
    local remaining = tree_damage_rules.clear_basic_attack_token(token, params.record)
    if not remaining and self.tree_attackers then
        self.tree_attackers[params.attacker] = nil
    end
end

function M:OnAttackRecordDestroy(params)
    if self.shared_tree_observer == true then return end
    return self:HandleAttackRecordDestroy(params)
end
function M:HandleAttackRecordDestroy(params)
    if not IsServer() or not params then return end
    -- This engine event is broadcast to every tree for every attack. Only the
    -- tree that observed this attacker may touch its pending evidence queue.
    local token = self.tree_attackers and self.tree_attackers[params.attacker]
    if not token then return end
    if not tree_damage_rules.clear_basic_attack_token(token, params.record) then
        self.tree_attackers[params.attacker] = nil
    end
end

function M:OnDestroy()
    tree_observer.unregister(self)
    if not IsServer() or not self.tree_attackers then return end
    for _, token in pairs(self.tree_attackers) do
        tree_damage_rules.clear_basic_attack_token(token, nil)
    end
    self.tree_attackers = nil
end

function M:GetModifierIncomingDamage_Percentage(params)
    params = params or {}
    if not tree_damage_rules.is_allowed_tree_attacker(params.attacker) then
        return -100
    end
    -- DamageFilter owns final classification and can consume the attack evidence
    -- recorded by this modifier. Modifier damage params can omit the category or
    -- report 0 for a real ranged attack, so keep only the attacker whitelist backstop.
    return 0
end

function M:GetMinHealth()
    return 1
end

function M:OnTakeDamage(params)
    if self.shared_tree_observer == true then return end
    return self:HandleTakeDamage(params)
end
function M:HandleTakeDamage(params)
    if not IsServer() then return end
    local parent = self:GetParent()
    if params.unit ~= parent or (tonumber(params.damage) or 0) <= 0 then return end
    if parent:GetHealth() > 1 or self.upgrade_pending then return end
    local callback = parent.survival_tree_depleted_callback
    if type(callback) ~= "function" then return end

    self.upgrade_pending = true
    callback(parent)
    self.upgrade_pending = false
end

return M
