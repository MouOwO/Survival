-- Team achievements share an event, while each account owns its save and perks.
local context = require("systems/player_context_service")
local multiplayer = require("systems/multiplayer_player_service")
local scheduler = require("core/scheduler")
local M = {}
local roster, roster_ids, challenge_events, endless_events = {}, {}, {}, {}
local difficulty_id, mode_id, begun, retry_active = nil, nil, false, false
local retry_events, endless_recipients = {}, {}
local RETRY_TIMER = "archive_cooperative_reward_retry"

local function normalized_id(value)
    local id = tonumber(value)
    return id and id >= 0 and id < math.huge and id == math.floor(id) and id or nil
end
local function normalized_difficulty(value)
    return tonumber(tostring(value or ""):lower():match("^n?(%d+)$"))
end
local function current_mode()
    local setup = package.loaded["systems/match_setup_service"]
    return setup and type(setup.get_mode) == "function" and setup.get_mode()
        or not setup and "standard" or nil
end
local function current_difficulty_matches(number)
    local wave = package.loaded["systems/wave_system"]
    return not wave or type(wave.get_difficulty) ~= "function"
        or normalized_difficulty(wave.get_difficulty()) == number
end
function M.matches_session(mode, difficulty)
    return begun and mode == mode_id and current_mode() == mode_id
        and normalized_difficulty(difficulty) == difficulty_id
        and current_difficulty_matches(difficulty_id)
end
local function enabled()
    return require("config/generated/archive_cooperative_reward_rules").by_id.default.enabled == true
end
local function eligible(id)
    -- The trusted victory roster does not depend on a loaded account profile.
    -- Failed/disconnected players cannot earn new team events; already queued
    -- rewards remain owned by archive_service across those transitions.
    if DOTA_TEAM_GOODGUYS == nil or not PlayerResource or not PlayerResource.IsValidPlayerID
        or not PlayerResource.IsFakeClient or not PlayerResource.GetTeam
        or not PlayerResource.GetPlayer then return false end
    return PlayerResource:IsValidPlayerID(id) and not PlayerResource:IsFakeClient(id)
        and PlayerResource:GetTeam(id) == DOTA_TEAM_GOODGUYS
        and PlayerResource:GetPlayer(id) ~= nil
        and not (context.is_defeated and context.is_defeated(id))
        and not multiplayer.is_defeated(id) and not multiplayer.is_disconnected(id)
end
local function source_allowed(id, difficulty)
    id = normalized_id(id)
    return enabled() and begun and id ~= nil and roster[id] == true
        and M.matches_session(mode_id, difficulty) and eligible(id)
