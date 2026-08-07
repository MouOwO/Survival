ability_survival_hero_ball_lightning = class({})

local MAX_DISTANCE = 800
local TRAVEL_SPEED = 7000

local function valid_destination(position)
    return GridNav:IsTraversable(position) and not GridNav:IsBlocked(position)
end

function ability_survival_hero_ball_lightning:CastFilterResultLocation(location)
    if not IsServer() then return UF_SUCCESS end
    local caster = self:GetCaster()
    if not caster or caster:IsNull() then return UF_FAIL_CUSTOM end
    if caster:HasModifier("modifier_survival_hero_ball_lightning") then
        self.cast_error = "正在传送中"
        return UF_FAIL_CUSTOM
    end
    if (location - caster:GetAbsOrigin()):Length2D() > MAX_DISTANCE then
        self.cast_error = "目标位置超出传送范围"
        return UF_FAIL_CUSTOM
    end
    local destination = Vector(
        location.x,
        location.y,
        GetGroundHeight(location, caster)
    )
    if not valid_destination(destination) then
        self.cast_error = "目标位置无法到达"
        return UF_FAIL_CUSTOM
    end
    return UF_SUCCESS
end

function ability_survival_hero_ball_lightning:GetCustomCastErrorLocation()
    return self.cast_error or "无法传送到该位置"
end

function ability_survival_hero_ball_lightning:RefundTravelMana()
    if self.travel_mana_refunded then return end
    self.travel_mana_refunded = true
    self:RefundManaCost()
end

function ability_survival_hero_ball_lightning:OnSpellStart()
    if not IsServer() then return end
    self.travel_mana_refunded = false
    local caster = self:GetCaster()
    if not caster or caster:IsNull() then return end

    local origin = caster:GetAbsOrigin()
    local cursor = self:GetCursorPosition()
    local delta = cursor - origin
    delta.z = 0
    local distance = delta:Length2D()
    if distance < 1 then
        self:RefundTravelMana()
        return
    end

    distance = math.min(distance, MAX_DISTANCE)
    local target = origin + delta:Normalized() * distance
    target.z = GetGroundHeight(target, caster)
    if not valid_destination(target) then
        self:RefundTravelMana()
        return
    end

    caster:Stop()
    ProjectileManager:ProjectileDodge(caster)
    local modifier = caster:AddNewModifier(
        caster,
        self,
        "modifier_survival_hero_ball_lightning",
        {
            x = target.x,
            y = target.y,
            z = target.z,
            speed = TRAVEL_SPEED,
        }
    )
    if not modifier then self:RefundTravelMana() end
end

return ability_survival_hero_ball_lightning