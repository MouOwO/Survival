-- Private, presentation-only cw/d dispatch. No reward/profile authority lives
-- here: every intent still goes through its registered business validator.
-- Schema/handler indexes initialize once. Idle has no timer or scan. A dispatch
-- processes at most eight urgent/two background frames and a real 2ms budget;
-- per-view invalidation visits at most eight queued transactions, never scenes.
local wire=require("ui/compact_wire")
local M={}
local function need(ok,why)if not ok then error(why,0)end end
local function record(lookup,key)
    local value=lookup.by_key[key]
    return type(value)=="table" and value.id or value
end
local ACTIONS={[1]="daily_claim",[2]="benefit_claim",[3]="pass_purchase",
    [4]="lottery_draw",[5]="archive_title",[6]="archive_action",[7]="lottery_read"}

function M.new(options)
    local lookup=options.lookup
    local schema=assert(wire.compile_lookup(lookup,1))
    local proof=assert(wire.measure_budget(options.budget,50))
    local fields=lookup.field_by_name
    local control=assert(record(lookup,"wire:control"))
    local handlers,players={},{}
    local generation,queued,running=1,false,false
    local budget_started,budget_work,budget_background,budget_cpu=nil,0,0,0
    local budget_initialized=false
    local queues={{first=1,last=0},{first=1,last=0}}
    local statistics={frames=0,native_bytes=0,max_native_bytes=0,transactions=0,rejected=0,drains=0}
    local api={}
    local function binding(state,view,epoch)
        return {schema=1,schema_sha256=lookup.sha256,session=state.session,epoch=epoch or 1,view=view}
    end
    local function push(job,priority)
        if job.queued then return end
        job.queued=true
        local queue=queues[priority and 1 or 2]
        queue.last=queue.last+1;queue[queue.last]=job
    end
    local function pop()
        for index=1,2 do
            local queue=queues[index]
            if queue.first<=queue.last then
                local job=queue[queue.first];queue[queue.first]=nil;queue.first=queue.first+1
                job.queued=false
                if queue.first>queue.last then queue.first,queue.last=1,0 end
                return job,index
            end
        end
    end
    local function has_jobs()return queues[1].last>0 or queues[2].last>0 end
    local function invalidate(view)
        for _,job in ipairs(view.jobs)do job.active=false end
        view.jobs={}
    end
    local function current(state)
        return players[state.id]==state and options.player(state.id)==state.handle and options.authorize(state.id)
    end
    local schedule
    local function drain(from_scheduler)
        if running then return end
        queued=false;running=true;statistics.drains=statistics.drains+1
        local started=options.cpu_ms and options.cpu_ms()
        -- Concurrent recipients/publish calls share this real-time window;
        -- each synchronous caller cannot restart another eight-frame/2ms slice.
        if not budget_initialized or started and (not budget_started or started-budget_started>=16 or started<budget_started)
            or not started and from_scheduler then
            budget_started,budget_work,budget_background,budget_cpu=started,0,0,0
            budget_initialized=true
        end
        while has_jobs() and budget_work<8 do
            if started and budget_cpu+options.cpu_ms()-started>=2 then break end
            if queues[1].last==0 and budget_background>=2 then break end
            local job,lane=pop();budget_work=budget_work+1
            if lane==2 then budget_background=budget_background+1 end
            if job.active and current(job.owner)then
                local packet=job.packets[job.next]
                local sent=wire.production_send(packet,proof,options.budget.engine_build,function(event,value)
                    return options.emit(job.owner.id,event,value)
                end,options.budget.networksystem_sha256)
                if not sent then
                    job.active=false;job.view.needs_full=true;statistics.rejected=statistics.rejected+1
                else
                    statistics.frames=statistics.frames+1
                    statistics.native_bytes=statistics.native_bytes+sent.native_message_bytes
                    statistics.max_native_bytes=math.max(statistics.max_native_bytes,sent.native_message_bytes)
                    job.next=job.next+1
                    if job.next<=#job.packets then push(job,job.priority)
                    else
                        job.active=false
                        -- Retire the direct per-view reference without scanning
                        -- the global queue. A view has at most eight in-flight tx.
                        local keep={};for _,pending in ipairs(job.view.jobs)do if pending.active then keep[#keep+1]=pending end end
                        job.view.jobs=keep
                        if keep[1]then push(keep[1],keep[1].priority)end
                    end
                end
            end
        end
        if started then budget_cpu=budget_cpu+math.max(0,options.cpu_ms()-started)end
        running=false;schedule()
    end
    schedule=function()
        if queued or running or not has_jobs()then return end
        queued=true;local own=generation
        options.after(0,function()if own==generation then drain(true)end end,"compact_ui_dispatch")
    end
    local function state_for(id,create)
        local handle=options.player(id)
        if not handle or not options.authorize(id)then return nil end
        local state=players[id]
        if state and state.handle~=handle then
            for _,view in pairs(state.views)do invalidate(view)end
            players[id]=nil;state=nil
        end
        if not state and create then
            state={id=id,handle=handle,session=options.session_token(id),views={},incoming={},hello_revision=0}
            need(type(state.session)=="number" and state.session>=1 and state.session<=16383,"short_session_alias_required")
            players[id]=state
        end
        return state
    end
    local function view_for(state,id)
        local view=state.views[id]
        if not view then view={id=id,epoch=0,revision=0,jobs={},open=false};state.views[id]=view end
        return view
    end
    local function enqueue(state,view,ops,full,priority,hello)
        if #ops==0 and not full then return {sent=false,unchanged=true}end
        if full then
            invalidate(view)
            if not hello then view.epoch=view.epoch+1 end
            need(view.epoch<=16383,"view_epoch_requires_new_session")
            view.revision=0;view.needs_full=false
        end
        need(view.epoch>0,"initial_full_required")
        if #view.jobs>=8 then return nil,"bounded_view_queue_requires_full_resync"end
        local revision=view.revision+1
        local packets,why=wire.encode(schema,binding(state,view.id,view.epoch),revision,ops,{full=full,value_budget=24})
        if not packets then return nil,why end
        view.revision=revision
        local job={owner=state,view=view,packets=packets,next=1,priority=priority~=false,active=true}
        view.jobs[#view.jobs+1]=job
        if #view.jobs==1 then push(job,job.priority)end
        statistics.transactions=statistics.transactions+1
        if job.priority and not running and not queued then drain()else schedule()end
        return {queued=true,frames=#packets,epoch=view.epoch,revision=revision}
    end
    local function hello(state)
        local view=view_for(state,1);view.epoch=1
        local ops={}
        for word=1,8 do
            ops[#ops+1]={record=assert(record(lookup,"wire:hello:"..word)),field=fields.count,
                value=tonumber(lookup.sha256:sub((word-1)*8+1,word*8),16)}
        end
        -- Repeated explicit bootstrap requests advance, never rewind, the
        -- handshake's revision within this server session.
        local prior=view.revision
        invalidate(view);view.revision=prior
        local packets,why=wire.encode(schema,binding(state,1,1),prior+1,ops,{full=true,value_budget=24})
        if not packets then return nil,why end
        view.revision=prior+1
        local job={owner=state,view=view,packets=packets,next=1,priority=true,active=true}
        view.jobs={job};push(job,true);if not running and not queued then drain()else schedule()end
        return true
    end
    function api.register_view(id,handler)
        need(type(id)=="number" and id>=2 and id<=16383 and not handlers[id],"unique_compact_view_required")
        need(type(handler)=="table" and type(handler.snapshot)=="function","compact_snapshot_provider_required")
        handlers[id]=handler;return true
    end
    function api.is_open(id,view)
        local state=state_for(id,false);return not not(state and state.views[view]and state.views[view].open)
    end
    function api.is_bound(id)
        local state=state_for(id,false)
        return state~=nil and state.views[1]~=nil and state.views[1].revision>0
    end
    function api.publish(id,view_id,ops,settings)
        settings=settings or {};local state=state_for(id,false)
        if not state or not handlers[view_id]then return nil,"compact_view_not_bound"end
        local view=view_for(state,view_id)
        if view.revision==0 then settings.full=true end
        if #view.jobs>=8 and not settings.full then view.needs_full=true end
        if view.needs_full and not settings.full then
            ops=handlers[view_id].snapshot(id);settings.full=true
        end
        if not ops then return nil,"compact_projection_unavailable"end
        return enqueue(state,view,ops,settings.full==true,settings.priority~=false)
    end
    local function full_snapshot(state,view_id,opening)
        local handler=handlers[view_id];if not handler then return nil,"compact_view_unknown"end
        local view=view_for(state,view_id);view.open=true
        local ops=opening and handler.open and handler.open(state.id)
        if not ops then ops=handler.snapshot(state.id)end
        return ops and enqueue(state,view,ops,true,true) or nil
    end
    function api.receive(id,packet)
        local header,why=wire.peek_header(packet)
        if not header then statistics.rejected=statistics.rejected+1;return nil,why end
        if header.view==1 and header.kind=="resync"then
            local bootstrap={schema=1,schema_sha256=lookup.sha256,session=1,epoch=1,view=1}
            if not wire.decode_resync(schema,bootstrap,packet)then return nil,"invalid_bootstrap_request"end
            local state=state_for(id,true);return state and hello(state)or nil
        end
        local state=state_for(id,false)
        if not state or header.session~=state.session or header.schema~=1 or not handlers[header.view]then
            return nil,"compact_binding_required"
        end
        local handler,view=handlers[header.view],view_for(state,header.view)
        if header.kind=="resync"then
            if not wire.decode_resync(schema,binding(state,header.view,view.epoch),packet)then return nil,"stale_resync"end
            return full_snapshot(state,header.view,false)
        end
        local incoming=state.incoming[header.view]
        if not incoming then incoming=assert(wire.new_receiver(schema,binding(state,header.view,1)));state.incoming[header.view]=incoming end
        local tx,error_code=incoming.accept(packet)
        if not tx then return nil,error_code end
        if tx.pending then return true end
        local values={}
        for _,change in ipairs(tx.changes)do
            if change.record~=control or change.remove then incoming.abort();return nil,"control_record_required"end
            local allowed=change.field==fields.visible or change.field==fields.known or change.field==fields.action_code
                or change.field==fields.arg_a or change.field==fields.arg_b or change.field==fields.arg_c or change.field==fields.request_token
            if not allowed then incoming.abort();return nil,"control_field_not_allowed"end
            values[change.field]=change.value
        end
        if values[fields.action_code]then
            local action=ACTIONS[values[fields.action_code]]
            if not action or not handler.intent or not view.open then incoming.abort();return nil,"view_intent_not_allowed"end
            local token=values[fields.request_token]
            if not token or token<1 or token>16383 then incoming.abort();return nil,"intent_token_required"end
            incoming.commit(tx)
            local result=handler.intent(id,action,{arg_a=values[fields.arg_a],arg_b=values[fields.arg_b],arg_c=values[fields.arg_c],request_token=token})
            return result==nil and true or result
        end
        incoming.commit(tx)
        if values[fields.visible]==true or values[fields.visible]==1 then return full_snapshot(state,header.view,true)end
        view.open=false
        -- A closed panel must not continue draining its former full catalogue.
        -- Its next tiny hint or real Open starts a fresh atomic epoch instead.
        invalidate(view);view.revision=0;view.needs_full=false
        if values[fields.known]==true or values[fields.known]==1 then
            if handler.probe then local result=handler.probe(id);return result==nil and true or result end
        elseif handler.close then local result=handler.close(id);return result==nil and true or result end
        return true
    end
    function api.disconnect(id)
        local state=players[id];if state then for _,view in pairs(state.views)do invalidate(view)end end
        players[id]=nil
    end
    function api.reset()
        generation=generation+1;players={};queues={{first=1,last=0},{first=1,last=0}};queued=false
        budget_started,budget_work,budget_background,budget_cpu=nil,0,0,0
        budget_initialized=false
        options.cancel("compact_ui_dispatch")
    end
    function api.inspect()return statistics end
    return api
end

local default,failed,pending_views=nil,false,{}
local world,listener=nil,nil
-- Never recycle an alias while this server Lua/module lifecycle can still have
-- queued callbacks. A fresh server/network channel has a separate namespace.
local next_session_alias=0
local function allocate_session_alias()
    need(next_session_alias<16383,"compact_session_alias_exhausted")
    next_session_alias=next_session_alias+1
    return next_session_alias
end
local function ensure_world()
    local bus=package.loaded["core/event_bus"]
    local current=bus and bus.get_generation and bus.get_generation()
    if world and current and current~=world then
        if default then default.reset()end
        if listener and CustomGameEventManager and type(CustomGameEventManager.UnregisterListener)=="function"then
            pcall(CustomGameEventManager.UnregisterListener,CustomGameEventManager,listener)
        end
        default,failed,pending_views,listener=nil,false,{},nil
    end
    world=current or world
end
local function instance()
    ensure_world()
    if default then return default end
    if failed then return nil end
    local ok,result=pcall(function()
        local lookup=require("config/generated/ui_static_catalog_lookup")
        local budget=require("config/generated/ui_compact_wire_budget")
        local scheduler=require("core/scheduler")
        local function authorize(id)
            local loading=package.loaded["systems/startup_loading_service"]
            return PlayerResource and PlayerResource:IsValidPlayerID(id)
                and require("core/test_access_policy").enforce(id)==true
                and loading and loading.is_player_ready(id)==true
        end
        local value=M.new({lookup=lookup,budget=budget,
            player=function(id)return PlayerResource and PlayerResource:GetPlayer(id)end,authorize=authorize,
            session_token=allocate_session_alias,
            after=scheduler.after,cancel=scheduler.cancel,
            cpu_ms=type(GetSystemTimeMS)=="function"and GetSystemTimeMS or nil,
            emit=function(id,event,packet)
                local player=PlayerResource:GetPlayer(id)
                if not player or not authorize(id)then return false end
                return CustomGameEventManager:Send_ServerToPlayer(player,event,packet)
            end})
        listener=CustomGameEventManager:RegisterListener("cw",function(source,payload)
            if value~=default then return end
            local id=tonumber(payload and payload.PlayerID)
            if not id or not authorize(id)or type(payload.d)~="string"then return end
            local player=PlayerResource:GetPlayer(id)
            if player and type(player.GetPlayerID)=="function"and player:GetPlayerID()~=id then return end
            local ok_actor,actor=pcall(EntIndexToHScript,tonumber(source)or-1)
            if not ok_actor or actor~=player then return end
            value.receive(id,{d=payload.d})
        end)
        for id,handler in pairs(pending_views)do value.register_view(id,handler)end
        return value
    end)
    if ok then default=result;return result end
    failed=true;return nil
end
function M.available()return instance()~=nil end
function M.register_view(id,handler)
    ensure_world()
    local existing=default
    need(not pending_views[id],"compact_view_registered_twice");pending_views[id]=handler
    local value=instance()
    -- A newly created instance consumed pending_views; an existing one has not.
    if existing and value==existing then return value.register_view(id,handler)end
    return value~=nil
end
function M.publish(...)local value=instance();if value then return value.publish(...)end;return nil,"compact_runtime_unavailable"end
function M.is_open(...)local value=instance();return value and value.is_open(...)or false end
function M.is_bound(...)local value=instance();return value and value.is_bound(...)or false end
function M.inspect()local value=instance();return value and value.inspect()or{available=false}end
return M
