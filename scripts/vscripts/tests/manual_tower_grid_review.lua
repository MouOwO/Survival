-- Explicit Tools helper for a normally admitted match. Requiring this file is
-- inert. run() submits real construction requests, never grants resources,
-- registers fixture buildings, changes difficulty/auth, or teleports a builder.
local M = {}
local active
local sequence = {"wall", "main_city", "arrow_tower"}
local TASK = "manual_tower_grid_review"
local TIMEOUT = 240

local function valid(unit)
    return unit and not unit:IsNull() and unit:IsAlive()
end

local function now() return GameRules:GetGameTime() end

local function emit(state, reason)
    local p = state.tower and valid(state.tower) and state.tower:GetAbsOrigin() or nil
    local ability = state.tower and valid(state.tower)
        and state.tower:FindAbilityByName("ability_building_blink") or nil
    print(string.format("TOWER_GRID_REVIEW status=%s stage=%s reason=%s player=%d tower=%s pos=%s ability=%s elapsed=%.2f",
        state.status, tostring(sequence[state.stage] or "complete"), tostring(reason or state.reason or ""),
        state.player_id, tostring(p and state.tower:entindex() or -1),
        p and string.format("%.0f,%.0f,%.1f",p.x,p.y,p.z) or "none",
        tostring(ability and ability:entindex() or -1),now()-state.started_at))
end

local function stop(state, reason)
    state.status, state.reason = "stopped", reason
    require("core/scheduler").cancel(TASK)
    -- Do not erase real construction or player's existing structures/orders.
    emit(state)
    return false
end

local function outside_art_fixture(point, footprint)
    -- Existing two-row presentation fixture centered at (320,5460), with extra
    -- clearance for larger wall footprints. This excludes only test placement.
    local margin=math.max(footprint.x or 2,footprint.y or 2)*32
    return point.x+margin < -512 or point.x-margin > 1152
        or point.y+margin < 5000 or point.y-margin > 6000
end

