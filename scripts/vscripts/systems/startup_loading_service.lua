-- Server-owned startup barrier. Client messages acknowledge UI readiness only;
-- account authentication is established exclusively by the HTTP profile service.
local profiles = require("systems/player_profile_service")
local multiplayer = require("systems/multiplayer_player_service")
local assets = require("systems/startup_asset_preload_service")
local match_setup = require("systems/match_setup_service")

local M = {}
local generation, session_id, started_at = 0, "", 0
local initialized, released, gameplay_released = false, false, false
local party_waiting, load_start = false, nil
local party_departed = {}
local entries, callbacks, gameplay_callbacks, listeners = {}, {}, {}, {}
local asset_retry_error = nil
local options, latest = {}, { started = false, all_ready = false, phase = "loading", progress = 0, players = {} }

local function now()
    -- GameTime can remain frozen throughout custom setup.
    return type(Time) == "function" and Time() or os.clock()
end

local function new_session_id()
    -- Persisted pure-mode baselines must not collide after restarting Tools or
    -- the game server. DoUniqueString alone is only process-local uniqueness.
    local parts = { "survival", tostring(generation) }
    if os and type(os.time) == "function" then parts[#parts + 1] = tostring(os.time()) end
    if type(GetSystemDate) == "function" then parts[#parts + 1] = tostring(GetSystemDate()) end
    if type(GetSystemTime) == "function" then parts[#parts + 1] = tostring(GetSystemTime()) end
    if type(RandomInt) == "function" then
        for _ = 1, 4 do parts[#parts + 1] = string.format("%08x", RandomInt(0, 2147483647)) end
    end
    parts[#parts + 1] = type(DoUniqueString) == "function" and DoUniqueString("startup")
        or tostring(now())
    return string.sub(string.gsub(table.concat(parts, "_"), "[^A-Za-z0-9_.:-]", ""), 1, 128)
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function player_id(value)
    value = tonumber(value)
    if not value or value ~= value or value < 0 or value ~= math.floor(value) or value > 255 then return nil end
    return value
end

local function resource(method, id)
    if not PlayerResource or type(PlayerResource[method]) ~= "function" then return nil end
    local ok, result = pcall(PlayerResource[method], PlayerResource, id)
    return ok and result or nil
end

local function human(id)
    if not resource("IsValidPlayerID", id) then return false end
    if resource("IsFakeClient", id) then return false end
    local team = resource("GetTeam", id)
    if team == (DOTA_TEAM_SPECTATOR or 1) then return false end
    return true
end

local function connected(id)
    if multiplayer.is_disconnected(id) then return false end
    if not resource("GetPlayer", id) then return false end
    local state = resource("GetConnectionState", id)
    return state == nil or state == (DOTA_CONNECTION_STATE_CONNECTED or 2)
end

local function lobby_roster_available()
    local minimum = tonumber(DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP)
    if not minimum or not GameRules or type(GameRules.State_Get) ~= "function" then return false end
    local ok, state = pcall(GameRules.State_Get, GameRules)
    state = ok and tonumber(state) or nil
    -- Before custom setup the first client's loading screen can already send
    -- its handshake, while other lobby humans have no PlayerResource slot yet.
    return state ~= nil and state >= minimum
end

local function discover()
    local found = {}
    for id = 0, (DOTA_MAX_TEAM_PLAYERS or 24) - 1 do found[id] = true end
    for _, id in ipairs(multiplayer.participating_player_ids()) do
        id = player_id(id)
        if id then found[id] = true end
    end
    for id in pairs(found) do
        if not entries[id] and human(id) and (not party_departed[id] or connected(id)) then
            entries[id] = { player_id = id, authenticated = false, client_ready = false,
                connected = false, ready = false, status = "connecting", next_retry = 0, attempt = 0 }
        end
    end
    -- Never remove a known human from the roster on disconnect/invalid slot.
end

local function actor(source)
    -- eventSourceIndex is a server-supplied player entity index, not a PlayerID.
    local index = tonumber(source)
    if not index or index < 0 or index ~= math.floor(index) or type(EntIndexToHScript) ~= "function" then return nil end
    local ok, entity = pcall(EntIndexToHScript, index)
    if not ok or not entity or type(entity.GetPlayerID) ~= "function" then return nil end
    if type(entity.IsNull) == "function" and entity:IsNull() then return nil end
    local resolved, id = pcall(entity.GetPlayerID, entity)
    id = resolved and player_id(id) or nil
    if id == nil or resource("GetPlayer", id) ~= entity or not human(id) or not connected(id) then return nil end
    return id
end

local function safe_error(reason)
    reason = tostring(reason or "")
    if reason:find("token_missing", 1, true) or reason:find("unauthorized", 1, true)
        or reason:find("http_status_401", 1, true) or reason:find("http_status_403", 1, true) then
        return "backend_authentication_failed"
    end
    return "profile_load_failed"
end

local function begin_load(entry, current)
    entry.attempt = entry.attempt + 1
    entry.last_attempt = current
    local attempt, epoch = entry.attempt, generation
    entry.inflight, entry.waiting_since, entry.force_retry = true, current, false
    entry.error, entry.status = nil, "authenticating"
    local function complete(reason)
        if generation ~= epoch or entries[entry.player_id] ~= entry or entry.attempt ~= attempt then return end
        entry.inflight, entry.waiting_since = false, nil
        entry.next_retry = now() + options.retry_seconds
        entry.error = reason and safe_error(reason) or nil
    end
    local completed = false
    local ok, result = pcall(profiles.authenticate_player, entry.player_id, "startup_admission", function(response)
        completed = true
        if type(response) == "table" and response.ok then complete(nil)
        else complete(type(response) == "table" and response.error or "profile_load_failed") end
    end)
    if not ok then complete("profile_load_failed")
    elseif type(result) ~= "table" then complete("profile_load_failed")
    elseif not result.pending and not completed then complete(not result.ok and result.error or nil) end
end

local function update_player(entry, current)
    local id = entry.player_id
    local online = human(id) and connected(id)
    if entry.connected and not online then entry.client_ready = false end
    entry.connected, entry.ready = online, false
    if not online then
        entry.status = (entry.ever_connected or multiplayer.is_disconnected(id)) and "disconnected" or "connecting"
        return
    end
    entry.ever_connected = true
    local steam = tonumber(resource("GetSteamAccountID", id))
    if not steam or steam <= 0 then entry.authenticated = false entry.status = "connecting" return end
    local account = string.format("%.0f", steam)
    if entry.account and entry.account ~= account then
        entry.authenticated, entry.client_ready, entry.status = false, false, "auth_error"
        entry.error = "player_identity_changed"
        return
    end
    entry.account = account -- Private; never included in published state.
    entry.authenticated = type(profiles.is_authenticated_for_account) == "function"
        and profiles.is_authenticated_for_account(id, account) == true
    if entry.authenticated then
        entry.inflight, entry.waiting_since, entry.error = false, nil, nil
        entry.status = entry.client_ready and "ready" or "client_loading"
        return
    end
    local pending = type(profiles.is_authenticating) == "function" and profiles.is_authenticating(id) or false
    if entry.inflight or pending then
        entry.waiting_since = entry.waiting_since or current
        if current - entry.waiting_since >= options.request_timeout_seconds then
            entry.inflight, entry.waiting_since, entry.force_retry = false, nil, true
            entry.error, entry.next_retry = "profile_load_timeout", current + options.retry_seconds
        elseif not entry.force_retry then
            entry.status = "authenticating"
            return
        end
    elseif entry.waiting_since then
        -- An independently started preload failed; do not immediately race it.
        entry.waiting_since = nil
        entry.error, entry.next_retry = "profile_load_failed", current + options.retry_seconds
    end
    if current >= entry.next_retry and (not pending or entry.force_retry) then begin_load(entry, current) end
    entry.status = entry.error and "auth_error" or "authenticating"
end

local function asset_snapshot()
    local ok, value = pcall(assets.snapshot)
    value = ok and type(value) == "table" and value or {}
    local total = math.max(0, tonumber(value.total) or 0)
    local ready = math.min(total, math.max(0, tonumber(value.ready) or 0))
    local failed = math.max(0, tonumber(value.failed) or 0)
    if value.complete == true and failed == 0 then asset_retry_error = nil end
    return { total = total, ready = ready, failed = failed,
        progress = math.max(0, math.min(100, tonumber(value.progress) or 0)),
        complete = value.complete == true and failed == 0 },
        asset_retry_error or ((not ok or value.error) and "asset_preload_failed" or nil)
end

local function publish(value)
    latest = value
    if CustomNetTables and type(CustomNetTables.SetTableValue) == "function" then
        CustomNetTables:SetTableValue("survival_loading", "state", copy(value))
    end
end

local function setup_snapshot()
    local value = match_setup.snapshot()
    local progression = type(profiles.get_progression) == "function"
        and profiles.get_progression(value.selector_player_id) or nil
    value.difficulty_options = require("config/difficulty_config").client_options(progression)
    return value
end

local function run_callbacks(queue, phase)
    for _, callback in ipairs(queue) do
        if not pcall(callback) then print("[StartupLoading] " .. phase .. "_callback_failed") end
    end
end

-- Admission is irreversible for this match. Mode-specific profile preparation
-- happens in the HUD and must never reopen the loading background.
local function tick_profiles()
    local all_loaded, count, failure = match_setup.is_mode_selected(), 0, nil
    local current = now()
    for id, entry in pairs(entries) do
        count = count + 1
        local steam = tonumber(resource("GetSteamAccountID", id))
        local same_account = steam and steam > 0 and string.format("%.0f", steam) == entry.account
        local eligible = human(id) and connected(id) and same_account
        local loaded = eligible and match_setup.is_mode_selected()
            and type(profiles.is_loaded_for_account) == "function"
            and profiles.is_loaded_for_account(id, entry.account) == true
        if not loaded then
            all_loaded = false
            if not eligible then
                failure = failure or (same_account and "player_disconnected" or "player_identity_changed")
            elseif match_setup.is_mode_selected() then
                if entry.profile_inflight and current - (entry.profile_waiting_since or current) >= options.request_timeout_seconds then
                    entry.profile_inflight = false
                    entry.profile_error, entry.profile_retry_at = "profile_load_timeout", current + options.retry_seconds
                end
                local pending = type(profiles.is_loading) == "function" and profiles.is_loading(id)
                if pending then entry.profile_pending_since = entry.profile_pending_since or current
                else entry.profile_pending_since = nil end
                local stalled = pending and current - (entry.profile_pending_since or current) >= options.request_timeout_seconds
                if stalled then
                    entry.profile_inflight = false
                    entry.profile_error = "profile_load_timeout"
                end
                if not entry.profile_inflight and (not pending or stalled) and current >= (entry.profile_retry_at or 0) then
                    entry.profile_inflight, entry.profile_waiting_since = true, current
                    entry.profile_pending_since = current
                    entry.profile_attempt = (entry.profile_attempt or 0) + 1
                    local attempt, epoch = entry.profile_attempt, generation
                    local function complete(reason)
                        if generation ~= epoch or entries[id] ~= entry or entry.profile_attempt ~= attempt then return end
                        entry.profile_inflight = false
                        entry.profile_error = reason and safe_error(reason) or nil
                        entry.profile_retry_at = now() + options.retry_seconds
                    end
                    local ok, result = pcall(profiles.load_player, id, "match_mode_selected",
                        function() complete(nil) end, function(reason) complete(reason) end)
                    if not ok or type(result) ~= "table" then complete("profile_load_failed")
                    elseif not result.pending then complete(not result.ok and result.error or nil) end
                end
                failure = failure or entry.profile_error
            end
        else
            entry.profile_inflight, entry.profile_error = false, nil
        end
    end
    all_loaded = all_loaded and count > 0
    local state = copy(latest)
    state.admission_complete, state.all_ready, state.phase, state.error = true, true, "ready", nil
    state.profiles_ready, state.setup = all_loaded, setup_snapshot()
    state.setup.error = failure
    publish(state)
    if all_loaded then
        gameplay_released = true
        local run = gameplay_callbacks
        gameplay_callbacks = {}
        run_callbacks(run, "gameplay_ready")
        return nil
    end
    return options.tick_seconds
end

function M.tick()
    if not initialized then return nil end
    if gameplay_released then return nil end
    if released then return tick_profiles() end
    discover()
    if party_waiting then
        local public, count, accounts = {}, 0, {}
        for id, entry in pairs(entries) do
            local account = tonumber(resource("GetSteamAccountID", id))
            local online = human(id) and connected(id) and account and account > 0
            if online and not accounts[account] then
                accounts[account] = true
                count = count + 1
                public[#public + 1] = { player_id = id, authenticated = false,
                    client_ready = entry.client_ready, ready = false, status = "party_waiting" }
            end
        end
        table.sort(public, function(a, b) return a.player_id < b.player_id end)
        publish({ session_id = session_id, started = true, phase = "party_waiting",
            progress = 0, players = public, party_count = count,
            selector_player_id = match_setup.selector_player_id(),
            all_ready = false, admission_complete = false, profiles_ready = false })
        return options.tick_seconds
    end
    if options.tools_party and Convars and type(Convars.GetStr) == "function"
        and Convars:GetStr("survival_fishing_api_token") == "" then
        local public = {}
        for id, entry in pairs(entries) do
            public[#public + 1] = { player_id = id, authenticated = false,
                client_ready = entry.client_ready, ready = false, status = "connecting_backend" }
        end
        table.sort(public, function(a, b) return a.player_id < b.player_id end)
        local timed_out = now() - started_at >= options.request_timeout_seconds
        publish({ session_id = session_id, started = true, phase = "connecting_backend",
            progress = 0, players = public, all_ready = false, admission_complete = false,
            profiles_ready = false, error = timed_out and "backend_connection_pending" or nil })
        return options.tick_seconds
    end
    local current = now()
    local asset, failure = asset_snapshot()
    if asset.failed > 0 then failure = failure or "asset_preload_failed" end
    local ids = {}
    for id in pairs(entries) do ids[#ids + 1] = id end
    table.sort(ids)
    local public, completed_steps, ready_count = {}, 0, 0
    for _, id in ipairs(ids) do
        local entry = entries[id]
        update_player(entry, current)
        entry.ready = entry.connected and entry.authenticated and entry.client_ready and asset.complete
        if entry.connected and entry.authenticated and entry.client_ready and not asset.complete then
            entry.status = "asset_loading"
        end
        if entry.authenticated then completed_steps = completed_steps + 1 end
        if entry.client_ready then completed_steps = completed_steps + 1 end
        if entry.ready then ready_count = ready_count + 1 end
        if entry.error then failure = failure or entry.error end
        public[#public + 1] = { player_id = id, authenticated = entry.authenticated,
            client_ready = entry.client_ready, ready = entry.ready, status = entry.status }
    end
    local ready = lobby_roster_available() and #ids > 0 and ready_count == #ids and asset.complete and not failure
        and current - started_at >= options.minimum_wait_seconds
    local phase = ready and "ready" or (failure and "error" or (ready_count > 0 and "waiting" or "loading"))
    if not ready then
        for _, player in ipairs(public) do if player.ready then player.status = "waiting" end end
    end
    local progress = asset.progress * 0.6 + (#ids > 0 and completed_steps / (#ids * 2) * 40 or 0)
    publish({ session_id = session_id, started = true, phase = phase,
        progress = ready and 100 or math.floor(progress), assets = asset, players = public,
        all_ready = ready, admission_complete = ready, profiles_ready = false,
        error = failure, setup = setup_snapshot() })
    if ready then
        released = true
        local run = callbacks
        callbacks = {}
        run_callbacks(run, "admission_ready")
        return options.tick_seconds
    end
    return options.tick_seconds
end

function M.is_ready() return initialized and released end
function M.is_party_waiting() return initialized and party_waiting end
function M.is_gameplay_ready() return initialized and gameplay_released end
function M.is_player_ready(value)
    if not M.is_gameplay_ready() then return false end
    local id = player_id(value)
    local entry = id ~= nil and entries[id] or nil
    if not entry or not entry.ready or not entry.account or not human(id) or not connected(id) then return false end
    local steam = tonumber(resource("GetSteamAccountID", id))
    if not steam or steam <= 0 or string.format("%.0f", steam) ~= entry.account then return false end
    if not match_setup.is_mode_selected() then return false end
    if type(profiles.is_loaded_for_account) == "function" then
        return profiles.is_loaded_for_account(id, entry.account)
    end
    local ok, profile = pcall(profiles.get_profile, id)
    return ok and type(profile) == "table" and tostring(profile.account_id or "") == entry.account
end
function M.snapshot() return copy(latest) end
function M.gate(callback)
    assert(type(callback) == "function", "startup ready callback required")
    if M.is_ready() then callback() return true end
    callbacks[#callbacks + 1] = callback
    return false
end
function M.gameplay_gate(callback)
    assert(type(callback) == "function", "gameplay ready callback required")
    if M.is_gameplay_ready() then callback() return true end
    gameplay_callbacks[#gameplay_callbacks + 1] = callback
    return false
end

function M.init(settings)
    settings = settings or {}
    generation = generation + 1
    local epoch = generation
    if CustomGameEventManager and type(CustomGameEventManager.UnregisterListener) == "function" then
        for _, listener in ipairs(listeners) do pcall(CustomGameEventManager.UnregisterListener, CustomGameEventManager, listener) end
    end
    entries, callbacks, gameplay_callbacks, listeners = {}, {}, {}, {}
    party_departed = {}
    asset_retry_error = nil
    options = { minimum_wait_seconds = math.max(0, tonumber(settings.minimum_wait_seconds) or 0),
        retry_seconds = math.max(1, tonumber(settings.retry_seconds) or 5),
        request_timeout_seconds = math.max(30, tonumber(settings.request_timeout_seconds) or 45),
        tick_seconds = 0.25, tools_party = settings.wait_for_party == true }
    party_waiting = settings.wait_for_party == true
    load_start = settings.on_load_start
    session_id = new_session_id()
    match_setup.init(session_id)
    started_at, initialized, released, gameplay_released = now(), true, false, false
    if type(settings.on_ready) == "function" then callbacks[1] = settings.on_ready end
    local function listen(name, callback, after_admission)
        if CustomGameEventManager and type(CustomGameEventManager.RegisterListener) == "function" then
            listeners[#listeners + 1] = CustomGameEventManager:RegisterListener(name, function(source, payload)
                if epoch ~= generation or (released and not after_admission) or type(payload) ~= "table" or payload.session_id ~= session_id then return end
                local id = actor(source)
                if id == nil then return end
                if not released then discover() end
                local entry = entries[id]
                if not entry then return end
                callback(entry, payload)
                M.tick()
            end)
        end
    end
    listen("survival_loading_client_ready", function(entry) entry.client_ready = true end)
    listen("survival_party_start", function(entry)
        if not party_waiting or not match_setup.is_selector(entry.player_id)
            or not lobby_roster_available() then return end
        -- Freeze only the current connected roster. A player who left the
        -- waiting room must not hold the subsequent admission barrier forever.
        for id in pairs(entries) do
            local account = tonumber(resource("GetSteamAccountID", id))
            if not human(id) or not connected(id) or not account or account <= 0 then
                entries[id], party_departed[id] = nil, true
            end
        end
        party_waiting = false
        started_at = now()
        if load_start then load_start() end
    end)
    listen("survival_loading_mode_select", function(entry, payload)
        local steam = tonumber(resource("GetSteamAccountID", entry.player_id))
        local admitted = released and steam and steam > 0
            and string.format("%.0f", steam) == entry.account
            and profiles.is_authenticated_for_account(entry.player_id, entry.account)
        local result = admitted and match_setup.select_mode(entry.player_id, payload.mode_id, payload.session_id)
            or { ok = false, error = "admission_not_complete" }
        if CustomGameEventManager and type(CustomGameEventManager.Send_ServerToPlayer) == "function" then
            CustomGameEventManager:Send_ServerToPlayer(resource("GetPlayer", entry.player_id),
                "survival_loading_mode_result", { success = result.ok and 1 or 0,
                    session_id = session_id, mode_id = result.mode_id or "", error = result.error or "" })
        end
        if result.ok then
            local waves = package.loaded["systems/wave_system"]
            if waves and type(waves.refresh_selection) == "function" then
                waves.refresh_selection("mode_selected")
            end
        end
    end, true)
    listen("survival_loading_retry", function(entry)
        if party_waiting then return end
        local current = now()
        if current < (entry.last_manual_retry or -math.huge) + options.retry_seconds then return end
        if released then
            entry.last_manual_retry = current
            entry.profile_retry_at = current
            return
        end
        local asset_state, asset_error = asset_snapshot()
        local retry_assets = (asset_state.failed > 0 or asset_error ~= nil) and type(assets.retry) == "function"
            and asset_retry_error ~= "asset_reload_required"
        local retry_profile = not entry.authenticated and not entry.inflight
        if not retry_assets and not retry_profile then return end
        entry.last_manual_retry = current
        -- Asset repair is independent from profile authentication: an already
        -- authenticated player can retry assets without clearing their save.
        if retry_assets then
            local ok, result = pcall(assets.retry)
            if ok and type(result) == "table" and result.error == "startup_assets_require_map_reload" then
                asset_retry_error = "asset_reload_required"
            elseif ok and type(result) == "table" and result.ok then
                asset_retry_error = nil
            end
        end
        if retry_profile then
            entry.next_retry = math.max(current, (entry.last_attempt or -math.huge) + options.retry_seconds)
        end
    end, true)
    local entity = GameRules and type(GameRules.GetGameModeEntity) == "function" and GameRules:GetGameModeEntity() or nil
    assert(entity and type(entity.SetContextThink) == "function", "startup real-time thinker unavailable")
    entity:SetContextThink("SurvivalStartupLoadingThink", function()
        if epoch ~= generation then return nil end
        return M.tick()
    end, options.tick_seconds)
    if not party_waiting and load_start then load_start() end
    M.tick()
    return M.snapshot()
end

return M
