LinkLuaModifier("modifier_equipment_effects", "modifiers/modifier_equipment_effects", LUA_MODIFIER_MOTION_NONE)

local event_bus = require("core/event_bus")
local events = require("core/events")

local M = {}
modifier_equipment_effects = class({})

local function equipment_values(player_id)
    local response = event_bus.request(events.EQUIPMENT_STATS_GET_REQUEST,
        { player_id = player_id })
    local current = response and response.snapshot
        and response.snapshot.values or {}
    return {
        attack_flat = tonumber(current.attack_flat) or 0,
        attack_speed_pct = tonumber(current.attack_speed_pct) or 0,
        health_flat = tonumber(current.health_flat) or 0,
        armor_flat = tonumber(current.armor_flat) or 0,
        lifesteal_pct = tonumber(current.lifesteal_pct) or 0,
    }
end

function modifier_equipment_effects:IsHidden() return true end
function modifier_equipment_effects:IsPurgable() return false end
function modifier_equipment_effects:RemoveOnDeath() return false end

function modifier_equipment_effects:OnCreated(kv)
    if IsServer() then
        self.player_id = tonumber(kv.player_id) or self:GetParent():GetPlayerOwnerID()
        self.aura_ready = {}
        self.server_values = equipment_values(self.player_id)
        self:SetHasCustomTransmitterData(true)
        if self.SendBuffRefreshToClients then
            self:SendBuffRefreshToClients()
        end
        self:StartIntervalThink(0.25)
    end
end

function modifier_equipment_effects:OnRefresh()
    if IsServer() then
        self.server_values = equipment_values(self.player_id)
        if self.SendBuffRefreshToClients then
            self:SendBuffRefreshToClients()
        end
    end
end

local function game_time()
    if GameRules and GameRules.GetGameTime then return GameRules:GetGameTime() end
    return 0
end

local function attributes(player_id)
    local response = event_bus.request(
        events.HERO_COMBAT_STATS_GET_REQUEST,
        { player_id = player_id }
    )
    local stats = response and response.snapshot or {}
    return (tonumber(stats.strength) or 0)
        + (tonumber(stats.agility) or 0)
        + (tonumber(stats.intellect) or 0)
end

function modifier_equipment_effects:OnIntervalThink()
    local parent = self:GetParent()
    if not parent or parent:IsNull() or not parent:IsAlive()
        or not FindUnitsInRadius or not ApplyDamage then return end
    local response = event_bus.request(events.EQUIPMENT_EFFECT_SNAPSHOT_GET_REQUEST,
        { player_id = self.player_id })
    local snapshot = response and response.snapshot
    if not snapshot or snapshot.enabled == false then return end
    for _, source in ipairs(snapshot.sources or {}) do
        for index, effect in ipairs(source.effects or {}) do
            if effect.effect_type == "aura_attribute_damage" then
                local value = effect.value
                local key = tostring(source.source_id) .. ":" .. tostring(index)
                if game_time() >= (self.aura_ready[key] or 0) then
                    local cooldown = tonumber(value.internal_cooldown
                        or value.interval) or 1
                    self.aura_ready[key] = game_time() + math.max(0.03, cooldown)
                    local victims = FindUnitsInRadius(parent:GetTeamNumber(),
                        parent:GetAbsOrigin(), nil, tonumber(value.range or value.radius),
                        DOTA_UNIT_TARGET_TEAM_ENEMY,
                        DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC,
                        DOTA_UNIT_TARGET_FLAG_NONE, FIND_ANY_ORDER, false) or {}
                    local damage = attributes(self.player_id)
                        * (tonumber(value.multiplier) or 0)
                    for _, victim in ipairs(victims) do
                        -- DAMAGE_MODULE_MIGRATION: legacy aura damage remains for compatibility;
                        -- migrate after validating interval/aura transaction semantics.
                        ApplyDamage({ victim = victim, attacker = parent, damage = damage,
                            damage_type = DAMAGE_TYPE_MAGICAL, ability = nil })
                    end
                end
            end
        end
    end
end

function modifier_equipment_effects:DeclareFunctions()
    return {
        MODIFIER_PROPERTY_PREATTACK_BONUS_DAMAGE,
        MODIFIER_PROPERTY_ATTACKSPEED_BONUS_CONSTANT,
        MODIFIER_PROPERTY_HEALTH_BONUS,
        MODIFIER_PROPERTY_PHYSICAL_ARMOR_BONUS,
        MODIFIER_EVENT_ON_TAKEDAMAGE,
    }
end

local function values(self)
    if IsServer() then return self.server_values or {} end
    return self.client_values or {}
end

function modifier_equipment_effects:AddCustomTransmitterData()
    local current = values(self)
    return {
        attack_flat = tonumber(current.attack_flat) or 0,
        attack_speed_pct = tonumber(current.attack_speed_pct) or 0,
        health_flat = tonumber(current.health_flat) or 0,
        armor_flat = tonumber(current.armor_flat) or 0,
        lifesteal_pct = tonumber(current.lifesteal_pct) or 0,
    }
end

function modifier_equipment_effects:HandleCustomTransmitterData(data)
    self.client_values = data or {}
end

function modifier_equipment_effects:GetModifierPreAttack_BonusDamage()
    return tonumber(values(self).attack_flat) or 0
end
function modifier_equipment_effects:GetModifierAttackSpeedBonus_Constant()
    return tonumber(values(self).attack_speed_pct) or 0
end
function modifier_equipment_effects:GetModifierHealthBonus()
    return tonumber(values(self).health_flat) or 0
end
function modifier_equipment_effects:GetModifierPhysicalArmorBonus()
    return tonumber(values(self).armor_flat) or 0
end
function modifier_equipment_effects:OnTakeDamage(params)
    if not IsServer() or params.attacker ~= self:GetParent() then return end
    local victim = params.unit
    if not victim or victim:IsNull() or victim:GetTeamNumber() == params.attacker:GetTeamNumber() then return end
    -- Only real basic-attack damage may trigger equipment lifesteal. The
    -- equipment aura also uses ApplyDamage with ability=nil, so checking only
    -- inflictor would incorrectly turn its first proximity tick into a large
    -- (often 20000+) heal before the monster's next attack lands.
    if tonumber(params.damage_category) ~= DOTA_DAMAGE_CATEGORY_ATTACK then return end
    local percent = tonumber(values(self).lifesteal_pct) or 0
    -- OnTakeDamage.damage is post-mitigation basic-attack damage here.
    local amount = math.max(0, tonumber(params.damage) or 0) * percent / 100
    if amount > 0 and self:GetParent().Heal then self:GetParent():Heal(amount, nil) end
end

return M
