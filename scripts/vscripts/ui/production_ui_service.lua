local event_bus = require("core/event_bus")
local events = require("core/events")
local player_context = require("systems/player_context_service")
local research_events = require("research/research_event_names")
local research_abilities = require("config/generated/research_lab_abilities")
local runtime_builder = require("ui/ability_runtime_builder")

-- Selected-building presentation and authenticated intent routing only.
-- The worker/shop systems own jobs, prices, limits and completion timers.
local M = {}

local function entity_index(value)
    local n = tonumber(value)
    if not n or n <= 0 or n ~= math.floor(n) then return nil end
    return n
end

local function resolve_entity(index)
    if not index then return nil end
    local ok, unit = pcall(EntIndexToHScript, index)
    if not ok or not unit or unit:IsNull() then return nil end
    return unit
end

function M.decorate(player_id, unit, snapshot)
    snapshot = snapshot or {}
    if not unit or unit:IsNull() then return snapshot end
    local entindex = entity_index(snapshot.entindex)
        or (unit.entindex and unit:entindex())
    if not entindex then return snapshot end
    local building = event_bus.request(events.BUILDING_QUERY_REQUEST, {
        entindex = entindex, read_only = true,
    })
    if not building then return snapshot end
    local id = building.building_id
    snapshot.building_id = id
    if id ~= "main_city" and id ~= "building_research_lab"
        and id ~= "building_advanced_research_lab" then return snapshot end
    snapshot.server_time = GameRules:GetGameTime()
    local owned = tonumber(building.player_id) == tonumber(player_id)
    if id == "main_city" and owned then
        snapshot.training = event_bus.request(events.WORKER_TRAINING_GET_REQUEST, {
            player_id = player_id,
            team = building.team,
            source_entindex = entindex,
        }) or {}
    elseif owned or (id == "building_advanced_research_lab"
        and PlayerResource.GetTeam
        and tonumber(building.team) == tonumber(PlayerResource:GetTeam(player_id))) then
        local state = event_bus.request(events.TECHNOLOGY_STATE_GET_REQUEST, {
            player_id = player_id,
            source_entindex = entindex,
        })
        snapshot.research = state and state.research or {}
        -- Entity NetTables describe the building owner. Shared research labs
        -- need the requesting player's levels, prices and automation instead.
        local personal = event_bus.request(research_events.STATE_GET_REQUESTED, {
            player_id = player_id,
        }) or {}
        local progression = event_bus.request(events.HERO_PROGRESSION_GET_REQUEST, {
            player_id = player_id,
        }) or {}
        local resources = event_bus.request(events.RESOURCE_GET_REQUEST, {
            player_id = player_id,
        })
        local view = {
            player_id = player_id, team = building.team,
            building_id = id, entindex = entindex,
            research_levels = personal.legacy_levels or {},
            research_transaction = snapshot.research,
            reincarnation_level = tonumber(progression.snapshot
                and progression.snapshot.rebirth_level) or 0,
        }
        local abilities = {}
        for _, mapping in ipairs(research_abilities.rows or {}) do
            if mapping.enabled ~= false and mapping.building_id == id then
                abilities[mapping.ability_name] = runtime_builder.build(
                    mapping.ability_name, view, resources)
            end
        end
        snapshot.research.abilities_by_name = abilities
    end
    return snapshot
end

