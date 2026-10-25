-- Server-owned progression. Client clicks can request a snapshot or skip;
-- only completed gameplay events can advance the four tutorial steps.
local bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local profiles = require("systems/player_profile_service")
local setup = require("systems/match_setup_service")
local context = require("systems/player_context_service")
local persistence = require("systems/onboarding_persistence")
local locations = require("systems/onboarding_targets")
local M = {}
local key = "SURVIVAL_ONBOARDING_RUNTIME"
local runtime = rawget(_G,key) or {generation=0,states={}}
rawset(_G,key,runtime)
local steps = {
    {id="wall",building="wall",ability="ability_build_wall",title="守住楼梯口",
        description="点击城墙技能，在自己楼梯口的绿色区域建造城墙，挡住敌人的进攻。"},
    {id="main_city",building="main_city",ability="ability_build_main_city",title="建立主城",
        description="点击主城技能，在绿色区域建立主城，解锁人口和农民训练。"},
    {id="worker",title="训练一名农民",
        description="已选中你的主城。点击高亮的农民图标，训练一名农民采集木材。"},
    {id="tower",building="arrow_tower",ability="ability_build_arrow_tower",title="建立防线",
        description="农民会自动采集木材，木材足够后点击防御塔技能，在绿色区域建造防御塔，配合城墙抵御敌人。"},
}
local function now() return type(Time)=="function" and Time() or GameRules:GetGameTime() end
local function valid(unit)
    return unit and (not unit.IsNull or not unit:IsNull()) and (not unit.IsAlive or unit:IsAlive())
end
local function index(unit) return valid(unit) and unit.entindex and unit:entindex() or -1 end
local function entity(id)
    if type(EntIndexToHScript)~="function" or not tonumber(id) or tonumber(id)<0 then return nil end
    local ok,value=pcall(EntIndexToHScript,tonumber(id));return ok and valid(value) and value or nil
end
local function player(id)
    return PlayerResource and PlayerResource.GetPlayer and PlayerResource:GetPlayer(id) or nil
end
local function connected(id)
    return player(id) and (not PlayerResource.GetConnectionState
        or PlayerResource:GetConnectionState(id)==(DOTA_CONNECTION_STATE_CONNECTED or 2))
end
local function supported()
    local mode=setup.get_mode()
    return GetMapName()=="template_map" and (mode=="standard" or mode=="pure")
end
local function builder(id)
    local result=bus.request(events.BUILDER_GET_REQUEST,{player_id=id})
    return result and valid(result.builder) and result.builder or nil
end
local function owned(unit,id)
    -- Factories register ownership before emitting completion. An engine owner
    -- chain can still be stale, or default to player zero for an unknown unit.
    return valid(unit) and type(context.is_owned_by)=="function"
        and context.is_owned_by(id,unit)==true and type(context.owner_player_id)=="function"
        and context.owner_player_id(unit,true)==id or false
end
local function account(id)
    local provider=profiles.get_provider and profiles.get_provider()
    if provider and provider.resolve_account_id then
        local ok,value=pcall(provider.resolve_account_id,id)
        if ok and value then return tostring(value) end
    end
    local profile=profiles.get_account_profile and profiles.get_account_profile(id)
        or profiles.get_profile and profiles.get_profile(id)
    return profile and profile.account_id and tostring(profile.account_id) or nil
end
local function state(id)
    id=tonumber(id)
    if not id or id~=id or id<0 or id~=math.floor(id) then return nil end
    local binding,session=account(id),setup.get_session_id()
    if not binding then return nil end
    local value=runtime.states[id]
    if not value or value.account~=binding or value.session~=session then
        runtime.message_generation=(runtime.message_generation or 0)+1
        value={player_id=id,account=binding,session=session,step=1,revision=0,completed={},
            ui_generation=runtime.message_generation}
        runtime.states[id]=value
    end
    return value
end
local function current(value,generation)
    return runtime.generation==generation and runtime.states[value.player_id]==value
        and runtime.world==GameRules:GetGameModeEntity() and account(value.player_id)==value.account
        and setup.get_session_id()==value.session
end
local function in_target(position,target)
    return position and target and math.abs(position.x-target.x)<=target.width/2
        and math.abs(position.y-target.y)<=target.height/2
end
local function active(value)
    return value and value.required and not value.terminal and value.started and supported()
        and connected(value.player_id) and not (context.is_defeated and context.is_defeated(value.player_id))
        and owned(builder(value.player_id),value.player_id) or false
