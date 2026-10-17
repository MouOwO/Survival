local event_bus = require("core/event_bus")
local events = require("core/events")
local hero_health_guard = require("core/hero_health_guard")
local armor_balance = require("config/armor_balance")

local M = {}
modifier_equipment_effects = _G.modifier_equipment_effects or class({})
_G.modifier_equipment_effects = modifier_equipment_effects

local function decide_damage_route(self, phase)
    -- Production/client/class queries leave the original five declarations and
    -- add no experiment fields. Tools legacy instances never migrate on refresh.
    if self == modifier_equipment_effects or not self.GetParent
        or not IsServer() or not IsInToolsMode or not IsInToolsMode()
        or self.equipment_damage_mode_decided then return end
    self.equipment_damage_mode_decided = true
    self.shared_equipment_damage_observer = false
    self.equipment_damage_route_reason = "legacy_or_probe_disabled"
    if phase ~= "declare" or self.server_values ~= nil or self.player_id ~= nil
        or _G.SURVIVAL_SHARED_HERO_EQUIPMENT_DAMAGE_PROBE ~= true then return end
    local ok, registration, reason = pcall(function()
        return require("systems/hero_equipment_damage_observer").register_new(self:GetParent(), self)
    end)
    self.shared_equipment_damage_observer = ok and type(registration) == "table"
        and self.equipment_damage_registration == registration and registration.modifier == self
        and registration.token ~= nil and self.equipment_damage_registration_token == registration.token
    self.equipment_damage_route_reason = self.shared_equipment_damage_observer
        and "shared_registered_at_first_declare" or (ok and (reason or "registration_commit_unconfirmed") or "registration_exception")
end

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
        decide_damage_route(self, "created")
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
        decide_damage_route(self, "refresh")
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
                        -- Native filter keys can omit both category and ability.
                        -- This transaction preserves the aura's logical damage
                        -- independently of the hero's native attack projection.
                        require("combat/damage_service"):Deal({
                            victim = victim, attacker = parent, base_damage = damage,
                            source_kind = "item", damage_type = DAMAGE_TYPE_MAGICAL,
                        })
                    end
                end
            end
        end
    end
end

function modifier_equipment_effects:DeclareFunctions()
    decide_damage_route(self, "declare")
    local declarations = {
        MODIFIER_PROPERTY_PREATTACK_BONUS_DAMAGE,
        MODIFIER_PROPERTY_ATTACKSPEED_BONUS_CONSTANT,
        MODIFIER_PROPERTY_HEALTH_BONUS,
        MODIFIER_PROPERTY_PHYSICAL_ARMOR_BONUS,
    }
    if not (IsServer() and self.shared_equipment_damage_observer == true) then
        declarations[#declarations + 1] = MODIFIER_EVENT_ON_TAKEDAMAGE
    end
    return declarations
end

local function values(self)
    if IsServer() then return self.server_values or {} end
    return self.client_values or {}
end

function modifier_equipment_effects:AddCustomTransmitterData()
    local current = values(self)
    return {
        attack_flat = tonumber(current.attack_flat) or 0,
        native_attack_flat = (tonumber(current.attack_flat) or 0)
            / math.max(1, tonumber(self:GetParent().survival_endless_attack_scale) or 1),
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
    local current = values(self)
    if IsServer() then
        return (tonumber(current.attack_flat) or 0)
            / math.max(1, tonumber(self:GetParent().survival_endless_attack_scale) or 1)
    end
    return tonumber(current.native_attack_flat) or tonumber(current.attack_flat) or 0
end
function modifier_equipment_effects:GetModifierAttackSpeedBonus_Constant()
    return tonumber(values(self).attack_speed_pct) or 0
end
function modifier_equipment_effects:GetModifierHealthBonus()
    return tonumber(values(self).health_flat) or 0
end
function modifier_equipment_effects:GetModifierPhysicalArmorBonus()
    return armor_balance.from_war3(values(self).armor_flat)
end
function modifier_equipment_effects:HandleTakeDamage(params)
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
    local amount = require("combat/lifesteal_amount").calculate(
        params.attacker, victim, params.damage, percent)
    if amount > 0 and self:GetParent().Heal then
        -- Invalidate deferred CalculateStatBonus health rollbacks before this
        -- legitimate heal. Otherwise a full lifesteal heal can be mistaken for
        -- an engine refill and restored to the old damaged value 0.12s later.
        hero_health_guard.allow_healing(self:GetParent())
        self:GetParent():Heal(amount, nil)
    end
end

function modifier_equipment_effects:OnTakeDamage(params)
    if self.shared_equipment_damage_observer == true then return end
    return self:HandleTakeDamage(params)
end

function modifier_equipment_effects:OnDestroy()
    if not IsServer() or not self.equipment_damage_registration then return end
    self.equipment_damage_destroyed = true
    local observer = package.loaded["systems/hero_equipment_damage_observer"]
    if observer and type(observer.unregister) == "function" then observer.unregister(self) end
end

return M