function M.init(options)
    local function refresh(payload)
        local player_id = tonumber(payload and payload.player_id)
        if player_id == nil then return end
        local selected = entity_index(options.selected(player_id))
        if not selected then return end
        local building = event_bus.request(events.BUILDING_QUERY_REQUEST, {
            entindex = selected, read_only = true,
        })
        if not building or (building.building_id ~= "main_city"
            and building.building_id ~= "building_research_lab"
            and building.building_id ~= "building_advanced_research_lab") then return end
        if tonumber(building.player_id) ~= player_id then
            if building.building_id ~= "building_advanced_research_lab"
                or not PlayerResource.GetTeam
                or tonumber(building.team) ~= tonumber(PlayerResource:GetTeam(player_id)) then return end
        end
        local source = entity_index(payload.source_entindex)
        if source and source ~= selected then return end
        options.push({
            player_id = player_id,
            entindex = selected,
            reason = "production_changed",
        })
    end
    event_bus.subscribe(events.WORKER_CHANGED, refresh)
    event_bus.subscribe(events.RESOURCE_CHANGED, refresh)
    event_bus.subscribe(events.TECHNOLOGY_RESEARCH_STATE_CHANGED, refresh)
    event_bus.subscribe(research_events.LEVEL_CHANGED, refresh)
    event_bus.subscribe(events.HERO_PROGRESSION_CHANGED, refresh)
    CustomGameEventManager:RegisterListener("ui_research_queue_request", function(_, payload)
        payload = payload or {}
        local player_id = options.source_player_id(payload)
        if not options.valid_player_id(player_id) then return end
        local source = entity_index(payload.source_entindex)
        local unit = resolve_entity(source)
        local building = unit and event_bus.request(events.BUILDING_QUERY_REQUEST, {entindex = source})
        local owned = building and tonumber(building.player_id) == player_id
        local shared = building and building.building_id == "building_advanced_research_lab"
            and PlayerResource.GetTeam
            and tonumber(building.team) == tonumber(PlayerResource:GetTeam(player_id))
        local result
        if not building or (not owned and not shared)
            or (building.building_id ~= "building_research_lab"
                and building.building_id ~= "building_advanced_research_lab")
            or (unit.IsAlive and not unit:IsAlive()) then
            result = {ok = false, error = "请选择可用的研究所"}
        else
            result = event_bus.request(events.TECHNOLOGY_PURCHASE_NEXT_REQUEST, {
                player_id = player_id,
                technology_group = tostring(payload.technology_group or ""),
                source_entindex = source,
                request_id = tostring(payload.request_id or ""),
                source = "research_queue_ui",
            }) or {ok = false, error = "研究请求未响应"}
        end
        options.send("ui_operation_result", player_id, {
            operation = "research_queue", request_id = tostring(payload.request_id or ""),
            source_entindex = source or -1, success = result.ok and 1 or 0,
            queued = result.queued and 1 or 0,
            error = result.ok and "" or (result.error or "研究排队失败"),
        })
        if result.ok then refresh({player_id = player_id, source_entindex = source})
        else
            event_bus.emit(events.UI_NOTIFICATION, {player_id = player_id,
                message = result.error or "研究排队失败", level = "error"})
        end
    end)
    CustomGameEventManager:RegisterListener("ui_worker_train_request", function(_, payload)
        payload = payload or {}
        local player_id = options.source_player_id(payload)
        if not options.valid_player_id(player_id) then return end
        local source = entity_index(payload.source_entindex)
        local city = resolve_entity(source)
        local building = city and event_bus.request(events.BUILDING_QUERY_REQUEST, {
            entindex = source,
        })
        local result
        if not building or building.building_id ~= "main_city"
            or tonumber(building.player_id) ~= player_id
            or not player_context.is_owned_by(player_id, city)
            or (city.IsAlive and not city:IsAlive()) then
            result = { ok = false, error = "请选择自己的主基地" }
        else
            -- Never forward client-supplied counts, free flags, owner IDs or
            -- reward sources. One click requests one configured lumberjack.
            result = event_bus.request(events.WORKER_TRAIN_REQUEST, {
                player_id = player_id,
                city = city,
                source_entindex = source,
                training_id = tostring(payload.training_id or ""),
                source = "main_city_training_ui",
            }) or { ok = false, error = "训练请求未响应" }
        end
        options.send("ui_operation_result", player_id, {
            operation = "worker_train",
            request_id = tostring(payload.request_id or ""),
            source_entindex = source or -1,
            success = result.ok and 1 or 0,
            queued = result.queued and 1 or 0,
            job_id = result.job_id,
            error = result.ok and "" or (result.error or "训练失败"),
        })
        if result.ok then
            refresh({ player_id = player_id, source_entindex = source })
        else
            event_bus.emit(events.UI_NOTIFICATION, {
                player_id = player_id,
                message = result.error or "训练失败",
                level = "error",
            })
        end
    end)
end

return M
