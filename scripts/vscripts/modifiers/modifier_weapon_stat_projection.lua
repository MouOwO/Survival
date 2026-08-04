LinkLuaModifier("modifier_weapon_stat_projection", "modifiers/modifier_weapon_stat_projection", LUA_MODIFIER_MOTION_NONE)

local event_bus = require("core/event_bus")
local events = require("core/events")

modifier_weapon_stat_projection = class({})

local critical_records = {}
local displayed_damage_records = {}
local damage_number_diagnostic_count = 0

local function diagnose_damage_number(action, fields)
    if not GameRules or not GameRules.GetGameTime
        or damage_number_diagnostic_count >= 80 then return end
    damage_number_diagnostic_count = damage_number_diagnostic_count + 1
    print(string.format(
        "[HERO_ATTACK_DAMAGE_NUMBER] action=%s record=%s attacker=%s "
            .. "victim=%s critical=%s chance=%s multiplier=%s damage=%s category=%s "
            .. "inflictor=%s style=%s",
        tostring(action),
        tostring(fields and fields.record or "nil"),
        tostring(fields and fields.attacker or "nil"),
        tostring(fields and fields.victim or "nil"),
        tostring(fields and fields.critical or false),
        tostring(fields and fields.chance or "nil"),
        tostring(fields and fields.multiplier or "nil"),
        tostring(fields and fields.damage or "nil"),
        tostring(fields and fields.category or "nil"),
        tostring(fields and fields.inflictor or "nil"),
        tostring(fields and fields.style or "nil")
    ))
end

local function combat_snapshot(player_id)
    local result = event_bus.request(
        events.HERO_COMBAT_STATS_GET_REQUEST,
        { player_id = player_id }
    )
    return result and result.snapshot or {}
end

function modifier_weapon_stat_projection:IsHidden() return true end
function modifier_weapon_stat_projection:IsPurgable() return false end
function modifier_weapon_stat_projection:RemoveOnDeath() return false end

function modifier_weapon_stat_projection:OnCreated(kv)
    if IsServer() then
        self.player_id = tonumber(kv.player_id)
            or self:GetParent():GetPlayerOwnerID()
        -- hero_combat_stat_service populates this with ForceRefresh after all
        -- hero modifiers exist. Requesting the snapshot during OnCreated would
        -- recurse into recalculate while this modifier is still being created.
        self.server_snapshot = {}
        self:SetHasCustomTransmitterData(true)
    end
end

function modifier_weapon_stat_projection:OnRefresh()
    if IsServer() then
        self.server_snapshot = combat_snapshot(self.player_id)
        if self.SendBuffRefreshToClients then
            self:SendBuffRefreshToClients()
        end
    end
end

function modifier_weapon_stat_projection:DeclareFunctions()
    return {
        MODIFIER_PROPERTY_PREATTACK_BONUS_DAMAGE,
        MODIFIER_PROPERTY_BASE_ATTACK_TIME_CONSTANT,
        MODIFIER_PROPERTY_DAMAGEOUTGOING_PERCENTAGE,
        MODIFIER_EVENT_ON_ATTACK_RECORD,
        MODIFIER_EVENT_ON_TAKEDAMAGE,
    }
end

local function snapshot(self)
    if IsServer() then return self.server_snapshot or {} end
    return self.client_snapshot or {}
end

local function record_key(attacker, record)
    if not attacker or attacker:IsNull() or record == nil then return nil end
    return tostring(attacker:entindex()) .. ":" .. tostring(record)
end

local function roll_critical_record(record, stats, attacker)
    if not IsServer() or record == nil then return 0 end
    local key = record_key(attacker, record)
    if not key then return 0 end
    displayed_damage_records[key] = nil
    local chance = math.max(0, math.min(100,
        tonumber(stats and stats.critical_chance_pct) or 0))
    local multiplier = math.max(100,
        tonumber(stats and stats.critical_damage_pct) or 200)
    local critical = chance > 0 and RandomFloat(0, 100) < chance
    critical_records[key] = critical and multiplier or false
    diagnose_damage_number("roll", {
        record = record,
        attacker = attacker and attacker:entindex() or nil,
        critical = critical,
        chance = chance,
        multiplier = multiplier,
    })
    return critical and multiplier or 0
end

function modifier_weapon_stat_projection:OnAttackRecord(params)
    if not IsServer() or not params
        or params.attacker ~= self:GetParent() then return end
    self.active_attack_multiplier = roll_critical_record(
        params.record, snapshot(self), self:GetParent()
    )
    self.active_attack_record = params.record
end

function modifier_weapon_stat_projection:GetModifierDamageOutgoing_Percentage()
    local multiplier = tonumber(self.active_attack_multiplier) or 0
    self.active_attack_multiplier = nil
    self.active_attack_record = nil
    return multiplier > 0 and multiplier - 100 or 0
end

function modifier_weapon_stat_projection.RollCriticalAttackRecord(
        record, stats, attacker)
    return roll_critical_record(record, stats or {}, attacker)
end

function modifier_weapon_stat_projection.ClearCriticalAttackRecord(attacker, record)
    local key = record_key(attacker, record)
    if key then
        local value = critical_records[key]
        diagnose_damage_number("clear", {
            record = record,
            attacker = attacker:entindex(),
            critical = value ~= nil and value ~= false,
            multiplier = value,
        })
        critical_records[key] = nil
        displayed_damage_records[key] = nil
    end
end

function modifier_weapon_stat_projection.PeekCriticalAttackRecord(attacker, record)
    local key = record_key(attacker, record)
    if not key then return false, 1 end
    local value = critical_records[key]
    if value == nil or value == false then return false, 1 end
    return true, (tonumber(value) or 100) / 100
