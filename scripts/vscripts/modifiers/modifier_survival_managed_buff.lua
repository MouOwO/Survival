modifier_survival_managed_buff = class({})
modifier_survival_managed_aura = class({})

local definitions = require("config/generated/buff_definitions")
local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")

local function now()
    return GameRules:GetGameTime()
end

local function definition(buff_id)
    return (definitions.by_id or {})[buff_id]
end

local function affects_combat_stats_ui(modifier)
    local effect_type = modifier.definition and modifier.definition.effect_type
    return effect_type == "attack_speed_bonus"
        or effect_type == "attack_speed_pct"
        or effect_type == "machine_gun_interval_pct"
        or effect_type == "base_damage_outgoing_pct"
end

local function publish_combat_stats_changed(modifier, reason, deferred)
    if not affects_combat_stats_ui(modifier) then return end
    local parent = modifier:GetParent()
    if not parent or parent:IsNull() then return end
    local entindex = parent:entindex()
    local buff_id = modifier.buff_id
    local function publish()
        if not parent or parent:IsNull() then return end
        event_bus.emit(events.UNIT_COMBAT_STATS_CHANGED, {
            entindex = entindex,
            unit = parent,
            reason = reason,
            buff_id = buff_id,
        })
    end
    if deferred then
        scheduler.after(0, publish)
    else
        publish()
    end
end

function modifier_survival_managed_buff:GetAttributes()
    return MODIFIER_ATTRIBUTE_MULTIPLE
end

function modifier_survival_managed_buff:IsHidden() return false end
function modifier_survival_managed_buff:IsDebuff()
    return self.definition and self.definition.polarity == "negative" or false
end
function modifier_survival_managed_buff:IsPurgable()
    return self.definition and self.definition.purgable == true or false
end
function modifier_survival_managed_buff:RemoveOnDeath()
    return not self.definition or self.definition.remove_on_death ~= false
end
function modifier_survival_managed_buff:GetTexture()
    return self.definition and self.definition.texture or ""
end
function modifier_survival_managed_buff:GetEffectName()
    return self.definition and self.definition.particle_name or nil
end
function modifier_survival_managed_buff:GetEffectAttachType()
    if self.definition and self.definition.particle_attach == "PATTACH_OVERHEAD_FOLLOW" then
        return PATTACH_OVERHEAD_FOLLOW
    end
    return PATTACH_ABSORIGIN_FOLLOW
end
function modifier_survival_managed_buff:GetStatusEffectName()
    return self.definition and self.definition.status_effect_name or nil
end
function modifier_survival_managed_buff:StatusEffectPriority()
    return tonumber(self.definition and self.definition.status_effect_priority) or 0
end

function modifier_survival_managed_buff:OnCreated(params)
    self.buff_id = params and params.buff_id or ""
    self.definition = definition(self.buff_id) or {}
    self.value = tonumber(params and params.managed_value)
        or tonumber(self.definition.default_value) or 0
    self.expirations = {}
    if IsServer() then
        local sound_name = self.definition.sound_name
        if sound_name and sound_name ~= "" then
            self.active_sound_name = sound_name
            self:GetParent():EmitSound(sound_name)
        end
        self:ApplyManaged(
            self.value,
            tonumber(params and params.managed_duration) or 0,
            tonumber(params and params.managed_max_stacks)
                or tonumber(self.definition.max_stacks) or 1
        )
        -- 等引擎完成本 Modifier 的属性重算后再读取当前战斗属性。
        publish_combat_stats_changed(self, "managed_buff_applied", true)
    end
end

function modifier_survival_managed_buff:OnDestroy()
    if not IsServer() then return end
    local parent = self:GetParent()
    if self.active_sound_name then
        parent:StopSound(self.active_sound_name)
        self.active_sound_name = nil
    end
    publish_combat_stats_changed(self, "managed_buff_removed", true)
end

function modifier_survival_managed_buff:OnRefresh(params)
    if not IsServer() then return end
    self:RefreshManaged(
        tonumber(params and params.managed_value) or self.value,
        tonumber(params and params.managed_duration) or 0,
        tonumber(params and params.managed_max_stacks)
            or tonumber(self.definition.max_stacks) or 1
    )
end

function modifier_survival_managed_buff:RefreshManaged(value, duration, max_stacks)
    if not IsServer() then return end
    self:ApplyManaged(
        value,
        duration,
        max_stacks
    )
    publish_combat_stats_changed(self, "managed_buff_refreshed", true)
end

