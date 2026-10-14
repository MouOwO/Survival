-- Default-OFF isolated Tools candidate. Reuses the existing five-event native
-- carrier. Attack records/properties, overhead helpers and gameplay are intact.
local M={}
local FLAG='SURVIVAL_SHARED_WEAPON_PROJECTION_DAMAGE_PROBE'
local STATE='survival_weapon_projection_damage_state'
local POINTER='survival_shared_weapon_projection_damage_registration'
local VERSION='survival_weapon_projection_damage_observer_version'
local bus=require('core/event_bus')
local events=require('core/events')
local function valid(u)
    local ok,v=pcall(function() return u and type(u.IsNull)=='function' and not u:IsNull() end)
    return ok and v==true
end
local function world()
    local mode=GameRules and GameRules.GetGameModeEntity and GameRules:GetGameModeEntity()
    return mode and (not mode.IsNull or not mode:IsNull()) and mode or nil
end
local function tools()
    return IsServer and IsServer() and IsInToolsMode and IsInToolsMode()
        and GetMapName and GetMapName()=='template_map'
end
local function carrier_ready(mode)
    local holder=mode and mode.survival_tower_damage_observer_holder
    local service=package.loaded['systems/tower_damage_observer']
    local ok,result=pcall(function() return valid(holder) and holder[VERSION]==1 and service
        and type(service.is_authoritative)=='function' and service.is_authoritative(holder)==true end)
    return ok and result==true
end
local function admission()
    if _G[FLAG]~=true or not tools() then return nil end
    local mode=world();local state=mode and mode[STATE];local guard=_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION
    return mode and state and state.enabled==true and guard and guard.mode==mode and state.guard==guard
        and state.bus==bus and require('core/event_bus')==bus and state.generation==bus.get_generation() and mode or nil
end
function M.set_probe(enabled)
    if not enabled then
        _G[FLAG]=false;local mode=world();local state=mode and mode[STATE];if state then state.enabled=false end
        return true
    end
    local mode=world();local guard=_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION
    if not tools() or not mode or not guard or guard.mode~=mode then return false end
    local state=mode[STATE]
    if state and state.generation~=bus.get_generation() then return false end
    if not state then
        state={enabled=false,bus=bus,generation=bus.get_generation(),registrations={},owners={},serial=0,
            counters={registered=0,active_shared=0,unregistered=0,registration_failed=0,damage_seen=0,
                routed=0,known_owner_events=0,unknown_owner_events=0,owner_query_errors=0,
                route_rejected=0,handler_errors=0}}
        mode[STATE]=state
    end
    state.enabled=true;state.guard=guard;_G[FLAG]=true;return true
end
function M.register_new(unit,modifier)
    local mode=admission();if not mode then return nil,'admission_disabled_or_scope_mismatch' end
    local state=mode[STATE]
    local ok,id,why=pcall(function()
        if not carrier_ready(mode) then return nil,'native_carrier_version_unavailable' end
        local methods=_G.modifier_weapon_stat_projection
        if not methods or type(methods.HandleTakeDamage)~='function'
            or type(methods.ResolveDamageOwner)~='function' then return nil,'original_projection_methods_unavailable' end
        if not valid(unit) or type(unit.IsRealHero)~='function' or unit:IsRealHero()~=true
            or type(unit.IsIllusion)~='function' or unit:IsIllusion()~=false
            or type(unit.IsClone)=='function' and unit:IsClone()~=false then return nil,'not_canonical_real_hero' end
        for _,flag in ipairs({'survival_monkey_king_clone','survival_blademaster_clone','survival_drow_companion',
            'survival_is_summon','survival_permanent_summon','survival_exclusive_summon'}) do
            if unit[flag]==true then return nil,'clone_or_summon' end
        end
        local owner=unit.survival_player_id
        if type(owner)~='number' or owner<0 or owner~=math.floor(owner) or math.abs(owner)==math.huge
            or type(unit.GetPlayerOwnerID)~='function' or unit:GetPlayerOwnerID()~=owner then return nil,'native_owner_unknown' end
        local context=require('systems/player_context_service')
        if context.owner_player_id(unit,true)~=owner or not context.is_owned_by(owner,unit) then return nil,'context_owner_mismatch' end
        local canonical=bus.request(events.HERO_SUMMON_GET_REQUEST,{player_id=owner})
        if not canonical or canonical.ok~=true or canonical.unit~=unit or type(canonical.hero_id)~='string'
            or canonical.hero_id=='' or canonical.hero_id~=unit.survival_hero_id then return nil,'formal_hero_mismatch' end
        if not valid(modifier) or type(modifier.GetParent)~='function' or modifier:GetParent()~=unit then return nil,'modifier_parent_unknown' end
        if modifier.weapon_projection_damage_registration then return nil,'modifier_already_registered' end
        return owner
    end)
    if not ok or id==nil then
        state.counters.registration_failed=state.counters.registration_failed+1
        return nil,ok and why or 'native_or_registration_read_failed'
    end
    state.serial=state.serial+1
    local registration={unit=unit,modifier=modifier,world=mode,state=state,player_id=id,token={},serial=state.serial}
    local previous=unit[POINTER]
    local committed=pcall(function()
        modifier.weapon_projection_damage_registration=registration
        modifier.weapon_projection_damage_registration_token=registration.token
        unit[POINTER]=registration
        assert(modifier.weapon_projection_damage_registration==registration
            and modifier.weapon_projection_damage_registration_token==registration.token and unit[POINTER]==registration
            and admission()==mode and carrier_ready(mode))
        state.registrations[registration]=true
    end)
    if not committed then
        state.registrations[registration]=nil
        if modifier.weapon_projection_damage_registration==registration then modifier.weapon_projection_damage_registration=nil end
        if modifier.weapon_projection_damage_registration_token==registration.token then modifier.weapon_projection_damage_registration_token=nil end
        if valid(unit) and unit[POINTER]==registration then unit[POINTER]=previous end
        state.counters.registration_failed=state.counters.registration_failed+1
        return nil,'registration_commit_failed'
    end
    state.counters.registered=state.counters.registered+1;state.counters.active_shared=state.counters.active_shared+1
    state.owners[tostring(id)]=(state.owners[tostring(id)] or 0)+1
    return registration
