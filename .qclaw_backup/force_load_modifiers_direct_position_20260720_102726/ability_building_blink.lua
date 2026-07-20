local M = class({})

local BLINK_RANGE = 1000
local MAX_HEIGHT_DELTA = 32
local SAMPLE_RADIUS = 96

function M:CastFilterResultLocation(location)
    if IsServer() then print("[BuildingBlink] CastFilterResultLocation ability=" .. tostring(self:GetAbilityName())) end
    if not IsServer() then return UF_SUCCESS end
    local caster = self:GetCaster()
    local origin = caster:GetAbsOrigin()
    local delta = location - origin
    delta.z = 0
    if delta:Length2D() > BLINK_RANGE then
        self.cast_error = "目标位置超出闪现范围"
        return UF_FAIL_CUSTOM
    end
    local center = Vector(location.x, location.y, GetGroundHeight(location, caster))
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
    local cursor = self:GetCursorPosition()
    local delta = cursor - origin
    delta.z = 0
    local distance = delta:Length2D()
    if distance < 1 then
        self:EndCooldown()
        return
    end
    if distance > BLINK_RANGE then
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

_G.ability_building_blink = M
return M
