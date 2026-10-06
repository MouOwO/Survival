local armor_balance = require("config/armor_balance")
local runtime = require("config/generated/monkey_king_exclusive_runtime")
require("modifiers/modifier_weapon_stat_projection")

modifier_monkey_king_clone = class({})

local function secondary_attack(params, parent)
    local tracker = rawget(_G, "modifier_weapon_attack_tracker")
    return params.is_main_attack == false
        or params.is_multishot_secondary == true or params.is_multishot_secondary == 1
        or params.no_attack_cooldown == true or params.no_attack_cooldown == 1
        or parent.survival_is_multishot_secondary == true
        or parent.survival_next_multishot_secondary == true
        or parent.survival_next_drow_secondary == true
        or (tracker and tracker.IsSecondaryAttackRecord
            and tracker.IsSecondaryAttackRecord(params.record)) == true
end

function modifier_monkey_king_clone:IsHidden() return true end
function modifier_monkey_king_clone:IsPurgable() return false end
function modifier_monkey_king_clone:RemoveOnDeath() return false end

function modifier_monkey_king_clone:CheckState()
    return {
        [MODIFIER_STATE_NO_UNIT_COLLISION] = true,
    }
end

function modifier_monkey_king_clone:OnCreated(params)
    self.player_id = tonumber(params and params.player_id)
        or self:GetParent():GetPlayerOwnerID()
    self.attack_records = {}
    self.destroyed = false
end

function modifier_monkey_king_clone:DeclareFunctions()
    return {
        MODIFIER_PROPERTY_PHYSICAL_ARMOR_BONUS,
        MODIFIER_PROPERTY_DAMAGEOUTGOING_PERCENTAGE,
        MODIFIER_EVENT_ON_ATTACK_RECORD,
        MODIFIER_EVENT_ON_ATTACK_LANDED,
        MODIFIER_EVENT_ON_TAKEDAMAGE,
        MODIFIER_EVENT_ON_ATTACK_RECORD_DESTROY,
        MODIFIER_EVENT_ON_DEATH,
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
    if not IsServer() or self.destroyed or not params or params.record == nil
        or params.attacker ~= self:GetParent() then return end
    local parent = self:GetParent()
    if parent:IsNull() or not parent:IsAlive() then return end
    local key = tostring(params.record)
    if self.attack_records[key] then return end
    -- Capture the secondary flag while PerformAttack's temporary marker is set.
    -- It may already have been cleared by the time a projectile lands.
    self.attack_records[key] = {
        record = params.record, target = params.target,
        secondary = secondary_attack(params, parent), q_attempted = false,
    }
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
    if not IsServer() or not params or params.attacker ~= self:GetParent() then return end
    modifier_weapon_stat_projection.ShowFinalAttackDamage(
        self.player_id, self:GetParent(), params.unit, params
    )
    modifier_weapon_stat_projection.ShowFinalAbilityDamage(
        self.player_id, self:GetParent(), params.unit, params
    )
end

function modifier_monkey_king_clone:OnAttackRecordDestroy(params)
    if not IsServer() or not params or params.record == nil
        or params.attacker ~= self:GetParent() then return end
    self.attack_records[tostring(params.record)] = nil
    if self.active_attack_record == params.record then
        self.active_attack_multiplier = nil
        self.active_attack_record = nil
    end
    modifier_weapon_stat_projection.ClearCriticalAttackRecord(
        self:GetParent(), params.record
    )
end

function modifier_monkey_king_clone:OnAttackLanded(params)
    if not IsServer() or self.destroyed or not params or params.record == nil
        or params.attacker ~= self:GetParent() or params.inflictor ~= nil then return end
    local category = tonumber(params.damage_category)
    if category and category ~= 0 and category ~= DOTA_DAMAGE_CATEGORY_ATTACK then return end
    local parent = self:GetParent()
    local record = self.attack_records[tostring(params.record)]
    if not record or record.q_attempted or record.secondary
        or secondary_attack(params, parent) then return end
    local target = params.target
    if not target or target:IsNull()
        or target:GetTeamNumber() == parent:GetTeamNumber()
        or (record.target ~= nil and record.target ~= target) then return end
    -- One attempt per ordinary attack, including a failed roll or locked Q.
    -- The shared service owns the only probability roll and the complete Q.
    record.q_attempted = true
    require("systems/monkey_king_exclusive_service")
        .trigger_clone_q(self.player_id, parent, target)
end

function modifier_monkey_king_clone:ClearAttackRecords()
    for _, record in pairs(self.attack_records or {}) do
        modifier_weapon_stat_projection.ClearCriticalAttackRecord(
            self:GetParent(), record.record)
    end
    self.attack_records = {}
    self.active_attack_record = nil
    self.active_attack_multiplier = nil
end

function modifier_monkey_king_clone:OnDeath(params)
    if IsServer() and params and params.unit == self:GetParent() then self:ClearAttackRecords() end
end

function modifier_monkey_king_clone:OnDestroy()
    if not IsServer() then return end
    self.destroyed = true
    self:ClearAttackRecords()
end

return modifier_monkey_king_clone
