local event_bus = require("core/event_bus")
local events = require("core/events")
local player_context = require("systems/player_context_service")
local research_events = require("research/research_event_names")
local research_abilities = require("config/generated/research_lab_abilities")
local runtime_builder = require("ui/ability_runtime_builder")

-- Selected-building presentation and authenticated intent routing only.
-- The worker/shop systems own jobs, prices, limits and completion timers.
local M = {}
local compact_execute
local research_cache, research_generation = {}, {}
local presentation_versions,building_versions,presentation_cache,building_signatures={},{},{},{}
local active_lifecycle
function M.stamp(player_id,entity)
    return tostring(event_bus.get_generation())..':'..tostring(presentation_versions[player_id]or 0)..':'..tostring(building_versions[entity]or 0)
end
local function invalidate_presentation(payload)
    local id=tonumber(payload and payload.player_id)
    if id~=nil then presentation_versions[id]=(presentation_versions[id]or 0)+1 end
end
local operation_error_messages = {wood_not_enough = "木材不足", insufficient_wood = "木材不足",
        gold_not_enough = "金币不足", insufficient_gold = "金币不足",
        population_not_enough = "人口不足", insufficient_population = "人口不足",
        not_enough_population = "人口不足", population_limit = "人口不足",
        population_limit_reached = "人口不足",
        training_queue_full = "训练队列已满",
        training_max_count_reached = "本级训练名额已满",
        training_limit_reached = "训练名额已满",
        training_reserved_limit = "剩余训练名额已在队列中",
        training_not_available = "后续训练尚未开放",
        training_owner_mismatch = "只能在自己的主城训练",
        training_city_level_required = "主城等级不足，无法训练",
        training_building_missing = "主城不可用，无法继续训练",
        training_definition_invalid = "训练配置无效，请稍后重试",
        training_type_invalid = "当前训练类型不可用",
        training_cancelled = "训练已取消",
        training_completion_failed = "训练未能完成，请稍后重试",
        lumberjack_training_missing = "伐木工训练配置尚未就绪",
        repairer_training_missing = "修理工训练配置尚未就绪",
        worker_create_failed = "工人生成失败，请稍后重试",
        insufficient_resources = "资源不足", resource_error = "资源信息尚未就绪"}
local function operation_error(code, fallback)
    return operation_error_messages[code] or code or fallback
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

function M.decorate(player_id, unit, snapshot,compact)
    snapshot = snapshot or {}
    if not unit or unit:IsNull() then return snapshot end
    local entindex = entity_index(snapshot.entindex)
        or (unit.entindex and unit:entindex())
    if not entindex then return snapshot end
    local cache_key=tostring(player_id)..':'..tostring(entindex)
    local stamp=M.stamp(player_id,entindex)
    local old=presentation_cache[cache_key]
    if old and old.unit==unit and old.stamp==stamp then
        snapshot.training,snapshot.research,snapshot.building_id=old.training,old.research,old.building_id
        if compact then snapshot._production_stamp=stamp end
        return snapshot
    end
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
        if not cached or cached.generation~=generation or cached.unit~=unit or cached.building_id~=id then
            local abilities={}
            for _, mapping in ipairs(research_abilities.rows or {}) do
                if mapping.enabled ~= false and mapping.building_id == id then
                    abilities[mapping.ability_name] = runtime_builder.build(mapping.ability_name,view,nil)
                end
            end
            cached={generation=generation,abilities=abilities,unit=unit,building_id=id}
            research_cache[key]=cached
        end
        snapshot.research.abilities_by_name = cached.abilities
    end
    if compact then snapshot._production_stamp=stamp end
    presentation_cache[cache_key]={unit=unit,stamp=stamp,training=snapshot.training,research=snapshot.research,building_id=snapshot.building_id}
    return snapshot
end

