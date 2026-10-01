-- Shared by the released map and its art review. No preview camera/game rules.
local scheduler = require("core/scheduler")
local M = {}
local particles = {}
local props = {}
local bound_world, generation = nil, 0
local effect = "particles/units/heroes/heroes_underlord/abbysal_underlord_portal_ambient.vpcf"
local model = "models/heroes/abyssal_underlord/abyssal_underlord_portal_model.vmdl"
-- Player slots are east, south, west, north. Monsters leave the central
-- sanctuary along these outward lanes; the native door's normal is local X.
local lane_yaws = { 0, 270, 180, 90 }

local function supported_map()
    local name = GetMapName()
    return name == "template_map" or name == "valley_decor_review"
end

function M.precache(context)
    if supported_map() then
        PrecacheResource("particle", effect, context)
        PrecacheResource("model", model, context)
    end
end

function M.clear()
    local old_particles, old_props = particles, props
    particles, props = {}, {}
    for _, id in ipairs(old_particles) do
        pcall(ParticleManager.DestroyParticle, ParticleManager, id, true)
        pcall(ParticleManager.ReleaseParticleIndex, ParticleManager, id)
    end
    for _, prop in ipairs(old_props) do
        if not prop:IsNull() then UTIL_Remove(prop) end
    end
end

local function create_portal(marker, lane)
    local origin = marker:GetAbsOrigin()
    local position = Vector(origin.x, origin.y, GetGroundHeight(origin, nil) + 12)
    local yaw = lane_yaws[lane]
    local prop = SpawnEntityFromTableSynchronous("prop_dynamic", {
        targetname = "survival_underlord_portal_" .. lane,
        model = model, solid = 0, DefaultAnim = "au_portal_chanelling",
        origin = string.format("%f %f %f", position.x, position.y, position.z),
        angles = string.format("0 %d 0", yaw),
    })
    assert(prop and not prop:IsNull(), "Underlord portal model spawn failed")
    props[#props + 1] = prop
    prop:SetAbsOrigin(position)
    prop:SetAngles(0, yaw, 0)
    DoEntFireByInstanceHandle(prop, "SetAnimation", "au_portal_chanelling", 0, prop, prop)
    local id = ParticleManager:CreateParticle(effect, PATTACH_ABSORIGIN_FOLLOW, prop)
    assert(type(id) == "number" and id >= 0, "Underlord portal particle creation failed")
    particles[#particles + 1] = id
    ParticleManager:SetParticleControlEnt(id, 0, prop,
        PATTACH_ABSORIGIN_FOLLOW, "", position, true)
    -- Keep the native attachment transform: this positions and rotates the
    -- upright vortex with its door instead of using the old ground-ring frame.
    ParticleManager:SetParticleControlEnt(id, 1, prop,
        PATTACH_POINT_FOLLOW, "attach_portal", position + Vector(0, 0, 97.362), true)
    local radians = math.rad(yaw)
    local forward = Vector(math.cos(radians), math.sin(radians), 0)
    local right = Vector(forward.y, -forward.x, 0)
    for _, cp in ipairs({0, 2}) do
        ParticleManager:SetParticleControl(id, cp, position)
        ParticleManager:SetParticleControlOrientation(id, cp, forward, right, Vector(0, 0, 1))
    end
    -- CP4 is native size/channel state, not a position; CP61 selects the
    -- original orange style. Leaving both zero keeps a fully idle portal.
    ParticleManager:SetParticleControl(id, 4, Vector(0, 0, 0))
    ParticleManager:SetParticleControl(id, 61, Vector(0, 0, 0))
end

function M.apply()
    if not supported_map() then return 0 end
    M.clear()
    for i = 1, 4 do
        local marker = Entities:FindByName(nil, "monsterborn_player" .. i)
        local old = Entities:FindByName(nil, "valley_decor_v1_fx_monsterborn_player" .. i)
        if old then DoEntFireByInstanceHandle(old, "Stop", "", 0, old, old) end
        if marker then
            local ok, err = pcall(create_portal, marker, i)
            if not ok then
                M.clear()
                print("[ValleyEnvironment] portal setup failed: " .. tostring(err))
                return 0
            end
        end
    end
    print("VALLEY_UNDERLORD_PORTALS", #particles)
    return #particles
end

function M.init()
    local world = GameRules:GetGameModeEntity()
    if world == bound_world then M.clear() end
    -- Indices from the preceding world must not destroy the new world's FX.
    particles, props = {}, {}
    bound_world = world
    generation = generation + 1
    local current_generation = generation
    scheduler.after(0, function()
        if generation == current_generation then M.apply() end
    end, "valley_environment_initialise")
end

return M
