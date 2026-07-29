local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local logger = require("core/logger")
local catalog = require("config/asset_catalog")

local M = {}

local STATE = {
    NOT_REQUESTED = "not_requested",
    QUEUED = "queued",
    LOADING = "loading",
    READY = "ready",
    FAILED = "failed",
    RETIRED = "retired",
}

local STREAM_INITIAL_DELAY = 60
local STREAM_BATCH_INTERVAL = 60
local STREAM_BATCH_SIZE = 4
local INTER_ASSET_DELAY = 1

local states = {}
local initial_states = {}
local ready_callbacks = {}
local failed_callbacks = {}
local queue = {}
local queued = {}
local loading = false
local stream_cursor = 1
local stream_rows = {}
local generation = 0

local function now()
    return GameRules and GameRules.GetGameTime and GameRules:GetGameTime() or 0
end

local function set_state(asset_id, status, extra)
    local entry = states[asset_id] or {}
    entry.status = status
    for key, value in pairs(extra or {}) do entry[key] = value end
    states[asset_id] = entry
    return entry
end

local function precache_initial_resource(resource_type, path, context)
    if type(path) ~= "string" or path == "" then return true end
    local ok, error_message = pcall(
        PrecacheResource,
        resource_type,
        path,
        context
    )
    if not ok then
        logger.warn("AssetPreload", "initial resource failed type="
            .. tostring(resource_type) .. " path=" .. tostring(path)
            .. " error=" .. tostring(error_message))
    end
    return ok
end

local function precache_initial_row(row, context)
    local ok = precache_initial_resource("model", row.primary_model, context)
    for _, path in ipairs(row.attachment_models or {}) do
        ok = precache_initial_resource("model", path, context) and ok
    end
    for _, path in ipairs(row.particle_resources or {}) do
        ok = precache_initial_resource("particle", path, context) and ok
    end
    for _, path in ipairs(row.sound_resources or {}) do
        ok = precache_initial_resource("soundfile", path, context) and ok
    end
    local state = set_state(row.asset_id, ok and STATE.READY or STATE.FAILED, {
        completed_at = now(),
        source = "initial",
    })
    initial_states[row.asset_id] = state
end

function M.precache_initial(context)
    for _, row in ipairs(catalog.group("initial_required")) do
        precache_initial_row(row, context)
    end
end

local function sort_queue()
    table.sort(queue, function(a, b)
        if a.urgent ~= b.urgent then return a.urgent == true end
        if a.priority ~= b.priority then return a.priority > b.priority end
        if a.queued_at ~= b.queued_at then return a.queued_at < b.queued_at end
        return a.asset_id < b.asset_id
    end)
end

local function finish(asset_id, ok, source)
    loading = false
    queued[asset_id] = nil
    local started_at = (states[asset_id] or {}).started_at or now()
    set_state(asset_id, ok and STATE.READY or STATE.FAILED, {
        completed_at = now(),
        elapsed = math.max(0, now() - started_at),
        source = source,
    })
    logger.info("AssetPreload", string.format(
        "%s id=%s elapsed=%.2f",
        ok and "ready" or "failed",
        asset_id,
        math.max(0, now() - started_at)
    ))
    local callbacks = ready_callbacks[asset_id] or {}
    ready_callbacks[asset_id] = nil
    local failures = failed_callbacks[asset_id] or {}
    failed_callbacks[asset_id] = nil
    if ok then
        for _, callback in ipairs(callbacks) do
            local callback_ok, callback_error = pcall(callback)
            if not callback_ok then
                logger.warn("AssetPreload", "ready callback failed id="
                    .. tostring(asset_id) .. " error=" .. tostring(callback_error))
            end
        end
    else
        for _, callback in ipairs(failures) do
            local callback_ok, callback_error = pcall(callback, source)
            if not callback_ok then
                logger.warn("AssetPreload", "failed callback failed id="
                    .. tostring(asset_id) .. " error=" .. tostring(callback_error))
            end
        end
    end
    scheduler.after(INTER_ASSET_DELAY, function() M._pump() end,
        "asset_preload_pump")
end

function M._pump()
    if loading or #queue == 0 then return end
    sort_queue()
    local request = table.remove(queue, 1)
    local row = catalog.resolve(request.asset_id)
    if not row then
        finish(request.asset_id, false, "catalog_missing")
        return
    end
    if (states[row.asset_id] or {}).status == STATE.READY then
        queued[request.asset_id] = nil
        M._pump()
        return
    end

    loading = true
    set_state(request.asset_id, STATE.LOADING, { started_at = now() })
    logger.info("AssetPreload", "started id=" .. request.asset_id)

    local async_name = row.async_unit_name
    local request_generation = generation
    if type(PrecacheUnitByNameAsync) == "function"
        and type(async_name) == "string" and async_name ~= "" then
        local ok, error_message = pcall(
            PrecacheUnitByNameAsync,
            async_name,
            function()
                if request_generation == generation then
                    finish(request.asset_id, true, "unit_async")
                end
            end,
            -1
        )
        if ok then return end
        logger.warn("AssetPreload", "async request failed id="
            .. request.asset_id .. " error=" .. tostring(error_message))
    end

    -- No safe runtime model-unload/precache-context API is available. Mark the
    -- request failed so callers keep their current/fallback visual.
    finish(request.asset_id, false, "async_unavailable")
end