end
function M.snapshot(id)
    local value=state(id)
    if not value then return {generation=runtime.generation,revision=0,active=false} end
    local step=steps[value.step]
    local target=step and value.targets and value.targets[step.id]
    return {generation=value.ui_generation,revision=value.revision,active=active(value),
        step=value.terminal=="completed" and "complete" or step and step.id or "complete",
        step_index=math.min(value.step,4),total_steps=4,title=step and step.title or "入门引导已完成",
        description=step and step.description or "你已经学会建立自己的防线。",
        ability_name=step and step.ability or "",builder_entindex=index(builder(value.player_id)),
        main_city_entindex=value.completed.main_city or -1,build_grid_size=64,
        targets=target and {target} or {},placement_required=step and step.building~=nil or false,
        waiting=value.started and not value.targets or false,persisting=value.persisting or 0,
        error=value.error or ""}
end
local function publish(value)
    value.revision=value.revision+1
    local recipient=player(value.player_id)
    if recipient then CustomGameEventManager:Send_ServerToPlayer(recipient,"survival_onboarding_state",M.snapshot(value.player_id)) end
end
local save_terminal
save_terminal=function(value)
    if value.saved or value.saving or not value.terminal then return end
    value.saving=true;value.persisting=1
    local generation=runtime.generation
    persistence.finish(value.player_id,value.terminal,function(receipt)
        if not current(value,generation) then return end
        value.saving=false
        if receipt.ok then value.saved=true;value.persisting=0;value.error=nil
        else
            value.persisting=2;value.error="引导状态保存暂未完成，将自动重试。"
            scheduler.after(5,function()
                if current(value,generation) then save_terminal(value) end
            end,"onboarding_save_"..value.player_id)
        end
        publish(value)
    end)
end
local function terminal(value,outcome)
    if value.terminal then return end
    value.terminal=outcome;value.error=nil;value.persisting=1
    if outcome=="completed" then value.step=5 end
    -- Release the local mask immediately; a failed durable receipt must not
    -- trap a player who already chose to skip. Keep retrying only the save.
    publish(value);save_terminal(value)
end
local function advance(value)
    value.step=value.step+1;value.error=nil
    if value.step>4 then terminal(value,"completed") else publish(value) end
end
local function recover(value)
    local existing=value.targets.existing or {}
    value.completed.wall=existing.wall or value.completed.wall
    value.completed.main_city=existing.main_city or value.completed.main_city
    value.completed.tower=existing.tower or value.completed.tower
    local list=bus.request(events.WORKER_LIST_REQUEST,{player_id=value.player_id})
    for _,row in ipairs(list and (list.workers or list) or {}) do
        if row.player_id==value.player_id and row.worker_type=="lumberjack" and not row.super_lumberjack
            and owned(row.unit,value.player_id) then value.worker=true end
    end
    while value.step<=4 do
        local name=steps[value.step].id
        if name=="worker" and value.worker or name~="worker" and value.completed[name] then value.step=value.step+1
        else break end
    end
    if value.step>4 then terminal(value,"completed") end
end
function M.refresh(id)
    local value=state(id)
    if not value then return end
    if value.terminal then publish(value);return end
    local metadata=persistence.get(value.player_id)
    if not metadata.loaded then
        if not value.reading and connected(value.player_id) and now()>=(value.next_read or 0) then
            value.reading=true
            local generation=runtime.generation
            persistence.ensure(value.player_id,function(receipt)
                if not current(value,generation) then return end
                value.reading=false
                if receipt.ok and receipt.loaded then
                    value.read_failures=0;value.next_read=nil;M.refresh(value.player_id)
                else
                    value.read_failures=(value.read_failures or 0)+1
                    value.next_read=now()+math.min(30,2^math.min(5,value.read_failures))
                end
            end)
        end
        publish(value);return
    end
    value.required=metadata.required==true
    if not value.required then publish(value);return end
    if supported() and owned(builder(value.player_id),value.player_id) then
        value.started=true
        if not value.targets then
            local targets,reason=locations.get(value.player_id,setup.get_mode())
            value.targets=targets
            value.error=not targets and (reason=="misplaced_wall"
                and "已有城墙不在引导位置，请跳过本次引导继续游戏。"
                or "引导区域暂不可用，请稍候或选择跳过。") or nil
            if targets then recover(value) end
        end
    end
    publish(value)
end
function M.skip(id)
    local value=state(id)
    if not value or not value.required or value.terminal then return false end
    terminal(value,"skipped");return true
end
function M.can_build(payload)
    local value=state(payload and payload.player_id)
    if not active(value) then return nil end
    local step=steps[value.step]
    if not step or not step.building or payload.building_id~=step.building then
        return {ok=false,error="请先完成当前新手引导，或点击跳过引导。"}
    end
    if not in_target(payload.position,value.targets and value.targets[step.id]) then
        return {ok=false,error="请在新手引导的绿色区域内建造。"}
    end
    return {ok=true}
