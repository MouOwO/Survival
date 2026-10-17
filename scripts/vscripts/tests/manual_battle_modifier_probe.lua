-- Inert default-OFF Workshop diagnostic. Counts only calls reaching existing
-- class methods; never invokes declarations/callbacks, refreshes or creates mods.
local M={}
local active,last,sequence=nil,nil,0
local CONTEXT='survival_battle_modifier_probe'
local SAMPLE_LIMIT,PER_METHOD_SAMPLES,SAMPLE_EVERY,PARENT_CACHE_LIMIT=64,4,64,2048
local CENSUS_EXAMPLES,ENTITY_LIMIT=32,131072
local CLASS_NAMES={
    'modifier_rogue_combat_bonus','modifier_rogue_training_dummy','modifier_rogue_training_attack','modifier_rogue_training_attack_gain',
    'modifier_building_damage_sound','modifier_equipment_effects','modifier_rogue_corrosive_shield_attack',
    'modifier_single_health_bar','modifier_tree_progression','modifier_tree_attack_observer',
    'modifier_lumberjack_ai','modifier_lumberjack_attack_observer','modifier_enemy_wall_ai','modifier_enemy_attack_observer',
    'modifier_tower_auto_attack','modifier_tower_attack_effects','modifier_tower_damage_observer',
    'modifier_rogue_ultimate_tower_effects','modifier_weapon_stat_projection','modifier_weapon_attack_tracker',
    'modifier_weapon_growth_tracker','modifier_survival_hero_skill','modifier_monkey_king_clone','modifier_blademaster_clone',
    'modifier_hero_exclusive_summon_attack_rate','modifier_practice_monster_ai','modifier_challenge_11_staging',
    'modifier_survival_managed_buff','modifier_building_under_construction','modifier_repair_worker_ai'}
local METHODS={
    OnTakeDamage='global_event',OnAttacked='global_event',OnAttackStart='global_event',OnAttack='global_event',
    OnAttackLanded='global_event',OnAttackFail='global_event',OnAttackRecord='global_event',
    OnAttackRecordDestroy='global_event',OnDeath='global_event',OnOrder='global_event',
    OnAbilityExecuted='global_event',OnAbilityFullyCast='global_event',OnModifierAdded='global_event',
    OnIntervalThink='interval',publish_state='health_bar_publish',CheckState='state_query',
    HandleTakeDamage='shared_route',HandleAttackLanded='shared_route',HandleAttack='shared_route',
    HandleAttackStart='shared_route',HandleAttackRecordDestroy='shared_route',HandleDeath='shared_route',
    GetModifierIncomingDamage_Percentage='property_query',GetModifierPhysicalArmorBonus='property_query',
    GetModifierPreAttack_BonusDamage='property_query',GetModifierBaseDamageOutgoing_Percentage='property_query',
    GetModifierDamageOutgoing_Percentage='property_query',GetMinHealth='property_query'}