function M.queue(asset_id, options)
    options = options or {}
    local row = catalog.resolve(asset_id)
    if not row then return false, "asset_not_found" end
    local state = states[asset_id]
    if state and state.status == STATE.READY then
        if type(options.on_ready) == "function" then pcall(options.on_ready) end
        return true, state.status
    end
    if state and state.status == STATE.RETIRED then
        return false, state.status
    end
    if state and state.status == STATE.FAILED and not options.retry then
        return false, state.status
    end
    if type(options.on_ready) == "function" then
        ready_callbacks[asset_id] = ready_callbacks[asset_id] or {}
        table.insert(ready_callbacks[asset_id], options.on_ready)
    end
    if type(options.on_failed) == "function" then
        failed_callbacks[asset_id] = failed_callbacks[asset_id] or {}
        table.insert(failed_callbacks[asset_id], options.on_failed)
    end
    if state and state.status == STATE.LOADING then
        return true, state.status
    end
    if queued[asset_id] then
        if options.urgent then queued[asset_id].urgent = true end
        return true, STATE.QUEUED
    end
    local request = {
        asset_id = asset_id,
        priority = tonumber(options.priority) or tonumber(row.priority) or 0,
        urgent = options.urgent == true,
        queued_at = now(),
    }
    queued[asset_id] = request
    table.insert(queue, request)
    set_state(asset_id, STATE.QUEUED, { queued_at = request.queued_at })
    logger.info("AssetPreload", "queued id=" .. asset_id
        .. " urgent=" .. tostring(request.urgent))
    M._pump()
    local current_status = (states[asset_id] or {}).status or STATE.QUEUED
    if current_status == STATE.FAILED then return false, current_status end
    return true, current_status
end

function M.queue_model(model_path, options)
    local row = catalog.for_model(model_path)
    if not row then return false, "model_asset_not_registered" end
    return M.queue(row.asset_id, options)
end

function M.queue_particle(particle_path, options)
    if type(particle_path) ~= "string" or particle_path == "" then
        return true, "particle_empty"
    end
    local row = catalog.for_particle(particle_path)
    if not row then return false, "particle_asset_not_registered" end
    return M.queue(row.asset_id, options)
end

function M.is_ready(asset_id)
    return (states[asset_id] or {}).status == STATE.READY
end

function M.status(asset_id)
    local state = states[asset_id] or { status = STATE.NOT_REQUESTED }
    local copy = {}
    for key, value in pairs(state) do copy[key] = value end
    return copy
end

function M.retire(asset_id)
    if not catalog.by_id[asset_id] then return false end
    queued[asset_id] = nil
    ready_callbacks[asset_id] = nil
    failed_callbacks[asset_id] = nil
    for index = #queue, 1, -1 do
        if queue[index].asset_id == asset_id then table.remove(queue, index) end
    end
    set_state(asset_id, STATE.RETIRED, { retired_at = now() })
    return true
end

local function queue_stream_batch()
    local added = 0
    while stream_cursor <= #stream_rows and added < STREAM_BATCH_SIZE do
        local row = stream_rows[stream_cursor]
        stream_cursor = stream_cursor + 1
        M.queue(row.asset_id)
        added = added + 1
    end
    logger.info("AssetPreload", "stream batch added=" .. tostring(added)
        .. " remaining=" .. tostring(math.max(0, #stream_rows - stream_cursor + 1)))
    if stream_cursor > #stream_rows then return false end
    return STREAM_BATCH_INTERVAL
end

function M.init()
    generation = generation + 1
    states = {}
    for asset_id, state in pairs(initial_states) do
        states[asset_id] = state
    end
    queue = {}
    queued = {}
    ready_callbacks = {}
    failed_callbacks = {}
    loading = false
    stream_cursor = 1
    stream_rows = catalog.group("zombie_stream")
    table.sort(stream_rows, function(a, b)
        local a_wave = tonumber(a.first_use_wave) or math.huge
        local b_wave = tonumber(b.first_use_wave) or math.huge
        if a_wave ~= b_wave then return a_wave < b_wave end
        local a_order = tonumber(a.load_order) or math.huge
        local b_order = tonumber(b.load_order) or math.huge
        return a_order < b_order
    end)
    for _, row in ipairs(catalog.group("tower_stream")) do
        table.insert(stream_rows, row)
    end
    for _, row in ipairs(catalog.group("wall_stream")) do
        table.insert(stream_rows, row)
    end
    event_bus.subscribe(events.GAME_STARTED, function()
        scheduler.after(STREAM_INITIAL_DELAY, queue_stream_batch,
            "asset_stream_batch")
    end)
    logger.info("AssetPreload", "initialized stream_assets="
        .. tostring(#stream_rows) .. " batch_size=" .. tostring(STREAM_BATCH_SIZE))
end

M.STATE = STATE
M._queue_stream_batch_for_test = queue_stream_batch
M._reset_for_test = M.init
M._snapshot_for_test = function()
    local callback_count = 0
    for _, callbacks in pairs(ready_callbacks) do
        callback_count = callback_count + #callbacks
    end
    for _, callbacks in pairs(failed_callbacks) do
        callback_count = callback_count + #callbacks
    end
    return {
        loading = loading,
        queued_count = #queue,
        ready_callback_count = callback_count,
        stream_cursor = stream_cursor,
        stream_total = #stream_rows,
    }
end

return M