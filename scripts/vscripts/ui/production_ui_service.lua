local event_bus = require("core/event_bus")
local events = require("core/events")
local player_context = require("systems/player_context_service")
local research_events = require("research/research_event_names")
local research_abilities = require("config/generated/research_lab_abilities")
local runtime_builder = require("ui/ability_runtime_builder")

-- Selected-building presentation and authenticated intent routing only.
-- The worker/shop systems own jobs, prices, limits and completion timers.
local M = {}
local research_cache, research_generation = {}, {}
local function operation_error(code, fallback)
    local messages = {wood_not_enough = "木材不足", insufficient_wood = "木材不足",
        gold_not_enough = "金币不足", insufficient_gold = "金币不足",
        population_not_enough = "人口不足", insufficient_population = "人口不足",
        insufficient_resources = "资源不足", resource_error = "资源信息尚未就绪"}
    return messages[code] or code or fallback
end
local function invalidate_research(payload)
    local player=tonumber(payload and payload.player_id)
    if player~=nil then research_generation[player]=(research_generation[player] or 0)+1 end
end

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
        local view = {
            player_id = player_id, team = building.team,
            building_id = id, entindex = entindex,
            research_levels = personal.legacy_levels or {},
            research_transaction = snapshot.research,
            reincarnation_level = tonumber(progression.snapshot
                and progression.snapshot.rebirth_level) or 0,
        }
        local key=tostring(player_id)..":"..tostring(entindex)
        local generation=research_generation[player_id] or 0
        local cached=research_cache[key]
        if not cached or cached.generation~=generation then
            local abilities={}
            for _, mapping in ipairs(research_abilities.rows or {}) do
                if mapping.enabled ~= false and mapping.building_id == id then
                    abilities[mapping.ability_name] = runtime_builder.build(mapping.ability_name,view,nil)
                end
            end
            cached={generation=generation,abilities=abilities}
            research_cache[key]=cached
        end
        snapshot.research.abilities_by_name = cached.abilities
    end
    return snapshot
end

function M.init(options)
    research_cache,research_generation={},{}
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
    event_bus.subscribe(events.WORKER_CHANGED, function(payload)
        if not payload or not payload.super_lumberjack or not payload.removed_entindexes then return end
        local player = PlayerResource:GetPlayer(tonumber(payload.player_id))
        if not player then return end
        local consumed = { payload.entindex }
        for _, id in ipairs(payload.removed_entindexes) do consumed[#consumed + 1] = id end
        -- Covers engine casts as well as custom HUD requests, including death replication races.
        CustomGameEventManager:Send_ServerToPlayer(player, "survival_lumberjack_fused", {
            target_entindex = payload.entindex, consumed_entindexes = consumed,
        })
    end)
    event_bus.subscribe(events.WORKER_CHANGED, refresh)
    -- Training prices and unlocks change with progression or queue events.
    -- Wallet changes are checked on a training click and do not repaint options.
    local function refresh_research(payload)
        invalidate_research(payload)
        refresh(payload)
    end
    event_bus.subscribe(events.TECHNOLOGY_RESEARCH_STATE_CHANGED,refresh_research)
    event_bus.subscribe(research_events.LEVEL_CHANGED,refresh_research)
    event_bus.subscribe(events.HERO_PROGRESSION_CHANGED,refresh_research)
    event_bus.subscribe(events.PERMANENT_REWARD_EFFECTS_CHANGED,function(payload)
        -- Growth/income ticks share this event. Only a rebuilt cost projection
        -- can change research prices, not each hero attack or wood increment.
        if type(payload and payload.totals)=="table" then refresh_research(payload) end
    end)
    event_bus.subscribe(events.BUILDING_DESTROYED,function(payload)
        for key in pairs(research_cache) do
            if key:match(":"..tostring(payload.entindex).."$") then research_cache[key]=nil end
        end
    end)
    local function research_request(operation, request_event, payload)
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
            result = event_bus.request(request_event, {
                player_id = player_id,
                technology_group = tostring(payload.technology_group or ""),
                job_id = tostring(payload.job_id or ""),
                source_entindex = source,
                request_id = tostring(payload.request_id or ""),
                source = "research_queue_ui",
            }) or {ok = false, error = "研究请求未响应"}
        end
        options.send("ui_operation_result", player_id, {
            operation = operation, request_id = tostring(payload.request_id or ""),
            source_entindex = source or -1, success = result.ok and 1 or 0,
            queued = result.queued and 1 or 0,
            refunded = result.refunded and 1 or 0,
            error = result.ok and "" or operation_error(result.error, "研究排队失败"),
        })
        if result.ok then refresh({player_id = player_id, source_entindex = source})
        else
            event_bus.emit(events.UI_NOTIFICATION, {player_id = player_id,
                message = operation_error(result.error, "研究排队失败"), level = "error"})
        end
    end
    CustomGameEventManager:RegisterListener("ui_research_queue_request", function(_, payload)
        research_request("research_queue", events.TECHNOLOGY_PURCHASE_NEXT_REQUEST, payload)
    end)
    CustomGameEventManager:RegisterListener("ui_research_cancel_request", function(_, payload)
        research_request("research_cancel", events.TECHNOLOGY_RESEARCH_CANCEL_REQUEST, payload)
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
            error = result.ok and "" or operation_error(result.error, "训练失败"),
        })
        if result.ok then
            refresh({ player_id = player_id, source_entindex = source })
        else
            event_bus.emit(events.UI_NOTIFICATION, {
                player_id = player_id,
                message = operation_error(result.error, "训练失败"),
                level = "error",
            })
        end
    end)
end

return M