function modifier_survival_managed_buff:ApplyManaged(value, duration, max_stacks)
    if not IsServer() then return end
    self.value = tonumber(value) or self.value or 0
    duration = math.max(0, tonumber(duration) or 0)
    max_stacks = math.max(1, tonumber(max_stacks) or 1)
    if self.definition.refresh_rule == "independent" then
        local active = {}
        for _, expiry in ipairs(self.expirations or {}) do
            if expiry > now() then active[#active + 1] = expiry end
        end
        if #active < max_stacks then active[#active + 1] = now() + duration end
        self.expirations = active
        self:SetStackCount(#active)
        self:SetDuration(duration, true)
        self:StartIntervalThink(0.1)
    else
        self:SetStackCount(1)
        if duration > 0 then self:SetDuration(duration, true) end
    end
end

function modifier_survival_managed_buff:OnIntervalThink()
    if self.definition.refresh_rule ~= "independent" then return end
    local active = {}
    for _, expiry in ipairs(self.expirations or {}) do
        if expiry > now() then active[#active + 1] = expiry end
    end
    self.expirations = active
    self:SetStackCount(#active)
    if #active == 0 then self:Destroy() end
end

function modifier_survival_managed_buff:DeclareFunctions()
    return {
        MODIFIER_PROPERTY_MOVESPEED_BONUS_PERCENTAGE,
        MODIFIER_PROPERTY_ATTACKSPEED_BONUS_CONSTANT,
        MODIFIER_PROPERTY_ATTACKSPEED_PERCENTAGE,
        MODIFIER_PROPERTY_PHYSICAL_ARMOR_BONUS,
        MODIFIER_PROPERTY_TOTALDAMAGEOUTGOING_PERCENTAGE,
        MODIFIER_PROPERTY_BASEDAMAGEOUTGOING_PERCENTAGE,
    }
end

function modifier_survival_managed_buff:GetModifierMoveSpeedBonus_Percentage()
    return self.definition.effect_type == "move_speed_pct" and self.value or 0
end
function modifier_survival_managed_buff:GetModifierAttackSpeedBonus_Constant()
    return self.definition.effect_type == "attack_speed_bonus" and self.value or 0
end
function modifier_survival_managed_buff:GetModifierAttackSpeedPercentage()
    return self.definition.effect_type == "attack_speed_pct" and self.value or 0
end
function modifier_survival_managed_buff:GetModifierPhysicalArmorBonus()
    if self.definition.effect_type ~= "physical_armor_base_pct" then return 0 end
    local base = math.max(0, self:GetParent():GetPhysicalArmorBaseValue())
    return base * (self.value or 0) * 0.01
end
function modifier_survival_managed_buff:GetModifierTotalDamageOutgoing_Percentage()
    if self.definition.effect_type ~= "total_damage_outgoing_pct" then return 0 end
    return (self.value or 0) * math.max(1, self:GetStackCount())
end

function modifier_survival_managed_buff:GetModifierBaseDamageOutgoing_Percentage()
    if self.definition.effect_type ~= "base_damage_outgoing_pct" then return 0 end
    return self.value or 0
end

function modifier_survival_managed_aura:IsHidden() return true end
function modifier_survival_managed_aura:IsPurgable() return false end
function modifier_survival_managed_aura:RemoveOnDeath() return true end

function modifier_survival_managed_aura:OnCreated(params)
    if not IsServer() then return end
    self:Configure(params and params.buff_id, params and params.radius)
    self:StartIntervalThink(0.2)
end

function modifier_survival_managed_aura:Configure(buff_id, radius)
    self.buff_id = buff_id or self.buff_id
    self.radius = math.max(1, tonumber(radius) or self.radius or 1)
end

function modifier_survival_managed_aura:OnIntervalThink()
    local parent = self:GetParent()
    if not parent or parent:IsNull() or not parent:IsAlive() then return end
    local manager = require("systems/buff_manager")
    local enemies = FindUnitsInRadius(
        parent:GetTeamNumber(), parent:GetAbsOrigin(), nil, self.radius,
        DOTA_UNIT_TARGET_TEAM_ENEMY,
        DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC,
        DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES,
        FIND_ANY_ORDER, false
    ) or {}
    for _, enemy in ipairs(enemies) do
        manager.apply(parent, enemy, self.buff_id, { duration = 0.35 })
    end
end

_G.modifier_survival_managed_buff = modifier_survival_managed_buff
_G.modifier_survival_managed_aura = modifier_survival_managed_aura

return modifier_survival_managed_buff