end
function M.begin(player_ids, difficulty)
    if begun then return false, "cooperative_roster_already_started" end
    local number = normalized_difficulty(difficulty)
    local mode = current_mode()
    if not enabled() or not number or not mode
        or not require("config/difficulty_config").get("N" .. number, mode)
        or not current_difficulty_matches(number) then
        return false, "cooperative_rewards_unavailable"
    end
    local active
    if context.active_player_ids then
        active = {}
        for _, id in ipairs(context.active_player_ids()) do active[id] = true end
    end
    for _, value in ipairs(player_ids or {}) do
        local id = normalized_id(value)
        if id and not roster[id] and (not active or active[id]) and eligible(id) then
            roster[id], roster_ids[#roster_ids + 1] = true, id
        end
    end
    table.sort(roster_ids)
    if #roster_ids == 0 then return false, "cooperative_roster_empty" end
    difficulty_id, mode_id, begun = number, mode, true
    return true
end
local function deliver(event)
    local archive = require("systems/archive_service")
    local waiting = false
    for _, id in ipairs(event.player_ids) do
        if not event.delivered[id] then
            local ok, result = pcall(function()
                if event.kind == "challenge" then
                    return archive.record_challenge(id, event.challenge_id, event.kill_sequence, event.difficulty)
                end
                    return archive.record_endless_wave(id, event.wave, event.difficulty, event.variant)
            end)
            -- A false local-settlement result can still mean the durable intent
            -- is queued (e.g. the account has not loaded yet). Hand it off once;
            -- archive_service alone owns save retries and its five-second batch.
            local reward_id = event.kind == "challenge" and event.challenge_id or event.wave
            if ok and (type(result) == "table" and result.ok == true
                or archive.has_reward_pending and archive.has_reward_pending(id, event.kind, reward_id, event.variant)) then
                event.delivered[id] = true
            else
                waiting = true
                print("[ArchiveCooperative] delivery pending player=" .. tostring(id)
                    .. " kind=" .. event.kind .. " error="
                    .. tostring(ok and result and result.error or result))
            end
        end
    end
    return not waiting
end
local function ensure_retry()
    if retry_active then return end
    retry_active = true
    scheduler.every(1, function()
        for key, event in pairs(retry_events) do
            if deliver(event) then retry_events[key] = nil end
        end
        if next(retry_events) == nil then retry_active = false; return false end
    end, RETRY_TIMER)
end
local function freeze_event(event, key)
    event.player_ids, event.delivered = {}, {}
    for _, id in ipairs(roster_ids) do
        if eligible(id) and (event.variant ~= "tower" or id == event.source_player_id) then
            event.player_ids[#event.player_ids + 1] = id
            if event.kind == "endless" then endless_recipients[id] = true end
        end
    end
    -- The save barrier must see the intent even during a synchronous provider
    -- callback that finishes the phase before the remaining accounts enqueue.
    retry_events[key] = event
    if deliver(event) then retry_events[key] = nil else ensure_retry() end
    return {ok = true, shared = true, recipients = #event.player_ids}
end
function M.record_challenge(source_player_id, challenge_id, kill_sequence, difficulty)
    if not source_allowed(source_player_id, difficulty) then
        return {ok = false, error = "cooperative_source_invalid"}
    end
    local definition = require("config/generated/archive_challenge_definitions").by_id[challenge_id]
    if not definition or not definition.enabled or definition.min_difficulty > difficulty_id
        or type(kill_sequence) ~= "number" or not normalized_id(kill_sequence)
        or kill_sequence < 1 or kill_sequence > 100000 then
        return {ok = false, error = "cooperative_challenge_invalid"}
    end
    if challenge_events[challenge_id] then return {ok = true, duplicate = true} end
    local event = {kind = "challenge", challenge_id = challenge_id,
        kill_sequence = kill_sequence, difficulty = difficulty}
    -- Claim before calling account providers, which can synchronously emit more
    -- native death/profile events. No drops, account profile or VIP is copied.
    challenge_events[challenge_id] = event
    return freeze_event(event, "challenge:" .. tostring(challenge_id))
end
function M.record_endless_wave(source_player_id, wave, difficulty, variant)
    variant = variant or "endless"
    if not source_allowed(source_player_id, difficulty) then
        return {ok = false, error = "cooperative_source_invalid"}
    end
    local config = require("systems/archive_endless_config")
    if not config.allowed_variant(difficulty_id, mode_id, variant)
        or type(wave) ~= "number" or not normalized_id(wave) or wave < 1
        or not require("systems/archive_endless_config").wave(difficulty_id, wave, mode_id) then
        return {ok = false, error = "endless_wave_invalid"}
    end
    -- A solo tower belongs to its source, while endless is one shared team
    -- event. Both identities stay separate even at the same wave number.
    local key = variant .. ":" .. (variant == "tower" and tostring(source_player_id) .. ":" or "") .. tostring(wave)
    if endless_events[key] then return {ok = true, duplicate = true} end
    local event = {kind = "endless", wave = wave, difficulty = difficulty,
        variant = variant, source_player_id = tonumber(source_player_id)}
    endless_events[key] = event
    return freeze_event(event, key)
end
function M.flush_endless_rewards()
    local archive = require("systems/archive_service")
    if archive.flush_endless_rewards then
        for id in pairs(endless_recipients) do archive.flush_endless_rewards(id) end
    end
end
function M.has_pending()
    return next(retry_events) ~= nil
end
function M.init()
    scheduler.cancel(RETRY_TIMER)
    roster, roster_ids, challenge_events, endless_events = {}, {}, {}, {}
    retry_events, endless_recipients = {}, {}
    difficulty_id, mode_id, begun, retry_active = nil, nil, false, false
end
return M
