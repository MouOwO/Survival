LinkLuaModifier("modifier_rogue_training_dummy", "modifiers/modifier_rogue_training_dummy", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_rogue_training_attack_gain", "modifiers/modifier_rogue_training_dummy", LUA_MODIFIER_MOTION_NONE)

local event_bus = require("core/event_bus")
local events = require("core/events")

modifier_rogue_training_dummy = class({})
_G.modifier_rogue_training_dummy = modifier_rogue_training_dummy

function modifier_rogue_training_dummy:IsHidden() return false end
function modifier_rogue_training_dummy:IsPurgable() return false end

function modifier_rogue_training_dummy:DeclareFunctions()
    return { MODIFIER_EVENT_ON_ATTACK_LANDED }
end

function modifier_rogue_training_dummy:OnCreated(params)
    self.attack_gain = tonumber(params and params.value) or 0
    self.wall_entindex = tonumber(params and params.wall_entindex) or -1
    self.parent = self:GetParent()
    self.parent.survival_is_training_dummy = true
    self.parent.survival_training_dummy = true
    if IsServer() then
        self.wave_subscription = event_bus.subscribe(events.WAVE_CHANGED, function()
            if self and not self:IsNull() then self:Destroy() end
        end)
        self:StartIntervalThink(0.25)
    end
end

function modifier_rogue_training_dummy:OnIntervalThink()
    local wall = self.wall_entindex >= 0
        and EntIndexToHScript(self.wall_entindex) or nil
    if not wall or wall:IsNull() or not wall:IsAlive() then self:Destroy() end
end

function modifier_rogue_training_dummy:OnAttackLanded(params)
    if not IsServer() or params.target ~= self:GetParent() then return end
    local attacker = params.attacker
    if not attacker or attacker:IsNull() or not attacker:IsAlive() then return end
    if attacker.survival_is_training_dummy then return end
    if self.attack_gain <= 0 then return end
    local modifier = attacker:FindModifierByName("modifier_rogue_training_attack_gain")
        or attacker:AddNewModifier(attacker, nil, "modifier_rogue_training_attack_gain", {})
    if modifier then
        modifier:SetStackCount(modifier:GetStackCount() + self.attack_gain)
    end
end

function modifier_rogue_training_dummy:OnDestroy()
    if self.wave_subscription then
        event_bus.unsubscribe(self.wave_subscription)
        self.wave_subscription = nil
    end
    if IsServer() and self.parent and not self.parent:IsNull() then
        self.parent.survival_is_training_dummy = nil
        self.parent.survival_training_dummy = nil
        self.parent:ForceKill(false)
    end
end

modifier_rogue_training_attack_gain = class({})
_G.modifier_rogue_training_attack_gain = modifier_rogue_training_attack_gain

function modifier_rogue_training_attack_gain:IsHidden() return true end
function modifier_rogue_training_attack_gain:IsPurgable() return false end
function modifier_rogue_training_attack_gain:RemoveOnDeath() return false end
function modifier_rogue_training_attack_gain:GetAttributes()
    return MODIFIER_ATTRIBUTE_PERMANENT
end
function modifier_rogue_training_attack_gain:DeclareFunctions()
    return { MODIFIER_PROPERTY_PREATTACK_BONUS_DAMAGE }
end
function modifier_rogue_training_attack_gain:GetModifierPreAttack_BonusDamage()
    return self:GetStackCount()
end

return modifier_rogue_training_dummy