end
local function completed_building(payload)
    local id=tonumber(payload and payload.player_id)
    local value=id and runtime.states[id]
    if not active(value) then return end
    local step=steps[value.step]
    if not step or payload.building_id~=step.building or payload.constructing==true
        or payload.constructing==1 or payload.pending==true or payload.pending==1 then return end
    local unit=payload.unit or entity(payload.entindex)
    if not owned(unit,id) or unit.HasModifier and unit:HasModifier("modifier_building_under_construction")
        or not in_target(unit:GetAbsOrigin(),value.targets and value.targets[step.id]) then return end
    value.completed[step.id]=index(unit);advance(value)
end
local function completed_worker(payload)
    local id=tonumber(payload and payload.player_id)
    local value=id and runtime.states[id]
    if not active(value) or value.step~=3 or payload.worker_type~="lumberjack"
        or tonumber(payload.count_delta)~=1 or payload.super_lumberjack or payload.training_queue_changed
        or payload.source_entindex and tonumber(payload.source_entindex)~=value.completed.main_city then return end
    local unit=payload.unit or entity(payload.entindex)
    if not owned(unit,id) then return end
    value.worker=true;advance(value)
end
local function actor(source)
    local source_index=tonumber(source)
    if not source_index or source_index~=math.floor(source_index) then return nil end
    local unit=entity(source_index)
    if not unit or type(unit.GetPlayerID)~="function" then return nil end
    local id=unit:GetPlayerID()
    if player(id)~=unit or not connected(id) then return nil end
    if PlayerResource.IsFakeClient and PlayerResource:IsFakeClient(id) then return nil end
    if PlayerResource.GetTeam and PlayerResource:GetTeam(id)~=(DOTA_TEAM_GOODGUYS or 2) then return nil end
    return id
end
function M.init()
    for _,subscription in ipairs(runtime.subscriptions or {}) do (runtime.bus or bus).unsubscribe(subscription) end
    if runtime.world==GameRules:GetGameModeEntity() then
        for _,listener in ipairs(runtime.listeners or {}) do CustomGameEventManager:UnregisterListener(listener) end
    else runtime.states={} end
    runtime.world=GameRules:GetGameModeEntity();runtime.generation=runtime.generation+1;runtime.bus=bus
    local generation=runtime.generation
    persistence.init()
    for _,value in pairs(runtime.states) do
        -- Those requests belonged to the previous callback generation. Their
        -- eventual receipts cannot own this generation's local waiting flags.
        value.reading=nil;value.saving=nil;value.next_request=nil;value.next_read=nil
        runtime.message_generation=(runtime.message_generation or 0)+1
        value.ui_generation=runtime.message_generation
    end
    local function changed(payload) if payload and payload.player_id~=nil then M.refresh(payload.player_id) end end
    runtime.subscriptions={bus.subscribe(events.PLAYER_PROFILE_CHANGED,changed),bus.subscribe(events.BUILDER_READY,changed),
        bus.subscribe(events.BUILDING_CREATED,completed_building),bus.subscribe(events.WORKER_CHANGED,completed_worker),
        bus.subscribe(events.PLAYER_DISCONNECTED,changed),bus.subscribe(events.PLAYER_DEFEATED,changed),
        bus.subscribe(events.BUILDING_DESTROYED,function(payload)
            local value=payload and runtime.states[tonumber(payload.player_id)]
            if not value or value.terminal then return end
            if payload.entindex==value.completed.wall then value.completed.wall=nil;value.step=1;value.targets=nil end
            if payload.entindex==value.completed.main_city then value.completed.main_city=nil;value.step=math.min(value.step,2);value.targets=nil end
            M.refresh(value.player_id)
        end)}
    runtime.delegate=M
    if runtime.request_generation~=bus.get_generation() then
        runtime.request_generation=bus.get_generation()
        bus.handle_request("onboarding.build_allowed.request",function(payload)
            return runtime.delegate.can_build(payload)
        end)
    end
    runtime.listeners={}
    local function listen(name,handler)
        runtime.listeners[#runtime.listeners+1]=CustomGameEventManager:RegisterListener(name,function(source)
            if runtime.generation~=generation then return end
            local id=actor(source)
            if id~=nil then handler(id) end
        end)
    end
    listen("ui_onboarding_request_state",function(id)
        local value=state(id)
        if value and now()>=(value.next_request or 0) then value.next_request=now()+0.5;M.refresh(id) end
    end)
    listen("ui_onboarding_skip",M.skip)
    for _,value in pairs(runtime.states) do
        if value.terminal and not value.saved then save_terminal(value) end
    end
    scheduler.every(1,function()
        if runtime.generation~=generation or runtime.world~=GameRules:GetGameModeEntity() then return false end
        for _,id in ipairs(context.active_player_ids()) do
            local value=state(id)
            if value and not value.saved and not value.terminal and (value.required or not persistence.get(id).loaded) then M.refresh(id) end
        end
    end,"onboarding_monitor")
end
return M
