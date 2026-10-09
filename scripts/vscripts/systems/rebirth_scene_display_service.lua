-- Ten stationary presentation bodies. Combat ownership and rewards remain in
-- monster_spawn_service; these units never publish MONSTER_SPAWNED.
local encounters = require("config/generated/monster_encounters")
local spawn_points = require("config/generated/monster_spawn_points")
local archetypes = require("config/generated/monster_archetypes")
local rules = require("config/generated/global_rules")
local visuals = require("systems/monster_hero_visual_service")
local scheduler = require("core/scheduler")
local logger = require("core/logger")

local M = {}
local bodies, unavailable, revisions = {}, {}, {}
local started, generation = false, 0
local MODIFIER = "modifier_rebirth_scene_display"
local PREFIX = "rebirth_scene_restore:"

local function valid(unit)
    return unit and (not unit.IsNull or not unit:IsNull())
end

local function encounter_for(id)
    local encounter = encounters.by_id[id]
    return encounter and encounter.enabled ~= false
        and encounter.encounter_type == "rebirth_boss" and encounter or nil
end

local function call(unit, method, ...)
    if type(unit[method]) == "function" then unit[method](unit, ...) end
end

local function remove_body(id)
    local body = bodies[id]
    bodies[id] = nil
    if valid(body) then
        visuals.clear(body)
        UTIL_Remove(body)
    end
end

local function create_body(id)
    if not started or unavailable[id] then return false, "display_unavailable" end
    if valid(bodies[id]) then return true end
    local encounter = encounter_for(id)
    local point = encounter and spawn_points.by_id[encounter.spawn_point_id]
    local archetype = encounter and archetypes.by_id[encounter.archetype_id]
    if not point or point.enabled == false or not archetype or archetype.enabled == false then
        return false, "display_definition_missing"
    end
    local marker = Entities:FindByName(nil, point.hammer_target_name)
    if not valid(marker) then return false, "display_marker_missing:" .. point.hammer_target_name end
    local origin = marker:GetAbsOrigin()
    local body
    local ok, reason = pcall(function()
        -- NPC activity selection is intentional: hero/Arcana bodies do not
        -- share an "idle" sequence that a prop_dynamic could safely select.
        body = CreateUnitByName(archetype.unit_name, origin, false, nil, nil,
            DOTA_TEAM_NEUTRALS)
        assert(valid(body), "display_unit_create_failed")
        body.survival_rebirth_scene_display = true
        body.survival_hide_custom_health_bar = true
        body:AddNewModifier(body, nil, MODIFIER, {})
        assert(body:HasModifier(MODIFIER), "display_isolation_modifier_failed")
        -- npc_spawned may have attached the shared health-bar thinker before
        -- CreateUnitByName returns; remove it rather than leave ten idle ticks.
        require("systems/unit_health_bar_service").exclude(body)
        call(body, "SetIdleAcquire", false)
        call(body, "SetAcquisitionRange", 0)
        call(body, "SetDayTimeVisionRange", 0)
        call(body, "SetNightTimeVisionRange", 0)
        call(body, "SetDeathXP", 0)
        call(body, "SetMinimumGoldBounty", 0)
        call(body, "SetMaximumGoldBounty", 0)
        call(body, "SetHullRadius", 0)
        body:SetModel(archetype.model_path)
        body:SetOriginalModel(archetype.model_path)
        body:SetModelScale(tonumber(archetype.model_scale) or 1)
        -- Arena markers sit above their deck. Sample the local ground, keeping
        -- marker XY exact; FindClearSpace could displace a decorative body.
        local ground = GetGroundPosition(origin, body)
        body:SetAbsOrigin(Vector(origin.x, origin.y, ground.z))
        if marker.GetForwardVector then body:SetForwardVector(marker:GetForwardVector()) end
        body:Stop()
        local applied, error_code = visuals.apply(body, archetype, {
            fresh_unit = true, encounter = true, allow_outside_formal_wave = true,
            model_path = archetype.model_path,
        })
        assert(applied, "display_outfit_failed:" .. tostring(error_code))
    end)
    if not ok then
        if valid(body) then visuals.clear(body); UTIL_Remove(body) end
        logger.warn("RebirthScene", tostring(id) .. ":" .. tostring(reason))
        return false, tostring(reason)
    end
    bodies[id] = body
    return true
end

local function invalidate(id)
    revisions[id] = (revisions[id] or 0) + 1
    scheduler.cancel(PREFIX .. id)
    return revisions[id]
end

local function corpse_delay()
    local function value(id, fallback)
        local row = rules.by_id[id]
        return row and row.enabled ~= false and math.max(0, tonumber(row.value) or fallback) or fallback
    end
    -- Reuse the corpse service's configured lifetime, plus its bounded tick
    -- margin. No repeating display task or second resource preload is needed.
    return value("monster_corpse_hold_seconds", 0.6)
        + math.max(0.05, value("monster_corpse_sink_seconds", 0.8))
        + value("monster_corpse_remove_delay_seconds", 0.05)
        + 2 * math.max(0.01, value("monster_corpse_update_interval", 0.05))
end

function M.start()
    if not require("systems/startup_asset_preload_service").snapshot().complete then
        return { ok = false, error = "startup_assets_not_ready" }
    end
    started = true
    local count, failed, failures = 0, 0, {}
    for _, encounter in ipairs(encounters.rows) do
        if encounter_for(encounter.encounter_id) and not unavailable[encounter.encounter_id] then
            local ok, reason = create_body(encounter.encounter_id)
            if ok then count = count + 1 else
                failed = failed + 1
                failures[encounter.encounter_id] = reason
                logger.warn("RebirthScene", tostring(encounter.encounter_id) .. ":" .. tostring(reason))
            end
        end
    end
    logger.info("RebirthScene", string.format("startup displayed=%d failures=%d", count, failed))
    return { ok = next(failures) == nil, displayed = count, failures = failures }
end

function M.hide(id)
    if not encounter_for(id) then return end
    invalidate(id)
    unavailable[id] = true
    remove_body(id)
end

function M.restore(id, options)
    if not encounter_for(id) then return end
    local revision, current_generation = invalidate(id), generation
    unavailable[id] = nil
    if not started then return end
    if options and options.after_corpse then
        unavailable[id] = true
        scheduler.after(corpse_delay(), function()
            if not started or generation ~= current_generation or revisions[id] ~= revision then return end
            unavailable[id] = nil
            create_body(id)
        end, PREFIX .. id)
    else
        create_body(id)
    end
end

function M.reset()
    started = false
    generation = generation + 1
    for id in pairs(revisions) do scheduler.cancel(PREFIX .. id) end
    local ids = {}
    for id in pairs(bodies) do ids[#ids + 1] = id end
    for _, id in ipairs(ids) do remove_body(id) end
    bodies, unavailable, revisions = {}, {}, {}
end

return M
