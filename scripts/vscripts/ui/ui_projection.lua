local event_bus = require("core/event_bus")
local events = require("core/events")

local M = {}
local resource_by_player = {}
local city_level_by_team = {}
local worker_count_by_team = {}
local wave = {}
local research_unlocked_by_team = {}
local advanced_research_unlocked_by_team = {}
local shop_unlocked_by_player = {}

local function mark_dirty(team)
    event_bus.emit(events.UI_DIRTY, { team = team })
end

local function on_resource_changed(payload)
    resource_by_player[payload.player_id] = payload
    mark_dirty(payload.team)
end

local function on_building_changed(payload)
    if payload.building_id == "main_city" then
        city_level_by_team[payload.team] = payload.level
    end
    mark_dirty(payload.team)
end

local function on_building_created(payload)
    if payload.building_id == "building_research_lab" then
        research_unlocked_by_team[payload.team] = true
    elseif payload.building_id == "building_advanced_research_lab" then
        advanced_research_unlocked_by_team[payload.team] = true
    end
    on_building_changed(payload)
end

local function on_building_destroyed(payload)
    if payload.building_id == "main_city" then
        city_level_by_team[payload.team] = 0
    elseif payload.building_id == "building_research_lab" then
        research_unlocked_by_team[payload.team] = false
    elseif payload.building_id == "building_advanced_research_lab" then
        advanced_research_unlocked_by_team[payload.team] = false
    end
    mark_dirty(payload.team)
end

local function on_hero_summon_changed(payload)
    shop_unlocked_by_player[payload.player_id] = payload.shop_unlocked == 1
        or payload.hero_summoned == 1
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
    local resource = resource_by_player[payload.player_id]
    if not resource then
        local requested = event_bus.request(events.RESOURCE_GET_REQUEST, { player_id = payload.player_id })
        resource = requested or {
            wood = 0,
            gold = 0,
            population = 0,
            max_population = 0,
            version = 0,
        }
        resource_by_player[payload.player_id] = resource
    end
    if advanced_research_unlocked_by_team[team] == nil then
        local result = event_bus.request(events.BUILDING_LIST_REQUEST, {
            player_id = payload.player_id,
        })
        advanced_research_unlocked_by_team[team] = false
        for _, building in ipairs(result and result.buildings or {}) do
            if building.building_id == "building_advanced_research_lab" then
                advanced_research_unlocked_by_team[team] = true
                break
            end
        end
    end
    return {
        schema_version = 2,
        player_id = payload.player_id,
        team = team,
        server_time = GameRules:GetGameTime(),
        resources = resource,
        city_level = city_level_by_team[team] or 0,
        worker_count = worker_count_by_team[team] or 0,
        shop_unlocked = shop_unlocked_by_player[payload.player_id] and 1 or 0,
        research_unlocked = research_unlocked_by_team[team] and 1 or 0,
        advanced_researcher_unlocked =
            advanced_research_unlocked_by_team[team] and 1 or 0,
        wave = wave,
    }
end

function M.init()
    resource_by_player = {}
    city_level_by_team = {}
    worker_count_by_team = {}
    wave = {}
    research_unlocked_by_team = {}
    advanced_research_unlocked_by_team = {}
    shop_unlocked_by_player = {}
    event_bus.subscribe(events.RESOURCE_CHANGED, on_resource_changed)
    event_bus.subscribe(events.BUILDING_CREATED, on_building_created)
    event_bus.subscribe(events.BUILDING_CHANGED, on_building_changed)
    event_bus.subscribe(events.BUILDING_DESTROYED, on_building_destroyed)
    event_bus.subscribe(events.WORKER_CHANGED, on_worker_changed)
    event_bus.subscribe(events.WAVE_CHANGED, on_wave_changed)
    event_bus.subscribe(events.HERO_SUMMON_STATE_CHANGED, on_hero_summon_changed)
    event_bus.handle_request("ui.projection.build_snapshot", build_snapshot)
end

return M
