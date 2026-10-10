-- Io's presentation is independent of builder identity, navigation and repair.
local bus = require("core/event_bus")
local events = require("core/events")
local definitions = require("config/generated/builder_definitions")
local catalog = require("config/asset_catalog")
local M = {}
local owners, work = {}, {}
local generation = 0
local io_body_particle = "particles/units/heroes/hero_wisp/wisp_ambient.vpcf"
local io_arcana_particle = "particles/econ/items/wisp/wisp_ambient_ti7.vpcf"
local arcana_attachments = { "attach_hitloc", "attach_top_card", "attach_bot_card",
    "attach_side_card_01", "attach_side_card_02", "attach_side_card_03", "attach_side_card_04" }

local function valid(unit) return unit and not unit:IsNull() end
local function retire(id)
    if id == nil or not ParticleManager then return end
    pcall(ParticleManager.DestroyParticle, ParticleManager, id, true)
    pcall(ParticleManager.ReleaseParticleIndex, ParticleManager, id)
end
local function particle(path, unit)
    if not ParticleManager or not path or path == "" then return nil end
    local id
    local ok = pcall(function()
        id = ParticleManager:CreateParticle(path, PATTACH_ABSORIGIN_FOLLOW, unit)
        -- A creature has no equipped-item particle bindings. Reproduce Valve's
        -- preview bindings explicitly instead of leaving all card CPs at zero.
        if path == io_arcana_particle then
            for index, point in ipairs(arcana_attachments) do
                ParticleManager:SetParticleControlEnt(id, index - 1, unit,
                    PATTACH_POINT_FOLLOW, point, unit:GetAbsOrigin(), true)
            end
        elseif path == io_body_particle then
            ParticleManager:SetParticleControlEnt(id, 0, unit,
                PATTACH_POINT_FOLLOW, "attach_hitloc", unit:GetAbsOrigin(), true)
            ParticleManager:SetParticleControlEnt(id, 1, unit,
                PATTACH_ABSORIGIN_FOLLOW, "", unit:GetAbsOrigin(), true)
            ParticleManager:SetParticleControl(id, 10, Vector(1, 1, 0))
            ParticleManager:SetParticleControl(id, 11, Vector(1, 0, 0))
            ParticleManager:SetParticleControl(id, 13, Vector(0, 1, 1))
        end
    end)
    if not ok then retire(id); return nil end
    return id
end
local function remove_wearable(entity)
    if not valid(entity) then return end
    if UTIL_Remove then pcall(UTIL_Remove, entity)
    elseif entity.RemoveSelf then pcall(entity.RemoveSelf, entity) end
end
local function set_sequence(wearables, sequence)
    if not sequence or sequence == "" then return end
    for _, entity in ipairs(wearables) do
        if valid(entity) and entity.SetSequence then pcall(entity.SetSequence, entity, sequence) end
    end
end
local function wearable(unit, path, entity_class, idle)
    if type(SpawnEntityFromTableSynchronous) ~= "function" then return nil end
    local ok, entity = pcall(SpawnEntityFromTableSynchronous,
        entity_class or "prop_dynamic", {model = path, solid = "0", spawnflags = "256",
            DisableBoneFollowers = "1", DefaultAnim = idle})
    if not ok or not valid(entity) then return nil end
    local attached = pcall(function()
        -- An unbound dota_item_wearable exists on the server but does not render
        -- on this creature. Parent a renderable prop without merging Io's root
        -- skeleton with the arcana's independent root_immortal/card skeleton.
        entity:SetModel(path)
        assert(entity:SetOwner(unit) ~= false)
        assert(entity:SetParent(unit, "") ~= false)
        entity:SetLocalOrigin(Vector(0, 0, 0))
        entity:SetLocalAngles(0, 0, 0)
    end)
    if not attached then remove_wearable(entity); return nil end
    set_sequence({entity}, idle)
    return entity
end
local function stop_work(state)
    if state.building_index and work[state.building_index] == state then
        work[state.building_index] = nil
    end
    local activity, owner = state.activity, state.owner
    -- Detach ownership before engine calls: cleanup callbacks may re-enter.
    state.building, state.building_index, state.activity, state.animation_token = nil, nil, nil, nil
    if state.world == GameRules then
        if valid(owner) and owner.SetContextThink then
            pcall(owner.SetContextThink, owner, "survival_builder_construction_animation", nil, 0)
        end
        set_sequence(state.wearables, state.idle_sequence)
    end
    if state.world == GameRules and activity and valid(owner) and owner.FadeGesture then
        pcall(owner.FadeGesture, owner, activity)
    end
