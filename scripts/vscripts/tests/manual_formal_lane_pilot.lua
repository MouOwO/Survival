-- Inert Tools single formal birth; only prepare({enabled=true}) opens admission.
-- Native read-only loader proof is reused; no raw unit adoption or fake events.
local M={}
local KEY='SURVIVAL_FORMAL_LANE_PILOT'
local function scope(s)
    local ok,result=pcall(function()
        local setup=require('systems/match_setup_service')
        return s and _G[KEY]==s and not s.stopped and IsServer() and IsInToolsMode()
            and GetMapName()=='template_map' and GameRules:State_Get()==DOTA_GAMERULES_STATE_GAME_IN_PROGRESS
            and GameRules:GetGameModeEntity()==s.world and _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION==s.guard
            and s.guard.mode==s.world and _G.SURVIVAL_FOUR_PLAYER_LIVE_PERF==s.fixture
            and s.fixture.mode==s.world and s.fixture.guard==s.guard and s.fixture.status=='ready'
            and s.fixture.write_isolated==true and setup.get_mode()==s.match_mode and setup.get_session_id()==s.session
            and s.bus==require('core/event_bus') and s.bus.get_generation()==s.generation
    end)
    return ok and result==true
end
local function same(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~='table' then return a==b end
    for k,v in pairs(a) do if not same(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
local function owners(s)
    local profiles=require('systems/player_profile_service')
    local context=require('systems/player_context_service')
    local events=require('core/events');local ids=context.active_player_ids();local set={}
    assert(#ids==4 and #s.fixture.ids==4,'four_owner_required')
    for _,id in ipairs(ids) do set[id]=true end
    for index=1,4 do
        local id=index-1;local expected=s.fixture.memory_profiles[id];local profile=profiles.get_profile(id)
        assert(set[id] and s.fixture.ids[index]==id and PlayerResource:IsValidPlayerID(id)
            and PlayerResource:GetPlayer(id) and PlayerResource:GetTeam(id)==DOTA_TEAM_GOODGUYS,'native_owner_changed')
        assert(expected and profile and expected.account_id==profile.account_id and expected.revision==profile.revision
            and expected.save and profile.save and same(expected.save.gameplay_stats,profile.save.gameplay_stats),'isolated_profile_changed')
        local rows=s.bus.request(events.BUILDING_LIST_REQUEST,{player_id=id}) or {};local found=false
        for _,row in ipairs(rows.buildings or rows) do
            local u=row.unit
            if row.building_id=='wall' and row.constructing~=true and tonumber(row.player_id)==id
                and u and not u:IsNull() and u:IsAlive() and context.is_owned_by(id,u) then
                local native=u:GetPlayerOwnerID();found=native==id or native==-1
            end
        end
        assert(found,'completed_wall_changed')
    end
end
function M.authorize(ticket)
    local s=_G[KEY]
    if not s or s.ticket~=ticket or not s.precache_proven or not scope(s) then return false end
    return pcall(owners,s)
end
function M.selection(ticket)
    if not M.authorize(ticket) then return nil end
    local s=_G[KEY]
    return {variant=s.variant,player_id=s.player_id,archetype_id='humanoid_white_melee',
        unit_name=s.unit_name,class_name=s.class_name}
end
function M.prepare(options)
    if not options or options.enabled~=true then return {ok=false,error='explicit_enable_required',enabled=false} end
    local wave=require('systems/wave_system')
    if type(wave._tools_start_formal_lane)~='function' or type(wave._tools_stop_formal_lane)~='function'
        or type(wave._tools_formal_lane_snapshot)~='function' then return {ok=false,error='fresh_map_wave_exports_required'} end
    local previous=_G[KEY]
    if previous and not previous.stopped then return {ok=false,error='stop_previous_formal_pilot_first'} end
    if previous and previous.last_report and not previous.last_report.unit_removed then
        return {ok=false,error='previous_formal_unit_not_removed'}
    end
    local id=options.player_id or 0
    if type(id)~='number' or id~=math.floor(id) or id<0 or id>3 then return {ok=false,error='owner_invalid'} end
    if options.variant~=nil and options.variant~='lane' and options.variant~='control' then return {ok=false,error='variant_invalid'} end
    local lifetime=options.lifetime_seconds or 30
    if type(lifetime)~='number' or lifetime~=lifetime or lifetime<1 or lifetime>60 then return {ok=false,error='lifetime_invalid'} end
    local loader=require('tests/manual_native_lane_pilot')
    local prepared=loader.prepare({enabled=true,variant=options.variant or 'lane',archetype_id='humanoid_white_melee'})
    if not prepared.ok then return prepared end
    local setup=require('systems/match_setup_service');local bus=require('core/event_bus')
    local s={ticket={},world=GameRules:GetGameModeEntity(),guard=_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION,
        fixture=_G.SURVIVAL_FOUR_PLAYER_LIVE_PERF,match_mode=setup.get_mode(),session=setup.get_session_id(),
        bus=bus,generation=bus.get_generation(),loader_state=_G.SURVIVAL_NATIVE_LANE_PILOT,loader=loader,
        variant=options.variant or 'lane',player_id=id,status='preparing',used=0,lifetime=lifetime}
    s.unit_name=s.variant=='lane' and 'npc_survival_tools_lane_humanoid_white_melee' or 'npc_survival_wave_named_humanoid_white_melee'
    s.class_name=s.variant=='lane' and 'npc_dota_creep_lane' or 'npc_dota_creature'
    _G[KEY]=s
    if not scope(s) then loader.stop();s.stopped=true;return {ok=false,error='isolated_write_guard_required'} end
    return M.snapshot()
end
local function prove_preload(s)
    if s.precache_proven then return true end
    if _G.SURVIVAL_NATIVE_LANE_PILOT~=s.loader_state or not scope(s) then return false end
    local result=s.loader.snapshot()
    if result.precache_ready and result.enabled and result.budget_used==0 and result.unit_name==s.unit_name then
        s.precache_proven=true;s.status='ready'
        -- Stop this exact idle loader, preserving the engine's completed cache;
        -- no raw actor is ever created or handed to the formal transaction.
        s.loader.stop()
        return true
    end
    return false
end
function M.spawn(options)
    if not options or options.enabled~=true then return {ok=false,error='explicit_enable_required'} end
    local s=_G[KEY]
    if not s or not scope(s) then return {ok=false,error='formal_scope_changed'} end
    if s.used~=0 then return {ok=false,error='one_formal_birth_budget_exhausted'} end
    if not prove_preload(s) then return {ok=false,error='formal_precache_not_ready'} end
    if not M.authorize(s.ticket) then return {ok=false,error='formal_owner_or_profile_changed'} end
    s.used=1;s.status='spawning'
    local ok,result=pcall(require('systems/wave_system')._tools_start_formal_lane,s.ticket)
    if not ok then
        result=require('systems/wave_system')._tools_stop_formal_lane(s.ticket)
        result.ok=false;result.error='formal_transaction_api_failed'
    end
    if not result.ok then
        local absent=require('systems/wave_system')._tools_formal_lane_snapshot(s.ticket)
        if absent.error=='formal_lane_ticket_unknown' then result.unit_removed=true;result.no_birth_admitted=true end
    end
    s.last_report=result;s.status=result.ok and 'spawned' or 'failed'
    if not result.ok then s.stopped=true end
    if result.ok then
        s.timeout_task='formal_lane_pilot_timeout:'..tostring(s.ticket)
        require('core/scheduler').after(s.lifetime,function()
            if _G[KEY]==s then M.stop() end
        end,s.timeout_task)
    end
    return result
end
function M.snapshot()
    local s=_G[KEY]
    if not s then return {ok=true,enabled=false,formal_registration=false} end
    if scope(s) then prove_preload(s) end
    local report
    if s.used==1 then report=require('systems/wave_system')._tools_formal_lane_snapshot(s.ticket) end
    if report and report.ok then s.last_report=report else report=s.last_report end
    return {ok=s.status~='failed',enabled=scope(s),status=s.status,precache_ready=s.precache_proven==true,
        budget_used=s.used,unit_budget=1,variant=s.variant,player_id=s.player_id,unit_name=s.unit_name,
        report=report,formal_rewards_verified=false,DPS_verified=false,FPS_gain_verified=false,persistent_write=false}
end
function M.stop()
    local s=_G[KEY]
    if not s then return M.snapshot() end
    if s.timeout_task then require('core/scheduler').cancel(s.timeout_task) end
    if s.used==1 then
        local report=require('systems/wave_system')._tools_stop_formal_lane(s.ticket)
        if report.ok then s.last_report=report end
    elseif _G.SURVIVAL_NATIVE_LANE_PILOT==s.loader_state then s.loader.stop() end
    s.stopped=true;s.status='stopped'
    return M.snapshot()
end
return M
