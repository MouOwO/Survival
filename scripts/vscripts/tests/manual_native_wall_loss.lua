-- Inert by default. Tools natural-wall-loss observation, not a death simulator.
-- start({enabled=true}), snapshot({quiet=true}), release(player_id), stop().
-- Releases only the selected fixture's exact test protections. Native attacks
-- must cause death. No account contents/identity, auth or provider data is output.
local M = {}
local KEY = 'SURVIVAL_NATIVE_WALL_LOSS'
local FLOOR = 'modifier_manual_real_game_stress_wall'
local function bus() return require('core/event_bus') end
local function events() return require('core/events') end
local function request(name,payload) return bus().request(events()[name] or name,payload) end
local function safe(fn,...)
    if type(fn)~='function' then return nil,false end
    local ok,value=pcall(fn,...);if ok then return value,true end;return nil,false
end
local function number(value)
    return type(value)=='number' and value==value and math.abs(value)<math.huge and value or nil
end
local function scalar(value) return type(value)=='string' and value:sub(1,160) or nil end
local function live(unit)
    local ok,result=pcall(function() return unit and not unit:IsNull() and unit:IsAlive() end)
    return ok and result==true
end
local function now()
    return GameRules and number(safe(GameRules.GetGameTime,GameRules)) or nil
end
local function mode() return GameRules and safe(GameRules.GetGameModeEntity,GameRules) or nil end
local function state() return GameRules and number(safe(GameRules.State_Get,GameRules)) or nil end
local function tools()
    assert(IsServer and IsServer() and IsInToolsMode and IsInToolsMode(),'Tools server only')
    assert(GetMapName and GetMapName()=='template_map','template_map only')
end
local function same_world(s)
    if not s or _G[KEY]~=s or mode()~=s.mode
        or _G.SURVIVAL_FOUR_PLAYER_LIVE_PERF~=s.fixture
        or _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION~=s.guard
        or _G.SURVIVAL_REAL_GAME_STRESS~=s.scene
        or s.guard.mode~=s.mode or s.scene.mode~=s.mode
        or s.fixture.guard~=s.guard or s.fixture.defender_scene~=s.scene then return false end
    local setup=require('systems/match_setup_service')
    return setup.get_mode()==s.match_mode and setup.get_session_id()==s.session