local function candidates(builder, definition)
    local source=builder:GetAbsOrigin()
    local result={}
    -- Exact placement still comes from BUILD_CAN_PLACE_REQUEST. Prefer nearby
    -- cells outside the builder hull, then expand up to 1280 world units.
    for dx=-20,20 do
        for dy=-20,20 do
            local distance=dx*dx+dy*dy
            if distance>=9 and distance<=400 then
                local point=Vector(source.x+dx*64,source.y+dy*64,source.z)
                if outside_art_fixture(point,definition.footprint or {}) then
                    result[#result+1]={position=point,distance=distance}
                end
            end
        end
    end
    table.sort(result,function(a,b)
        if a.distance~=b.distance then return a.distance<b.distance end
        if a.position.x~=b.position.x then return a.position.x<b.position.x end
        return a.position.y<b.position.y
    end)
    return result
end

local function under_construction(state, building_id)
    if state.constructing and valid(state.constructing)
        and state.constructing:HasModifier("modifier_building_under_construction") then return true end
    state.constructing=nil
    -- Walls are npc_dota_building; city/tower are npc_dota_creature. The builder
    -- clears its approach task at construction START, before BUILDING_LIST can
    -- see the finished structure. Scanning only creatures misreports that gap.
    for _,class_name in ipairs({"npc_dota_building","npc_dota_creature"}) do
        for _,unit in ipairs(Entities:FindAllByClassname(class_name) or {}) do
            if valid(unit) and tonumber(unit.survival_player_id)==state.player_id
                and unit.survival_building_id==building_id
                and unit:HasModifier("modifier_building_under_construction") then
                state.constructing=unit
                print("TOWER_GRID_REVIEW constructing="..building_id.." ent="..unit:entindex().." class="..class_name)
                return true
            end
        end
    end
    return false
end

local function wait_for_wood(state, builder, required)
    local bus,events=require("core/event_bus"),require("core/events")
    local wallet=bus.request(events.RESOURCE_GET_REQUEST,{player_id=state.player_id}) or {}
    local workers=bus.request(events.WORKER_LIST_REQUEST,{player_id=state.player_id}) or {}
    local worker
    for _,entry in ipairs(workers) do
        if tonumber(entry.player_id)==state.player_id and valid(entry.unit)
            and (entry.worker_type=="lumberjack" or entry.unit.survival_worker_type=="lumberjack") then
            worker=entry.unit;break
        end
    end
    if not worker and not state.worker_training_requested then
        local city=state.units.main_city
        if not valid(city) then return stop(state,"wood_requires_completed_city") end
        local progress=bus.request(events.WORKER_TRAINING_GET_REQUEST,{
            player_id=state.player_id,source_entindex=city:entindex()}) or {}
        if (tonumber(progress.queue_count) or 0)>0 then
            state.worker_training_requested=true
            print("TOWER_GRID_REVIEW reuse_pending_lumberjack=1")
        else
            -- Train once through the real queue at the CSV price. Do not use
            -- cost overrides, prepaid flags, free slots, grants or fake hits.
            local training=bus.request(events.WORKER_TRAIN_REQUEST,{
                player_id=state.player_id,city=city,training_id="train_lumberjack_auto"})
            if not training or not training.ok then
                return stop(state,"lumberjack_train:"..tostring(training and training.error or "unavailable"))
            end
            state.worker_training_requested=true
            print("TOWER_GRID_REVIEW train_lumberjack=queued source=normal_worker_training")
        end
    end
    state.last_error="waiting_for_wood:"..tostring(wallet.wood or "unknown").."/"..tostring(required)
    if not state.last_harvest_log or now()-state.last_harvest_log>=5 then
        state.last_harvest_log=now()
        print(string.format("TOWER_GRID_REVIEW harvesting wood=%s required=%s worker=%s elapsed=%.2f",
            tostring(wallet.wood or "unknown"),tostring(required),tostring(worker and worker:entindex() or "training"),
            now()-state.started_at))
    end
    -- The existing lumberjack modifier selects and attacks its assigned real
    -- resource tree; this helper only observes the normal wallet until ready.
    return 0.5
end

local function step(state)
    if active~=state or state.status~="running" then return false end
    if now()-state.started_at>=TIMEOUT then return stop(state,"timeout_240s:"..tostring(state.last_error or "waiting_for_construction")) end
    local bus,events=require("core/event_bus"),require("core/events")
    local owner=bus.request(events.BUILDER_GET_REQUEST,{player_id=state.player_id})
    if not owner or not owner.ok or not valid(owner.builder) then
        return stop(state,"builder_unavailable:"..tostring(owner and owner.error))
    end
    local builder=owner.builder
    local building_id=sequence[state.stage]
    local listed=bus.request(events.BUILDING_LIST_REQUEST,{player_id=state.player_id})
    for _,item in ipairs(listed and listed.buildings or {}) do
        if item.player_id==state.player_id and item.building_id==building_id and valid(item.unit) then
            state.completed[building_id]=item.entindex or item.unit:entindex()
            state.units[building_id]=item.unit
            print("TOWER_GRID_REVIEW completed="..building_id.." ent="..tostring(state.completed[building_id]))
            if building_id=="arrow_tower" then
                state.tower=item.unit;state.status="ready";state.reason="real_construction_complete"
                emit(state)
                return false
            end
            state.stage=state.stage+1;state.queued=false;state.points=nil;state.point_index=1;state.constructing=nil
            state.approach_ended_at=nil
            return 0.05
        end
    end
    if under_construction(state,building_id) then return 0.2 end
    if state.queued then
        if builder.survival_build_task then return 0.2 end
        -- Allow the engine's entity visibility/completion projection to settle
        -- after approach ends. Time this from the handoff, not from walking.
        state.approach_ended_at=state.approach_ended_at or now()
        local definition=require("config/buildings_config")[building_id] or {}
        if now()-state.approach_ended_at<math.max(2,(tonumber(definition.build_time) or 3)+1) then return 0.2 end
        return stop(state,"queued_build_ended_without_structure:"..building_id)
    end
    if builder.survival_build_task then
        if builder.survival_build_task.building_id==building_id then
            state.queued=true;state.submitted_at=now()
            print("TOWER_GRID_REVIEW reuse_pending="..building_id)
            return 0.2
        end
        return stop(state,"builder_busy:"..tostring(builder.survival_build_task.building_id))
    end
    local definition=require("config/buildings_config")[building_id]
    if not definition then return stop(state,"missing_definition:"..building_id) end
    local cost=definition.build_cost or {}
    local affordable=bus.request(events.RESOURCE_CAN_SPEND_REQUEST,{player_id=state.player_id,
        team=builder:GetTeamNumber(),wood=cost.wood or 0,gold=cost.gold or 0,
        population=definition.population_cost or 0})
    if not affordable or not affordable.ok then
        if building_id=="arrow_tower" and affordable and affordable.error=="wood_not_enough" then
            return wait_for_wood(state,builder,cost.wood)
        end
        return stop(state,"resource_check:"..tostring(affordable and affordable.error or "unavailable"))
    end
    state.points=state.points or candidates(builder,definition)
    for _=1,12 do
        local item=state.points[state.point_index]
        state.point_index=state.point_index+1
        if not item then return stop(state,"no_reachable_legal_cell:"..tostring(state.last_error)) end
        local check=bus.request(events.BUILD_CAN_PLACE_REQUEST,{player_id=state.player_id,
            caster=builder,building_id=building_id,position=item.position})
        if check and check.ok then
            local result=bus.request(events.BUILD_REQUEST,{player_id=state.player_id,caster=builder,
                building_id=building_id,position=check.grid.world_position})
            if result and result.ok then
                state.queued=true;state.submitted_at=now();state.position=check.grid.world_position
                state.approach_ended_at=nil
                print(string.format("TOWER_GRID_REVIEW queued=%s target=%.0f,%.0f,%.1f cost=%swood,%sgold",
                    building_id,state.position.x,state.position.y,state.position.z,tostring(cost.wood or 0),tostring(cost.gold or 0)))
                local task=builder.survival_build_task
                local work=task and task.work_position
                if work then print(string.format("TOWER_GRID_REVIEW builder=%d work=%.0f,%.0f,%.1f timeout=%.2f",
                    builder:entindex(),work.x,work.y,work.z,tonumber(task.timeout_at) or 0)) end
                return 0.2
            end
            state.last_error=result and result.error or "build_request_unavailable"
        else
            state.last_error=check and check.error or "validation_unavailable"
        end
    end
    return 0.05
end

function M.run(player_id)
    assert(IsInToolsMode and IsInToolsMode(),"tower grid review is Tools-only")
    player_id=tonumber(player_id) or 0
    if active and active.status=="running" then emit(active,"already_running");return active end
    local ready=require("systems/startup_loading_service")
    assert(ready.is_player_ready(player_id),"finish normal mode/difficulty and player loading before run()")
    local state={player_id=player_id,started_at=now(),status="running",stage=1,point_index=1,completed={},units={}}
    active=state
    local delay=step(state)
    if delay then require("core/scheduler").after(delay,function() return step(state) end,TASK) end
    return state
end

function M.status()
    if not active then print("TOWER_GRID_REVIEW status=not_started");return nil end
    emit(active)
    return active
end

function M.stop()
    if active and active.status=="running" then stop(active,"explicit_stop") end
    return active
end

return M
