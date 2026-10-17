-- Explicit, short Workshop diagnostic. require() is inert. No modifiers,
-- native declarations, timers, business wrappers or argument inspection.
-- start({seconds=5}) counts calls; optional sample_timings=true adds bounded
-- inclusive wall samples. Those samples INCLUDE debug-hook overhead.
-- Call-only additionally counts source-limited C/no-Lua-caller boundaries,
-- including anonymous engine-bound closures. C ancestry does not prove which
-- native subsystem called a function, or that it was an engine callback.
local M = {}
local MAX_SECONDS, MAX_CALLS, MAX_ROWS = 5, 100000, 64
local MAX_METADATA, MAX_CLASSES, MAX_STACK, MAX_SAMPLES = 4096, 512, 512, 256
local capture
local function finite(value)
    return type(value)=="number" and value==value and math.abs(value)<math.huge
end
local function current_thread()
    return coroutine and coroutine.running and coroutine.running() or nil
end
local function current_world()
    return GameRules and GameRules.GetGameModeEntity and GameRules:GetGameModeEntity()
end
local function context_ok(state)
    return IsServer and IsServer() and IsInToolsMode and IsInToolsMode()
        and GetMapName and GetMapName()=="template_map"
        and current_world()==state.world
        and rawget(_G,"SURVIVAL_REAL_GAME_STRESS_ISOLATION")==state.guard
        and state.guard.mode==state.world
end
local function clock(state)
    local ok,value=pcall(state.clock)
    if ok and finite(value) then return value end
end
local function source_name(source)
    if type(source)~="string" then return "source_unavailable" end
    if source:sub(1,1)=="@" then return source:sub(2,241):gsub("\\","/") end
    if source=="[C]" then return source end
    if source:match("^=[%w_/.%-]+$") then return source:sub(2,181) end
    -- debug.source can contain the ENTIRE loadstring body. Never report it.
    return "dynamic_source_omitted"
end
local function callback_name(name)
    return type(name)=="string" and #name<=128 and name:match("^[%w_]+$")
        and (name:match("^GetModifier") or name=="CheckState"
            or name:match("^OnAttack") or name=="OnTakeDamage")
end
local function runtime_name(name)
    return type(name)=="string" and #name<=128 and name:match("^[%w_]+$") and name or nil
