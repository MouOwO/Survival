local event_bus = require("core/event_bus")
local events = require("core/events")

local M = {}
local resource_by_team = {}
local city_level_by_team = {}
local worker_count_by_team = {}
local wave = {}

local function mark_dirty(team)
    event_bus.emit(events.UI_DIRTY, { team = team })
end

local function on_resource_changed(payload)
    resource_by_team[payload.team] = payload
    mark_dirty(payload.team)
end

local function on_building_changed(payload)
    if payload.building_id == "main_city" then
        city_level_by_team[payload.team] = payload.level
    end
    mark_dirty(payload.team)
end

local function on_building_destroyed(payload)
    if payload.building_id == "main_city" then
        city_level_by_team[payload.team] = 0
    end
    mark_dirty(payload.team)
end

local function on_worker_changed(payload)
    worker_count_by_team[payload.team] = math.max(
        0,
        (worker_count_by_team[payload.team] or 0) + (payload.count_delta or 0)
    )
    mark_dirty(payload.team)
end

local function on_wave_changed(payload)
    wave = payload
    mark_dirty(nil)
end

local function build_snapshot(payload)
    local team = payload.team
    local resource = resource_by_team[team]
    if not resource then
        local requested = event_bus.request(events.RESOURCE_GET_REQUEST, { team = team })
        resource = requested or {
            wood = 0,
            gold = 0,
            population = 0,
            max_population = 0,
            version = 0,
        }
        resource_by_team[team] = resource
    end
    return {
        schema_version = 2,
        player_id = payload.player_id,
        team = team,
        server_time = GameRules:GetGameTime(),
        resources = resource,
        city_level = city_level_by_team[team] or 0,
        worker_count = worker_count_by_team[team] or 0,
        wave = wave,
    }
end

function M.init()
    resource_by_team = {}
    city_level_by_team = {}
    worker_count_by_team = {}
    wave = {}
    event_bus.subscribe(events.RESOURCE_CHANGED, on_resource_changed)
    event_bus.subscribe(events.BUILDING_CHANGED, on_building_changed)
    event_bus.subscribe(events.BUILDING_DESTROYED, on_building_destroyed)
    event_bus.subscribe(events.WORKER_CHANGED, on_worker_changed)
    event_bus.subscribe(events.WAVE_CHANGED, on_wave_changed)
    event_bus.handle_request("ui.projection.build_snapshot", build_snapshot)
end

return M
