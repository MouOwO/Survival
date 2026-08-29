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
local resource_states = {}
local initial_resource_states = {}
local ready_callbacks = {}
local failed_callbacks = {}
local queue = {}
local queued = {}
local background_loading_asset_id = nil
local inflight = {}
local gradual_sessions = {}
local stream_cursor = 1
local stream_rows = {}
local generation = 0
local gradual_snapshot
local gradual_asset_finished
local begin_async_request

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

local function set_resource_state(resource_type, path, status)
    if type(path) ~= "string" or path == "" then return end
    local key = tostring(resource_type) .. ":" .. path
    resource_states[key] = status
    return key
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

local function precache_row_resources(row, context, mark_asset_ready)
    local ok = precache_initial_resource("model", row.primary_model, context)
    for _, path in ipairs(row.attachment_models or {}) do
        ok = precache_initial_resource("model", path, context) and ok
    end
    for _, component in ipairs(row.components or {}) do
        ok = precache_initial_resource("model", component.model_path, context) and ok
    end
    for _, path in ipairs(row.particle_resources or {}) do
        ok = precache_initial_resource("particle", path, context) and ok
    end
    for _, path in ipairs(row.sound_resources or {}) do
        ok = precache_initial_resource("soundfile", path, context) and ok
    end
    local status = ok and STATE.READY or STATE.FAILED
    local function remember(resource_type, path)
        local key = set_resource_state(resource_type, path, status)
        if key then initial_resource_states[key] = status end
    end
    remember("model", row.primary_model)
    for _, path in ipairs(row.attachment_models or {}) do
        remember("model", path)
    end
    for _, component in ipairs(row.components or {}) do
        remember("model", component.model_path)
    end
    for _, path in ipairs(row.particle_resources or {}) do
        remember("particle", path)
    end
    for _, path in ipairs(row.sound_resources or {}) do
        remember("soundfile", path)
    end
    if mark_asset_ready then
        local state = set_state(row.asset_id, status, {
            completed_at = now(),
            source = "initial",
        })
        initial_states[row.asset_id] = state
    end
    return ok
end

local function precache_initial_row(row, context)
    return precache_row_resources(row, context, true)
end

local function append_resource(result, seen, resource_type, path, asset_id,
        async_unit_name)
    path = tostring(path or "")
    local key = resource_type .. ":" .. path
    if path == "" or seen[key] then return end
    seen[key] = true
    result[#result + 1] = {
        resource_type = resource_type,
        path = path,
        asset_id = asset_id,
        async_unit_name = async_unit_name,
    }
end

local function append_asset_resources(result, seen, asset)
    if not asset then return end
    append_resource(result, seen, "model", asset.primary_model,
        asset.asset_id, asset.async_unit_name)
    for _, path in ipairs(asset.attachment_models or {}) do
        append_resource(result, seen, "model", path)
    end
    for _, component in ipairs(asset.components or {}) do
        append_resource(result, seen, "model", component.model_path)
    end
    for _, path in ipairs(asset.particle_resources or {}) do
        append_resource(result, seen, "particle", path)
    end
    for _, path in ipairs(asset.sound_resources or {}) do
        append_resource(result, seen, "soundfile", path)
    end
end

function M.resources_for_models(model_paths, extra_resources)
    local result = {}
    local seen = {}
    for _, model_path in ipairs(model_paths or {}) do
        local asset = catalog.for_model(model_path)
        if asset then
            append_asset_resources(result, seen, asset)
        else
            append_resource(result, seen, "model", model_path)
        end
    end
    for _, resource in ipairs(extra_resources or {}) do
        append_resource(result, seen, resource.resource_type, resource.path,
            resource.asset_id, resource.async_unit_name)
    end
    return result
end

function M.precache_initial(context)
    for _, row in ipairs(catalog.group("initial_required")) do
        precache_initial_row(row, context)
    end
end

function M.precache_group(context, group_name)
    for _, row in ipairs(catalog.group(group_name)) do
        precache_row_resources(row, context, false)
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
    local was_background = background_loading_asset_id == asset_id
    if was_background then background_loading_asset_id = nil end
    inflight[asset_id] = nil
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
    if gradual_asset_finished then
        gradual_asset_finished(asset_id, ok, source)
    end
    if was_background then
        scheduler.after(INTER_ASSET_DELAY, function() M._pump() end,
            "asset_preload_pump")
    end
end

local function protected_callback(label, callback, ...)
    if type(callback) ~= "function" then return end
    local ok, error_message = pcall(callback, ...)
    if not ok then
        logger.warn("AssetPreload", label .. " callback failed error="
            .. tostring(error_message))
    end
