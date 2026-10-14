-- Default-OFF Tools admission. Reuses the existing native tower damage carrier;
-- never creates a holder, changes a cached declaration or subscribes per hero.
local M={}
local FLAG='SURVIVAL_SHARED_HERO_EQUIPMENT_DAMAGE_PROBE'
local STATE='survival_hero_equipment_damage_state'
local POINTER='survival_shared_hero_equipment_damage_registration'
local VERSION='survival_hero_equipment_damage_observer_version'
local function valid(u)
    local ok,result=pcall(function() return u and type(u.IsNull)=='function' and not u:IsNull() end)
    return ok and result==true
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
    return valid(holder) and holder[VERSION]==1 and service and type(service.is_authoritative)=='function'
        and service.is_authoritative(holder)==true or false
end
local function admission()
    if _G[FLAG]~=true or not tools() then return nil end
    local mode=world();local state=mode and mode[STATE];local guard=_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION
    return mode and state and state.enabled==true and guard and guard.mode==mode and state.guard==guard and mode or nil
end
function M.set_probe(enabled)
    if not enabled then
        _G[FLAG]=false;local mode=world();local state=mode and mode[STATE];if state then state.enabled=false end
        return true
    end
    local mode=world();local guard=_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION
    if not tools() or not mode or not guard or guard.mode~=mode then return false end
    local state=mode[STATE]
    if not state then
        state={enabled=false,counters={registered=0,active_registrations=0,unregistered=0,routed=0,
            registration_failed=0,route_rejected=0},owners={}}
        mode[STATE]=state
    end
    state.enabled=true;state.guard=guard;_G[FLAG]=true;return true
end
function M.register_new(unit,modifier)
    local mode=admission();if not mode then return nil,'admission_disabled_or_guard_mismatch' end
    local state=mode[STATE]
    local ok,id,why=pcall(function()
        if not carrier_ready(mode) then return nil,'native_carrier_version_unavailable' end
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
        local bus,events=require('core/event_bus'),require('core/events')
        local canonical=bus.request(events.HERO_SUMMON_GET_REQUEST,{player_id=owner})
        if not canonical or canonical.ok~=true or canonical.unit~=unit or type(canonical.hero_id)~='string'
            or canonical.hero_id=='' or canonical.hero_id~=unit.survival_hero_id then return nil,'formal_hero_mismatch' end
        if not valid(modifier) or type(modifier.GetParent)~='function' or modifier:GetParent()~=unit then return nil,'modifier_parent_unknown' end
        if modifier.equipment_damage_registration then return nil,'modifier_already_registered' end
        return owner
    end)
    if not ok or id==nil then
        state.counters.registration_failed=state.counters.registration_failed+1
        return nil,ok and why or 'native_or_registration_read_failed'
    end
    -- Commit the exact pointer before returning permission to omit the event.
    -- If assignment fails, remove only the partial registration we own.
    local registration={unit=unit,modifier=modifier,world=mode,state=state,player_id=id,token={}}
    local previous=unit[POINTER]
    local committed=pcall(function()
        modifier.equipment_damage_registration=registration
        modifier.equipment_damage_registration_token=registration.token
        unit[POINTER]=registration
        assert(modifier.equipment_damage_registration==registration and modifier.equipment_damage_registration_token==registration.token
            and unit[POINTER]==registration and world()==mode and carrier_ready(mode))
    end)
    if not committed then
        if modifier.equipment_damage_registration==registration then modifier.equipment_damage_registration=nil end
        if modifier.equipment_damage_registration_token==registration.token then modifier.equipment_damage_registration_token=nil end
        if unit[POINTER]==registration then unit[POINTER]=previous end
        state.counters.registration_failed=state.counters.registration_failed+1
        return nil,'registration_commit_failed'
    end
    state.counters.registered=state.counters.registered+1
    state.counters.active_registrations=state.counters.active_registrations+1
    state.owners[tostring(id)]=(state.owners[tostring(id)] or 0)+1
    return registration
end
function M.unregister(modifier)
    local registration=modifier and modifier.equipment_damage_registration
    if not registration or registration.modifier~=modifier or modifier.equipment_damage_registration_token~=registration.token then return false end
    local unit,state=registration.unit,registration.state
    -- The registration table is the unforgeable generation token. Never erase
    -- a replacement receiver, even if its parent/native index is identical.
    if valid(unit) and unit[POINTER]==registration then unit[POINTER]=nil end
    modifier.equipment_damage_registration=nil
    modifier.equipment_damage_registration_token=nil
    state.counters.unregistered=state.counters.unregistered+1
    state.counters.active_registrations=math.max(0,state.counters.active_registrations-1)
    state.owners[tostring(registration.player_id)]=math.max(0,(state.owners[tostring(registration.player_id)] or 0)-1)
    return true
end
function M.route(holder,params)
    if not IsServer() or type(params)~='table' then return false end
    local unit=params.attacker
    local read_ok,registration=pcall(function() return valid(unit) and unit[POINTER] or nil end)
    if not read_ok then return false end
    if not registration then return false end
    local mode=world();local receiver=registration.modifier
    local ok,allowed=pcall(function()
        return mode==registration.world and valid(unit) and registration.unit==unit
            and mode.survival_tower_damage_observer_holder==holder and carrier_ready(mode)
            and valid(receiver) and receiver:GetParent()==unit
            and receiver.equipment_damage_registration==registration
            and receiver.equipment_damage_registration_token==registration.token
            and receiver.shared_equipment_damage_observer==true and receiver.equipment_damage_destroyed~=true
    end)
    if not ok or not allowed then registration.state.counters.route_rejected=registration.state.counters.route_rejected+1;return false end
    local methods=_G.modifier_equipment_effects
    if not methods or type(methods.HandleTakeDamage)~='function' then return false end
    -- Admission flag/guard and IsAlive are intentionally absent. A cached empty
    -- declaration must still process the original dead-hero in-flight hit.
    registration.state.counters.routed=registration.state.counters.routed+1
    methods.HandleTakeDamage(receiver,params)
    return true
end
function M.snapshot()
    if not tools() then return {default_off=true,available=false} end
    local mode=world();local state=mode and mode[STATE]
    local result={default_off=true,enabled=admission()~=nil,carrier_ready=carrier_ready(mode),counters={},owners={},
        scope='canonical_real_hero_equipment_lifesteal_attacker_route',new_registrations_only=true,
        flag_off_keeps_registered_routes=true,guard_changes_do_not_disable_existing_routes=true,
        native_lifesteal_or_fps_verified=false}
    if state then for k,v in pairs(state.counters) do result.counters[k]=v end;for k,v in pairs(state.owners) do result.owners[k]=v end end
    return result
end
return M
