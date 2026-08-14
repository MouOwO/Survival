ability_survival_builder_blink = class({})

local BLINK_RANGE = 1000
local destination_validation = require("systems/destination_validation_service")
local blink_destination = require("systems/blink_destination")
local START_PARTICLE = "particles/items_fx/blink_dagger_start.vpcf"
local END_PARTICLE = "particles/items_fx/blink_dagger_end.vpcf"

local function valid_destination(position)
    return destination_validation.validate(position)
end

function ability_survival_builder_blink:CastFilterResultLocation(location)
    if not IsServer() then return UF_SUCCESS end
    local caster = self:GetCaster()
    if not caster or caster:IsNull() then return UF_FAIL_CUSTOM end
    local target = blink_destination.clamp(
        caster:GetAbsOrigin(), location, BLINK_RANGE
    )
    local destination = Vector(
        target.x,
        target.y,
        GetGroundHeight(target, caster)
    )
    if not valid_destination(destination) then
        self.cast_error = "目标位置无法移动到达"
        return UF_FAIL_CUSTOM
    end
    return UF_SUCCESS
end

function ability_survival_builder_blink:GetCustomCastErrorLocation()
    return self.cast_error or "无法闪烁到该位置"
end

local function flash(path, position, caster)
    local particle = ParticleManager:CreateParticle(
        path,
        PATTACH_WORLDORIGIN,
        caster
    )
    ParticleManager:SetParticleControl(particle, 0, position)
    ParticleManager:ReleaseParticleIndex(particle)
end

function ability_survival_builder_blink:OnSpellStart()
    if not IsServer() then return end
    local caster = self:GetCaster()
    if not caster or caster:IsNull() then return end
    local origin = caster:GetAbsOrigin()
    local cursor = blink_destination.clamp(
        origin, self:GetCursorPosition(), BLINK_RANGE
    )
    local destination = Vector(cursor.x, cursor.y, GetGroundHeight(cursor, caster))
    if not valid_destination(destination) then return end

    caster:Stop()
    flash(START_PARTICLE, origin, caster)
    ProjectileManager:ProjectileDodge(caster)
    local moved = destination_validation.teleport(caster, destination, true)
    if not moved then self:EndCooldown(); return end
    flash(END_PARTICLE, caster:GetAbsOrigin(), caster)
end

return ability_survival_builder_blink