-- Linked directly by the registry in both engine VMs.
modifier_single_health_bar = _G.modifier_single_health_bar or class({})
_G.modifier_single_health_bar = modifier_single_health_bar

function modifier_single_health_bar:IsHidden() return true end
function modifier_single_health_bar:IsPurgable() return false end
function modifier_single_health_bar:RemoveOnDeath() return false end
function modifier_single_health_bar:GetAttributes()
    return MODIFIER_ATTRIBUTE_PERMANENT
end

local TABLE = "survival_hero_health_bar"

local function publish(unit, value, cached_entindex)
    if not CustomNetTables
        or type(CustomNetTables.SetTableValue) ~= "function"
        or (not cached_entindex and (not unit or not unit.entindex)) then
        return false
    end
    CustomNetTables:SetTableValue(
        TABLE,
        "unit_" .. tostring(cached_entindex or unit:entindex()),
        value
    )
    return true
end

local function publish_removed(self, unit)
    if self.health_bar_published_removed then return end
    if publish(unit, { removed = 1 }, self.health_bar_entindex) then
        self.health_bar_last_sample = nil
        self.health_bar_published_removed = true
    end
end

function modifier_single_health_bar:OnCreated()
    if not IsServer() then return end
    self.health_bar_entindex = self:GetParent():entindex()
    self.health_bar_last_sample = nil
    self.health_bar_published_removed = false
    self:publish_state()
    -- Keep the existing reaction time without subscribing every visible NPC
    -- to global damage/attack events. Stable samples produce no network writes.
    self:StartIntervalThink(0.1)
end

function modifier_single_health_bar:OnIntervalThink()
    self:publish_state()
end

function modifier_single_health_bar:publish_state()
    if not IsServer() then return end
    local unit = self:GetParent()
    if not unit or (unit.IsNull and unit:IsNull())
        or not unit.entindex
        or not unit.GetHealth
        or not unit.GetMaxHealth
        or not unit.IsAlive
        or not unit.GetTeamNumber then
        publish_removed(self, nil)
        return
    end
    if unit.survival_hide_custom_health_bar
        or unit.survival_is_native_wearable_visual
        or (unit.HasModifier and unit:HasModifier("modifier_native_wearable_visual_carrier"))
        or (unit.IsNoDraw and unit:IsNoDraw())
        or (unit.GetClassname and unit:GetClassname() == "npc_dota_thinker") then
        publish_removed(self, unit)
        return
    end

    local health = math.max(0, unit:GetHealth())
    local max_health = math.max(1, unit:GetMaxHealth())
    local scale = tonumber(unit.survival_endless_health_scale)
    local alive = unit:IsAlive() and 1 or 0
    local team = unit:GetTeamNumber()
    local unit_name = unit.GetUnitName and unit:GetUnitName() or nil
    local previous = self.health_bar_last_sample
    if previous and previous.health == health and previous.max_health == max_health
        and previous.scale == scale and previous.alive == alive
        and previous.team == team and previous.unit_name == unit_name then
        return
    end

    local projection = require("combat/endless_stat_projection")
    local sent = publish(unit, {
        entindex = unit:entindex(),
        health = projection.for_ui(unit, health, "health"),
        max_health = projection.for_ui(unit, max_health, "health"),
        health_scale = string.format("%.17g", scale or 1),
        alive = alive,
        team = team,
        unit_name = unit_name,
    })
    if sent then
        self.health_bar_last_sample = { health = health, max_health = max_health,
            scale = scale, alive = alive, team = team, unit_name = unit_name }
        self.health_bar_published_removed = false
    end
end

function modifier_single_health_bar:OnDestroy()
    if not IsServer() then return end
    -- The parent may already be invalid when RemoveSelf/ReplaceHeroWith destroys it.
    publish_removed(self, nil)
end

function modifier_single_health_bar:CheckState()
    local states = {}
    if MODIFIER_STATE_NO_HEALTH_BAR ~= nil then
        states[MODIFIER_STATE_NO_HEALTH_BAR] = true
    end
    return states
end

return modifier_single_health_bar
