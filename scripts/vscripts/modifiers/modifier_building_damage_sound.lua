if LinkLuaModifier then
    LinkLuaModifier(
        "modifier_building_damage_sound",
        "modifiers/modifier_building_damage_sound",
        LUA_MODIFIER_MOTION_NONE
    )
end

modifier_building_damage_sound = class({})
_G.modifier_building_damage_sound = modifier_building_damage_sound
local M = modifier_building_damage_sound
local building_sound = require("systems/building_sound_service")

function M:IsHidden() return true end
function M:IsPurgable() return false end
function M:GetAttributes() return MODIFIER_ATTRIBUTE_PERMANENT end

function M:DeclareFunctions()
    return { MODIFIER_EVENT_ON_TAKEDAMAGE }
end

function M:OnTakeDamage(params)
    if not IsServer() then return end
    local wall = self:GetParent()
    if params.unit ~= wall or (tonumber(params.damage) or 0) <= 0 then return end
    building_sound.wall_damaged(wall)
end

return M
