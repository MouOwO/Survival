-- Body skins, activity modifiers and persistent outfit particles. Components
-- remain owned by model_appearance_service; gameplay is never changed here.
local M = {}

local function call(entity, name, ...)
    if entity and type(entity[name]) == "function" then
        return pcall(entity[name], entity, ...)
    end
    return false
end

function M.clear(unit)
    local state = unit and unit.survival_monster_cosmetic_details
    if not state then return end
    for _, particle in ipairs(state.particles) do
        call(ParticleManager, "DestroyParticle", particle, false)
        call(ParticleManager, "ReleaseParticleIndex", particle)
    end
    if state.original_skin ~= nil then call(unit, "SetSkin", state.original_skin) end
    if state.has_activities then call(unit, "ClearActivityModifiers") end
    unit.survival_monster_cosmetic_details = nil
end

function M.apply(unit, asset, components)
    local previous = unit.survival_monster_cosmetic_details
    if previous and previous.asset == asset and previous.components == components then return end
    M.clear(unit)
    local state = { asset = asset, components = components, particles = {} }
    unit.survival_monster_cosmetic_details = state
    if tonumber(asset.model_skin) then
        local ok, skin = call(unit, "GetSkin")
        state.original_skin = ok and tonumber(skin) or 0
        call(unit, "SetSkin", tonumber(asset.model_skin))
    end
    for _, entry in ipairs(asset.activity_modifiers or {}) do
        if entry.enabled ~= false and entry.modifier_name then
            if call(unit, "AddActivityModifier", entry.modifier_name) then
                state.has_activities = true
            end
        end
    end
    for _, effect in ipairs(asset.effects or {}) do
        if effect.enabled ~= false and effect.effect_group_id == "wave_cosmetic_ambient" then
            local owner = unit
            if effect.owner_component_id and effect.owner_component_id ~= "" then
                owner = components and components[effect.owner_component_id]
            end
            if owner then
                local attach = rawget(_G, effect.attach_type or "PATTACH_ABSORIGIN_FOLLOW")
                    or rawget(_G, "PATTACH_ABSORIGIN_FOLLOW") or 1
                local ok, particle = call(ParticleManager, "CreateParticle", effect.particle_path, attach, owner)
                if ok and particle ~= nil then
                    state.particles[#state.particles + 1] = particle
                    -- CSV control_profile: CP=attachment|CP=attachment, from
                    -- Valve's attribute_controlled_attached_particles schema.
                    for point, attachment in tostring(effect.control_profile or ""):gmatch("(%d+)=([^|]+)") do
                        local _, origin = call(owner, "GetAbsOrigin")
                        call(ParticleManager, "SetParticleControlEnt", particle, tonumber(point), owner,
                            rawget(_G, "PATTACH_POINT_FOLLOW") or 4, attachment, origin, true)
                    end
                end
            end
        end
    end
end

return M