end
function M.unregister(modifier)
    local r=modifier and modifier.weapon_projection_damage_registration
    if not r or r.modifier~=modifier or modifier.weapon_projection_damage_registration_token~=r.token then return false end
    if not r.state.registrations[r] then return false end
    r.state.registrations[r]=nil
    if valid(r.unit) and r.unit[POINTER]==r then r.unit[POINTER]=nil end
    modifier.weapon_projection_damage_registration=nil;modifier.weapon_projection_damage_registration_token=nil
    r.state.counters.unregistered=r.state.counters.unregistered+1
    r.state.counters.active_shared=math.max(0,r.state.counters.active_shared-1)
    local key=tostring(r.player_id);r.state.owners[key]=math.max(0,(r.state.owners[key] or 0)-1)
    return true
end
local function exact(r,mode)
    local ok,result=pcall(function() return r.world==mode and r.state.registrations[r] and valid(r.unit) and valid(r.modifier)
        and r.unit[POINTER]==r and r.modifier:GetParent()==r.unit
        and r.modifier.weapon_projection_damage_registration==r
        and r.modifier.weapon_projection_damage_registration_token==r.token
        and r.modifier.shared_weapon_projection_damage_observer==true
        and r.modifier.weapon_projection_damage_destroyed~=true end)
    return ok and result==true
end
function M.route(holder,params)
    if not IsServer() or type(params)~='table' then return false end
    local mode=world();local state=mode and mode[STATE]
    if not state or state.counters.active_shared==0 then return false end
    -- Disabling admission or changing its guard cannot silence a declaration
    -- that is already cached. A new world/bus generation never receives it.
    if state.bus~=bus or require('core/event_bus')~=bus or state.generation~=bus.get_generation()
        or mode.survival_tower_damage_observer_holder~=holder or not carrier_ready(mode) then
        state.counters.route_rejected=state.counters.route_rejected+1;return false
    end
    state.counters.damage_seen=state.counters.damage_seen+1
    local methods=_G.modifier_weapon_stat_projection
    if not methods or type(methods.HandleTakeDamage)~='function' or type(methods.ResolveDamageOwner)~='function' then return false end
    local owner_ok,owner=pcall(methods.ResolveDamageOwner,params.attacker)
    if not owner_ok then owner=nil;state.counters.owner_query_errors=state.counters.owner_query_errors+1 end
    if owner==nil then state.counters.unknown_owner_events=state.counters.unknown_owner_events+1
    else state.counters.known_owner_events=state.counters.known_owner_events+1 end
    local receivers={}
    for r in pairs(state.registrations) do if owner==nil or r.player_id==owner then receivers[#receivers+1]=r end end
    table.sort(receivers,function(a,b) return a.player_id==b.player_id and a.serial<b.serial or a.player_id<b.player_id end)
    local first_error,has_error,delivered=nil,false,0
    for _,r in ipairs(receivers) do
        if exact(r,mode) then
            -- Original handler performs the complete team/positive/owner guard.
            -- No tree, spell, clone, worker, tower or IsAlive shortcut is added.
            -- Independent native callbacks previously survived another
            -- receiver's exception: finish this stable snapshot before raising.
            state.counters.routed=state.counters.routed+1;delivered=delivered+1
            local ok,err=pcall(methods.HandleTakeDamage,r.modifier,params)
            if not ok then
                state.counters.handler_errors=state.counters.handler_errors+1
                if not has_error then first_error=err;has_error=true end
            end
        end
    end
    if has_error then error(first_error,0) end
    return delivered>0
end
function M.snapshot()
    if not tools() then return {default_off=true,available=false} end
    local mode=world();local state=mode and mode[STATE]
    local result={default_off=true,enabled=admission()~=nil,carrier_ready=carrier_ready(mode),counters={},owners={},
        scope='canonical_projection_same_owner_damage_unknown_owner_legacy_fanout',native_event_slots=5,
        attack_record_unchanged=true,properties_unchanged=true,new_instances_only=true,
        flag_off_keeps_registered_routes=true,guard_changes_keep_registered_routes=true,native_fps_verified=false}
    if state then for k,v in pairs(state.counters) do result.counters[k]=v end;for k,v in pairs(state.owners) do result.owners[k]=v end end
    return result
end
return M
