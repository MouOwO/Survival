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
    return { MODIFIER_EVENT_ON_TAKEDAMAGE, MODIFIER_EVENT_ON_ATTACK_LANDED }
end

function M:OnAttackLanded(params)
    if not IsServer() or params.target ~= self:GetParent() then return end
    require("systems/wall_hit_effect").play(self:GetParent(),params.attacker)
end

function M:OnTakeDamage(params)
    if not IsServer() then return end
    local wall = self:GetParent()
    if params.unit ~= wall or (tonumber(params.damage) or 0) <= 0 then return end
    building_sound.wall_damaged(wall)
    local wakeup = package.loaded["systems/repair_worker_wakeup"]
    if wakeup then wakeup.wall_damaged(wall) end
end

return M