end

function modifier_weapon_stat_projection.ShowFinalAttackDamage(
        player_id, attacker, victim, params)
    if not IsServer() or not attacker or attacker:IsNull()
        or not victim or victim:IsNull() or not params then return false end
    local damage = math.max(0, tonumber(params.damage) or 0)
    local record = params.record
    local category = tonumber(params.damage_category)
    if damage <= 0 or record == nil or params.inflictor ~= nil
        or (category ~= nil and DOTA_DAMAGE_CATEGORY_ATTACK ~= nil
            and category ~= DOTA_DAMAGE_CATEGORY_ATTACK) then return false end
    local key = record_key(attacker, record)
    if not key then return false end
    local victim_key = tostring(victim:entindex())
    displayed_damage_records[key] = displayed_damage_records[key] or {}
    if displayed_damage_records[key][victim_key] then
        diagnose_damage_number("dedup", {
            record = record,
            attacker = attacker:entindex(),
            victim = victim:entindex(),
            damage = damage,
            category = category,
        })
        return false
    end
    displayed_damage_records[key][victim_key] = true
    local state = critical_records[key]
    local critical = state ~= nil and state ~= false
    local player = player_id ~= nil and player_id >= 0
        and PlayerResource:GetPlayer(player_id) or nil
    local rounded_damage = math.max(1, math.floor(damage + 0.5))
    local style = critical and OVERHEAD_ALERT_CRITICAL
        or OVERHEAD_ALERT_BONUS_SPELL_DAMAGE
    diagnose_damage_number("show", {
        record = record,
        attacker = attacker:entindex(),
        victim = victim:entindex(),
        critical = critical,
        multiplier = state,
        damage = damage,
        category = category,
        inflictor = params.inflictor,
        style = style,
    })
    local secondary = modifier_weapon_attack_tracker
        and modifier_weapon_attack_tracker.IsSecondaryAttackRecord
        and modifier_weapon_attack_tracker.IsSecondaryAttackRecord(record)
    if critical and not secondary then
        event_bus.emit(events.HERO_FINAL_CRITICAL_ATTACK_DAMAGE, {
            player_id = player_id,
            attacker = attacker,
            target = victim,
            record = record,
            final_damage = damage,
            critical = true,
            is_main_attack = true,
        })
    end
    SendOverheadEventMessage(player, style, victim, rounded_damage, nil)
    return true
end

function modifier_weapon_stat_projection.ShowFinalAbilityDamage(
        player_id, attacker, victim, params)
    if not IsServer() or not attacker or attacker:IsNull()
        or not victim or victim:IsNull() or not params then return false end
    local ability = params.inflictor
    local damage = math.max(0, tonumber(params.damage) or 0)
    if damage <= 0 or not ability or ability:IsNull() then return false end
    local player = player_id ~= nil and player_id >= 0
        and PlayerResource:GetPlayer(player_id) or nil
    SendOverheadEventMessage(
        player,
        OVERHEAD_ALERT_DAMAGE,
        victim,
        math.max(1, math.floor(damage + 0.5)),
        nil
    )
    return true
end

function modifier_weapon_stat_projection:AddCustomTransmitterData()
    local current = snapshot(self)
    return {
        base_attack_time = tonumber(current.base_attack_time) or 0,
        engine_weapon_attack_bonus =
            tonumber(current.engine_weapon_attack_bonus) or 0,
        engine_research_attack_bonus =
            tonumber(current.engine_research_attack_bonus) or 0,
    }
end

function modifier_weapon_stat_projection:HandleCustomTransmitterData(data)
    self.client_snapshot = data or {}
end

function modifier_weapon_stat_projection:GetModifierBaseAttackTimeConstant()
    local stats = snapshot(self)
    local value = tonumber(stats.base_attack_time)
    return value and math.max(0.1, value) or nil
end

function modifier_weapon_stat_projection:GetModifierPreAttack_BonusDamage()
    local stats = snapshot(self)
    return (tonumber(stats.engine_weapon_attack_bonus) or 0)
        + (tonumber(stats.engine_research_attack_bonus) or 0)
end

function modifier_weapon_stat_projection:OnTakeDamage(params)
    if not IsServer() then return end
    local attacker = params.attacker
    local victim = params.unit
    if not attacker or attacker:IsNull() or not victim or victim:IsNull()
        or attacker:GetTeamNumber() ~= self:GetParent():GetTeamNumber()
        or victim:GetTeamNumber() == self:GetParent():GetTeamNumber()
        or (tonumber(params.damage) or 0) <= 0 then return end
    if attacker == self:GetParent() then
        modifier_weapon_stat_projection.ShowFinalAttackDamage(
            self.player_id, attacker, victim, params
        )
        modifier_weapon_stat_projection.ShowFinalAbilityDamage(
            self.player_id, attacker, victim, params
        )
    end
    local ability = params.inflictor
    event_bus.emit(events.COMBAT_DAMAGE_RESOLVED, {
        player_id = self.player_id,
        attacker_entindex = attacker:entindex(),
        victim_entindex = victim:entindex(),
        damage_kind = ability and not ability:IsNull() and "ability" or "attack",
        damage_type = tonumber(params.damage_type) or DAMAGE_TYPE_PHYSICAL,
        final_damage = tonumber(params.damage) or 0,
        victim_armor = victim.GetPhysicalArmorValue
            and victim:GetPhysicalArmorValue(false) or 0,
        ability_name = ability and not ability:IsNull()
            and ability:GetAbilityName() or "",
        target = victim,
        damage_category = tonumber(params.damage_category),
    })
end