end
local function clear_state(state)
    if owners[state.index] == state then owners[state.index] = nil end
    local ambient, wearables = state.ambient, state.wearables
    state.ambient, state.wearables = {}, {}
    stop_work(state)
    if state.world == GameRules then
        for _, id in ipairs(ambient) do retire(id) end
        for _, entity in ipairs(wearables) do remove_wearable(entity) end
    end
end

function M.clear(unit)
    if not valid(unit) then return end
    local state = owners[unit:entindex()]
    if state and state.owner == unit then clear_state(state) end
end

function M.apply(unit, definition)
    if not valid(unit) then return false end
    definition = definition or definitions.by_id[unit.survival_builder_id or "default_builder"]
    local asset = definition and catalog.get(definition.visual_asset_id)
    if not asset then return false end
    local previous = owners[unit:entindex()]
    if previous then clear_state(previous) end
    local state = { owner = unit, index = unit:entindex(), definition = definition, ambient = {}, wearables = {}, idle_sequence = asset.default_sequence, world = GameRules }
    owners[state.index] = state
    for _, path in ipairs(asset.attachment_models or {}) do
        local entity = wearable(unit, path, asset.attachment_entity_class, asset.default_sequence)
        if entity then state.wearables[#state.wearables+1] = entity end
    end
    -- The native Io model alone has no visible light body. If the cosmetic
    -- cannot attach, retain a visible builder using Io's original body effect.
    local visual_owner = state.wearables[1] or unit
    local ambient_paths = state.wearables[1] and asset.environment_particles or { io_body_particle }
    for _, path in ipairs(ambient_paths or {}) do
        local id = particle(path, visual_owner)
        if id ~= nil then state.ambient[#state.ambient+1] = id end
    end
    return true
end

function M.construction_started(unit, building)
    if not valid(unit) or not valid(building) then return false end
    local state = owners[unit:entindex()]
    if not state or state.owner ~= unit then return false end
    stop_work(state)
    state.building, state.building_index = building, building:entindex()
    local previous = work[state.building_index]
    if previous and previous ~= state then stop_work(previous) end
    work[state.building_index] = state
    state.activity = rawget(_G, state.definition.construction_activity or "")
    if state.activity and unit.StartGesture then pcall(unit.StartGesture, unit, state.activity) end
    set_sequence(state.wearables, state.definition.construction_sequence)
    -- Play the native attack once, then return to idle independently of the
    -- build duration. No charging emitter or recurring construction timer.
    local visual_owner = state.wearables[1]
    local duration = 1 -- Native Io/arcana attack: 31 frames at 30 fps.
    if valid(visual_owner) and visual_owner.SequenceDuration then
        local ok, value = pcall(visual_owner.SequenceDuration, visual_owner,
            state.definition.construction_sequence)
        value = tonumber(value)
        if ok and value and value > 0 and value < 10 then duration = value end
    end
    if unit.SetContextThink then
        local token = {}
        state.animation_token = token
        pcall(unit.SetContextThink, unit, "survival_builder_construction_animation", function()
            if state.world ~= GameRules or owners[state.index] ~= state
                or state.animation_token ~= token or not valid(unit) then return end
            state.animation_token = nil
            local activity = state.activity
            state.activity = nil
            set_sequence(state.wearables, state.idle_sequence)
            if activity and unit.FadeGesture then pcall(unit.FadeGesture, unit, activity) end
        end, duration)
    end
    return true
end

function M.construction_finished(building, entindex)
    local index = tonumber(entindex) or (valid(building) and building:entindex())
    if not index then return end
    local state = work[index]
    if state and state.building == building then stop_work(state) end
end

function M.init()
    local old = {}
    for _, state in pairs(owners) do old[#old+1] = state end
    for _, state in ipairs(old) do clear_state(state) end
    generation = generation + 1
    local current = generation
    bus.subscribe(events.ENGINE_ENTITY_KILLED, function(payload)
        if current ~= generation then return end
        local victim = payload.victim
        local index = tonumber(payload.victim_entindex)
            or (valid(victim) and victim:entindex())
        local state = index and owners[index]
        if state and state.owner == victim then clear_state(state) end
        state = index and work[index]
        if state and state.building == victim then stop_work(state) end
    end)
end

return M