end

local function remove_queued_request(asset_id)
    queued[asset_id] = nil
    for index = #queue, 1, -1 do
        if queue[index].asset_id == asset_id then
            table.remove(queue, index)
        end
    end
end

gradual_snapshot = function(session)
    local pending = 0
    for _ in pairs(session.pending or {}) do pending = pending + 1 end
    return {
        session_id = session.session_id,
        total = session.total,
        ready = session.ready,
        failed = session.failed,
        pending = pending,
        dispatched = session.dispatched,
        dispatch_total = session.dispatch_total,
        dispatch_complete = session.dispatch_complete == true,
        window_complete = session.window_complete == true,
        running = session.complete ~= true,
        started_at = session.started_at,
        duration_seconds = session.duration_seconds,
    }
end

local function complete_gradual_session(session)
    if session.complete then return end
    for _ in pairs(session.pending) do return end
    session.complete = true
    session.completed_at = now()
    logger.info("AssetPreload", "gradual complete id=" .. session.session_id
        .. " ready=" .. tostring(session.ready)
        .. " failed=" .. tostring(session.failed))
    protected_callback(
        "gradual complete",
        session.on_complete,
        gradual_snapshot(session)
    )
end

gradual_asset_finished = function(asset_id, ok, source)
    for _, session in pairs(gradual_sessions) do
        if not session.complete and session.pending[asset_id] then
            session.pending[asset_id] = nil
            if ok then
                session.ready = session.ready + 1
            else
                session.failed = session.failed + 1
                session.last_error = source
            end
            complete_gradual_session(session)
        end
    end
end

local function dispatch_gradual_asset(session, asset_id)
    if session.complete or not session.pending[asset_id] then return end

    session.dispatched = session.dispatched + 1
    if session.dispatched >= session.dispatch_total then
        session.dispatch_complete = true
        protected_callback(
            "gradual dispatched",
            session.on_dispatched,
            gradual_snapshot(session)
        )
    end

    local status = (states[asset_id] or {}).status
    if status == STATE.READY then
        gradual_asset_finished(asset_id, true, "already_ready")
        return
    end
    if inflight[asset_id] then return end
    if status == STATE.RETIRED then
        gradual_asset_finished(asset_id, false, STATE.RETIRED)
        return
    end

    remove_queued_request(asset_id)
    if status == STATE.FAILED and not session.retry then
        gradual_asset_finished(asset_id, false, STATE.FAILED)
        return
    end
    if status == STATE.FAILED then
        set_state(asset_id, STATE.NOT_REQUESTED, { retried_at = now() })
    end
    begin_async_request(asset_id, "gradual:" .. session.session_id)
end

function M.preload_gradually(asset_ids, options)
    options = options or {}
    local session_id = tostring(options.session_id or "default")
    local existing = gradual_sessions[session_id]
    if existing and not existing.complete then
        return true, "already_running", gradual_snapshot(existing)
    end

    local unique_ids = {}
    local seen = {}
    for _, raw_asset_id in ipairs(asset_ids or {}) do
        local asset_id = tostring(raw_asset_id or "")
        if asset_id ~= "" and not seen[asset_id] then
            if not catalog.resolve(asset_id) then
                return false, "asset_not_found:" .. asset_id
            end
            seen[asset_id] = true
            table.insert(unique_ids, asset_id)
        end
    end

    local duration = math.max(0, tonumber(options.duration_seconds) or 10)
    local dispatch_ratio = math.max(0, math.min(
        1,
        tonumber(options.dispatch_ratio) or 0.8
    ))
    local session = {
        session_id = session_id,
        total = #unique_ids,
        ready = 0,
        failed = 0,
        dispatched = 0,
        dispatch_total = 0,
        dispatch_complete = false,
        window_complete = false,
        complete = false,
        pending = {},
        started_at = now(),
        duration_seconds = duration,
        retry = options.retry == true,
        on_dispatched = options.on_dispatched,
        on_complete = options.on_complete,
        on_window_complete = options.on_window_complete,
    }
    gradual_sessions[session_id] = session

    local dispatch_ids = {}
    for _, asset_id in ipairs(unique_ids) do
        local status = (states[asset_id] or {}).status
        if status == STATE.READY then
            session.ready = session.ready + 1
        elseif status == STATE.RETIRED then
            session.failed = session.failed + 1
        else
            session.pending[asset_id] = true
            table.insert(dispatch_ids, asset_id)
        end
    end
    session.dispatch_total = #dispatch_ids

    if session.dispatch_total == 0 then
        session.dispatch_complete = true
        protected_callback(
            "gradual dispatched",
            session.on_dispatched,
            gradual_snapshot(session)
        )
        complete_gradual_session(session)
        return true, "complete", gradual_snapshot(session)
    end

    local dispatch_window = duration * dispatch_ratio
    local divisor = math.max(1, session.dispatch_total - 1)
    for index, asset_id in ipairs(dispatch_ids) do
        local delay = (index - 1) * dispatch_window / divisor
        if delay <= 0 then
            dispatch_gradual_asset(session, asset_id)
        else
            scheduler.after(delay, function()
                dispatch_gradual_asset(session, asset_id)
            end, "asset_gradual:" .. session_id .. ":" .. tostring(index))
        end
    end
    scheduler.after(duration, function()
        if gradual_sessions[session_id] ~= session then return end
        session.window_complete = true
        protected_callback(
            "gradual window",
            session.on_window_complete,
            gradual_snapshot(session)
        )
    end, "asset_gradual_window:" .. session_id)

    logger.info("AssetPreload", "gradual started id=" .. session_id
        .. " total=" .. tostring(session.total)
        .. " dispatch=" .. tostring(session.dispatch_total)
        .. " duration=" .. tostring(duration))
    return true, "started", gradual_snapshot(session)
