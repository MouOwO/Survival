local definition_sources = {
    require("config/generated/building_sound_definitions"),
    require("config/generated/hero_skill_sound_definitions"),
    require("config/generated/tower_skill_sound_definitions"),
    require("config/generated/worker_sound_definitions"),
}

local definitions = { rows = {}, by_id = {} }
for _, source in ipairs(definition_sources) do
    for _, row in ipairs(source.rows or {}) do
        definitions.rows[#definitions.rows + 1] = row
    end
    for cue_id, row in pairs(source.by_id or {}) do
        assert(definitions.by_id[cue_id] == nil,
            "duplicate sound cue across definitions: " .. tostring(cue_id))
        definitions.by_id[cue_id] = row
    end
end

local M = {}
local last_played = {}
local play_windows = {}
local active_plays = {}
local active_loops = {}

local function game_time()
    if GameRules and GameRules.GetGameTime then
        return tonumber(GameRules:GetGameTime()) or 0
    end
    return 0
end

local function valid_entity(entity)
    if not entity then return false end
    if entity.IsNull then
        local ok, is_null = pcall(function() return entity:IsNull() end)
        if not ok or is_null then return false end
    end
    return true
end

local function entity_key(entity)
    if valid_entity(entity) and entity.entindex then
        local ok, index = pcall(function() return entity:entindex() end)
        if ok and index ~= nil then return tostring(index) end
    end
    return tostring(entity or "global")
end

local function cue(cue_id)
    local row = (definitions.by_id or {})[tostring(cue_id or "")]
    local has_events = row and ((row.sound_event and row.sound_event ~= "")
        or (type(row.sound_events) == "table" and #row.sound_events > 0))
    if not row or row.enabled == false or not has_events then return nil end
    return row
end

local function sound_events(row)
    if type(row.sound_events) == "table" and #row.sound_events > 0 then
        return row.sound_events
    end
    return { row.sound_event }
end

local function sound_resources(row)
    if type(row.sound_resources) == "table" and #row.sound_resources > 0 then
        return row.sound_resources
    end
    return { row.sound_resource }
end

local function limiter_key(row, source, limiter_scope)
    local scope_key = limiter_scope ~= nil and tostring(limiter_scope)
        or entity_key(source)
    return tostring(row.cooldown_group or row.cue_id) .. ":" .. scope_key
end

local function allowed(row, source, now, limiter_scope)
    local key = limiter_key(row, source, limiter_scope)
    local previous_window = play_windows[key]
    local previous_active = active_plays[key]
    local reservation = {
        key = key,
        last_played = last_played[key],
        window = previous_window and {
            started_at = previous_window.started_at,
            count = previous_window.count,
        } or false,
        active = {},
    }
    for _, expires_at in ipairs(previous_active or {}) do
        reservation.active[#reservation.active + 1] = expires_at
    end
    local cooldown = math.max(0, tonumber(row.cooldown_seconds) or 0)
    local previous = last_played[key]
    if previous and now + 0.0001 < previous + cooldown then
        return false, nil
    end

    local window_seconds = math.max(0, tonumber(row.window_seconds) or 0)
    local maximum = math.max(0, math.floor(
        (tonumber(row.max_plays_per_window) or 0) + 0.001
    ))
    if window_seconds > 0 and maximum > 0 then
        local window = play_windows[key]
        if not window or now + 0.0001 >= window.started_at + window_seconds then
            window = { started_at = now, count = 0 }
            play_windows[key] = window
        end
        if window.count >= maximum then return false, nil end
    end

    local concurrency_seconds = math.max(
        0, tonumber(row.concurrency_seconds) or 0
    )
    local max_concurrent = math.max(0, math.floor(
        (tonumber(row.max_concurrent) or 0) + 0.001
    ))
    local active = active_plays[key] or {}
    local retained = {}
    for _, expires_at in ipairs(active) do
        if now + 0.0001 < expires_at then
            retained[#retained + 1] = expires_at
        end
    end
    if concurrency_seconds > 0 and max_concurrent > 0
        and #retained >= max_concurrent then
        active_plays[key] = retained
        return false, nil
    end

    local window = play_windows[key]
    if window_seconds > 0 and maximum > 0 and window then
        window.count = window.count + 1
    end
    if concurrency_seconds > 0 and max_concurrent > 0 then
        retained[#retained + 1] = now + concurrency_seconds
        active_plays[key] = retained
    else
        active_plays[key] = nil
    end
    last_played[key] = now
    return true, reservation
end

local function rollback(reservation)
    if not reservation then return end
    local key = reservation.key
    last_played[key] = reservation.last_played
    play_windows[key] = reservation.window or nil
    active_plays[key] = #reservation.active > 0 and reservation.active or nil
end

local function emit_on_unit(sound_event, unit)
    if not valid_entity(unit) then return false end
    if unit.EmitSound then
        unit:EmitSound(sound_event)
        return true
    end
    if EmitSoundOn then
        EmitSoundOn(sound_event, unit)
        return true
    end
    return false
end

local function emit_at_position(sound_event, position, source)
    if not position or not valid_entity(source)
        or not EmitSoundOnLocationWithCaster then return false end
    EmitSoundOnLocationWithCaster(position, sound_event, source)
    return true
end

function M.get(cue_id)
    return cue(cue_id)
end

function M.play(cue_id, options)
    local row = cue(cue_id)
    if not row then return false, "unknown_cue" end
    if row.playback_mode == "loop" then return false, "loop_requires_lifecycle" end
    options = options or {}
    local source = options.source or options.unit
    local now = game_time()
    local accepted, reservation = allowed(row, source, now, options.limiter_scope)
    if not accepted then return false, "limited" end

    local ok, played = pcall(function()
        for _, sound_event in ipairs(sound_events(row)) do
            local played
            if row.attach_scope == "position" and options.position then
                played = emit_at_position(sound_event, options.position, source)
            else
                played = emit_on_unit(sound_event, options.unit or source)
            end
            if not played then return false end
        end
        return true
    end)
    if not ok or not played then
        -- Failed engine calls must not consume a cooldown in tests or during
        -- transient entity teardown.
        rollback(reservation)
        if not ok then
            print("[SoundService] play failed cue=" .. tostring(cue_id)
                .. " error=" .. tostring(played))
        end
        return false, ok and "emitter_unavailable" or "emit_failed"
    end
    return true
end

function M.start_loop(cue_id, lifecycle_key, unit)
    local row = cue(cue_id)
    lifecycle_key = tostring(lifecycle_key or "")
    if not row or row.playback_mode ~= "loop" or lifecycle_key == ""
        or not valid_entity(unit) then return false end
    M.stop_loop(lifecycle_key)
    local ok, played = pcall(emit_on_unit, row.sound_event, unit)
    if not ok or not played then return false end
    active_loops[lifecycle_key] = { event = row.sound_event, unit = unit }
    return true
end

function M.stop_loop(lifecycle_key)
    lifecycle_key = tostring(lifecycle_key or "")
    local active = active_loops[lifecycle_key]
    if not active then return false end
    active_loops[lifecycle_key] = nil
    if valid_entity(active.unit) then
        pcall(function()
            if active.unit.StopSound then
                active.unit:StopSound(active.event)
            elseif StopSoundOn then
                StopSoundOn(active.event, active.unit)
            end
        end)
    end
    return true
end

function M.reset()
    local keys = {}
    for key, _ in pairs(active_loops) do keys[#keys + 1] = key end
    for _, key in ipairs(keys) do M.stop_loop(key) end
    last_played = {}
    play_windows = {}
    active_plays = {}
    active_loops = {}
end

function M.init()
    M.reset()
end

function M.precache(context)
    if not PrecacheResource then return 0 end
    local seen = {}
    local count = 0
    for _, row in ipairs(definitions.rows or {}) do
        if row.enabled ~= false then
            for _, resource in ipairs(sound_resources(row)) do
                if resource and resource ~= "" and not seen[resource] then
                    PrecacheResource("soundfile", resource, context)
                    seen[resource] = true
                    count = count + 1
                end
            end
        end
    end
    return count
end

function M._snapshot_for_test()
    local loops = 0
    for _, _ in pairs(active_loops) do loops = loops + 1 end
    return { active_loops = loops }
end

return M