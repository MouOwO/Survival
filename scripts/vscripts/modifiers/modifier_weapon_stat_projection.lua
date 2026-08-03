LinkLuaModifier("modifier_weapon_stat_projection", "modifiers/modifier_weapon_stat_projection", LUA_MODIFIER_MOTION_NONE)

local event_bus = require("core/event_bus")
local events = require("core/events")

modifier_weapon_stat_projection = class({})

local critical_records = {}

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
        MODIFIER_PROPERTY_PREATTACK_CRITICALSTRIKE,
        MODIFIER_EVENT_ON_TAKEDAMAGE,
    }
end

local function snapshot(self)
    if IsServer() then return self.server_snapshot or {} end
    return self.client_snapshot or {}
end

function modifier_weapon_stat_projection:GetModifierPreAttack_CriticalStrike(params)
    if not IsServer() then return 0 end
    local stats = snapshot(self)
    local chance = math.max(0, math.min(100,
        tonumber(stats.critical_chance_pct) or 0))
    local multiplier = math.max(100,
        tonumber(stats.critical_damage_pct) or 200)
    local record = params and params.record
    local recorded = record ~= nil and critical_records[tostring(record)] or nil
    if recorded ~= nil then
        return recorded == false and 0 or tonumber(recorded) or 0
    end
    local critical = chance > 0 and RandomFloat(0, 100) < chance
    if record ~= nil then
        critical_records[tostring(record)] = critical and multiplier or false
    end
    return critical and multiplier or 0
end

function modifier_weapon_stat_projection.ClearCriticalAttackRecord(record)
    if record ~= nil then critical_records[tostring(record)] = nil end
end

function modifier_weapon_stat_projection.ConsumeCriticalAttackRecord(record)
    if record == nil then return false, 1 end
    local key = tostring(record)
    local value = critical_records[key]
    critical_records[key] = nil
    if value == nil or value == false then return false, 1 end
    return true, (tonumber(value) or 100) / 100
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
