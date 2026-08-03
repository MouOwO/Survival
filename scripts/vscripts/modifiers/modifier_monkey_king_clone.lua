local events = require("core/events")
local armor_balance = require("config/armor_balance")
local runtime = require("config/generated/monkey_king_exclusive_runtime")

modifier_monkey_king_clone = class({})

function modifier_monkey_king_clone:IsHidden() return true end
function modifier_monkey_king_clone:IsPurgable() return false end
function modifier_monkey_king_clone:RemoveOnDeath() return false end

function modifier_monkey_king_clone:OnCreated(params)
    self.player_id = tonumber(params and params.player_id)
        or self:GetParent():GetPlayerOwnerID()
end

function modifier_monkey_king_clone:DeclareFunctions()
    return {
        MODIFIER_PROPERTY_PHYSICAL_ARMOR_BONUS,
        MODIFIER_PROPERTY_PREATTACK_CRITICALSTRIKE,
        MODIFIER_EVENT_ON_ATTACK_LANDED,
    }
end

function modifier_monkey_king_clone:SetCombatSnapshot(value)
    self.combat_snapshot = value or {}
end

function modifier_monkey_king_clone:GetModifierPhysicalArmorBonus()
    local row = runtime.by_id.monkey_king_exclusive or {}
    local desired = armor_balance.from_war3(row.w_clone_war3_armor)
    local base = self:GetParent():GetPhysicalArmorBaseValue()
    return desired - (tonumber(base) or 0)
end

function modifier_monkey_king_clone:GetModifierPreAttack_CriticalStrike()
    if not IsServer() then return 0 end
    local stats = self.combat_snapshot or {}
    local chance = math.max(0, math.min(100,
        tonumber(stats.critical_chance_pct) or 0))
    return chance > 0 and RandomFloat(0, 100) < chance
        and math.max(100, tonumber(stats.critical_damage_pct) or 200) or 0
end

function modifier_monkey_king_clone:OnAttackLanded(params)
    if not IsServer() or params.attacker ~= self:GetParent() then return end
    local target = params.target
    if not target or target:IsNull()
        or target:GetTeamNumber() == self:GetParent():GetTeamNumber() then return end
    require("systems/monkey_king_exclusive_service")
        .trigger_clone_q(self.player_id, self:GetParent(), target)
end

return modifier_monkey_king_clone