local event_bus = require("core/event_bus")
local events = require("core/events")
local heroes = require("config/generated/hero_definitions")
local asset_preload = require("systems/asset_preload_service")
local logger = require("core/logger")

local M = {}

local SESSION_ID = "hero_permanent"
local DEFAULT_DURATION_SECONDS = 30
local ASSET_PREFIX = "hero_permanent_"

local hero_to_asset = {}
local preload_started = false

local function asset_id_for(hero_id)
    return hero_to_asset[tostring(hero_id or "")]
end

local function collect_asset_ids()
    local result = {}
    for _, definition in ipairs(heroes.rows or {}) do
        if definition.enabled ~= false then
            local asset_id = ASSET_PREFIX .. tostring(definition.hero_id)
            hero_to_asset[definition.hero_id] = asset_id
            result[#result + 1] = asset_id
        end
    end
    table.sort(result)
    return result
end

function M.start()
    if preload_started then
        return true, "already_started"
    end
    preload_started = true
    local asset_ids = collect_asset_ids()
    local ok, status, snapshot = asset_preload.preload_gradually(asset_ids, {
        session_id = SESSION_ID,
        duration_seconds = DEFAULT_DURATION_SECONDS,
        dispatch_ratio = 0.8,
        retry = true,
        on_complete = function(progress)
            logger.info("HeroAssetPreload", "complete ready="
                .. tostring(progress.ready) .. " failed="
                .. tostring(progress.failed) .. " total="
                .. tostring(progress.total))
        end,
    })
    if not ok then preload_started = false end
    return ok, status, snapshot
end

function M.request(hero_id, callbacks)
    callbacks = callbacks or {}
    local asset_id = asset_id_for(hero_id)
    if not asset_id then
        collect_asset_ids()
        asset_id = asset_id_for(hero_id)
    end
    if not asset_id then return false, "hero_asset_missing" end
    return asset_preload.queue(asset_id, {
        urgent = true,
        retry = true,
        on_ready = callbacks.on_ready,
        on_failed = callbacks.on_failed,
    })
end

function M.status(hero_id)
    local asset_id = asset_id_for(hero_id)
    if not asset_id then
        collect_asset_ids()
        asset_id = asset_id_for(hero_id)
    end
    if not asset_id then return asset_preload.STATE.FAILED end
    return asset_preload.status(asset_id).status
end

function M.is_ready(hero_id)
    return M.status(hero_id) == asset_preload.STATE.READY
end

function M.init()
    hero_to_asset = {}
    preload_started = false
    collect_asset_ids()
    event_bus.subscribe(events.GAME_STARTED, function()
        local ok, status = M.start()
        if not ok then
            logger.warn("HeroAssetPreload", "startup failed: " .. tostring(status))
        end
    end)
end

M.SESSION_ID = SESSION_ID
M.DEFAULT_DURATION_SECONDS = DEFAULT_DURATION_SECONDS

return M