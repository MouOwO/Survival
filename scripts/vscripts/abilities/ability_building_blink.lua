-- Use an explicit global class name. Dota's ability_lua loader resolves the
-- ScriptFile class by the KV ability name, not only by the returned module.
ability_building_blink = class({})
local M = ability_building_blink
_G.ability_building_blink = M
print("[BuildingBlink] ability class loaded name=ability_building_blink")

local relocation = require("systems/tower_relocation_service")

local function owner(caster)
    return tonumber(caster.survival_player_id) or caster:GetPlayerOwnerID()
end

function M:OnAbilityPhaseStart()
    if IsServer() then
        print("[BuildingBlink] OnAbilityPhaseStart caster=" .. tostring(self:GetCaster():entindex()))
    end
    return true
end

function M:OnAbilityPhaseInterrupted()
    if IsServer() then
        print("[BuildingBlink] OnAbilityPhaseInterrupted caster=" .. tostring(self:GetCaster():entindex()))
    end
end

function M:CastFilterResultLocation(location)
    if IsServer() then print("[BuildingBlink] CastFilterResultLocation ability=" .. tostring(self:GetAbilityName())) end
    if not IsServer() then return UF_SUCCESS end
    local caster = self:GetCaster()
    local result = relocation.validate(owner(caster), caster:entindex(), location, self:entindex())
    self.cast_error = result.error
    return result.ok and UF_SUCCESS or UF_FAIL_CUSTOM
end

function M:GetCustomCastErrorLocation()
    if self.cast_error == "relocation_out_of_range" then return "移动距离不能超过1000" end
    if self.cast_error == "move_ability_cooldown" then return "移动防御塔CD中" end
    return "请选择网格内可放置的位置"
end

function M:OnSpellStart()
    if not IsServer() then return end
    local caster = self:GetCaster()
    -- The engine has started the native cooldown before OnSpellStart.
    local result = relocation.move(owner(caster), caster:entindex(),
        self:GetCursorPosition(), self:entindex(), true)
    if not result.ok then self:EndCooldown() end
end

return M
