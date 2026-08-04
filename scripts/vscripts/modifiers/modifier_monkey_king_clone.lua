local events = require("core/events")
local armor_balance = require("config/armor_balance")
local runtime = require("config/generated/monkey_king_exclusive_runtime")
require("modifiers/modifier_weapon_stat_projection")

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
        MODIFIER_PROPERTY_DAMAGEOUTGOING_PERCENTAGE,
        MODIFIER_EVENT_ON_ATTACK_RECORD,
        MODIFIER_EVENT_ON_ATTACK_LANDED,
        MODIFIER_EVENT_ON_TAKEDAMAGE,
        MODIFIER_EVENT_ON_ATTACK_RECORD_DESTROY,
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

function modifier_monkey_king_clone:OnAttackRecord(params)
    if not IsServer() or not params
        or params.attacker ~= self:GetParent() then return end
    self.active_attack_multiplier =
        modifier_weapon_stat_projection.RollCriticalAttackRecord(
            params.record, self.combat_snapshot or {}, self:GetParent()
        )
    self.active_attack_record = params.record
end

function modifier_monkey_king_clone:GetModifierDamageOutgoing_Percentage()
    local multiplier = tonumber(self.active_attack_multiplier) or 0
    self.active_attack_multiplier = nil
    self.active_attack_record = nil
    return multiplier > 0 and multiplier - 100 or 0
end

function modifier_monkey_king_clone:OnTakeDamage(params)
    if not IsServer() or params.attacker ~= self:GetParent() then return end
    modifier_weapon_stat_projection.ShowFinalAttackDamage(
        self.player_id, self:GetParent(), params.unit, params
    )
end

function modifier_monkey_king_clone:OnAttackRecordDestroy(params)
    if not IsServer() or params.attacker ~= self:GetParent() then return end
    if self.active_attack_record == params.record then
        self.active_attack_multiplier = nil
        self.active_attack_record = nil
    end
    modifier_weapon_stat_projection.ClearCriticalAttackRecord(
        self:GetParent(), params.record
    )
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