ability_survival_hero_ball_lightning = class({})

local MAX_DISTANCE = 800
local TRAVEL_SPEED = 7000
local destination_validation = require("systems/destination_validation_service")
local blink_destination = require("systems/blink_destination")

local function valid_destination(position, caster)
    return destination_validation.validate(position, caster)
end

function ability_survival_hero_ball_lightning:CastFilterResultLocation(location)
    if not IsServer() then return UF_SUCCESS end
    local caster = self:GetCaster()
    if not caster or caster:IsNull() then return UF_FAIL_CUSTOM end
    if caster:HasModifier("modifier_survival_hero_ball_lightning") then
        self.cast_error = "正在传送中"
        return UF_FAIL_CUSTOM
    end
    local target = blink_destination.clamp(
        caster:GetAbsOrigin(), location, MAX_DISTANCE
    )
    local destination = Vector(
        target.x,
        target.y,
        GetGroundHeight(target, caster)
    )
    if not valid_destination(destination, caster) then
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
    local target, distance = blink_destination.clamp(
        origin, self:GetCursorPosition(), MAX_DISTANCE
    )
    if distance < 1 then
        self:RefundTravelMana()
        return
    end

    target.z = GetGroundHeight(target, caster)
    if not valid_destination(target, caster) then
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