end

function M.gradual_status(session_id)
    local session = gradual_sessions[tostring(session_id or "default")]
    return session and gradual_snapshot(session) or nil
end

begin_async_request = function(asset_id, request_source)
    local row = catalog.resolve(asset_id)
    if not row then
        finish(asset_id, false, "catalog_missing")
        return false
    end

    inflight[asset_id] = request_source or "background"
    set_state(asset_id, STATE.LOADING, { started_at = now() })
    logger.info("AssetPreload", "started id=" .. asset_id
        .. " source=" .. tostring(request_source or "background"))

    local resources = {}
    append_asset_resources(resources, {}, row)
    logger.info("AssetPreload", "expanded id=" .. asset_id
        .. " resources=" .. tostring(#resources)
        .. " components=" .. tostring(#(row.components or {}))
        .. " effects=" .. tostring(#(row.effects or {})))
    local resource_keys = {}
    for _, resource in ipairs(resources) do
        local resource_key = tostring(resource.resource_type) .. ":"
            .. tostring(resource.path)
        if initial_resource_states[resource_key] == STATE.FAILED then
            logger.warn("AssetPreload", "startup resource unavailable id="
                .. asset_id .. " type=" .. tostring(resource.resource_type)
                .. " path=" .. tostring(resource.path))
            finish(asset_id, false, "resource_precache_failed")
            return false
        end
        resource_keys[#resource_keys + 1] = set_resource_state(
            resource.resource_type,
            resource.path,
            STATE.LOADING
        )
    end

    local async_name = row.async_unit_name
    local request_generation = generation
    if type(PrecacheUnitByNameAsync) == "function"
        and type(async_name) == "string" and async_name ~= "" then
        local ok, error_message = pcall(
            PrecacheUnitByNameAsync,
            async_name,
            function()
                if request_generation == generation then
                    for _, key in ipairs(resource_keys) do
                        resource_states[key] = STATE.READY
                    end
                    finish(asset_id, true, "unit_async")
                end
            end,
            -1
        )
        if ok then return true end
        logger.warn("AssetPreload", "async request failed id="
            .. asset_id .. " error=" .. tostring(error_message))
    end

    -- No safe runtime model-unload/precache-context API is available. Mark the
    -- request failed so callers keep their current/fallback visual.
    finish(asset_id, false, "async_unavailable")
    return false
end

function M._pump()
    if background_loading_asset_id or #queue == 0 then return end
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

    background_loading_asset_id = request.asset_id
    begin_async_request(request.asset_id, "background")
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
        if options.urgent then
            -- A formal wave can be only a few seconds away. Do not leave its
            -- exact-model proxy behind the minute-based tower/wall stream.
            remove_queued_request(asset_id)
            local started = begin_async_request(asset_id, "urgent")
            local current_status = (states[asset_id] or {}).status
                or STATE.LOADING
            return started, current_status
        end
        return true, STATE.QUEUED
    end
    local request = {
        asset_id = asset_id,
        priority = tonumber(options.priority) or tonumber(row.priority) or 0,
        urgent = options.urgent == true,
        queued_at = now(),
    }
    queued[asset_id] = request
    set_state(asset_id, STATE.QUEUED, { queued_at = request.queued_at })
    logger.info("AssetPreload", "queued id=" .. asset_id
        .. " urgent=" .. tostring(request.urgent))
    if request.urgent then
        local started = begin_async_request(asset_id, "urgent")
        local current_status = (states[asset_id] or {}).status
            or STATE.LOADING
        if not started then return false, current_status end
        return true, current_status
    end
    table.insert(queue, request)
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

function M.queue_resources(resources, options)
    options = options or {}
    local queued_count = 0
    local failed_count = 0
    local seen_resources = {}
    local resources_by_asset = {}
    local direct_resources = {}
    for _, resource in ipairs(resources or {}) do
        local resource_type = tostring(resource.resource_type or "")
        local path = tostring(resource.path or "")
        local resource_key = resource_type .. ":" .. path
        local status = resource_states[resource_key]
        if path ~= "" and not seen_resources[resource_key]
            and status ~= STATE.READY and status ~= STATE.LOADING then
            seen_resources[resource_key] = true
            local asset = resource.asset_id and catalog.resolve(resource.asset_id)
                or (resource_type == "model" and catalog.for_model(path))
                or nil
            local asset_id = asset and asset.asset_id or nil
            if asset_id then
                resources_by_asset[asset_id] = resources_by_asset[asset_id] or {}
                resources_by_asset[asset_id][#resources_by_asset[asset_id] + 1]
                    = resource_key
            else
                direct_resources[#direct_resources + 1] = {
                    key = resource_key,
                    resource_type = resource_type,
                    async_unit_name = resource.async_unit_name,
                }
            end
        end
    end
    for asset_id, resource_keys in pairs(resources_by_asset) do
        for _, key in ipairs(resource_keys) do
            resource_states[key] = STATE.LOADING
        end
        local request_options = {}
        for key, value in pairs(options) do request_options[key] = value end
        request_options.on_ready = function()
            for _, key in ipairs(resource_keys) do
                resource_states[key] = STATE.READY
            end
            protected_callback("resource ready", options.on_ready, asset_id)
        end
        request_options.on_failed = function(reason)
            for _, key in ipairs(resource_keys) do
                resource_states[key] = STATE.FAILED
            end
            protected_callback("resource failed", options.on_failed,
                asset_id, reason)
        end
        local ok = M.queue(asset_id, request_options)
        if ok then
            queued_count = queued_count + 1
        else
            for _, key in ipairs(resource_keys) do
                resource_states[key] = STATE.FAILED
            end
            failed_count = failed_count + 1
        end
    end
    for _, resource in ipairs(direct_resources) do
        local async_name = tostring(resource.async_unit_name or "")
        if resource.resource_type == "model" and async_name ~= ""
            and type(PrecacheUnitByNameAsync) == "function" then
            resource_states[resource.key] = STATE.LOADING
            local request_generation = generation
            local ok = pcall(PrecacheUnitByNameAsync, async_name, function()
                if request_generation == generation then
                    resource_states[resource.key] = STATE.READY
                end
            end, -1)
            if ok then
                queued_count = queued_count + 1
            else
                resource_states[resource.key] = STATE.FAILED
                failed_count = failed_count + 1
            end
        elseif resource.resource_type == "model"
            or resource.resource_type == "particle"
            or resource.resource_type == "soundfile" then
            resource_states[resource.key] = STATE.FAILED
            failed_count = failed_count + 1
        else
            resource_states[resource.key] = STATE.FAILED
            failed_count = failed_count + 1
        end
    end
    if failed_count > 0 then
        return false, "resource_queue_failed", queued_count, failed_count
    end
    return true, queued_count > 0 and "queued" or "ready", queued_count, 0
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

function M.resource_status(resource_type, path)
    local key = tostring(resource_type or "") .. ":" .. tostring(path or "")
    return resource_states[key] or STATE.NOT_REQUESTED
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
    resource_states = {}
    for key, status in pairs(initial_resource_states) do
        resource_states[key] = status
    end
    queue = {}
    queued = {}
    ready_callbacks = {}
    failed_callbacks = {}
    background_loading_asset_id = nil
    inflight = {}
    gradual_sessions = {}
    stream_cursor = 1
    stream_rows = {}
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
        loading = background_loading_asset_id ~= nil,
        inflight_count = (function()
            local count = 0
            for _ in pairs(inflight) do count = count + 1 end
            return count
        end)(),
        queued_count = #queue,
        ready_callback_count = callback_count,
        stream_cursor = stream_cursor,
        stream_total = #stream_rows,
        resource_state_count = (function()
            local count = 0
            for _ in pairs(resource_states) do count = count + 1 end
            return count
        end)(),
    }
end

return M