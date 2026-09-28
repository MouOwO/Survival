local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")

local M = {}
local sequence = 0
local dirty_teams = {}
local dirty_players = {}
local flush_pending = false
local generation = 0

local function valid_player(player_id)
    return PlayerResource:IsValidPlayerID(player_id)
       and PlayerResource:GetPlayer(player_id) ~= nil
end

local function publish_player(player_id)
    if not valid_player(player_id) then return false end
    local team = PlayerResource:GetTeam(player_id)
    local snapshot = event_bus.request("ui.projection.build_snapshot", {
        player_id = player_id,
        team = team,
    })
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
    for player_id = 0, DOTA_MAX_TEAM_PLAYERS - 1 do
        if valid_player(player_id) and (teams.all or players[player_id]
            or teams[PlayerResource:GetTeam(player_id)]) then
            publish_player(player_id)
        end
    end
end

local function on_dirty(payload)
    payload = payload or {}
    if payload.player_id ~= nil then
        local player_id = tonumber(payload.player_id)
        -- An invalid personal recipient must never fall back to broadcasting.
        if not player_id or not valid_player(player_id) then return end
        dirty_players[player_id] = true
    elseif payload.team ~= nil then dirty_teams[payload.team] = true
    else dirty_teams.all = true end
    if flush_pending then return end
    flush_pending = true
    local current_generation = generation
    scheduler.after(0.25, function()
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
    event_bus.subscribe(events.UI_DIRTY, on_dirty)
    event_bus.subscribe(events.UI_SNAPSHOT_REQUESTED, on_snapshot_requested)
    on_dirty({})
end

function M.publish_player(player_id)
    return publish_player(player_id)
end

return M
