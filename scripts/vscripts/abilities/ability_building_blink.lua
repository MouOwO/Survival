-- Use an explicit global class name. Dota's ability_lua loader resolves the
-- ScriptFile class by the KV ability name, not only by the returned module.
ability_building_blink = class({})
local M = ability_building_blink
_G.ability_building_blink = M
print("[BuildingBlink] ability class loaded name=ability_building_blink")

local BLINK_RANGE = 1000
local blink_destination = require("systems/blink_destination")
local MAX_HEIGHT_DELTA = 32
local SAMPLE_RADIUS = 96

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
    local target = blink_destination.clamp(
        caster:GetAbsOrigin(), location, BLINK_RANGE
    )
    local center = Vector(target.x, target.y, GetGroundHeight(target, caster))
    if not self:IsFlat(center, caster) then
        self.cast_error = "目标地形不平坦"
        return UF_FAIL_CUSTOM
    end
    return UF_SUCCESS
end

function M:GetCustomCastErrorLocation()
    return self.cast_error or "无法闪现到该位置"
end

function M:OnSpellStart()
    if not IsServer() then return end
    local caster = self:GetCaster()
    print("[BuildingBlink] OnSpellStart entered ability=" .. tostring(self:GetAbilityName()) .. " caster=" .. tostring(caster and caster:entindex() or -1))
    local origin = caster:GetAbsOrigin()
    local cursor, distance = blink_destination.clamp(
        origin, self:GetCursorPosition(), BLINK_RANGE
    )
    if distance < 1 then
        self:EndCooldown()
        return
    end
    print(string.format("[BuildingBlink] cast ent=%d cursor=(%.1f,%.1f,%.1f) distance=%.1f", caster:entindex(), cursor.x, cursor.y, cursor.z, distance))
    local ground = GetGroundHeight(cursor, caster)
    local center = Vector(cursor.x, cursor.y, ground)
    if not self:IsFlat(center, caster) then
        print("[BuildingBlink] rejected: terrain_not_flat")
        self:EndCooldown()
        return
    end

    local building_system = require("systems/building_system")
    local moved, reason = building_system.relocate_building(caster, center)
    if not moved then
        print("[BuildingBlink] move failed ent=" .. tostring(caster:entindex()) .. " reason=" .. tostring(reason))
        self:EndCooldown()
        return
    end
    caster:Stop()
end

function M:IsFlat(center, caster)
    local base = GetGroundHeight(center, caster)
    local samples = {
        Vector(center.x + SAMPLE_RADIUS, center.y, center.z),
        Vector(center.x - SAMPLE_RADIUS, center.y, center.z),
        Vector(center.x, center.y + SAMPLE_RADIUS, center.z),
        Vector(center.x, center.y - SAMPLE_RADIUS, center.z),
    }
    for _, point in ipairs(samples) do
        if math.abs(GetGroundHeight(point, caster) - base) > MAX_HEIGHT_DELTA then
            return false
        end
    end
    return true
end

return M
