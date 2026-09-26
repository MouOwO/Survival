local event_bus = require("core/event_bus")
local events = require("core/events")

local M = {}
local resource_by_player = {}
local city_level_by_player = {}
local worker_count_by_player = {}
local wave = {}
local research_unlocked_by_player = {}
local advanced_research_unlocked_by_player = {}
local shop_unlocked_by_player = {}

local function mark_dirty(team)
    event_bus.emit(events.UI_DIRTY, { team = team })
end

local function on_resource_changed(payload)
    resource_by_player[payload.player_id] = payload
    mark_dirty(payload.team)
end

local function on_building_changed(payload)
    if payload.player_id == nil then mark_dirty(payload.team); return end
    if payload.building_id == "main_city" then
        city_level_by_player[payload.player_id] = payload.level
    end
    mark_dirty(payload.team)
end

local function on_building_created(payload)
    if payload.player_id == nil then mark_dirty(payload.team); return end
    if payload.building_id == "building_research_lab" then
        research_unlocked_by_player[payload.player_id] = true
    elseif payload.building_id == "building_advanced_research_lab" then
        advanced_research_unlocked_by_player[payload.player_id] = true
    end
    on_building_changed(payload)
end

local function on_building_destroyed(payload)
    if payload.player_id == nil then mark_dirty(payload.team); return end
    if payload.building_id == "main_city" then
        city_level_by_player[payload.player_id] = 0
    elseif payload.building_id == "building_research_lab" then
        research_unlocked_by_player[payload.player_id] = false
    elseif payload.building_id == "building_advanced_research_lab" then
        advanced_research_unlocked_by_player[payload.player_id] = false
    end
    mark_dirty(payload.team)
end

local function on_hero_summon_changed(payload)
    shop_unlocked_by_player[payload.player_id] = payload.shop_unlocked == 1
        or payload.hero_summoned == 1
    mark_dirty(payload.team)
end

local function on_worker_changed(payload)
    if payload.player_id == nil then mark_dirty(payload.team); return end
    worker_count_by_player[payload.player_id] = math.max(
        0,
        (worker_count_by_player[payload.player_id] or 0) + (payload.count_delta or 0)
    )
    mark_dirty(payload.team)
end

local function on_wave_changed(payload)
    wave = payload
    mark_dirty(nil)
end

local function player_wave_snapshot(player_id)
    -- Wave lifecycle stays global. Counts and defeat warnings belong only to
    -- the recipient, even when all four players share DOTA_TEAM_GOODGUYS.
    local snapshot = {}
    for key, value in pairs(wave) do snapshot[key] = value end
    local personal = event_bus.request(events.WAVE_STATE_GET_REQUEST, {
        player_id = player_id,
    })
    if not personal or personal.ok ~= true
        or tonumber(personal.player_id) ~= tonumber(player_id) then
        personal = {}
    end
    snapshot.player_id = player_id
    snapshot.alive = math.max(0, tonumber(personal.alive) or 0)
    snapshot.overflow_active = personal.overflow_active == true
    snapshot.overflow_remaining = tonumber(personal.overflow_remaining) or 0
    snapshot.player_defeated = personal.player_defeated == true
    snapshot.defeat_reason = personal.defeat_reason
    if personal.alive_limit ~= nil then snapshot.alive_limit = personal.alive_limit end
    if personal.overflow_grace_seconds ~= nil then
        snapshot.overflow_grace_seconds = personal.overflow_grace_seconds
    end
    return snapshot
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
    if advanced_research_unlocked_by_player[payload.player_id] == nil then
        local result = event_bus.request(events.BUILDING_LIST_REQUEST, {
            player_id = payload.player_id,
        })
        advanced_research_unlocked_by_player[payload.player_id] = false
        for _, building in ipairs(result and result.buildings or {}) do
            if building.building_id == "building_advanced_research_lab" then
                advanced_research_unlocked_by_player[payload.player_id] = true
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
        city_level = city_level_by_player[payload.player_id] or 0,
        worker_count = worker_count_by_player[payload.player_id] or 0,
        shop_unlocked = shop_unlocked_by_player[payload.player_id] and 1 or 0,
        research_unlocked = research_unlocked_by_player[payload.player_id] and 1 or 0,
        advanced_researcher_unlocked =
            advanced_research_unlocked_by_player[payload.player_id] and 1 or 0,
        wave = player_wave_snapshot(payload.player_id),
    }
end

function M.init()
    require("ui/boss_warning_ui_service").init()
    resource_by_player = {}
    city_level_by_player = {}
    worker_count_by_player = {}
    wave = {}
    research_unlocked_by_player = {}
    advanced_research_unlocked_by_player = {}
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
