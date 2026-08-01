modifier_hero_poison_cloud_armor = class({})

local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")

local ARMOR_EPSILON = 0.0001

local function publish_armor_changed(modifier, reason, stacks, reduction)
    if not IsServer() then return end
    local parent = modifier:GetParent()
    if not parent or parent:IsNull() then return end
    local entindex = parent:entindex()
    scheduler.after(0, function()
        if not parent or parent:IsNull() then return end
        event_bus.emit(events.UNIT_COMBAT_STATS_CHANGED, {
            entindex = entindex,
            unit = parent,
            reason = reason,
            poison_cloud_stacks = stacks or 0,
            poison_cloud_armor_reduction = math.max(0,
                tonumber(reduction) or tonumber(modifier.armor_reduction) or 0),
        })
    end)
end

function modifier_hero_poison_cloud_armor:IsHidden() return false end
function modifier_hero_poison_cloud_armor:IsDebuff() return true end
function modifier_hero_poison_cloud_armor:IsPurgable() return false end
function modifier_hero_poison_cloud_armor:RemoveOnDeath() return true end
function modifier_hero_poison_cloud_armor:GetTexture() return "viper_nethertoxin" end

function modifier_hero_poison_cloud_armor:OnCreated(params)
    self:SetPoisonValues(params)
end

function modifier_hero_poison_cloud_armor:OnRefresh(params)
    self:SetPoisonValues(params)
end

function modifier_hero_poison_cloud_armor:SetPoisonValues(params)
    params = params or {}
    local previous_pct = tonumber(self.armor_per_stack_pct)
    local previous_stacks = tonumber(self:GetStackCount()) or 0
    local previous_reduction = math.max(0, tonumber(self.armor_reduction) or 0)
    local next_pct = math.max(
        0,
        tonumber(params.armor_per_stack_pct) or self.armor_per_stack_pct or 20
    )
    self.armor_per_stack_pct = next_pct
    self:SetPoisonStacks(params.poison_stacks or self:GetStackCount())
    local next_stacks = tonumber(self:GetStackCount()) or 0
    local parent = self:GetParent()
    local current_armor = parent and not parent:IsNull()
        and tonumber(parent:GetPhysicalArmorValue(false)) or 0
    -- GetPhysicalArmorValue already contains this modifier's previous flat
    -- reduction. Add it back before calculating the new percentage so every
    -- sync follows current equipment, technology and all other modifiers.
    local armor_without_poison = current_armor + previous_reduction
    local reduction_pct = math.min(100, next_pct * next_stacks) / 100
    local next_reduction = math.abs(armor_without_poison) * reduction_pct
    self.armor_reduction = next_reduction
    if previous_pct ~= next_pct or previous_stacks ~= next_stacks
        or math.abs(previous_reduction - next_reduction) > ARMOR_EPSILON then
        publish_armor_changed(self, "poison_cloud_armor_changed", next_stacks)
    end
end

function modifier_hero_poison_cloud_armor:SetPoisonStacks(stacks)
    if not IsServer() then return end
    self:SetStackCount(math.max(1, math.min(3, math.floor(
        (tonumber(stacks) or 1) + 0.001
    ))))
end

function modifier_hero_poison_cloud_armor:DeclareFunctions()
    return { MODIFIER_PROPERTY_PHYSICAL_ARMOR_BONUS }
end

function modifier_hero_poison_cloud_armor:GetModifierPhysicalArmorBonus()
    return -math.max(0, tonumber(self.armor_reduction) or 0)
end

function modifier_hero_poison_cloud_armor:OnDestroy()
    publish_armor_changed(self, "poison_cloud_armor_removed", 0, 0)
end

_G.modifier_hero_poison_cloud_armor = modifier_hero_poison_cloud_armor
return modifier_hero_poison_cloud_armor