end
local function normalize_declared_root(value)
    if type(value)~="string" or #value>512 or value:find("%c")
        or value:find('[<>|"?*]') then return nil end
    local path=value:gsub("\\","/"):gsub("/+$","")
    local drive=path:match("^%a:/")
    if not drive and (path:sub(1,1)~="/" or path:sub(1,2)=="//") then return nil end
    if path:find("//",1,true) or path:sub(drive and 3 or 1):find(":",1,true) then return nil end
    for segment in path:gmatch("[^/]+") do if segment=="." or segment==".." then return nil end end
    if path:sub(-#"/scripts/vscripts"):lower()~="/scripts/vscripts" then return nil end
    return path.."/"
end
local function workspace_source(state,source)
    -- Require a file-style source. A debug source label is not authenticated
    -- filesystem provenance; never inspect dynamic source text or upvalues.
    if type(source)~="string" or source:sub(1,1)~="@" or #source>1024 then return nil end
    local path=source:sub(2):gsub("\\","/")
    if path:find("%c") or not path:match("%.lua$") then return nil end
    for segment in path:gmatch("[^/]+") do if segment==".." then return nil end end
    local relative
    if state.vscripts_root and path:sub(1,#state.vscripts_root):lower()==state.vscripts_root:lower() then
        relative=path:sub(#state.vscripts_root+1)
    elseif path:match("^scripts/vscripts/") then
        relative=path:sub(#"scripts/vscripts/"+1)
    elseif not path:find(":",1,true) and path:sub(1,1)~="/"
        and path:match("^[%w_]+/") then
        local folder=path:match("^([^/]+)/")
        if state.relative_module_sources and ({abilities=true,combat=true,core=true,maps=true,
            modifiers=true,modifier_bindings=true,systems=true,tests=true,ui=true})[folder] then relative=path end
    end
    if not relative or #relative>240 or relative:sub(1,1)=="/" then return nil end
    if relative=="tests/manual_native_lua_callback_probe.lua" then return nil end
    return "scripts/vscripts/"..relative
end
local function map_boundary_exports(state)
    local own=state.api.getinfo(M.start,"S")
    local source=own and own.source
    if type(source)=="string" and source:sub(1,1)=="@" then
        local path=source:sub(2):gsub("\\","/")
        local root=path:match("^(.*scripts/vscripts/)tests/manual_native_lua_callback_probe%.lua$")
            or path:match("^(.*vscripts/)tests/manual_native_lua_callback_probe%.lua$")
        if root and not state.declared_root then
            state.vscripts_root=root
            if root:match("^%a:/") or root:sub(1,1)=="/" then
                state.source_scope_origin="derived_absolute_probe_source"
            else state.source_scope_origin="derived_relative_probe_source" end
        end
        state.relative_module_sources=path:match("^tests/manual_native_lua_callback_probe%.lua$")~=nil
    end
    for _,module in ipairs({"combat/damage_filter_service","systems/tree_attack_order_filter"}) do
        -- These are existing exported function identities, not inspected
        -- closure captures. Do not require a module or alter a native binding.
        local service=package.loaded[module]
        local fn=type(service)=="table" and rawget(service,"_filter_for_test")
        if type(fn)=="function" then
            local info=state.api.getinfo(fn,"S")
            if info and workspace_source(state,info.source) then
                state.boundary_exports[fn]={module..":_filter_for_test"}
                state.boundary_metadata_count=state.boundary_metadata_count+1
            end
        end
    end
end
local function owned_hook(state)
    if state.thread then return state.api.gethook(state.thread) end
    if current_thread()~=nil then return nil,"different_thread" end
    return state.api.gethook()
end
local function unset_hook(state)
    if state.thread then state.api.sethook(state.thread)
    else state.api.sethook() end
end
local function discard_samples(state,reason)
    for _,frame in ipairs(state.stack) do
        if frame.sample then
            state.samples_discarded=state.samples_discarded+1
            frame.row.discarded_samples=frame.row.discarded_samples+1
        end
    end
    state.stack={};state.open_samples=0
    state.discard_reasons[reason]=(state.discard_reasons[reason] or 0)+1
end
local function restore_own(state)
    if state.restoring then return end
    state.restoring=true
    state.restore_attempts=state.restore_attempts+1
    local ok,hook,mask=pcall(owned_hook,state)
    if not ok then
        state.restore_status="gethook_failed"
        state.restore_pending=state.restore_attempts<3
    elseif mask=="different_thread" then
        state.restore_status="deferred_until_installing_thread"
        state.restore_pending=true
    elseif hook~=state.hook then
        state.restore_status=hook==nil and "already_empty" or "external_hook_preserved"
        state.restore_pending=false
    else
        local removed=pcall(unset_hook,state)
        local checked,after=pcall(owned_hook,state)
        if removed and checked and after==nil then
            state.restore_status="restored_empty_hook"
            state.restore_pending=false
        elseif checked and after~=state.hook and after~=nil then
            state.restore_status="external_hook_preserved"
            state.restore_pending=false
        else
            state.restore_status="sethook_or_verification_failed"
            state.restore_pending=state.restore_attempts<3
        end
    end
    state.restoring=false
end
local function finish(state,reason,t)
    if state.active then
        state.active=false;state.reason=reason
        state.finished=t or state.last_clock or state.started
        discard_samples(state,"capture_stopped")
    end
    restore_own(state)
end
local function map_callbacks(state)
    local classes=0
    for class_name,methods in pairs(_G) do
        if type(class_name)=="string" and #class_name<=128 and class_name:match("^modifier_[%w_]+$")
            and type(methods)=="table" then
            classes=classes+1
            if classes>MAX_CLASSES then state.metadata_class_overflow=true;break end
            for name,fn in pairs(methods) do
                if callback_name(name) and type(fn)=="function" then
                    local meta=state.metadata[fn]
                    if not meta and state.metadata_count<MAX_METADATA then
                        local info=state.api.getinfo(fn,"S")
                        if info and info.what~="C" then
                            meta={name=name,source=source_name(info.source),linedefined=info.linedefined or 0,
                                aliases={},match="loaded_modifier_function_identity"}
                            state.metadata[fn]=meta;state.metadata_count=state.metadata_count+1
                        end
                    end
                    if meta and #meta.aliases<4 then meta.aliases[#meta.aliases+1]=class_name..":"..name end
                end
            end
        end
    end
end
local function row_for(state,info,caller)
    if info.what=="C" then return nil,false,false end
    local meta=state.metadata[info.func]
    if not meta and callback_name(info.name) then
        local source=source_name(info.source)
        -- A similarly named ordinary Lua helper is not proof of a modifier.
        -- Identity aliases are preferred; fallback needs a modifier source.
        if source:find("/modifiers/",1,true) or source:find("/modifier_bindings/",1,true)
            or source:match("^modifiers/") or source:match("^modifier_bindings/") then
            meta={name=info.name,source=source,linedefined=info.linedefined or 0,
                aliases={},match="runtime_callback_name_modifier_source"}
        end
    end
    local source=not state.sample_timings and (not caller or caller.what=="C")
        and workspace_source(state,info.source) or nil
    local boundary=source~=nil and (not caller or caller.what=="C")
    local modifier=meta~=nil
    if not modifier and not boundary then return nil,false,false end
    -- Per-instance anonymous closures often share the same source template.
    -- Keep a maximum of 64 source groups, not a growing function-identity map.
    -- Legacy modifier rows retain their original exact-function identity.
    local group=not modifier and source..":"..tostring(info.linedefined or 0)..":"..tostring(info.lastlinedefined or 0) or nil
    local row=modifier and state.by_function[info.func] or state.boundary_rows[group]
    if row then
        if boundary and not row.workspace_source then row.workspace_source=source end
        return row,modifier,boundary
    end
    if #state.rows>=MAX_ROWS then
        if modifier then state.detail_omitted_calls=state.detail_omitted_calls+1 end
        if boundary then state.boundary_detail_omitted_calls=state.boundary_detail_omitted_calls+1 end
        return nil,modifier,boundary
    end
    row={name=meta and meta.name or runtime_name(info.name) or "<anonymous>",
        source=meta and meta.source or source,linedefined=info.linedefined or 0,lastlinedefined=info.lastlinedefined or 0,
        aliases=meta and meta.aliases or {},
        match=meta and meta.match or "workspace_lua_c_or_no_lua_caller_boundary",
        is_modifier_callback=modifier,workspace_source=source,runtime_name=runtime_name(info.name),
        callback_classification=modifier and "legacy_modifier_callback" or "workspace_boundary_unclassified",
        export_aliases=state.boundary_exports[info.func] or {},
        aggregation=modifier and "function_identity" or "source_definition_span",
        calls=0,c_boundary_calls=0,lua_caller_calls=0,native_boundary_calls=0,
        export_identity_calls=0,
        c_caller_calls=0,no_lua_caller_calls=0,
        timed_samples=0,discarded_samples=0,inclusive_wall_ms=0,max_inclusive_wall_ms=0}
    state.rows[#state.rows+1]=row
    if modifier then state.by_function[info.func]=row else state.boundary_rows[group]=row end
    return row,modifier,boundary
end
local function process_event(state,event)
    -- Some Lua hosts inherit hooks into new coroutines. This diagnostic
    -- promises only its installing thread and never owns another thread's hook.
    if current_thread()~=state.thread then return end
    if not state.active then
        if state.restore_pending and not state.restoring then restore_own(state) end
        return
    end
    local t=clock(state)
    if not t then finish(state,"clock_failed");return end
    if t<state.last_clock then finish(state,"clock_moved_backwards",t);return end
    state.last_clock=t
    if t-state.started>=state.seconds then finish(state,"time_limit",t);return end
    if not context_ok(state) then finish(state,"world_or_guard_changed",t);return end
    if event=="tail return" then
        state.tail_returns=state.tail_returns+1
        discard_samples(state,"tail_return_unverifiable")
        return -- Lua 5.1 getinfo is explicitly invalid for this event.
    end
    if event~="call" and event~="return" then return end
    -- Stack: target(4), hook(3), C pcall(2), THIS protected handler(1).
    -- Never replace this with getinfo(2), which would profile pcall itself.
    local info=state.api.getinfo(4,"fSn")
    if not info or type(info.func)~="function" then
        state.info_unavailable=state.info_unavailable+1
        if state.sample_timings and state.open_samples>0 then finish(state,"stack_information_lost",t) end
        return
    end
    if event=="call" then
        state.call_events=state.call_events+1
        if state.call_events>state.max_calls then finish(state,"call_limit",t);return end
        if info.what=="C" then state.c_calls=state.c_calls+1 else state.lua_calls=state.lua_calls+1 end
        local caller=state.api.getinfo(5,"fS")
        local row,modifier,boundary=row_for(state,info,caller)
        if modifier then state.callback_calls=state.callback_calls+1 end
        if boundary then
            state.native_boundary_calls=state.native_boundary_calls+1
            if modifier then state.workspace_legacy_modifier_boundary_calls=state.workspace_legacy_modifier_boundary_calls+1
            else state.workspace_other_boundary_calls=state.workspace_other_boundary_calls+1 end
            if state.boundary_exports[info.func] then state.boundary_export_identity_calls=state.boundary_export_identity_calls+1 end
            if caller then state.workspace_c_caller_calls=state.workspace_c_caller_calls+1
            else state.workspace_no_lua_caller_calls=state.workspace_no_lua_caller_calls+1 end
        end
        if row then
            row.calls=row.calls+1
            if boundary then row.native_boundary_calls=row.native_boundary_calls+1 end
            local aliases=boundary and state.boundary_exports[info.func]
            if aliases then
                row.export_identity_calls=row.export_identity_calls+1
                if #row.export_aliases==0 then row.export_aliases=aliases end
            end
        end
        if modifier then
            if not caller or caller.what=="C" then
                state.native_modifier_calls=state.native_modifier_calls+1
            else
                state.lua_dispatch_modifier_calls=state.lua_dispatch_modifier_calls+1
            end
        end
        if row then
            if not caller or caller.what=="C" then
                row.c_boundary_calls=row.c_boundary_calls+1
                if caller then row.c_caller_calls=row.c_caller_calls+1
                else row.no_lua_caller_calls=row.no_lua_caller_calls+1 end
            else row.lua_caller_calls=row.lua_caller_calls+1 end
        end
        if state.sample_timings then
            local top=state.stack[#state.stack]
            if top and (not caller or caller.func~=top.func) then
                if state.open_samples>0 then finish(state,"stack_unwind_detected",t);return end
                state.stack={};state.stack_resets=state.stack_resets+1
            end
            if #state.stack>=MAX_STACK then finish(state,"stack_limit",t);return end
            local sample=row and (row.calls==1 or row.calls%state.sample_every==0)
                and state.samples_started<MAX_SAMPLES
            state.stack[#state.stack+1]={func=info.func,row=row,sample=sample and true or false,started=sample and t or nil}
            if sample then state.samples_started=state.samples_started+1;state.open_samples=state.open_samples+1 end
        end
        if state.call_events>=state.max_calls then finish(state,"call_limit",t) end
    elseif state.sample_timings then
        state.return_events=state.return_events+1
        local frame=state.stack[#state.stack]
        if not frame then state.untracked_returns=state.untracked_returns+1;return end
        if frame.func~=info.func then
            if state.open_samples>0 then finish(state,"stack_unwind_detected",t)
            else state.stack={};state.stack_resets=state.stack_resets+1 end
            return
        end
        state.stack[#state.stack]=nil
        if frame.sample then
            state.open_samples=state.open_samples-1
            local ms=math.max(0,t-frame.started)*1000
            frame.row.timed_samples=frame.row.timed_samples+1
            frame.row.inclusive_wall_ms=frame.row.inclusive_wall_ms+ms
            frame.row.max_inclusive_wall_ms=math.max(frame.row.max_inclusive_wall_ms,ms)
            state.samples_completed=state.samples_completed+1
        end
    end
end
local function start_capture(options)
    options=options or {}
    if capture and (capture.active or capture.restore_pending) then return false,"already_active_or_cleanup_pending" end
    local seconds=options.seconds or 5
    local max_calls=options.max_calls or MAX_CALLS
    local sample_every=options.sample_every or 32
    local declared_root
    if options.vscripts_root~=nil then
        declared_root=normalize_declared_root(options.vscripts_root)
        if not declared_root then return false,"invalid_declared_vscripts_root" end
    end
    if not finite(seconds) or seconds<=0 or seconds>MAX_SECONDS
        or not finite(max_calls) or max_calls<1 or max_calls>MAX_CALLS or max_calls~=math.floor(max_calls)
        or not finite(sample_every) or sample_every<1 or sample_every>10000 or sample_every~=math.floor(sample_every) then
        return false,"invalid_or_excessive_limit"
    end
    local world=current_world()
    local guard=rawget(_G,"SURVIVAL_REAL_GAME_STRESS_ISOLATION")
    if not IsServer or not IsServer() or not IsInToolsMode or not IsInToolsMode()
        or not GetMapName or GetMapName()~="template_map" or not world
        or type(guard)~="table" or guard.mode~=world then return false,"requires_isolated_template_map_tools_server" end
    if not debug or type(debug.gethook)~="function" or type(debug.sethook)~="function"
        or type(debug.getinfo)~="function" or type(Plat_FloatTime)~="function" then return false,"hook_or_wall_clock_unavailable" end
    local state={active=false,world=world,guard=guard,thread=current_thread(),clock=Plat_FloatTime,
        api={gethook=debug.gethook,sethook=debug.sethook,getinfo=debug.getinfo},
        seconds=seconds,max_calls=max_calls,sample_timings=options.sample_timings==true,sample_every=sample_every,
        declared_root=declared_root,vscripts_root=declared_root,
        source_scope_origin=declared_root and "explicit_tools_option" or "relative_file_sources_only",
        metadata={},metadata_count=0,rows={},by_function={},stack={},call_events=0,c_calls=0,lua_calls=0,
        return_events=0,tail_returns=0,untracked_returns=0,stack_resets=0,info_unavailable=0,
        callback_calls=0,native_modifier_calls=0,lua_dispatch_modifier_calls=0,detail_omitted_calls=0,
        boundary_exports={},boundary_rows={},boundary_metadata_count=0,native_boundary_calls=0,
        boundary_export_identity_calls=0,
        workspace_c_caller_calls=0,workspace_no_lua_caller_calls=0,boundary_detail_omitted_calls=0,
        workspace_legacy_modifier_boundary_calls=0,workspace_other_boundary_calls=0,
        samples_started=0,samples_completed=0,samples_discarded=0,open_samples=0,discard_reasons={},
        hook_errors=0,restore_attempts=0,restore_status="not_installed"}
    local checked,existing=pcall(owned_hook,state)
    if not checked then return false,"gethook_failed" end
    if existing~=nil then return false,"existing_hook_preserved" end
    local t=clock(state)
    if not t then return false,"wall_clock_invalid" end
    local scanned=pcall(map_callbacks,state)
    if not scanned then return false,"callback_metadata_failed" end
    if not state.sample_timings then
        local mapped=pcall(map_boundary_exports,state)
        if not mapped then return false,"boundary_metadata_failed" end
    end
    state.started,state.last_clock=t,t
    state.hook=function(event)
        local ok=pcall(process_event,state,event)
        if not ok then
            state.hook_errors=state.hook_errors+1
            -- Never pass a diagnostic exception/private error string into
            -- gameplay. Restore only if gethook still identifies our closure.
            pcall(finish,state,"hook_processing_failed")
        end
    end
    capture=state;state.active=true
    local installed=pcall(function()
        if state.thread then state.api.sethook(state.thread,state.hook,state.sample_timings and "cr" or "c")
        else state.api.sethook(state.hook,state.sample_timings and "cr" or "c") end
    end)
    if not installed then finish(state,"installation_failed");return false,"installation_failed" end
    if not state.active then
        if state.reason=="call_limit" or state.reason=="time_limit" then return true,"completed_during_start" end
        return false,state.reason or "installation_stopped"
    end
    local verified,hook=pcall(owned_hook,state)
    if not state.active and (state.reason=="call_limit" or state.reason=="time_limit") then
        return true,"completed_during_start"
    end
    if not verified or hook~=state.hook then finish(state,"installation_not_verified");return false,"installation_not_verified" end
    return true
end
function M.start(options)
    local ok,result,reason=pcall(start_capture,options)
    if ok then return result,reason end
    if capture and capture.active then pcall(finish,capture,"start_failed") end
    return false,"start_failed"
end
function M.stop()
    if not capture then return false,"not_started" end
    local ok=pcall(finish,capture,"stopped",clock(capture))
    if not ok then return false,"cleanup_failed" end
    return not capture.restore_pending,capture.restore_status
end
function M.report()
    -- Freeze before assembling a report; report/JSON work must not contaminate
    -- observations or be instrumented indefinitely after the short window.
    if capture and capture.active then M.stop() end
    local result={schema="native_lua_callback_probe_v1",active=capture and capture.active or false,
        reason=capture and capture.reason or "not_started",max_seconds=MAX_SECONDS,max_calls=MAX_CALLS,
        max_details=MAX_ROWS,max_timing_samples=MAX_SAMPLES,clock="Plat_FloatTime",
        thread_scope="installing_lua_thread_only",timeouts_checked_on_next_hook_event=true,
        counts_only_business_unwinds_not_observable=true,
        timing_kind="optional_sampled_inclusive_wall_including_hook_overhead",
        self_time_measured=false,engine_cpp_body_time_measured=false,
        native_engine_origin_not_proven=true,args_upvalues_profiles_inspected=false,
        source_labels_not_authenticated=true,
        declared_root_not_independently_authenticated=true,
        count_definitions={native_modifier_calls="legacy modifier classifier only; C or missing Lua caller",
            native_boundary_calls="accepted workspace file source; C or missing Lua caller; may overlap modifier count",
            c_boundary_calls="per detail row; includes anonymous/unclassified rows; not a modifier total",
            is_modifier_callback="matched legacy modifier classifier, not a complete modifier census",
            totals_overlap_do_not_sum=true},
        coverage={native_modifier_calls=0,modifier_callback_calls=0,native_boundary_calls=0},details={}}
    local state=capture;if not state then return result end
    result.restore_status,result.restore_attempts,result.cleanup_pending=state.restore_status,state.restore_attempts,state.restore_pending or false
    result.seconds,result.call_limit,result.sample_timings=state.seconds,state.max_calls,state.sample_timings
    result.started_realtime,result.finished_realtime=state.started,state.finished
    result.elapsed_realtime_seconds=math.max(0,(state.finished or state.last_clock)-state.started)
    result.call_events,result.c_calls,result.lua_calls=state.call_events,state.c_calls,state.lua_calls
    result.return_events,result.tail_returns=state.return_events,state.tail_returns
    result.hook_errors,result.info_unavailable=state.hook_errors,state.info_unavailable
    result.untracked_returns,result.stack_resets=state.untracked_returns,state.stack_resets
    result.samples_started,result.samples_completed,result.samples_discarded=state.samples_started,state.samples_completed,state.samples_discarded
    result.detail_omitted_calls,result.callback_metadata_entries=state.detail_omitted_calls,state.metadata_count
    result.coverage.native_modifier_calls=state.native_modifier_calls
    result.coverage.modifier_callback_calls=state.callback_calls
    result.coverage.lua_dispatch_modifier_calls=state.lua_dispatch_modifier_calls
    result.coverage.native_origin_criterion="matching Lua callback called from C/no Lua caller; inferential"
    result.coverage.native_boundary_calls=state.native_boundary_calls
    result.coverage.workspace_c_caller_calls=state.workspace_c_caller_calls
    result.coverage.workspace_no_lua_caller_calls=state.workspace_no_lua_caller_calls
    result.coverage.workspace_legacy_modifier_boundary_calls=state.workspace_legacy_modifier_boundary_calls
    result.coverage.workspace_other_boundary_calls=state.workspace_other_boundary_calls
    result.coverage.boundary_export_identity_calls=state.boundary_export_identity_calls
    result.coverage.workspace_boundary_criterion="call-only Lua file source within repository vscripts; C/no Lua caller; not proof of a particular engine binding"
    result.boundary_classification_enabled=not state.sample_timings
    result.declared_root=state.declared_root or false
    result.source_scope={origin=state.source_scope_origin,root=state.vscripts_root or false,
        accepts_relative_vscripts_file_sources=true,accepts_arbitrary_absolute_vscripts_paths=false,
        declared_root_is_callers_current_repository_anchor=true}
    result.boundary_detail_omitted_calls=state.boundary_detail_omitted_calls
    result.boundary_export_metadata_entries=state.boundary_metadata_count
    result.discard_reasons={}
    for key,value in pairs(state.discard_reasons) do result.discard_reasons[key]=value end
    for _,row in ipairs(state.rows) do
        local copy={};for key,value in pairs(row) do
            if key=="aliases" or key=="export_aliases" then copy[key]={};for i,label in ipairs(value) do copy[key][i]=label end
            else copy[key]=value end
        end
        result.details[#result.details+1]=copy
    end
    table.sort(result.details,function(a,b) if a.calls==b.calls then return a.name<b.name end;return a.calls>b.calls end)
    return result
end
return M
