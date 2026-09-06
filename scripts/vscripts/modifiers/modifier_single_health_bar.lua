-- Linked through modifier_bindings by the registry; do not relink a cached module.
modifier_single_health_bar = class({})
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
        return
    end
    CustomNetTables:SetTableValue(
        TABLE,
        "unit_" .. tostring(cached_entindex or unit:entindex()),
        value
    )
end

function modifier_single_health_bar:OnCreated()
    if not IsServer() then return end
    self.health_bar_entindex = self:GetParent():entindex()
    self:publish_state()
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
        publish(nil, { removed = 1 }, self.health_bar_entindex)
        return
    end
    if unit.survival_hide_custom_health_bar
        or (unit.IsNoDraw and unit:IsNoDraw())
        or (unit.GetClassname and unit:GetClassname() == "npc_dota_thinker") then
        publish(unit, { removed = 1 })
        return
    end
    local projection = require("combat/endless_stat_projection")
    publish(unit, {
        entindex = unit:entindex(),
        health = projection.for_ui(unit, math.max(0, unit:GetHealth()), "health"),
        max_health = projection.for_ui(unit, math.max(1, unit:GetMaxHealth()), "health"),
        health_scale = string.format("%.17g", tonumber(unit.survival_endless_health_scale) or 1),
        alive = unit:IsAlive() and 1 or 0,
        team = unit:GetTeamNumber(),
        unit_name = unit.GetUnitName and unit:GetUnitName() or nil,
    })
end

function modifier_single_health_bar:OnDestroy()
    if not IsServer() then return end
    -- The parent may already be invalid when RemoveSelf/ReplaceHeroWith destroys it.
    publish(nil, { removed = 1 }, self.health_bar_entindex)
end

function modifier_single_health_bar:CheckState()
    local states = {}
    if MODIFIER_STATE_NO_HEALTH_BAR ~= nil then
        states[MODIFIER_STATE_NO_HEALTH_BAR] = true
    end
    return states
end

return modifier_single_health_bar
