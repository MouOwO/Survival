-- Explicit Workshop diagnostic only. require() is inert. Never manually calls
-- DeclareFunctions, re-creates modifiers, refreshes them or changes declarations.
local M = {}
local active, last
local INSTANCE_LIMIT, EXAMPLE_LIMIT, CALLER_SAMPLE_EVERY = 1024, 32, 32
local classes = {"modifier_lumberjack_ai","modifier_enemy_wall_ai","modifier_tower_auto_attack",
    "modifier_tower_attack_effects","modifier_tree_progression","modifier_weapon_stat_projection",
    "modifier_weapon_attack_tracker","modifier_weapon_growth_tracker","modifier_equipment_effects",
    "modifier_rogue_combat_bonus","modifier_rogue_ultimate_tower_effects","modifier_monkey_king_clone",
    "modifier_blademaster_clone","modifier_survival_hero_skill","modifier_hero_exclusive_summon_attack_rate"}
local events = {
    MODIFIER_EVENT_ON_ATTACK_START="OnAttackStart", MODIFIER_EVENT_ON_ATTACK="OnAttack",
    MODIFIER_EVENT_ON_ATTACK_FAIL="OnAttackFail", MODIFIER_EVENT_ON_ATTACK_LANDED="OnAttackLanded",
    MODIFIER_EVENT_ON_ATTACK_RECORD="OnAttackRecord", MODIFIER_EVENT_ON_ATTACK_RECORD_DESTROY="OnAttackRecordDestroy",
    MODIFIER_EVENT_ON_TAKEDAMAGE="OnTakeDamage", MODIFIER_EVENT_ON_DEATH="OnDeath",
    MODIFIER_EVENT_ON_ATTACKED="OnAttacked", MODIFIER_EVENT_ON_ORDER="OnOrder",
    MODIFIER_EVENT_ON_ABILITY_EXECUTED="OnAbilityExecuted",
    MODIFIER_EVENT_ON_ABILITY_FULLY_CAST="OnAbilityFullyCast",
    MODIFIER_EVENT_ON_MODIFIER_ADDED="OnModifierAdded"}
