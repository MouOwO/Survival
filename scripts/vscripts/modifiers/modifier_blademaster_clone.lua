require("modifiers/modifier_weapon_stat_projection")

modifier_blademaster_clone = _G.modifier_blademaster_clone or class({})
_G.modifier_blademaster_clone = modifier_blademaster_clone

local function finite(value, fallback)
    value = tonumber(value)
    if value and value == value and math.abs(value) < math.huge then return value end
    return fallback
end

local function valid(unit)
    return unit and not unit:IsNull()
end

local function secondary(params, parent)
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

local function attack_damage(params)
    if params.inflictor ~= nil then return false end
    local category = tonumber(params.damage_category)
    return category == nil or category == 0 or category == DOTA_DAMAGE_CATEGORY_ATTACK
end

function modifier_blademaster_clone:IsHidden() return true end
function modifier_blademaster_clone:IsPurgable() return false end
function modifier_blademaster_clone:RemoveOnDeath() return false end

function modifier_blademaster_clone:OnCreated(params)
    self.player_id = tonumber(params and params.player_id)
        or self:GetParent():GetPlayerOwnerID()
    self.records = {}
    self.combat_snapshot = {}
    self.active_attack_record = nil
    self.resolving_clone_q = false
    self.destroyed = false
end

function modifier_blademaster_clone:DeclareFunctions()
    return {
        MODIFIER_PROPERTY_DAMAGEOUTGOING_PERCENTAGE,
        MODIFIER_EVENT_ON_ATTACK_RECORD,
        MODIFIER_EVENT_ON_TAKEDAMAGE,
        MODIFIER_EVENT_ON_ATTACK_RECORD_DESTROY,
        MODIFIER_EVENT_ON_DEATH,
    }
end

function modifier_blademaster_clone:SetCombatSnapshot(value)
    -- Copy the critical fields: a later stat refresh must not change the roll
    -- already captured by an in-flight attack record.
    self.combat_snapshot = {
        critical_chance_pct = math.max(0, math.min(100,
            finite(value and value.critical_chance_pct, 0))),
        critical_damage_pct = math.max(100,
            finite(value and value.critical_damage_pct, 200)),
    }
end

function modifier_blademaster_clone:OnAttackRecord(params)
    if not IsServer() or self.destroyed or not params
        or params.attacker ~= self:GetParent() or params.record == nil
        or self.resolving_clone_q then return end
    local parent = self:GetParent()
    if not valid(parent) or (parent.IsAlive and not parent:IsAlive()) then return end
    local key = tostring(params.record)
    if self.records[key] then return end
    local is_secondary = secondary(params, parent)
    local multiplier = 0
    if not is_secondary then
        multiplier = modifier_weapon_stat_projection.RollCriticalAttackRecord(
            params.record, self.combat_snapshot, parent)
    end
    self.records[key] = {
        record = params.record, target = params.target,
        multiplier = multiplier, secondary = is_secondary,
        displayed_targets = {}, q_triggered = false,
    }
    self.active_attack_record = params.record
end

function modifier_blademaster_clone:GetModifierDamageOutgoing_Percentage(params)
    if not IsServer() or self.destroyed or self.resolving_clone_q then return 0 end
    params = params or {}
    if not attack_damage(params)
        or (params.attacker and params.attacker ~= self:GetParent()) then return 0 end
    local record = params.record
    if record == nil then record = self.active_attack_record end
    local state = record ~= nil and self.records[tostring(record)] or nil
    if not state or state.secondary or secondary(params, self:GetParent()) then return 0 end
    -- DamageFilter restores survival_endless_attack_scale exactly once. Adding
    -- its projection here would multiply large ordinary attacks a second time.
    return state.multiplier > 0 and state.multiplier - 100 or 0
end

local function show_damage(self, victim, damage, critical, ability_damage)
    local player = self.player_id ~= nil and self.player_id >= 0
        and PlayerResource:GetPlayer(self.player_id) or nil
    SendOverheadEventMessage(player,
        ability_damage and OVERHEAD_ALERT_DAMAGE
            or critical and OVERHEAD_ALERT_CRITICAL or OVERHEAD_ALERT_BONUS_SPELL_DAMAGE,
        victim, math.max(1, math.floor(damage + 0.5)), nil)
end

function modifier_blademaster_clone:OnTakeDamage(params)
    if not IsServer() or self.destroyed or not params
        or params.attacker ~= self:GetParent() then return end
    local parent, victim = self:GetParent(), params.unit
    if not valid(parent) or not valid(victim)
        or victim:GetTeamNumber() == parent:GetTeamNumber() then return end
    local native_damage = finite(params.damage, 0)
    if native_damage <= 0 then return end
    -- OnTakeDamage reports bounded engine health. Restore only the victim's
    -- health projection; the source attack projection was already restored by
    -- DamageFilter before armor, reductions and the victim projection.
    local damage = finite(native_damage * math.max(1,
        finite(victim.survival_endless_health_scale, 1)), 0)
    if damage <= 0 then return end
    if not attack_damage(params) then
        if valid(params.inflictor) then show_damage(self, victim, damage, false, true) end
        return
    end
    local record = params.record
    local state = record ~= nil and self.records[tostring(record)] or nil
    if not state then return end
    if self.active_attack_record == record then self.active_attack_record = nil end
    local victim_key = tostring(victim:entindex())
    if state.displayed_targets[victim_key] then return end
    state.displayed_targets[victim_key] = true
    local critical = modifier_weapon_stat_projection.PeekCriticalAttackRecord(parent, record)
    local primary = not state.secondary and not secondary(params, parent)
        and (state.target == nil or state.target == victim)
    show_damage(self, victim, damage, critical and primary, false)
    if not primary or not critical or state.q_triggered or self.resolving_clone_q
        or (parent.IsAlive and not parent:IsAlive()) then return end
    state.q_triggered = true
    -- Keep this isolated from HERO_MAIN_ATTACK_* and FINAL_CRITICAL_ATTACK:
    -- the permanent defender only copies its Q, never the owner's other procs.
    self.resolving_clone_q = true
    local ok, failure = pcall(function()
        require("systems/blademaster_exclusive_service")
            .trigger_clone_q(self.player_id, parent, victim, damage)
    end)
    self.resolving_clone_q = false
    if not ok then print("[BlademasterClone] critical Q failed: " .. tostring(failure)) end
end

function modifier_blademaster_clone:OnAttackRecordDestroy(params)
    if not IsServer() or not params or params.attacker ~= self:GetParent()
        or params.record == nil then return end
    local key = tostring(params.record)
    if self.records then self.records[key] = nil end
    if self.active_attack_record == params.record then self.active_attack_record = nil end
    modifier_weapon_stat_projection.ClearCriticalAttackRecord(self:GetParent(), params.record)
end

function modifier_blademaster_clone:ClearAttackRecords()
    for _, state in pairs(self.records or {}) do
        modifier_weapon_stat_projection.ClearCriticalAttackRecord(self:GetParent(), state.record)
    end
    self.records = {}
    self.active_attack_record = nil
end

function modifier_blademaster_clone:OnDeath(params)
    if IsServer() and params and params.unit == self:GetParent() then self:ClearAttackRecords() end
end

function modifier_blademaster_clone:OnDestroy()
    if not IsServer() then return end
    self.destroyed = true
    self:ClearAttackRecords()
end

return modifier_blademaster_clone
