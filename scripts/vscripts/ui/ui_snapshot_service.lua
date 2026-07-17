local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")

local M = {}
local sequence = 0
local dirty_teams = {}

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
    CustomNetTables:SetTableValue(
        "survival_ui_state",
        "player_" .. tostring(player_id),
        snapshot
    )
    return true
end

local function publish_team(team)
    for player_id = 0, DOTA_MAX_TEAM_PLAYERS - 1 do
        if valid_player(player_id) and PlayerResource:GetTeam(player_id) == team then
            publish_player(player_id)
        end
    end
end

local function flush_dirty()
    if dirty_teams.all then
        for player_id = 0, DOTA_MAX_TEAM_PLAYERS - 1 do
            publish_player(player_id)
        end
    else
        for team, _ in pairs(dirty_teams) do
            publish_team(team)
        end
    end
    dirty_teams = {}
end

local function on_dirty(payload)
    if payload.team then dirty_teams[payload.team] = true
    else dirty_teams.all = true end
end

local function on_snapshot_requested(payload)
    publish_player(payload.player_id)
end

function M.init()
    sequence = 0
    dirty_teams = { all = true }
    event_bus.subscribe(events.UI_DIRTY, on_dirty)
    event_bus.subscribe(events.UI_SNAPSHOT_REQUESTED, on_snapshot_requested)
    scheduler.every(0.25, function()
        flush_dirty()
        return true
    end, "ui_snapshot_flush")
end

function M.publish_player(player_id)
    return publish_player(player_id)
end

return M
