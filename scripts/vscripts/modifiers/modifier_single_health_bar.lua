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

function modifier_single_health_bar:CheckState()
    -- Keep this modifier as a compatibility marker, but let the engine render
    -- its native overhead health bars. This also removes the old 10 Hz
    -- CustomNetTable publishing path used by the Panorama world-bar overlay.
    return {}
end

return modifier_single_health_bar