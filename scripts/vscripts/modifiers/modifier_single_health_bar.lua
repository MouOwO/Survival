if LinkLuaModifier then
    LinkLuaModifier("modifier_single_health_bar", "modifiers/modifier_single_health_bar", LUA_MODIFIER_MOTION_NONE)
end
modifier_single_health_bar = class({})
_G.modifier_single_health_bar = modifier_single_health_bar

function modifier_single_health_bar:IsHidden() return true end
function modifier_single_health_bar:IsPurgable() return false end
function modifier_single_health_bar:RemoveOnDeath() return false end
function modifier_single_health_bar:GetAttributes()
    return MODIFIER_ATTRIBUTE_PERMANENT
end

local TABLE = "survival_hero_health_bar"

local function publish(unit, value)
    if not CustomNetTables
        or type(CustomNetTables.SetTableValue) ~= "function"
        or not unit or not unit.entindex then
        return
    end
    CustomNetTables:SetTableValue(
        TABLE,
        "unit_" .. tostring(unit:entindex()),
        value
    )
end

function modifier_single_health_bar:OnCreated()
    self:publish_state()
    self:StartIntervalThink(0.1)
end

function modifier_single_health_bar:OnIntervalThink()
    self:publish_state()
end

function modifier_single_health_bar:publish_state()
    local unit = self:GetParent()
    if not unit or (unit.IsNull and unit:IsNull())
        or not unit.entindex
        or not unit.GetHealth
        or not unit.GetMaxHealth
        or not unit.IsAlive
        or not unit.GetTeamNumber then
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
    })
end

function modifier_single_health_bar:OnDestroy()
    local unit = self:GetParent()
    if unit and (not unit.IsNull or not unit:IsNull()) then
        publish(unit, { removed = 1 })
    end
end

function modifier_single_health_bar:CheckState()
    local states = {}
    if MODIFIER_STATE_NO_HEALTH_BAR ~= nil then
        states[MODIFIER_STATE_NO_HEALTH_BAR] = true
    end
    return states
end

return modifier_single_health_bar
