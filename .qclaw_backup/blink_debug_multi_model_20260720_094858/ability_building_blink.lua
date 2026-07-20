local M = class({})

local BLINK_RANGE = 1000
local MAX_HEIGHT_DELTA = 32
local SAMPLE_RADIUS = 96

function M:OnSpellStart()
    if not IsServer() then return end
    local caster = self:GetCaster()
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

    local ground = GetGroundHeight(cursor, caster)
    local center = Vector(cursor.x, cursor.y, ground)
    if not GridNav:CanFindPath(origin, center) or not self:IsFlat(center, caster) then
        self:EndCooldown()
        return
    end

    local building_system = require("systems/building_system")
    local moved = building_system.relocate_building(caster, center)
    if not moved then
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
