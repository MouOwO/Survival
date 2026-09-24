local scheduler = require("core/scheduler")
local tree_damage_rules = require("systems/tree_damage_rules")

modifier_tree_progression = class({})
local M = modifier_tree_progression

function M:IsHidden() return true end
function M:IsPurgable() return false end
function M:RemoveOnDeath() return false end
function M:GetAttributes() return MODIFIER_ATTRIBUTE_PERMANENT end

function M:DeclareFunctions()
    return {
        MODIFIER_PROPERTY_MIN_HEALTH,
        MODIFIER_PROPERTY_INCOMING_DAMAGE_PERCENTAGE,
        MODIFIER_EVENT_ON_ATTACK_START,
        MODIFIER_EVENT_ON_ATTACK_FAIL,
        MODIFIER_EVENT_ON_ATTACK_RECORD_DESTROY,
        MODIFIER_EVENT_ON_TAKEDAMAGE,
    }
end

function M:OnAttackStart(params)
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
    if not IsServer() or not params or params.target ~= self:GetParent() then return end
    local token = self.tree_attackers and self.tree_attackers[params.attacker]
    local remaining = tree_damage_rules.clear_basic_attack_token(token, params.record)
    if not remaining and self.tree_attackers then
        self.tree_attackers[params.attacker] = nil
    end
end

function M:OnAttackRecordDestroy(params)
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
