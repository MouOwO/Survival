local event_bus = require("core/event_bus")
local events = require("core/events")
local encounter_members = require("config/generated/encounter_members")
local monster_archetypes = require("config/generated/monster_archetypes")
local catalog = require("config/asset_catalog")
local asset_preload = require("systems/asset_preload_service")
local logger = require("core/logger")

local M = {}

local SESSION_ID = "challenge_10_11_visuals"
local PRELOAD_DURATION_SECONDS = 2
local started = false

local function collect_asset_ids()
    local archetypes_by_id = {}
    for _, archetype in ipairs(monster_archetypes.rows or {}) do
        archetypes_by_id[archetype.archetype_id] = archetype
    end

    local result = {}
    local seen = {}
    for _, member in ipairs(encounter_members.rows or {}) do
        if member.enabled ~= false
            and (member.encounter_id == "encounter_challenge_10"
                or member.encounter_id == "encounter_challenge_11") then
            local archetype = archetypes_by_id[member.archetype_id]
            local asset = archetype and catalog.for_model(archetype.model_path)
            if asset and not seen[asset.asset_id] then
                seen[asset.asset_id] = true
                result[#result + 1] = asset.asset_id
            end
        end
    end
    table.sort(result)
    return result
end

function M.start()
    if started then return true, "already_started" end
    started = true
    local asset_ids = collect_asset_ids()
    local ok, status, snapshot = asset_preload.preload_gradually(asset_ids, {
        session_id = SESSION_ID,
        duration_seconds = PRELOAD_DURATION_SECONDS,
        dispatch_ratio = 1,
        retry = true,
        on_complete = function(progress)
            logger.info("ChallengeAssetPreload", "complete ready="
                .. tostring(progress.ready) .. " failed="
                .. tostring(progress.failed) .. " total="
                .. tostring(progress.total))
        end,
    })
    if not ok then started = false end
    return ok, status, snapshot
end

function M.asset_ids_for_test()
    return collect_asset_ids()
end

function M.init()
    started = false
    event_bus.subscribe(events.HERO_READY, function()
        local ok, status = M.start()
        if not ok then
            logger.warn("ChallengeAssetPreload", "startup failed: " .. tostring(status))
        end
    end)
end

M.SESSION_ID = SESSION_ID
M.PRELOAD_DURATION_SECONDS = PRELOAD_DURATION_SECONDS

return M