local callback_names={};for _,name in pairs(events) do callback_names[#callback_names+1]=name end
table.sort(callback_names)
local function pack(...) return {n=select("#",...),...} end
local function read(object,name)
    if not object or type(object[name])~="function" then return nil end
    local ok,value=pcall(object[name],object);if ok then return value end
end
local function parent(self) return read(self,"GetParent") end
local function scalar(value)
    if type(value)=="boolean" or type(value)=="number" or type(value)=="string" then return value end
end
local function flags(self)
    local result={}
    for _,name in ipairs({"shared_attack_observer","shared_death_observer","shared_tree_observer",
        "survival_tree_event_decl_sampled","survival_rogue_damage_decl_sampled",
        "survival_rogue_damage_decl_omitted"}) do
        result[name]=scalar(self and self[name])
    end
    local p=parent(self)
    result.survival_global_tower_damage=scalar(p and p.survival_global_tower_damage)
    return result
end
local function event_list(declarations)
    local result={}
    if type(declarations)=="table" then
        for _,value in ipairs(declarations) do
            for constant,name in pairs(events) do
                if _G[constant]~=nil and value==_G[constant] then result[#result+1]=name;break end
            end
        end
    end
    table.sort(result);return result
end
local function observer_ready(class)
    local module
    if class=="modifier_lumberjack_ai" then module=package.loaded["systems/lumberjack_attack_observer"]
    elseif class=="modifier_enemy_wall_ai" then module=package.loaded["systems/enemy_attack_observer"]
    elseif class=="modifier_tower_auto_attack" or class=="modifier_tower_attack_effects" then
        module=package.loaded["systems/tower_damage_observer"]
    elseif class=="modifier_tree_progression" then module=package.loaded["systems/tree_attack_observer"] end
    local result={}
    for _,name in ipairs({"is_ready","can_route_death","can_route_auto_attack","can_register_new"}) do
        if module and type(module[name])=="function" then
            local ok,value=pcall(module[name]);result[name]=ok and scalar(value) or "read_failed"
        end
    end
    return result
end
local function state(capture,self,class)
    if type(self)~="table" and type(self)~="userdata" then return nil end
    local row=capture.instances[self]
    if row then return row end
    if capture.instance_count>=INSTANCE_LIMIT then
        capture.instance_overflow_observations=capture.instance_overflow_observations+1;return nil
    end
    capture.instance_count=capture.instance_count+1
    row={class=class};capture.instances[self]=row;return row
end
local function example(capture,row,self)
    if row.example then return row.example end
    if #capture.examples>=EXAMPLE_LIMIT then return nil end
    local p=parent(self)
    local value={class=row.class,unit=read(p,"entindex"),unit_name=read(p,"GetUnitName")}
    capture.examples[#capture.examples+1]=value;row.example=value;return value
end
local function safe(capture,fn,...)
    local ok=pcall(fn,...);if not ok then capture.metadata_errors=capture.metadata_errors+1 end
end
local function lifecycle_before(capture,stats,self,method)
    local row=state(capture,self,stats.class)
    stats[method.."_calls"]=stats[method.."_calls"]+1
    if method=="DeclareFunctions" and row and not row.first_decl then
        row.first_before_created=row.created_entered~=true
        row.observer_ready_before=observer_ready(stats.class)
        row.flags_before=flags(self)
    end
    if method=="OnCreated" and row then row.created_entered=true end
end
local function lifecycle_after(capture,stats,self,method,result)
    local row=state(capture,self,stats.class);if not row then return end
    if method=="DeclareFunctions" and not row.first_decl then
        row.first_decl=true
        local returned=event_list(result)
        local phase=row.first_before_created and "before_created_enter" or "after_created_enter"
        stats.first_declarations=stats.first_declarations+1
        stats.first_phase[phase]=stats.first_phase[phase]+1
        if #returned==0 then stats.first_without_global_events=stats.first_without_global_events+1 end
        for _,name in ipairs(returned) do stats.first_global_events[name]=(stats.first_global_events[name] or 0)+1 end
        local ex=example(capture,row,self)
        if ex then ex.first_decl_phase=phase;ex.first_global_events=returned
            ex.observer_ready_at_first=row.observer_ready_before;ex.flags_before_first=row.flags_before
            ex.flags_at_first=flags(self) end
    elseif method=="OnCreated" then
        row.created_completed=true
        stats.created_instances=stats.created_instances+1
        if not row.first_decl then stats.created_without_observed_decl=stats.created_without_observed_decl+1 end
        local ex=example(capture,row,self);if ex then ex.flags_after_created=flags(self) end
    end
end
local function callback(capture,stats,self,name,params,caller,sampled)
    local count=stats.callbacks[name]
    count.calls=count.calls+1
    local p=parent(self)
    if p and type(params)=="table" then
        if params.attacker==p or params.unit==p or params.target==p then count.self_related=count.self_related+1
        else count.unrelated=count.unrelated+1 end
    else count.relevance_unknown=count.relevance_unknown+1 end
    if sampled then
        count.sampled_caller_reads=count.sampled_caller_reads+1
        local kind=caller and caller.what=="C" and "c_caller"
            or caller and caller.what=="Lua" and "lua_caller" or "unknown_caller"
        count[kind]=count[kind]+1
    end
end
local function install(capture,class)
    local target=_G[class]
    local stats={class=class,accessible=type(target)=="table",DeclareFunctions_calls=0,OnCreated_calls=0,
        first_declarations=0,first_without_global_events=0,created_instances=0,created_without_observed_decl=0,
        first_phase={before_created_enter=0,after_created_enter=0},first_global_events={},callbacks={},hooked={}}
    capture.classes[#capture.classes+1]=stats
    if not stats.accessible then return end
    local names={"DeclareFunctions","OnCreated"};for _,name in ipairs(callback_names) do names[#names+1]=name end
    for _,name in ipairs(names) do
        local original=target[name]
        if type(original)=="function" then
            local method=name
            if method~="DeclareFunctions" and method~="OnCreated" then
                stats.callbacks[method]={calls=0,self_related=0,unrelated=0,relevance_unknown=0,
                    sampled_caller_reads=0,c_caller=0,lua_caller=0,unknown_caller=0}
            end
            local wrapper=function(self,...)
                if active~=capture then return original(self,...) end
                if method=="DeclareFunctions" or method=="OnCreated" then
                    safe(capture,lifecycle_before,capture,stats,self,method)
                    -- No pcall around gameplay code: original errors propagate.
                    local returned=pack(original(self,...))
                    safe(capture,lifecycle_after,capture,stats,self,method,returned[1])
                    return unpack(returned,1,returned.n)
                end
                local row=stats.callbacks[method]
                local caller
                local sampled=row.calls%CALLER_SAMPLE_EVERY==0
                if sampled and debug and debug.getinfo then caller=debug.getinfo(2,"S") end
                safe(capture,callback,capture,stats,self,method,select(1,...),caller,sampled)
                return original(self,...)
            end
            target[method]=wrapper
            capture.hooks[#capture.hooks+1]={target=target,name=method,original=original,wrapper=wrapper}
            stats.hooked[#stats.hooked+1]=method
        end
    end
end
local function deep_copy(value)
    if type(value)~="table" then return value end
    local result={};for key,item in pairs(value) do result[key]=deep_copy(item) end;return result
end
local function report(capture)
    if not capture then return {status="not_started",default_off=true} end
    return {status=capture.stopped and "stopped" or "running",reason=capture.reason,
        clock=capture.clock_name,elapsed_seconds=(capture.ended or capture.clock())-capture.started,
        requested_seconds=capture.seconds,metadata_errors=capture.metadata_errors,
        instance_limit=INSTANCE_LIMIT,instances_tracked=capture.instance_count,
        instance_overflow_observations=capture.instance_overflow_observations,
        example_limit=EXAMPLE_LIMIT,examples=deep_copy(capture.examples),classes=deep_copy(capture.classes),
        caller_sample_every=CALLER_SAMPLE_EVERY,restore_skipped=capture.restore_skipped,
        limits="Only first declarations actually observed by these wrappers are reported. Zero calls or absent hooks are unconfirmed; engine-cached methods may bypass wrappers. Callbacks include shared Lua routing: sampled caller categories and unrelated counts are evidence, not proof of native origin. No manual DeclareFunctions calls or modifier refreshes."}
end
function M.snapshot() return report(active or last) end
function M.stop(reason)
    local capture=active;if not capture then return report(last) end
    active=nil;capture.stopped=true;capture.reason=reason or "manual";capture.ended=capture.clock()
    for _,hook in ipairs(capture.hooks) do
        if hook.target[hook.name]==hook.wrapper then hook.target[hook.name]=hook.original
        else capture.restore_skipped=capture.restore_skipped+1 end
    end
    if capture.mode and capture.mode.SetContextThink then capture.mode:SetContextThink(capture.context,nil,0) end
    last=capture;return report(capture)
end
function M.start(seconds)
    if active then return false,"already running" end
    if not IsServer or not IsServer() or not IsInToolsMode or not IsInToolsMode() then return false,"requires Workshop server" end
    seconds=tonumber(seconds) or 20
    if seconds<=0 or seconds>20 or seconds~=seconds then return false,"seconds must be 0..20" end
    local mode=GameRules and GameRules.GetGameModeEntity and GameRules:GetGameModeEntity()
    if not mode or type(mode.SetContextThink)~="function" then return false,"context timer unavailable" end
    local clock,clock_name
    if type(GetSystemTimeMS)=="function" then clock=function() return GetSystemTimeMS()/1000 end;clock_name="GetSystemTimeMS"
    elseif type(RealTime)=="function" then clock=RealTime;clock_name="RealTime"
    else return false,"real wall clock unavailable" end
    local capture={mode=mode,context="survival_modifier_declaration_probe",seconds=seconds,
        clock=clock,clock_name=clock_name,started=clock(),hooks={},classes={},examples={},
        instances=setmetatable({},{__mode="k"}),instance_count=0,instance_overflow_observations=0,
        metadata_errors=0,restore_skipped=0}
    active=capture
    for _,class in ipairs(classes) do install(capture,class) end
    mode:SetContextThink(capture.context,function()
        if active~=capture then return nil end
        if GameRules:GetGameModeEntity()~=mode then M.stop("world_changed");return nil end
        if clock()-capture.started>=seconds then M.stop("complete");return nil end
        return .25
    end,.25)
    return true
end
return M
