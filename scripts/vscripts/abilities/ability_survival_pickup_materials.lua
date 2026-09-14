local event_bus = require("core/event_bus")
local events = require("core/events")
local ground_item_pickup = require("systems/ground_item_pickup_service")
local upgrade_materials = require("systems/challenge_upgrade_material_service")

ability_survival_pickup_materials = class({})

local CAST_RANGE = 700
local PICKUP_RADIUS = 300
local AREA_PARTICLE = "particles/units/heroes/hero_riki/riki_smokebomb.vpcf"

function ability_survival_pickup_materials:GetAOERadius()
    return PICKUP_RADIUS
end

function ability_survival_pickup_materials:GetCastRange()
    return CAST_RANGE
end

function ability_survival_pickup_materials:CastFilterResultLocation(location)
    local caster = self:GetCaster()
    if not caster or caster:IsNull() or not location then return UF_FAIL_CUSTOM end
    if (location - caster:GetAbsOrigin()):Length2D() > CAST_RANGE then
        return UF_FAIL_CUSTOM
    end
    return UF_SUCCESS
end

function ability_survival_pickup_materials:GetCustomCastErrorLocation()
    return "#survival_pickup_out_of_range"
end

local function show_area(caster, origin)
    local particle = ParticleManager:CreateParticle(AREA_PARTICLE, PATTACH_WORLDORIGIN, caster)
    ParticleManager:SetParticleControl(particle, 0, origin)
    ParticleManager:SetParticleControl(particle, 1, Vector(PICKUP_RADIUS, PICKUP_RADIUS, PICKUP_RADIUS))
    -- Stop all smoke immediately at 0.5 seconds, including lingering particles.
    GameRules:GetGameModeEntity():SetContextThink("pickup_area_" .. tostring(particle), function()
        ParticleManager:DestroyParticle(particle, true)
        ParticleManager:ReleaseParticleIndex(particle)
        return nil
    end, 0.5)
end

function ability_survival_pickup_materials:OnSpellStart()
    if not IsServer() then return end
    local caster = self:GetCaster()
    if not caster or caster:IsNull() then return end
    local origin = self:GetCursorPosition()
    -- Recheck on the server: movement/queued orders must not extend the range.
    if self:CastFilterResultLocation(origin) ~= UF_SUCCESS then
        self:EndCooldown()
        return
    end
    show_area(caster, origin)
    local player_id = caster:GetPlayerOwnerID()
    local candidates = {}
    for _, candidate in ipairs(upgrade_materials.nearby(caster, player_id, origin)) do
        candidate.kind = "upgrade_material"
        candidates[#candidates + 1] = candidate
    end
    for _, candidate in ipairs(ground_item_pickup.nearby(caster, player_id, origin)) do
        candidate.kind = "ground_item"
        candidates[#candidates + 1] = candidate
    end
    table.sort(candidates, function(a, b)
        if a.distance == b.distance then return a.entindex < b.entindex end
        return a.distance < b.distance
    end)

    if #candidates == 0 then
        event_bus.emit(events.UI_NOTIFICATION, {
            player_id = player_id,
            message = "目标位置周围300范围内没有可拾取的物品",
        })
        return
    end

    for _, candidate in ipairs(candidates) do
        local result
        if candidate.kind == "upgrade_material" then
            result = upgrade_materials.pickup_candidate(candidate, player_id)
        else
            result = ground_item_pickup.pickup_candidate(caster, candidate)
        end
        if result and result.full then
            event_bus.emit(events.UI_NOTIFICATION, {
                player_id = player_id,
                message = "装备栏已满，已停止拾取剩余物品",
                level = "error",
            })
            break
        end
    end
end