local METHOD_NAMES={};for name in pairs(METHODS) do METHOD_NAMES[#METHOD_NAMES+1]=name end;table.sort(METHOD_NAMES)
local function copy(t) if type(t)~='table' then return t end local out={};for k,v in pairs(t) do out[k]=copy(v) end;return out end
local function read(o,name)
    if not o or type(o[name])~='function' then return false end
    return pcall(o[name],o)
end
local function scalar(v)
    if type(v)=='number' then if v==v and math.abs(v)~=math.huge then return v end
    elseif type(v)=='boolean' then return v
    elseif type(v)=='string' then return v:sub(1,160):gsub('[%c]','?') end
end
local function tools()
    return IsServer and IsServer() and IsInToolsMode and IsInToolsMode()
end
local function class_list(requested)
    local allowed,selected,names={},{},{}
    for _,name in ipairs(CLASS_NAMES) do allowed[name]=true end
    for _,name in ipairs(requested or CLASS_NAMES) do
        assert(type(name)=='string' and allowed[name],'Only documented battle modifier classes allowed')
        if not selected[name] then selected[name]=true;names[#names+1]=name end
    end
    assert(#names>0,'At least one battle class required');return names,selected
end
local function flags(mod)
    local out={}
    for _,name in ipairs({'shared_attack_observer','shared_death_observer','shared_tree_observer',
        'shared_wall_feedback_observer','health_bar_staging_paused','survival_rogue_damage_decl_omitted'}) do
        out[name]=scalar(mod[name])
    end
    return out
end
local function census(names,deadline,clock)
    local chosen,rows={},{}
    for _,name in ipairs(names) do chosen[name]=true;rows[name]={class=name,instances=0,parents=0,alive_parents=0,
        dead_parents=0,parent_liveness_unknown=0,owners={},flags={}} end
    local result={api='Entities.First/Next + entity.FindAllModifiers + modifier.GetName',entity_collection_complete=false,
        modifier_reads_complete=true,parent_reads_complete=true,entities_visited=0,modifier_containers=0,
        modifiers_observed=0,selected_instances=0,entity_duplicates=0,modifier_duplicates=0,
        invalid_entities=0,modifier_read_errors=0,modifier_name_errors=0,parent_read_errors=0,
        examples={},example_limit=CENSUS_EXAMPLES,classes={},only_observed_native_instances=true,
        native_declaration_registration_or_release_inferred=false}
    local seen_entities,seen_modifiers={},{}
    local parent_sets={};for _,name in ipairs(names) do parent_sets[name]={} end
    local function finish()
        for _,name in ipairs(names) do result.classes[#result.classes+1]=rows[name] end
        result.complete=result.entity_collection_complete and result.modifier_reads_complete and result.parent_reads_complete
        return result
    end
    if not Entities or type(Entities.First)~='function' or type(Entities.Next)~='function' then
        result.error='full_native_entity_iterator_unavailable';return finish()
    end
    local ok,entity=pcall(Entities.First,Entities)
    if not ok then result.error='native_first_failed';return finish() end
    while entity~=nil do
        if result.entities_visited>=ENTITY_LIMIT then result.error='entity_safety_limit';return finish() end
        if deadline and result.entities_visited%64==0 and clock()>=deadline then result.error='census_wall_deadline';return finish() end
        if seen_entities[entity] then result.entity_duplicates=result.entity_duplicates+1;result.error='native_iterator_cycle';return finish() end
        seen_entities[entity]=true;result.entities_visited=result.entities_visited+1
        local live,invalid=read(entity,'IsNull')
        if live and invalid==true then result.invalid_entities=result.invalid_entities+1
        elseif type(entity.FindAllModifiers)=='function' then
            result.modifier_containers=result.modifier_containers+1
            local mods_ok,mods=read(entity,'FindAllModifiers')
            local dense=mods_ok and type(mods)=='table';local entries=0
            if dense then for k in pairs(mods) do entries=entries+1;if type(k)~='number' or k<1 or k~=math.floor(k) then dense=false end end;dense=dense and entries==#mods end
            if not dense then result.modifier_reads_complete=false;result.modifier_read_errors=result.modifier_read_errors+1
            else for _,mod in ipairs(mods) do
                local name_ok,name=read(mod,'GetName')
                if not name_ok or type(name)~='string' then result.modifier_reads_complete=false;result.modifier_name_errors=result.modifier_name_errors+1
                elseif seen_modifiers[mod] then result.modifier_duplicates=result.modifier_duplicates+1
                else
                    seen_modifiers[mod]=name;result.modifiers_observed=result.modifiers_observed+1
                    if chosen[name] then
                        local row=rows[name];row.instances=row.instances+1;result.selected_instances=result.selected_instances+1
                        local parent_ok,parent=read(mod,'GetParent')
                        if not parent_ok or not parent then result.parent_reads_complete=false;result.parent_read_errors=result.parent_read_errors+1
                        else
                            if not parent_sets[name][parent] then
                                parent_sets[name][parent]=true;row.parents=row.parents+1
                                local alive_ok,alive=read(parent,'IsAlive')
                                if not alive_ok or type(alive)~='boolean' then row.parent_liveness_unknown=row.parent_liveness_unknown+1
                                elseif alive then row.alive_parents=row.alive_parents+1 else row.dead_parents=row.dead_parents+1 end
                            end
                            local owner_ok,owner=read(parent,'GetPlayerOwnerID')
                            local owner_key=owner_ok and type(owner)=='number' and tostring(owner) or 'unknown'
                            row.owners[owner_key]=(row.owners[owner_key] or 0)+1
                            for flag,value in pairs(flags(mod)) do
                                local key=flag..'='..tostring(value);row.flags[key]=(row.flags[key] or 0)+1
                            end
                            if #result.examples<CENSUS_EXAMPLES then
                                local _,index=read(parent,'entindex');local _,unit_name=read(parent,'GetUnitName')
                                result.examples[#result.examples+1]={class=name,parent_entindex=scalar(index),
                                    unit_name=scalar(unit_name),native_owner=scalar(owner),flags=flags(mod)}
                            end
                        end
                    end
                end
            end end
        end
        local next_ok,next_entity=pcall(Entities.Next,Entities,entity)
        if not next_ok then result.error='native_next_failed';return finish() end
        entity=next_entity
    end
    result.entity_collection_complete=true;return finish()
end
local function parent(capture,self)
    if type(self)~='table' and type(self)~='userdata' then return nil end
    local known=capture.parents[self]
    if known then return known.parent end
    local ok,p=read(self,'GetParent')
    if not ok then capture.parent_read_failures=capture.parent_read_failures+1 end
    if capture.parent_cache_count<PARENT_CACHE_LIMIT then
        capture.parents[self]={parent=ok and p or nil};capture.parent_cache_count=capture.parent_cache_count+1
    else capture.parent_cache_overflow=capture.parent_cache_overflow+1 end
    return ok and p or nil
end
local function count(capture,row,self,params)
    row.calls=row.calls+1;capture.total_observed_calls=capture.total_observed_calls+1
    capture.kind_totals[row.kind]=(capture.kind_totals[row.kind] or 0)+1
    local p=parent(capture,self)
    if row.kind~='global_event' and row.kind~='shared_route' then
        if p then row.intrinsic_parent_calls=row.intrinsic_parent_calls+1 else row.relevance_unknown=row.relevance_unknown+1 end
    elseif p and type(params)=='table' then
        local has_entity=params.attacker~=nil or params.target~=nil or params.unit~=nil
            or params.victim~=nil or params.caster~=nil
        if params.attacker==p or params.target==p or params.unit==p or params.victim==p or params.caster==p then
            row.parent_related=row.parent_related+1
        elseif has_entity then row.parent_unrelated=row.parent_unrelated+1 else row.relevance_unknown=row.relevance_unknown+1 end
        for _,field in ipairs({'attacker','target','unit','victim','caster'}) do
            if params[field]==p then row['parent_as_'..field]=row['parent_as_'..field]+1 end
        end
    else row.relevance_unknown=row.relevance_unknown+1 end
end
local function caller_sample(capture,row,caller)
    row.sampled_caller_reads=row.sampled_caller_reads+1
    local kind=caller and caller.what=='C' and 'c_frame' or caller and (caller.what=='Lua' or caller.what=='main') and 'lua_frame' or 'unknown_frame'
    row[kind..'_samples']=row[kind..'_samples']+1
    capture.caller_samples[#capture.caller_samples+1]={class=row.class,method=row.method,call_number=row.calls,
        observed_frame=kind,what=scalar(caller and caller.what),source=scalar(caller and caller.short_src),line=scalar(caller and caller.currentline),
        name=scalar(caller and caller.name),native_engine_origin_proven=false}
end
local function install(capture,name)
    local target=_G[name]
    local stats={class=name,accessible=type(target)=='table',methods={},hooked={}}
    capture.classes[#capture.classes+1]=stats;if not stats.accessible then return end
    for _,method in ipairs(METHOD_NAMES) do
        local original=target[method]
        if type(original)=='function' then
            local row={class=name,method=method,kind=METHODS[method],calls=0,parent_related=0,parent_unrelated=0,
                relevance_unknown=0,intrinsic_parent_calls=0,sampled_caller_reads=0,c_frame_samples=0,lua_frame_samples=0,unknown_frame_samples=0}
            for _,field in ipairs({'attacker','target','unit','victim','caster'}) do row['parent_as_'..field]=0 end
            stats.methods[method]=row;stats.hooked[#stats.hooked+1]=method
            local original_raw=rawget(target,method)
            local wrapper=function(self,...)
                if active~=capture then return original(self,...) end
                -- Diagnostic overhead is not valid for a render FPS comparison.
                local world_ok,current_world=pcall(GameRules.GetGameModeEntity,GameRules)
                if not world_ok then capture.metadata_errors=capture.metadata_errors+1
                elseif current_world~=capture.mode then pcall(M.stop,'world_changed');return original(self,...) end
                local timed,now=pcall(capture.clock)
                if not timed then capture.metadata_errors=capture.metadata_errors+1
                elseif now>=capture.deadline then pcall(M.stop,'complete');return original(self,...) end
                local counted=pcall(count,capture,row,self,select(1,...))
                if not counted then capture.metadata_errors=capture.metadata_errors+1 end
                if counted and (row.calls-1)%SAMPLE_EVERY==0 and row.sampled_caller_reads<PER_METHOD_SAMPLES
                    and #capture.caller_samples<SAMPLE_LIMIT then
                    -- Level 3 skips the protected C pcall and this wrapper.
                    local info;if debug and debug.getinfo then local ok,value=pcall(debug.getinfo,3,'Sln');if ok then info=value end end
                    local sampled=pcall(caller_sample,capture,row,info);if not sampled then capture.metadata_errors=capture.metadata_errors+1 end
                end
                -- Never pcall, suppress, normalize or inspect gameplay returns.
                return original(self,...)
            end
            rawset(target,method,wrapper)
            capture.hooks[#capture.hooks+1]={target=target,method=method,original_raw=original_raw,wrapper=wrapper}
        end
    end
end
local function report(capture)
    if not capture then return {status='not_started',default_off=true} end
    local now_ok,now=pcall(capture.clock);local ended=capture.ended or (now_ok and now or capture.started)
    return {status=capture.stopped and 'stopped' or 'running',default_off=true,reason=capture.reason,
        clock=capture.clock_name,requested_seconds=capture.seconds,elapsed_seconds=ended-capture.started,
        total_observed_calls=capture.total_observed_calls,kind_totals=copy(capture.kind_totals),classes=copy(capture.classes),
        caller_samples=copy(capture.caller_samples),caller_sample_limit=SAMPLE_LIMIT,per_method_sample_limit=PER_METHOD_SAMPLES,
        caller_sample_every=SAMPLE_EVERY,parent_cache_limit=PARENT_CACHE_LIMIT,parent_cache_entries=capture.parent_cache_count,
        parent_cache_overflow=capture.parent_cache_overflow,parent_read_failures=capture.parent_read_failures,metadata_errors=capture.metadata_errors,
        restore_skipped=capture.restore_skipped,census_before=copy(capture.census_before),census_after=copy(capture.census_after),
        context=capture.context,
        manual_declaration_or_callback_calls=0,modifier_create_refresh_or_destroy_calls=0,
        instrumentation_is_render_fps_validation=false,native_global_dispatch_total_proven=false,
        module_name_note='modifier_rogue_combat_effects is a file/module; its native combat modifier class is modifier_rogue_combat_bonus. Corrosive is defined in modifier_rogue_reward_effects. No module is loaded by this diagnostic.',
        limit='Only calls reaching these temporary class wrappers are counted. Engine-cached method pointers may bypass them; absent hooks or zero calls are unconfirmed. C/Lua caller samples describe the observed stack frame, not a complete origin classification. Census reports only actual returned instances and no inferred registration, release, or lifecycle. Support/route/property counts are separate from global events.'}
end
function M.snapshot()
    if active then
        local world_ok,current_world=pcall(GameRules.GetGameModeEntity,GameRules)
        if world_ok and current_world~=active.mode then return M.stop('world_changed') end
        local ok,now=pcall(active.clock);if ok and now>=active.deadline then return M.stop('complete') end
    end
    return report(active or last)
end
function M.census(options)
    if not tools() then return {complete=false,error='requires_workshop_server'} end
    options=options or {};local names=class_list(options.classes)
    local ok,value=pcall(census,names)
    local result=ok and value or {complete=false,error='census_metadata_exception'}
    if options.attach_to_report==true then
        local capture=active or last
        if capture and GameRules:GetGameModeEntity()==capture.mode then capture.census_after=copy(result) end
    end
    return result
end
function M.stop(reason)
    local capture=active;if not capture then return report(last) end
    active=nil;capture.stopped=true;capture.reason=reason or 'manual'
    local ok,now=pcall(capture.clock);capture.ended=ok and now or capture.started
    for _,hook in ipairs(capture.hooks) do
        if rawget(hook.target,hook.method)==hook.wrapper then rawset(hook.target,hook.method,hook.original_raw)
        else capture.restore_skipped=capture.restore_skipped+1 end
    end
    if capture.timer_installed and capture.mode and type(capture.mode.SetContextThink)=='function' then
        pcall(capture.mode.SetContextThink,capture.mode,capture.context,nil,0)
    end
    -- Never retain native parent/modifier handles after the bounded diagnostic.
    capture.parents=nil;capture.hooks={};last=capture
    return report(capture)
end
function M.start(options)
    options=options or {}
    if options.enabled~=true then return {status='disabled',default_off=true,side_effects=false} end
    if active then return {status='rejected',error='already_running'} end
    if not tools() then return {status='rejected',error='requires_workshop_server'} end
    local seconds=tonumber(options.seconds) or 20
    if seconds<=0 or seconds>20 or seconds~=seconds then return {status='rejected',error='seconds_must_be_0_to_20'} end
    local mode=GameRules and GameRules.GetGameModeEntity and GameRules:GetGameModeEntity()
    if not mode or type(mode.SetContextThink)~='function' then return {status='rejected',error='context_timer_unavailable'} end
    local clock,clock_name
    if type(GetSystemTimeMS)=='function' then clock=function() return GetSystemTimeMS()/1000 end;clock_name='GetSystemTimeMS'
    elseif type(RealTime)=='function' then clock=RealTime;clock_name='RealTime'
    else return {status='rejected',error='wall_clock_unavailable'} end
    local ok,names=pcall(class_list,options.classes);if not ok then return {status='rejected',error='invalid_class_selection'} end
    local capture={mode=mode,seconds=seconds,clock=clock,clock_name=clock_name,started=clock(),hooks={},classes={},
        total_observed_calls=0,kind_totals={},caller_samples={},parents=setmetatable({},{__mode='k'}),
        parent_cache_count=0,parent_cache_overflow=0,parent_read_failures=0,metadata_errors=0,restore_skipped=0,names=names}
    sequence=sequence+1;capture.context=CONTEXT..'_'..sequence
    capture.deadline=capture.started+seconds
    local census_ok,before=pcall(census,names,capture.deadline,clock)
    capture.census_before=census_ok and before or {complete=false,error='census_metadata_exception'}
    active=capture
    if clock()>=capture.deadline then return M.stop('census_consumed_wall_budget') end
    local hooked=pcall(function() for _,name in ipairs(names) do install(capture,name) end end)
    if not hooked then return M.stop('class_hook_install_failed') end
    local installed=pcall(mode.SetContextThink,mode,capture.context,function()
        if active~=capture then return nil end
        if GameRules:GetGameModeEntity()~=mode then M.stop('world_changed');return nil end
        if clock()>=capture.deadline then M.stop('complete');return nil end
        return .1
    end,.1)
    if not installed then return M.stop('context_timer_install_failed') end
    capture.timer_installed=true
    return report(capture)
end
return M
