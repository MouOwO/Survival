ability_survival_builder_blink = class({})

local BLINK_RANGE = 1000
local START_PARTICLE = "particles/items_fx/blink_dagger_start.vpcf"
local END_PARTICLE = "particles/items_fx/blink_dagger_end.vpcf"

local function valid_destination(position)
    return GridNav:IsTraversable(position) and not GridNav:IsBlocked(position)
end

function ability_survival_builder_blink:CastFilterResultLocation(location)
    if not IsServer() then return UF_SUCCESS end
    local caster = self:GetCaster()
    if not caster or caster:IsNull() then return UF_FAIL_CUSTOM end
    if (location - caster:GetAbsOrigin()):Length2D() > BLINK_RANGE then
        self.cast_error = "目标位置超出闪烁范围"
        return UF_FAIL_CUSTOM
    end
    local destination = Vector(
        location.x,
        location.y,
        GetGroundHeight(location, caster)
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
    local cursor = self:GetCursorPosition()
    if (cursor - origin):Length2D() > BLINK_RANGE then return end
    local destination = Vector(cursor.x, cursor.y, GetGroundHeight(cursor, caster))
    if not valid_destination(destination) then return end

    caster:Stop()
    flash(START_PARTICLE, origin, caster)
    ProjectileManager:ProjectileDodge(caster)
    FindClearSpaceForUnit(caster, destination, true)
    flash(END_PARTICLE, caster:GetAbsOrigin(), caster)
end

return ability_survival_builder_blink