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
    [4]="lottery_draw",[5]="archive_title",[6]="archive_action",[7]="lottery_read",
    [8]="production_train",[9]="production_research",[10]="production_auto",[11]="production_cancel",
    [12]="payment_capability",[13]="public_beta_claim"}
local function action_view(code,view)
    if code<=3 then return view==3 end
    if code==4 or code==7 then return view>=201 and view<=204 end
    if code==5 or code==6 then return view>=101 and view<=120 end
    if code==12 then return view==9 end
    if code==13 then return view==10 end
    return code>=8 and code<=11 and view==7
end

function M.new(options)
    local lookup=options.lookup
    local schema=assert(wire.compile_lookup(lookup,1))
    local proof=assert(wire.measure_budget(options.budget,50))
    local fields=lookup.field_by_name
    local control=assert(record(lookup,"wire:control"))
    local lottery_bulk_available=type(lookup.lottery_receipt)=="table"and lookup.lottery_receipt.wire_version==1
    local handlers,players={},{}
    local generation,queued,running=1,false,false
    local budget_started,budget_work,budget_background,budget_cpu=nil,0,0,0
    local budget_initialized=false
    local queues={{},{}}
    local statistics={frames=0,native_bytes=0,max_native_bytes=0,transactions=0,rejected=0,drains=0,
        bulk_frames=0,bulk_value_bytes=0,bulk_max_value_bytes=0}
    local api={}
    local function binding(state,view,epoch)
        return {schema=1,schema_sha256=lookup.sha256,session=state.session,epoch=epoch or 1,view=view}
    end
    local function unlink(job)
        if not job.queued then return end
        local queue=queues[job.lane]
        if job.previous then job.previous.following=job.following else queue.head=job.following end
        if job.following then job.following.previous=job.previous else queue.tail=job.previous end
        job.queued,job.previous,job.following,job.lane=false,nil,nil,nil
    end
    local function push(job,priority)
        if job.queued then return end
        local lane=priority and 1 or 2
        local queue=queues[lane]
        job.queued,job.lane,job.previous,job.following=true,lane,queue.tail,nil
        if queue.tail then queue.tail.following=job else queue.head=job end
        queue.tail=job
    end
    local function pop()
        for index=1,2 do
            local queue=queues[index]
            if queue.head then
                local job=queue.head;unlink(job)
                return job,index
            end
        end
    end
    local function has_jobs()return queues[1].head~=nil or queues[2].head~=nil end
    local function invalidate(view)
        for _,job in ipairs(view.jobs)do job.active=false;unlink(job)end
        view.jobs={}
    end
    local function current(state)
        local ok,result=pcall(function()
            return players[state.id]==state and (not options.is_current or options.is_current())
                and options.player(state.id)==state.handle and options.authorize(state.id)
        end)
        if not ok then statistics.rejected=statistics.rejected+1 end
        return ok and result
    end
    local function fail_view(view,reason)
        -- At most eight queued transactions, once per actual send failure.
        -- A receipt behind a failed CW predecessor also needs recovery.
        local failed=view.jobs
        invalidate(view);view.needs_full=true
        for _,job in ipairs(failed)do
            job.failed=reason
            if job.accepted_returned and job.on_failure and current(job.owner)
                and view.open and view.epoch==job.epoch then
                pcall(job.on_failure,reason)
            end
        end
    end
    local function cancel_idle()
        if queued and not running and not has_jobs()then
            queued=false;pcall(options.cancel,"compact_ui_dispatch")
        end
    end
    local schedule
    local function drain(from_scheduler)
        if running then return end
        queued=false;running=true;statistics.drains=statistics.drains+1
        local own_generation=generation
        local active_job
        local ok=pcall(function()
        local started=options.cpu_ms and options.cpu_ms()
        -- Concurrent recipients/publish calls share this real-time window;
        -- each synchronous caller cannot restart another eight-frame/2ms slice.
        if not budget_initialized or started and (not budget_started or started-budget_started>=16 or started<budget_started)
            or not started and from_scheduler then
            budget_started,budget_work,budget_background,budget_cpu=started,0,0,0
            budget_initialized=true
        end
        while own_generation==generation and has_jobs() and budget_work<8 do
            if started and budget_cpu+options.cpu_ms()-started>=2 then break end
            if not queues[1].head and budget_background>=2 then break end
            local job,lane=pop();budget_work=budget_work+1
            active_job=job
            if lane==2 then budget_background=budget_background+1 end
            local owner_current=job.active and current(job.owner)
            if own_generation~=generation then break end
            if job.active and not owner_current then
                fail_view(job.view,"owner_not_current")
            elseif job.active then
                local packet=job.packets[job.next]
                local sent
                if job.bulk then
                    local ok,result=pcall(options.emit,job.owner.id,"gb",packet)
                    if ok and result~=false then sent={bulk=true}end
                else
                    sent=wire.production_send(packet,proof,options.budget.engine_build,function(event,value)
                        return options.emit(job.owner.id,event,value)
                    end,options.budget.networksystem_sha256)
                end
                if sent then
                    if sent.bulk then
                        -- Rare gb data has separate native-envelope proof.
                        statistics.bulk_frames=statistics.bulk_frames+1
                        statistics.bulk_value_bytes=statistics.bulk_value_bytes+#packet.d
                        statistics.bulk_max_value_bytes=math.max(statistics.bulk_max_value_bytes,#packet.d)
                    else
                        statistics.frames=statistics.frames+1
                        statistics.native_bytes=statistics.native_bytes+sent.native_message_bytes
                        statistics.max_native_bytes=math.max(statistics.max_native_bytes,sent.native_message_bytes)
                    end
                end
                if own_generation~=generation then break end
                if not job.active then
                    -- Native emission can synchronously close/disconnect or
                    -- replace this view. Never resurrect its old transaction
                    -- or invalidate the replacement after an old send fails.
                elseif not sent then
                    -- A failed first job must not retain an inactive queue
                    -- head that strands every later transaction for this view.
                    fail_view(job.view,"native_send_failed");statistics.rejected=statistics.rejected+1
                else
                    job.next=job.next+1
                    if job.next<=#job.packets then push(job,job.priority)
                    else
                        job.active=false
                        -- Retire the direct per-view reference without scanning
                        -- the global queue. A view has at most eight in-flight tx.
                        local keep={};for _,pending in ipairs(job.view.jobs)do if pending.active then keep[#keep+1]=pending end end
                        job.view.jobs=keep
                        if keep[1]then push(keep[1],keep[1].priority)end
                        if job.on_complete and current(job.owner) and own_generation==generation
                            and job.view.open and job.view.epoch==job.epoch then
                            local ok=pcall(job.on_complete)
                            if not ok then
                                if own_generation==generation and job.view.epoch==job.epoch then job.view.needs_full=true end
                                statistics.rejected=statistics.rejected+1
                            end
                        end
                    end
                end
            end
            active_job=nil
        end
        if started and own_generation==generation then budget_cpu=budget_cpu+math.max(0,options.cpu_ms()-started)end
        end)
        running=false
        if not ok and own_generation==generation then
            statistics.rejected=statistics.rejected+1
            if active_job and active_job.active then fail_view(active_job.view,"dispatch_failed")end
            -- An unknown clock/codec/provider error does not spin every frame.
            -- A known failed job is retired; unrelated/replacement jobs can
            -- continue. A clock failure waits for an explicit publish/resync.
            queued=false
            if active_job then schedule()end
            return
        end
        schedule()
    end
    schedule=function()
        if queued or running or not has_jobs()then return end
        local ticket={};queued=ticket;local own=generation
        local ok,result=pcall(options.after,0,function()if own==generation and queued==ticket then drain(true)end end,"compact_ui_dispatch")
        if not ok or result==false then
            if own==generation and queued==ticket then
                queued=false;statistics.rejected=statistics.rejected+1
                pcall(options.cancel,"compact_ui_dispatch")
            end
        end
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
        if handler.bulk_static~=nil then need(id==6 and handler.bulk_static==true,"bulk_static_view_not_allowed")end
        if handler.bulk_lottery~=nil then need(id%1==0 and id>=201 and id<=204 and handler.bulk_lottery==true,"bulk_lottery_view_not_allowed")end
        if handler.input then
            local prefix=id==4 and "grid"or id==5 and "selected"or id==7 and "production"or nil
            need(prefix~=nil,"typed_input_view_not_allowed")
            local input_key=prefix..":input"
            local action_name=prefix.."_action"
            need((not handler.input_record or handler.input_record==input_key)
                and (not handler.input_action_field or handler.input_action_field==action_name),"typed_input_schema_scope_invalid")
            local input_id=record(lookup,input_key)
            need(input_id and fields[action_name],"typed_input_schema_required")
            need(type(handler.input_fields)=="table","typed_input_allowlist_required")
            local allowed={}
            for name,enabled in pairs(handler.input_fields)do
                need(enabled==true and type(name)=="string" and name:sub(1,#prefix+1)==prefix.."_"
                    and name~=action_name and fields[name],"typed_input_field_not_allowed")
                allowed[fields[name]]=name
            end
            local actions=handler.input_actions or (id==4 and {[1]=true,[2]=true,[3]=true,[4]=true,[5]=true}
                or {[1]=true,[2]=true})
            for action,on in pairs(actions)do
                need(type(action)=="number"and action==math.floor(action)and action>=1 and action<=16 and on==true,"typed_input_actions_invalid")
            end
            handler.input_field_ids,handler.input_record_id,handler.input_action_id,handler.allowed_input_actions=
                allowed,input_id,fields[action_name],actions
        end
        handlers[id]=handler;return true
    end
    function api.is_open(id,view)
        local state=state_for(id,false);return not not(state and state.views[view]and state.views[view].open)
    end
    function api.is_bound(id)
        local state=state_for(id,false)
        return state~=nil and state.views[1]~=nil and state.views[1].revision>0
    end
    function api.queue_depth(id,view_id)
        local state=state_for(id,false)
        local view=state and state.views[view_id]
        return view and #view.jobs or 0
    end
    function api.bulk_binding(id)
        local state=state_for(id,false);local view=state and state.views[6]
        if not view or not view.open or not view.bulk_static or view.epoch<1 then return nil end
        local result=binding(state,6,view.epoch);result.revision=view.revision;result.base_revision=view.revision
        return result
    end
    function api.bulk_static_enabled(id)
        local state=state_for(id,false);local view=state and state.views[6]
        return not not(view and view.open and view.bulk_static)
    end
    function api.publish_bulk_static(id,raw,scope,settings)
        settings=settings or{}
        local state=state_for(id,false);local view=state and state.views[6]
        if not view or not view.open or not view.bulk_static or not handlers[6]or not handlers[6].bulk_static then return nil,"bulk_static_not_negotiated"end
        if settings.epoch~=view.epoch or type(settings.base_revision)~="number" or settings.base_revision%1~=0
            or settings.base_revision<1 or settings.base_revision>view.revision then return nil,"bulk_static_stale_base"end
        if #view.jobs>=8 then return nil,"bounded_view_queue_requires_full_resync"end
        local context=binding(state,6,view.epoch);context.base_revision=settings.base_revision;context.revision=settings.base_revision
        local packets,metrics=require('ui/compact_grid_bulk_wire').Encode(context,scope,raw)
        if not packets then return nil,metrics end
        need(#packets>=1 and #packets<=32,"bulk_static_frame_limit")
        for _,packet in ipairs(packets)do
            need(type(packet)=="table"and type(packet.d)=="string"and #packet.d<=896,"bulk_static_value_limit")
            for key in pairs(packet)do need(key=="d","bulk_static_packet_key_unknown")end
        end
        need(settings.on_complete==nil or type(settings.on_complete)=='function','bulk_completion_callback_invalid')
        local job={owner=state,view=view,packets=packets,next=1,priority=false,bulk=true,active=true,
            epoch=view.epoch,on_complete=settings.on_complete}
        view.jobs[#view.jobs+1]=job;if #view.jobs==1 then push(job,false)end
        statistics.transactions=statistics.transactions+1;schedule()
        return {queued=true,frames=#packets,epoch=view.epoch,base_revision=settings.base_revision,metrics=metrics}
    end
    function api.bulk_lottery_enabled(id,view_id)
        local state=state_for(id,false);local view=state and state.views[view_id]
        return not not(lottery_bulk_available and view and view.open and view.bulk_lottery
            and not view.needs_full and view.revision>=1 and handlers[view_id]and handlers[view_id].bulk_lottery)
    end
    function api.bulk_lottery_binding(id,view_id)
        if not api.bulk_lottery_enabled(id,view_id)then return nil end
        local state=state_for(id,false);local view=state.views[view_id]
        local result=binding(state,view_id,view.epoch);result.revision=view.revision;result.base_revision=view.revision
        return result
    end
    function api.publish_bulk_lottery(id,view_id,raw,scope,settings)
        settings=settings or{}
        if not api.bulk_lottery_enabled(id,view_id)then return nil,"bulk_lottery_not_negotiated"end
        local state=state_for(id,false);local view=state.views[view_id]
        if settings.epoch~=view.epoch or settings.base_revision~=view.revision
            or type(settings.next_revision)~="number"or settings.next_revision~=view.revision+1
            or settings.next_revision>2097151 then return nil,"bulk_lottery_stale_base"end
        if type(scope)~="number"or scope%1~=0 or scope<1 or scope>16383 then return nil,"bulk_lottery_scope_invalid"end
        if #view.jobs>=8 then return nil,"bounded_view_queue_requires_full_resync"end
        local context=binding(state,view_id,view.epoch);context.base_revision=view.revision
        local packets,metrics=require('ui/compact_grid_bulk_wire').Encode(context,scope,raw)
        if not packets then return nil,metrics end
        need(settings.on_complete==nil or type(settings.on_complete)=='function','bulk_completion_callback_invalid')
        need(settings.on_failure==nil or type(settings.on_failure)=='function','bulk_failure_callback_invalid')
        -- Reserve exactly one revision after complete validation. Per-view FIFO
        -- puts both cw and gb behind any prior transaction; no second timer.
        view.revision=settings.next_revision
        local job={owner=state,view=view,packets=packets,next=1,priority=true,bulk=true,active=true,
            epoch=view.epoch,on_complete=settings.on_complete,on_failure=settings.on_failure}
        view.jobs[#view.jobs+1]=job;if #view.jobs==1 then push(job,true)end
        statistics.transactions=statistics.transactions+1
        if not running and not queued then drain()else schedule()end
        if job.failed then return nil,job.failed end
        job.accepted_returned=true
        return true,{queued=true,frames=#packets,epoch=view.epoch,base_revision=settings.base_revision,
            revision=settings.next_revision,next_revision=settings.next_revision,metrics=metrics}
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
        if type(packet)~="table"or type(packet.d)~="string"or #packet.d>24 then
            statistics.rejected=statistics.rejected+1;return nil,"compact_packet_budget_exceeded"
        end
        for key in pairs(packet)do if key~="d"then
            statistics.rejected=statistics.rejected+1;return nil,"compact_packet_key_unknown"
        end end
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
        if handler.input and tx.changes[1]and tx.changes[1].record==handler.input_record_id then
            if not view.open then incoming.abort();return nil,"typed_input_view_closed"end
            local action,args=nil,{}
            for _,change in ipairs(tx.changes)do
                if change.record~=handler.input_record_id or change.remove then incoming.abort();return nil,"typed_input_record_required"end
                if change.field==handler.input_action_id then action=change.value
                else
                    local name=handler.input_field_ids[change.field]
                    if not name then incoming.abort();return nil,"typed_input_field_not_allowed"end
                    args[name]=change.value
                end
            end
            if not handler.allowed_input_actions[action]then
                incoming.abort();return nil,"typed_input_action_invalid"
            end
            incoming.commit(tx)
            local result=handler.input(id,action,args,tx.revision)
            return result==nil and true or result
        end
        local values={}
        for _,change in ipairs(tx.changes)do
            if change.record~=control or change.remove then incoming.abort();return nil,"control_record_required"end
            local allowed=change.field==fields.visible or change.field==fields.known or change.field==fields.action_code
                or change.field==fields.arg_a or change.field==fields.arg_b or change.field==fields.arg_c or change.field==fields.request_token
                or header.view==6 and handler.bulk_static and change.field==fields.types
                or header.view>=201 and header.view<=204 and handler.bulk_lottery and change.field==fields.types
            if not allowed then incoming.abort();return nil,"control_field_not_allowed"end
            values[change.field]=change.value
        end
        if values[fields.action_code]then
            local code=values[fields.action_code]
            local action=ACTIONS[code]
            if not action or not action_view(code,header.view)or not handler.intent or not view.open then incoming.abort();return nil,"view_intent_not_allowed"end
            if code>=12 and(values[fields.arg_a]~=nil or values[fields.arg_b]~=nil or values[fields.arg_c]~=nil)then
                incoming.abort();return nil,"intent_arguments_forbidden"
            end
            local token=values[fields.request_token]
            if not token or token<1 or token>16383 then incoming.abort();return nil,"intent_token_required"end
            incoming.commit(tx)
            local result=handler.intent(id,action,{arg_a=values[fields.arg_a],arg_b=values[fields.arg_b],arg_c=values[fields.arg_c],request_token=token,
                session_token=state.session})
            return result==nil and true or result
        end
        local capability=values[fields.types]
        if capability~=nil and capability~=0 and not(header.view==6 and capability==1)
            and not(header.view>=201 and header.view<=204 and capability==2)then
            incoming.abort();return nil,"bulk_capability_invalid"
        end
        incoming.commit(tx)
        if values[fields.visible]==true or values[fields.visible]==1 then
            if header.view==6 then view.bulk_static=handler.bulk_static==true and values[fields.types]==1 end
            if header.view>=201 and header.view<=204 then
                view.bulk_lottery=lottery_bulk_available and handler.bulk_lottery==true and capability==2
            end
            return full_snapshot(state,header.view,true)
        end
        view.open=false
        view.bulk_static=false
        view.bulk_lottery=false
        -- A closed panel must not continue draining its former full catalogue.
        -- Its next tiny hint or real Open starts a fresh atomic epoch instead.
        invalidate(view);view.revision=0;view.needs_full=false
        cancel_idle()
        if values[fields.known]==true or values[fields.known]==1 then
            if handler.probe then local result=handler.probe(id);return result==nil and true or result end
        elseif handler.close then local result=handler.close(id);return result==nil and true or result end
        return true
    end
    function api.disconnect(id)
        local state=players[id];if state then for _,view in pairs(state.views)do invalidate(view)end end
        players[id]=nil
        cancel_idle()
    end
    function api.reset()
        generation=generation+1;players={};queues={{},{}};queued=false
        budget_started,budget_work,budget_background,budget_cpu=nil,0,0,0
        budget_initialized=false
        pcall(options.cancel,"compact_ui_dispatch")
    end
    function api.inspect()return statistics end
    return api
end

local default,failed,pending_views=nil,false,{}
local world,listener=nil,nil
local default_mode,default_driver
local disconnect_bus,disconnect_subscription
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
    local mode=GameRules and GameRules:GetGameModeEntity()
    if world and current and current~=world or default_mode and mode~=default_mode
        or disconnect_bus and bus~=disconnect_bus then
        if default then default.reset()end
        if default_driver then default_driver.dispose()end
        if disconnect_bus and disconnect_subscription then disconnect_bus.unsubscribe(disconnect_subscription)end
        if listener and CustomGameEventManager and type(CustomGameEventManager.UnregisterListener)=="function"then
            pcall(CustomGameEventManager.UnregisterListener,CustomGameEventManager,listener)
        end
        default,failed,pending_views,listener=nil,false,{},nil
        disconnect_bus,disconnect_subscription=nil,nil
        default_mode,default_driver=nil,nil
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
        local bus=require('core/event_bus');local own=bus.get_generation();world=own
        local mode=GameRules:GetGameModeEntity()
        local driver=require('ui/compact_dispatch_driver').new({entity=mode,is_current=function()
            return package.loaded['core/event_bus']==bus and bus.get_generation()==own
                and GameRules:GetGameModeEntity()==mode and not mode:IsNull()
        end})
        local cpu_ms
        if type(GetSystemTimeMS)=="function"then
            local valid,sample=pcall(GetSystemTimeMS)
            if valid and type(sample)=="number"and sample==sample and sample~=math.huge and sample~=-math.huge then
                cpu_ms=GetSystemTimeMS
            end
        end
        local function authorize(id)
            local loading=package.loaded["systems/startup_loading_service"]
            return PlayerResource and PlayerResource:IsValidPlayerID(id)
                and require("core/test_access_policy").enforce(id)==true
                and loading and loading.is_player_ready(id)==true
        end
        local value=M.new({lookup=lookup,budget=budget,
            player=function(id)return PlayerResource and PlayerResource:GetPlayer(id)end,authorize=authorize,
            session_token=allocate_session_alias,
            after=driver.after,cancel=driver.cancel,is_current=driver.is_current,
            cpu_ms=cpu_ms,
            emit=function(id,event,packet)
                local player=PlayerResource:GetPlayer(id)
                if not player or not authorize(id)then return false end
                return CustomGameEventManager:Send_ServerToPlayer(player,event,packet)
            end})
        listener=CustomGameEventManager:RegisterListener("cw",function(source,payload)
            if value~=default or not driver.is_current()then return end
            local id=tonumber(payload and payload.PlayerID)
            if not id or not authorize(id)or type(payload.d)~="string"then return end
            local player=PlayerResource:GetPlayer(id)
            if player and type(player.GetPlayerID)=="function"and player:GetPlayerID()~=id then return end
            local ok_actor,actor=pcall(EntIndexToHScript,tonumber(source)or-1)
            if not ok_actor or actor~=player then return end
            value.receive(id,{d=payload.d})
        end)
        for id,handler in pairs(pending_views)do value.register_view(id,handler)end
        disconnect_bus=bus
        disconnect_subscription=bus.subscribe(require('core/events').PLAYER_DISCONNECTED,function(payload)
            if default~=value or world~=own then return end
            local id=tonumber(payload and payload.player_id)
            if id then value.disconnect(id)end
        end)
        default_mode,default_driver=mode,driver
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
function M.queue_depth(...)local value=instance();return value and value.queue_depth(...)or 0 end
function M.bulk_binding(...)local value=instance();return value and value.bulk_binding(...)or nil end
function M.bulk_static_enabled(...)local value=instance();return value and value.bulk_static_enabled(...)or false end
function M.publish_bulk_static(...)local value=instance();if value then return value.publish_bulk_static(...)end;return nil,'compact_runtime_unavailable'end
function M.bulk_lottery_binding(...)local value=instance();return value and value.bulk_lottery_binding(...)or nil end
function M.bulk_lottery_enabled(...)local value=instance();return value and value.bulk_lottery_enabled(...)or false end
function M.publish_bulk_lottery(...)local value=instance();if value then return value.publish_bulk_lottery(...)end;return nil,'compact_runtime_unavailable'end
function M.disconnect(id)ensure_world();if default then default.disconnect(id);return true end;return false end
function M.inspect()local value=instance();return value and value.inspect()or{available=false}end
return M
