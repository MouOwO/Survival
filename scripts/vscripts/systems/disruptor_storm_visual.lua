-- A visual area only: no native ability, silence, damage or target queries.
local config = require("config/generated/tower_lightning_effects")
local scheduler = require("core/scheduler")
local M = {}
local active = {}
local function world()
    return GameRules.GetGameModeEntity and GameRules:GetGameModeEntity() or GameRules
end

local function finish(entry, immediate)
    if not entry or not active[entry] then return end
    active[entry] = nil
    if entry.task then scheduler.cancel(entry.task); entry.task = nil end
    -- IDs from a previous Tools world may already belong to other particles.
    if entry.world ~= world() then return end
    pcall(ParticleManager.DestroyParticle, ParticleManager, entry.particle, immediate == true)
    pcall(ParticleManager.ReleaseParticleIndex, ParticleManager, entry.particle)
end

function M.particle_name() return config.by_id.strike.particle_name end

function M.play(caster, position, radius, duration, previous, particle_name)
    local row = config.by_id.strike
    if row.enabled == false then return nil end
    duration = math.max(0.1, tonumber(duration) or tonumber(row.visual_duration) or 1.2)
    local entry = previous and active[previous] and previous or nil
    if entry and entry.world ~= world() then finish(entry, true); entry = nil end
    local created = entry == nil
    entry = entry or {world=world()}
    local ok, err = pcall(function()
        if GetGroundPosition then position = GetGroundPosition(position, nil) end
        if created then
            entry.particle = ParticleManager:CreateParticle(particle_name or row.particle_name,
                PATTACH_WORLDORIGIN, caster)
            assert(type(entry.particle)=="number" and entry.particle>=0, "invalid storm particle")
            active[entry] = true
        end
        ParticleManager:SetParticleControl(entry.particle, 0, position)
        ParticleManager:SetParticleControl(entry.particle, 1, Vector(math.max(1, radius), 1, 1))
        ParticleManager:SetParticleControl(entry.particle, 4, position)
        if created then
            ParticleManager:SetParticleControl(entry.particle, 2, Vector(duration, 0, 0))
            entry.task = scheduler.after(duration, function() finish(entry, false) end,
                "disruptor_storm_visual_" .. tostring(entry.particle))
        end
    end)
    if not ok then
        finish(entry, true)
        print("[DisruptorStormVisual] optional visual failed: " .. tostring(err))
        return nil
    end
    return entry
end

function M.clear()
    local entries = {}
    for entry in pairs(active) do entries[#entries+1] = entry end
    for _, entry in ipairs(entries) do finish(entry, true) end
end

return M