function M.init(options)
    compact_execute = nil
    research_cache,research_generation={},{}
    presentation_versions,building_versions,presentation_cache,building_signatures={},{},{},{}
    local lifecycle={};active_lifecycle=lifecycle;local world=event_bus.get_generation()
    local function current()return active_lifecycle==lifecycle and event_bus.get_generation()==world end
    local function refresh(payload)
        if not current()then return end
        local player_id = tonumber(payload and payload.player_id)
        if player_id == nil then return end
        -- The compact production view owns its own selection and preserves the
        -- viewer's private lane. Do not route it through the combat-only DTO.
        if options.compact_refresh and options.compact_refresh(player_id,payload) then return end
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
        if not current()then return end
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
    event_bus.subscribe(events.WORKER_CHANGED,function(payload)
        if not current()then return end
        if payload and(payload.training_queue_changed or payload.training or payload.training_capacity_changed)then invalidate_presentation(payload)end
        refresh(payload)
    end)
    -- Training prices and unlocks change with progression or queue events.
    -- Wallet changes are checked on a training click and do not repaint options.
    local function refresh_research(payload)
        if not current()then return end
        invalidate_presentation(payload)
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
        if not current()then return end
        local entity=tonumber(payload and payload.entindex)
        if entity then building_versions[entity]=(building_versions[entity]or 0)+1;building_signatures[entity]=nil end
        for key in pairs(research_cache) do
            if key:match(":"..tostring(payload.entindex).."$") then research_cache[key]=nil end
        end
        refresh(payload)
    end)
    local function changed_building(payload)
        if not current()or not payload then return end
        local id=payload.building_id
        if id~='main_city'and id~='building_research_lab'and id~='building_advanced_research_lab'then return end
        local entity=tonumber(payload.entindex);if not entity then return end
        local signature=tostring(payload.player_id)..':'..tostring(payload.team)..':'..tostring(payload.level)..':'..id
        if signature~=building_signatures[entity]then
            building_signatures[entity]=signature;building_versions[entity]=(building_versions[entity]or 0)+1
            refresh(payload)
        end
    end
    event_bus.subscribe(events.BUILDING_CHANGED,changed_building)
    for _,event in ipairs({events.PLAYER_DEFEATED,events.PLAYER_DISCONNECTED})do
        event_bus.subscribe(event,function(payload)if current()then invalidate_presentation(payload);refresh(payload)end end)
    end
    local function research_request(operation, request_event, payload, capture)
        if not current()then return end
        payload = payload or {}
        local player_id = options.source_player_id(payload)
        local request_id = tostring(payload.request_id or "")
        local diagnostic = type(IsInToolsMode) == "function" and IsInToolsMode()
        if diagnostic then
            print("[SURVIVAL_RESEARCH][SERVER] RECV operation=" .. operation
                .. " request_id=" .. request_id .. " player=" .. tostring(player_id)
                .. " unit=" .. tostring(payload.source_entindex)
                .. " group=" .. tostring(payload.technology_group))
        end
        if not options.valid_player_id(player_id) then
            if diagnostic then
                print("[SURVIVAL_RESEARCH][SERVER] REJECT request_id=" .. request_id
                    .. " reason=player_not_ready_or_unavailable")
            end
            return
        end
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
        if diagnostic then
            local research = result.research or {}
            print("[SURVIVAL_RESEARCH][SERVER] RESULT operation=" .. operation
                .. " request_id=" .. request_id .. " player=" .. tostring(player_id)
                .. " unit=" .. tostring(source) .. " success=" .. (result.ok and "1" or "0")
                .. " queued=" .. (result.queued and "1" or "0")
                .. " researching=" .. tostring(research.researching)
                .. " blocked_reason=" .. tostring(research.blocked_reason or "")
                .. " error=" .. tostring(result.error or "")
                .. " status_code=" .. tostring(result.error_code or ""))
        end
        local receipt = {
            operation = operation, request_id = request_id,
            source_entindex = source or -1, success = result.ok and 1 or 0,
            queued = result.queued and 1 or 0,
            refunded = result.refunded and 1 or 0,
            error = result.ok and "" or operation_error(result.error, "研究排队失败"),
            error_code = result.ok and "" or tostring(result.error_code or ""),
        }
        if not capture then options.send("ui_operation_result", player_id, receipt) end
        if result.ok then refresh({player_id = player_id, source_entindex = source})
        elseif not capture then
            event_bus.emit(events.UI_NOTIFICATION, {player_id = player_id,
                message = operation_error(result.error, "研究排队失败"), level = "error"})
        end
        return receipt
    end
    CustomGameEventManager:RegisterListener("ui_research_queue_request", function(_, payload)
        research_request("research_queue", events.TECHNOLOGY_PURCHASE_NEXT_REQUEST, payload)
    end)
    CustomGameEventManager:RegisterListener("ui_research_cancel_request", function(_, payload)
        research_request("research_cancel", events.TECHNOLOGY_RESEARCH_CANCEL_REQUEST, payload)
    end)
    local function worker_request(payload,capture)
        if not current()then return end
        payload = payload or {}
        local player_id = options.source_player_id(payload)
        if not options.valid_player_id(player_id) then return end
        local source = entity_index(payload.source_entindex)
        local city = resolve_entity(source)
        local building = city and event_bus.request(events.BUILDING_QUERY_REQUEST, {
            entindex = source,
        })
        local result, training
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
                _training_trace = capture and payload._training_trace or nil,
            }) or { ok = false, error = "训练请求未响应" }
            -- Reconcile this accepted or rejected click against the same
            -- authenticated city's current reservations. This is a per-click
            -- receipt; ordinary HUD updates continue through refresh().
            training = event_bus.request(events.WORKER_TRAINING_GET_REQUEST, {
                player_id = player_id, team = building.team,
                source_entindex = source,
            })
        end
        local receipt = {
            operation = "worker_train",
            request_id = tostring(payload.request_id or ""),
            source_entindex = source or -1,
            success = result.ok and 1 or 0,
            queued = result.queued and 1 or 0,
            job_id = result.job_id,
            training = training,
            error = result.ok and "" or operation_error(result.error, "训练失败"),
        }
        if not capture then options.send("ui_operation_result", player_id, receipt) end
        if result.ok then
            refresh({ player_id = player_id, source_entindex = source })
        elseif not capture then
            event_bus.emit(events.UI_NOTIFICATION, {
                player_id = player_id,
                message = operation_error(result.error, "训练失败"),
                level = "error",
            })
        end
        return receipt
    end
    CustomGameEventManager:RegisterListener("ui_worker_train_request", function(_,payload) return worker_request(payload,false) end)
    compact_execute = function(kind,payload)
        if kind=="production_train" then return worker_request(payload,true) end
        local routes={production_research={"research_queue",events.TECHNOLOGY_PURCHASE_NEXT_REQUEST},
            production_auto={"shop_auto_research_toggle",events.SHOP_AUTO_RESEARCH_TOGGLE_REQUEST},
            production_cancel={"research_cancel",events.TECHNOLOGY_RESEARCH_CANCEL_REQUEST}}
        local route=routes[kind]
        if route then return research_request(route[1],route[2],payload,true) end
    end
end

-- Called only by the authenticated compact view adapter. All original source,
-- owner/team, queue, price, refund and completion checks still run above.
function M.execute(kind,payload)
    if not compact_execute then return nil,"production_not_initialized" end
    return compact_execute(kind,payload)
end

return M
