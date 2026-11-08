-- Practice-kill presentation only. Native finite particles own their lifetime;
-- no queues, timers, entity scans, custom events or Panorama panels are added.
local particle_manager = require("core/particle_manager")
local M = {}
local PARTICLE = "particles/msg_fx/msg_heal.vpcf"
local ATTRIBUTE_COLORS = {
    { 228, 91, 79 }, -- Strength: same red as the hero attribute HUD.
    { 111, 201, 92 }, -- Agility.
    { 73, 169, 222 }, -- Intellect.
}

local function amount(value)
    value = tonumber(value) or 0
    if value ~= value or value <= 0 or value == math.huge then return 0 end
    return math.floor(value)
end

local function attribute_number(player, origin, value, row, color)
    local handle
    local ok = pcall(function()
        -- Snapshot the death position rather than following a sinking corpse.
        handle = ParticleManager:CreateParticleForPlayer(
            PARTICLE, PATTACH_WORLDORIGIN, nil, player
        )
        if type(handle) ~= "number" or handle < 0 then error("invalid_particle") end
        ParticleManager:SetParticleControl(handle, 0,
            Vector(origin.x, origin.y, origin.z + 96 + (row - 1) * 38))
        ParticleManager:SetParticleControl(handle, 1, Vector(10, value, 0))
        ParticleManager:SetParticleControl(handle, 2,
            Vector(1.2, #string.format("%.0f", value) + 1, 0))
        ParticleManager:SetParticleControl(handle, 3, Vector(color[1], color[2], color[3]))
    end)
    if type(handle) == "number" and handle >= 0 then
        if not ok then pcall(ParticleManager.DestroyParticle, ParticleManager, handle, true) end
        pcall(ParticleManager.ReleaseParticleIndex, ParticleManager, handle)
    end
end

function M.precache(context)
    PrecacheResource("particle", PARTICLE, context)
end

function M.show(victim, player_id, result)
    if not result or result.ok ~= true or not victim or victim:IsNull() then return end
    local player = PlayerResource:GetPlayer(player_id)
    if not player then return end -- Never turn a private reward into a broadcast.
    local resources = result.resources or {}
    local wood, gold = amount(resources.wood), amount(resources.gold)
    if wood > 0 and result.resource_result and result.resource_result.ok == true then
        pcall(particle_manager.show_green_number, victim, wood, player)
    end
    if gold > 0 and result.resource_result and result.resource_result.ok == true then
        pcall(SendOverheadEventMessage, player, OVERHEAD_ALERT_GOLD, victim, gold, nil)
    end
    if not result.progression_result or result.progression_result.ok ~= true then return end
    local attributes = 0
    for _, effect in ipairs(result.effects or {}) do
        if effect.enabled ~= false and effect.effect_type == "add_all_attributes" then
            attributes = attributes + (tonumber(effect.value) or 0)
        end
    end
    attributes = amount(attributes)
    if attributes <= 0 then return end
    local origin = victim:GetAbsOrigin()
    for row, color in ipairs(ATTRIBUTE_COLORS) do
        attribute_number(player, origin, attributes, row, color)
    end
end

return M
