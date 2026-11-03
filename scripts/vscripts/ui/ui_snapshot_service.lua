local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local compact = require("ui/compact_ui_transport")

local M = {}
local sequence = 0
local dirty_teams = {}
local dirty_players = {}
local flush_pending = false
local generation = 0
local compact_factory, compact_players
local recipients, recipients_by_team = {}, {}

local function build(player_id)
    return event_bus.request("ui.projection.build_snapshot", {
        player_id = player_id, team = PlayerResource:GetTeam(player_id),
    })
end

local function compact_full(player_id)
    if not compact_factory then return nil end
    local snapshot = build(player_id)
    if not snapshot then return nil end
    local state, operations = compact_factory.initialize(snapshot)
    if not state then return nil end
    compact_players[player_id] = state
    return operations
end

local function valid_player(player_id)
    return PlayerResource:IsValidPlayerID(player_id)
       and PlayerResource:GetPlayer(player_id) ~= nil
end

local function remember_player(player_id)
    if not valid_player(player_id) then return false end
    local team = PlayerResource:GetTeam(player_id)
    local previous = recipients[player_id]
    if previous and previous ~= team and recipients_by_team[previous] then
        recipients_by_team[previous][player_id] = nil
    end
    recipients[player_id] = team
    recipients_by_team[team] = recipients_by_team[team] or {}
    recipients_by_team[team][player_id] = true
    return true
end

local function publish_player(player_id)
    if not remember_player(player_id) then return false end
    -- A negotiated v3 client never also receives the legacy full JSON event.
    if compact.is_bound(player_id) then
        if not compact.is_open(player_id, 2) then return false end
        local state = compact_players and compact_players[player_id]
        if not state then
            local operations = compact_full(player_id)
            return operations and compact.publish(player_id, 2, operations, {full=true}) ~= nil
        end
        local snapshot = build(player_id)
        if not snapshot then return false end
        local operations = state.update(snapshot)
        if not operations then return false end
        if #operations == 0 then return true end
        return compact.publish(player_id, 2, operations, {priority=true}) ~= nil
    end
    local snapshot = build(player_id)
    if not snapshot then return false end
    sequence = sequence + 1
    snapshot.sequence = sequence
    local player = PlayerResource:GetPlayer(player_id)
    if not player then return false end
    CustomGameEventManager:Send_ServerToPlayer(
        player,
        "survival_ui_private_snapshot",
        snapshot
    )
    return true
end

local function flush_dirty()
    -- Detach both sets before publishing: reentrant changes belong to the next batch.
    local teams, players = dirty_teams, dirty_players
    dirty_teams, dirty_players = {}, {}
    flush_pending = false
    -- Direct recipient/team indexes: no per-flush PlayerResource slot scan.
    if teams.all then for player_id in pairs(recipients)do players[player_id]=true end
    else for team in pairs(teams)do
        for player_id in pairs(recipients_by_team[team] or {})do players[player_id]=true end
    end end
    for player_id in pairs(players)do publish_player(player_id)end
end

local function on_dirty(payload)
    payload = payload or {}
    if payload.player_id ~= nil then
        local player_id = tonumber(payload.player_id)
        -- An invalid personal recipient must never fall back to broadcasting.
        if not player_id or not remember_player(player_id) then return end
        dirty_players[player_id] = true
    elseif payload.team ~= nil then dirty_teams[payload.team] = true
    else dirty_teams.all = true end
    if flush_pending then return end
    flush_pending = true
    local current_generation = generation
    -- Coalesce the current engine burst on the next scheduler dispatch. No
    -- arbitrary quarter-second wait and no idle poll/retry/full-snapshot loop.
    scheduler.after(0, function()
        if current_generation ~= generation then return end
        flush_dirty()
    end, "ui_snapshot_flush")
end

local function on_snapshot_requested(payload)
    publish_player(payload.player_id)
end

function M.init()
    scheduler.cancel("ui_snapshot_flush")
    generation = generation + 1
    flush_pending = false
    sequence = 0
    dirty_teams, dirty_players = {}, {}
    recipients, recipients_by_team = {}, {}
    -- Initial registration is the only full engine-slot pass. Late arrivals
    -- register through readiness/personal state events and explicit resync.
    for player_id=0,DOTA_MAX_TEAM_PLAYERS-1 do remember_player(player_id)end
    compact_players = {}
    if compact.available() then
        local lookup = require("config/generated/ui_static_catalog_lookup")
        compact_factory = require("ui/compact_hud_projection").new(lookup)
        compact.register_view(2, {snapshot=compact_full,
            close=function(player_id) compact_players[player_id]=nil end})
    else compact_factory = nil end
    event_bus.subscribe(events.UI_DIRTY, on_dirty)
    event_bus.subscribe(events.UI_SNAPSHOT_REQUESTED, on_snapshot_requested)
    local function ready(payload)
        local player_id=tonumber(payload and payload.player_id)
        if player_id then on_dirty({player_id=player_id})end
    end
    event_bus.subscribe(events.HERO_READY, ready)
    event_bus.subscribe(events.BUILDER_READY, ready)
    event_bus.subscribe(events.PLAYER_DISCONNECTED, function(payload)
        if compact_players then compact_players[tonumber(payload.player_id)] = nil end
    end)
    on_dirty({})
end

function M.publish_player(player_id)
    return publish_player(player_id)
end

return M