end
local function sorted_ids(values)
    local result={};for _,id in ipairs(values or {}) do result[#result+1]=id end
    table.sort(result);return result
end
local function four_roster()
    local ids=sorted_ids(require('systems/multiplayer_player_service').participating_player_ids())
    if #ids~=4 then return false end
    for i=1,4 do if ids[i]~=i-1 then return false end end
    return true
end
local function profile_matches(s,id)
    local expected=s.fixture.memory_profiles and s.fixture.memory_profiles[id]
    if not expected or not expected.save or not expected.save.gameplay_stats then return false end
    local ok,actual=pcall(require('systems/player_profile_service').get_profile,id)
    if not ok or not actual or actual.account_id~=expected.account_id or actual.revision~=expected.revision
        or not actual.save or not actual.save.gameplay_stats then return false end
    for key,value in pairs(expected.save.gameplay_stats) do
        if actual.save.gameplay_stats[key]~=value then return false end
    end
    return true
end
local function formal_wall(id)
    local result=request('BUILDING_LIST_REQUEST',{player_id=id,building_id='wall',handles_only=true})
    local found
    for _,row in ipairs(result and result.buildings or {}) do
        if row.building_id=='wall' then
            if found then return nil,'multiple_formal_walls' end
            if tonumber(row.player_id)~=id or not live(row.unit) then return nil,'formal_wall_invalid' end
            local query=request('BUILDING_QUERY_REQUEST',{entindex=row.unit:entindex(),read_only=true})
            if not query or query.unit~=row.unit or query.building_id~='wall'
                or query.constructing==true or tonumber(query.player_id)~=id then return nil,'wall_not_completed_or_owned' end
            local context=require('systems/player_context_service')
            if context.owner_player_id(row.unit,true)~=id or not context.is_owned_by(id,row.unit) then
                return nil,'wall_context_owner_mismatch'
            end
            local native,known=safe(row.unit.GetPlayerOwnerID,row.unit)
            if not known or (native~=id and native~=-1) then return nil,'wall_native_owner_mismatch' end
            found=row.unit
        end
    end
    if found then return found,nil end
    return nil,'formal_wall_unavailable'
end
local function floor_for(s,wall)
    if s.guard.wall_targets[wall]~=s.scene then return nil,'wall_armor_guard_mismatch' end
    local modifier=s.scene.wall_survival and s.scene.wall_survival[wall]
    if not modifier then return nil,'wall_floor_missing' end
    local ok,valid=pcall(function()
        return not modifier:IsNull() and modifier:GetParent()==wall
            and wall:FindModifierByName(FLOOR)==modifier and modifier.scene==s.scene and modifier.guard==s.guard
            and modifier:GetStackCount()==1 and modifier:GetMinHealth()==1
            and type(modifier.SetStackCount)=='function' and type(modifier.Destroy)=='function'
    end)
    if ok and valid then return modifier,nil end
    return nil,'wall_floor_identity_mismatch'
end
local function counters()
    return {building_destroyed=0,wall_destroyed=0,player_defeated=0,player_disconnected=0,defeat_cleanup=0}
end
local function summary(s,label,id)
    if s.print_events~=true then return end
    local c=s.counts[id] or counters()
    local multiplayer=require('systems/multiplayer_player_service')
    local survivors=0
    for owner=0,3 do if not multiplayer.is_defeated(owner) then survivors=survivors+1 end end
    print(string.format('[NATIVE_WALL_LOSS] event=%s owner=%s native_state=%s survivors=%d wall_destroyed=%d defeated=%d disconnected=%d cleanup=%d',
        label,tostring(id),tostring(state()),survivors,c.wall_destroyed,c.player_defeated,c.player_disconnected,c.defeat_cleanup))
end
local function record(s,kind,payload)
    if s.status~='running' or not same_world(s) then return end
    local id=payload and payload.player_id
    if type(id)~='number' or id~=math.floor(id) or id<0 or id>3 then return end
    local c=s.counts[id]
    c[kind]=c[kind]+1
    if kind=='building_destroyed' and payload.building_id=='wall' then c.wall_destroyed=c.wall_destroyed+1 end
    if kind=='player_disconnected' and payload.defeat_cleanup==true then c.defeat_cleanup=c.defeat_cleanup+1 end
    s.event_total=s.event_total+1
    s.trace[(s.event_total-1)%128+1]={sequence=s.event_total,kind=kind,player_id=id,
        building_id=scalar(payload.building_id),entindex=number(payload.entindex),reason=scalar(payload.reason),
        defeat_cleanup=payload.defeat_cleanup==true,game_time=now(),native_state=state()}
    summary(s,kind,id)
end
function M.start(options)
    options=options or {}
    if options.enabled~=true then return {ok=false,error='probe_default_off'} end
    tools()
    local previous=_G[KEY]
    assert(not previous or previous.status~='running','Stop the previous wall-loss observer first')
    local fixture=assert(_G.SURVIVAL_FOUR_PLAYER_LIVE_PERF,'Current four-owner fixture required')
    local s={mode=mode(),fixture=fixture,guard=_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION,
        scene=_G.SURVIVAL_REAL_GAME_STRESS,status='validating',counts={},walls={},released={},trace={},event_total=0,
        print_events=options.print_events~=false,subscriptions={},started_game_time=now()}
    assert(s.guard and s.scene and s.mode,'Current isolated world required')
    local setup=require('systems/match_setup_service')
    s.match_mode,s.session=setup.get_mode(),setup.get_session_id()
    _G[KEY]=s
    assert(same_world(s) and fixture.status=='ready' and s.scene.status=='ready','Ready current fixture/guard/scene/session required')
    assert(number(DOTA_GAMERULES_STATE_GAME_IN_PROGRESS) and state()==DOTA_GAMERULES_STATE_GAME_IN_PROGRESS,
        'Native GAME_IN_PROGRESS enum and state required')
    assert(four_roster(),'Four registered participant IDs 0..3 required')
    for id=0,3 do
        local multiplayer=require('systems/multiplayer_player_service')
        assert(not multiplayer.is_defeated(id),'All four owners must initially be alive')
        assert(not multiplayer.is_disconnected or not multiplayer.is_disconnected(id),'All four owners must initially be connected')
        assert(profile_matches(s,id),'Current full isolated profile mismatch for owner '..id)
        local wall,reason=formal_wall(id);assert(wall,reason)
        local floor,why=floor_for(s,wall);assert(floor,why)
        s.walls[id],s.counts[id]=wall,counters()
    end
    for _,entry in ipairs({{'BUILDING_DESTROYED','building_destroyed'},
        {'PLAYER_DEFEATED','player_defeated'},{'PLAYER_DISCONNECTED','player_disconnected'}}) do
        local kind=entry[2]
        s.subscriptions[#s.subscriptions+1]=bus().subscribe(events()[entry[1]],function(payload) record(s,kind,payload) end)
    end
    s.status='running'
    return M.snapshot({quiet=not s.print_events})
end
local function actor(unit)
    if not unit then return {present=false} end
    local null,known=safe(unit.IsNull,unit)
    if not known or null then return {present=false,native_valid=false} end
    local result={present=true,entindex=number(safe(unit.entindex,unit)),native_owner=number(safe(unit.GetPlayerOwnerID,unit)),
        health=number(safe(unit.GetHealth,unit)),max_health=number(safe(unit.GetMaxHealth,unit)),
        unit_name=scalar(safe(unit.GetUnitName,unit))}
    local alive,alive_known=safe(unit.IsAlive,unit)
    result.alive,result.alive_known=alive==true,alive_known
    return result
end
local function numeric_fields(source,names)
    local result={};for _,name in ipairs(names) do local value=number(source and source[name]);if value~=nil then result[name]=value end end
    return result
end
local function levels(source)
    local result={};for key,value in pairs(type(source)=='table' and source or {}) do
        if type(key)=='string' and #key<=96 and number(value) then result[key]=value end
    end;return result
end
function M.snapshot(options)
    tools();options=options or {}
    local s=assert(_G[KEY],'Start the observer explicitly first')
    local current=same_world(s)
    local result={ok=current,status=s.status,current_world=current,scope='one_engine_world_four_formal_owners',
        network_clients_verified=false,natural_death_only=true,game_time=now(),native_state=state(),
        native_game_in_progress_enum=DOTA_GAMERULES_STATE_GAME_IN_PROGRESS,native_post_game_enum=DOTA_GAMERULES_STATE_POST_GAME,
        started_game_time=s.started_game_time,event_total=s.event_total,trace_retained=math.min(s.event_total,128),
        trace_dropped=math.max(0,s.event_total-128),owners={},events={},released={},
        stopped_game_time=s.stopped_game_time,stop_reason=s.stop_reason}
    if not current then return result end
    local multiplayer=require('systems/multiplayer_player_service')
    result.participating_player_ids=sorted_ids(multiplayer.participating_player_ids())
    result.active_player_ids=sorted_ids(require('systems/player_context_service').active_player_ids())
    result.all_participants_defeated=multiplayer.all_participants_defeated()
    for id=0,3 do
        local row={player_id=id,is_defeated=multiplayer.is_defeated(id),
            is_disconnected=multiplayer.is_disconnected and multiplayer.is_disconnected(id) or false,
            buildings={},counts={},events={}}
        for key,value in pairs(s.counts[id] or {}) do row.events[key]=value end
        local list=request('BUILDING_LIST_REQUEST',{player_id=id,handles_only=true})
        for _,entry in ipairs(list and list.buildings or {}) do
            local body=actor(entry.unit);body.building_id=scalar(entry.building_id);body.player_id=number(entry.player_id)
            row.buildings[#row.buildings+1]=body
            if body.building_id then row.counts[body.building_id]=(row.counts[body.building_id] or 0)+1 end
        end
        local wall=formal_wall(id);row.wall=actor(wall)
        local workers=request('WORKER_LIST_REQUEST',{player_id=id}) or {};row.workers=#workers;row.worker_entities={}
        for _,worker in ipairs(workers) do
            local body=actor(worker.unit);body.player_id=number(worker.player_id);body.level=number(worker.level)
            row.worker_entities[#row.worker_entities+1]=body
        end
        local hero=request('HERO_SUMMON_GET_REQUEST',{player_id=id}) or {}
        row.hero=actor(hero.ok and hero.unit or nil);row.hero.hero_id=scalar(hero.hero_id)
        local builder=request('BUILDER_GET_REQUEST',{player_id=id}) or {}
        row.builder=actor(builder.ok and builder.builder or nil);row.builder.formal_ok=builder.ok==true
        row.builder.formal_player_id=number(builder.player_id);row.builder.error=scalar(builder.error)
        if row.builder.present then
            local ok,origin=pcall(function()
                local p=builder.builder:GetAbsOrigin()
                return p and number(p.x)~=nil and number(p.y)~=nil and number(p.z)~=nil
            end)
            row.builder.native_origin_valid=ok and origin==true
            local context_owner,context_known=safe(require('systems/player_context_service').owner_player_id,builder.builder,true)
            row.builder.context_owned=context_known and context_owner==id
            row.builder.formal_ownership_valid=row.builder.formal_player_id==id and row.builder.context_owned
                and (row.builder.native_owner==id or row.builder.native_owner==-1)
        end
        local wave=request('WAVE_STATE_GET_REQUEST',{player_id=id}) or {}
        row.wave=numeric_fields(wave,{'alive','alive_limit','overflow_remaining','current_wave','total_waves'})
        row.wave.status=scalar(wave.status)
        for _,key in ipairs({'player_defeated','defeat_settled','victory_settled','post_clear_frozen','game_started','overflow_active'}) do
            row.wave[key]=wave[key]==true
        end
        row.wave.defeat_reason=scalar(wave.defeat_reason)
        row.wallet=numeric_fields(request('RESOURCE_GET_REQUEST',{player_id=id}),{'wood','gold','population','max_population','debug_mode'})
        row.research_levels=levels((request('RESEARCH_STATE_GET_REQUEST',{player_id=id}) or {}).levels)
        local profile=safe(require('systems/player_profile_service').get_profile,id)
        row.profile_revision=number(profile and profile.revision)
        row.map_level=number(profile and profile.save and profile.save.gameplay_stats and profile.save.gameplay_stats.map_level)
        row.isolated_profile_matches=profile_matches(s,id)
        result.owners[#result.owners+1]=row
        if s.released[id] then result.released[#result.released+1]=id end
    end
    for index=math.max(1,s.event_total-127),s.event_total do
        local row=s.trace[(index-1)%128+1];local copied={};for key,value in pairs(row) do copied[key]=value end
        result.events[#result.events+1]=copied
    end
    if options.quiet~=true then
        print(string.format('[NATIVE_WALL_LOSS] snapshot status=%s native_state=%s events=%d active=%d all_defeated=%s',
            s.status,tostring(result.native_state),result.event_total,#result.active_player_ids,tostring(result.all_participants_defeated)))
    end
    return result
end
function M.release(id)
    tools()
    local s=assert(_G[KEY],'Start the observer explicitly first')
    assert(s.status=='running' and same_world(s),'Running current observer/world/guard/session required')
    assert(s.fixture.status=='ready' and s.scene.status=='ready','Ready fixture and scene required')
    assert(state()==DOTA_GAMERULES_STATE_GAME_IN_PROGRESS,'Native GAME_IN_PROGRESS required')
    assert(type(id)=='number' and id==math.floor(id) and id>=0 and id<=3,'Owner 0..3 required')
    if s.released[id] then return {ok=false,error='wall_already_released',player_id=id} end
    assert(four_roster(),'Participant roster changed')
    for owner=0,3 do assert(profile_matches(s,owner),'Current full isolated profile mismatch for owner '..owner) end
    assert(not require('systems/multiplayer_player_service').is_defeated(id),'Selected owner already defeated')
    local multiplayer=require('systems/multiplayer_player_service')
    assert(not multiplayer.is_disconnected or not multiplayer.is_disconnected(id),'Selected owner disconnected')
    local wall,reason=formal_wall(id);assert(wall,reason);assert(wall==s.walls[id],'Selected formal wall was replaced')
    local modifier,why=floor_for(s,wall);assert(modifier,why)
    local entindex=wall:entindex()
    -- All validation completes before either protection is modified. Do not
    -- call generic RemoveModifierByName: preserve unrelated/live modifiers.
    s.guard.wall_targets[wall]=nil
    s.scene.wall_survival[wall]=nil
    local ok,failure=pcall(function() modifier:SetStackCount(0);modifier:Destroy() end)
    if not ok then
        s.status='release_failed'
        print('[NATIVE_WALL_LOSS] release_failed owner='..id..' protection_partial=true reload_map_required=true')
        return {ok=false,error='exact_test_modifier_release_failed',protection_partial=true,reload_map_required=true,player_id=id,entindex=entindex}
    end
    s.released[id]=true
    bus().emit(events().PERMANENT_REWARD_EFFECTS_CHANGED,{player_id=id,changed_section='wall',reason='tools_wall_protection_released'})
    print('[NATIVE_WALL_LOSS] released owner='..id..' entindex='..entindex..' wait_for_native_damage=1 direct_health_or_death_edits=0')
    return {ok=true,player_id=id,entindex=entindex,wait_for_native_damage=true,natural_death_only=true}
end
function M.stop(reason)
    local s=_G[KEY]
    if not s then return false end
    for _,subscription in ipairs(s.subscriptions or {}) do bus().unsubscribe(subscription) end
    s.subscriptions={}
    s.stopped_game_time=now();s.stop_reason=scalar(reason) or 'explicit_stop'
    if s.status=='running' or s.status=='validating' then s.status='stopped' end
    return true
end
return M
