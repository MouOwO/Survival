-- Inert Tools-only correctness probe. No raw actor, orders, damage setters,
-- invented engine events or persistent writes. The caller prepares the pilot.
local M = {}
local KEY = 'SURVIVAL_FORMAL_LANE_COMBAT_PROBE'
local OBS_KEY = 'SURVIVAL_ROOT_FORMAL_LANE_OBSERVATION'
local OBS_MOD = 'modifier_native_formal_lane_observer'
local serial = 0
local function finite(n) return type(n)=='number' and n==n and math.abs(n)<math.huge end
local function copy(t)
    if type(t)~='table' then return t end
    local r={};for k,v in pairs(t) do r[k]=copy(v) end;return r
end
local function valid(u)
    local ok,v=pcall(function() return u and not u:IsNull() end)
    return ok and v==true
end
local function live(u)
    local ok,v=pcall(function() return valid(u) and u:IsAlive() end)
    return ok and v==true
end
local function now() return GameRules:GetGameTime() end
local function read_number(u,method)
    if not valid(u) or type(u[method])~='function' then return nil end
    local ok,v=pcall(u[method],u);if ok and finite(v) then return v end
end
local function identity(s)
    local ok,v=pcall(function()
        local setup=require('systems/match_setup_service')
        return _G[KEY]==s and not s.stopped and IsServer() and IsInToolsMode()
            and GetMapName()=='template_map' and GameRules:State_Get()==DOTA_GAMERULES_STATE_GAME_IN_PROGRESS
            and GameRules:GetGameModeEntity()==s.world
            and _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION==s.guard and s.guard.mode==s.world
            and _G.SURVIVAL_FOUR_PLAYER_LIVE_PERF==s.fixture and s.fixture.guard==s.guard
            and s.fixture.mode==s.world and s.fixture.write_isolated==true and s.fixture.status=='ready'
            and _G.SURVIVAL_FORMAL_LANE_PILOT==s.pilot_state and s.pilot_state.ticket==s.ticket
            and s.pilot_state.stopped~=true and s.pilot_state.used==1
            and setup.get_session_id()==s.session and setup.get_mode()==s.match_mode
            and s.bus==require('core/event_bus') and s.bus.get_generation()==s.generation
    end)
    return ok and v==true
end
local function authorized(s)
    return identity(s) and s.pilot.authorize(s.ticket)==true
end
local function exact_actor(s)
    local ok,v=pcall(function()
        return valid(s.unit) and EntIndexToHScript(s.entindex)==s.unit
            and s.unit:entindex()==s.entindex and s.unit.survival_formal_lane_pilot_token==s.ticket
            and s.unit.survival_player_id==s.owner and s.unit.survival_is_wave_monster==true
            and s.unit.survival_monster_role=='normal' and s.unit:GetTeamNumber()==DOTA_TEAM_BADGUYS
    end)
    return ok and v==true
end
local function canonical(s)
    local r=s.bus.request(s.events.HERO_SUMMON_GET_REQUEST,{player_id=s.owner})
    assert(r and r.ok==true and live(r.unit),'canonical_hero_unavailable')
    local u=r.unit;local context=require('systems/player_context_service')
    assert(EntIndexToHScript(u:entindex())==u and u:IsRealHero() and not u:IsIllusion()
        and (not u.IsClone or not u:IsClone()) and u.survival_player_id==s.owner
        and u:GetPlayerOwnerID()==s.owner and u:GetTeamNumber()==DOTA_TEAM_GOODGUYS
        and context.owner_player_id(u,true)==s.owner and context.is_owned_by(s.owner,u),
        'canonical_hero_owner_mismatch')
    assert(type(u.PerformAttack)=='function','native_PerformAttack_missing')
    return u
end
local function wallets(s)
    local rows={}
    for id=0,3 do
        local r=s.bus.request(s.events.RESOURCE_GET_REQUEST,{player_id=id})
        assert(r and r.ok~=false and r.player_id==id and finite(r.wood) and finite(r.gold)
            and finite(r.population) and finite(r.max_population),'formal_wallet_unavailable')
        rows[#rows+1]={player_id=id,wood=r.wood,gold=r.gold,population=r.population,
            max_population=r.max_population,version=finite(r.version) and r.version or nil}
    end
    return rows
end
local function formal(s)
    local snap=s.pilot.snapshot()
    assert(type(snap.report)=='table' and snap.report.ok==true and snap.report.entindex==s.entindex
        and snap.report.player_id==s.owner and snap.report.variant==s.variant,'formal_report_identity_changed')
    return copy(snap.report)
end
local function observation(s)
    local o=s.observation
    return {counts=copy(o and o.counts or {}),events=copy(o and o.events or {}),
        event_samples_limit=32,event_samples_are_prefix=true,
        target_entindex=exact_actor(s) and (function()
            local ok,u=pcall(s.unit.GetAttackTarget,s.unit)
            if ok and valid(u) then local ok2,id=pcall(u.entindex,u);if ok2 and finite(id) then return id end end
        end)() or nil}
end
local function error_code(err)
    for _,code in ipairs({'canonical_hero_unavailable','canonical_hero_owner_mismatch','native_PerformAttack_missing',
        'formal_wallet_unavailable','formal_report_identity_changed'}) do
        if tostring(err):find(code,1,true) then return code end
    end
    return 'probe_api_failed'
end
local function cleanup(s)
    for _,key in ipairs(s.tasks or {}) do s.scheduler.cancel(key) end
    s.report.cleanup.tasks_cancelled=true
    if s.damage_subscription then s.bus.unsubscribe(s.damage_subscription);s.damage_subscription=nil end
    s.report.cleanup.damage_subscription_removed=true
    local o=s.observation;if o then o.active=false end
    if o and valid(o.observer) then
        local ok,owned=pcall(function()
            return GameRules:GetGameModeEntity()==s.world and EntIndexToHScript(s.entindex)==s.unit
                and o.observer:GetParent()==s.unit and o.observer.survival_root_token==o.token
        end)
        if ok and owned then
            s.report.cleanup.observer_destroy_requested=pcall(o.observer.Destroy,o.observer)
        else s.report.cleanup.observer_destroy_refused=true end
    else s.report.cleanup.observer_already_removed=true end
    if _G[OBS_KEY]==o then _G[OBS_KEY]=s.previous_observation;s.report.cleanup.observation_slot_restored=true
    else s.report.cleanup.observation_slot_restored=false end
    -- stop() resolves its current global pilot. Call it only for our exact
    -- original state/ticket/world, never for a replacement run.
    if s.spawn_attempted and _G.SURVIVAL_FORMAL_LANE_PILOT==s.pilot_state
        and s.pilot_state.ticket==s.ticket and GameRules:GetGameModeEntity()==s.world then
        local ok,result=pcall(s.pilot.stop)
        if ok and result then
            s.report.after_stop=copy(result.report)
            s.report.cleanup.pilot_stop_called=true
            s.report.cleanup.own_unit_removed=result.report and result.report.unit_removed==true or false
            s.report.cleanup.baseline_restored=result.report and result.report.restored_baseline==true or false
        else s.report.cleanup.pilot_stop_failed=true end
    elseif s.spawn_attempted then s.report.cleanup.pilot_stop_refused=true end
end
local function finish(s,reason)
    if s.stopped then return end
    s.report.observation=observation(s)
    s.report.finished_at=now();s.report.reason=reason
    s.report.status=reason=='completed' and 'completed' or 'failed'
    s.report.passed=reason=='completed'
    s.stopped=true
    cleanup(s)
    -- A successful death test must also remove only its own actor/diagnostic.
    if s.report.passed and (not s.report.cleanup.own_unit_removed
        or s.report.cleanup.observer_destroy_refused or s.report.cleanup.pilot_stop_failed) then
        s.report.passed=false;s.report.status='failed';s.report.reason='exact_cleanup_not_confirmed'
    end
end
local function resolved(s,p)
    if not authorized(s) or not exact_actor(s) or type(p)~='table' then return end
    local direction
    if p.attacker_entindex==s.entindex then direction='actor_outgoing'
    elseif p.victim_entindex==s.entindex and s.command_hero_entindex==p.attacker_entindex
        and EntIndexToHScript(p.attacker_entindex)==s.command_hero then direction='command_hero_to_actor' end
    if not direction then return end
    if not finite(p.engine_damage) or not finite(p.final_damage) or p.final_damage<0 then
        s.report.resolved.rejected_nonfinite=s.report.resolved.rejected_nonfinite+1;return
    end
    local r=s.report.resolved;r.counts[direction]=r.counts[direction]+1
    if direction=='actor_outgoing' and p.victim_entindex==s.expected_wall_entindex then
        r.expected_wall_resolutions=r.expected_wall_resolutions+1
    end
    r.final_damage_sum[direction]=r.final_damage_sum[direction]+p.final_damage
    if #r.events<64 then r.events[#r.events+1]={direction=direction,time=now(),
        attacker_entindex=p.attacker_entindex,victim_entindex=p.victim_entindex,
        engine_damage=p.engine_damage,final_damage=p.final_damage,
        transaction_id=type(p.transaction_id)=='number' and p.transaction_id or nil} end
end
local function settle(s)
    if not authorized(s) then finish(s,'scope_or_profile_changed');return end
    local ok,err=pcall(function()
        s.report.before_stop=formal(s);s.report.wallet_after=wallets(s)
        local r=s.report.before_stop
        s.report.death_pipeline={natural_deaths=r.natural_deaths,formal_registration=r.formal_registration,
            native_actor_alive=exact_actor(s) and live(s.unit) or false,population=copy(r.population),
            resource_session=copy(r.resource_session),killed=r.killed,pending=r.pending,alive=r.alive}
        local empty=true
        for _,row in ipairs(r.population or {}) do if row.alive~=0 then empty=false end end
        s.report.death_pipeline.passed=s.report.command.calls==1 and s.report.command.returned==true
            and r.natural_deaths==1 and r.formal_registration==false and empty and r.alive==0 and r.pending==0
            and r.killed==1 and r.resource_session and r.resource_session.alive==0
            and r.resource_session.pending==0 and r.resource_session.generation_completed==true
            and r.resource_session.released==true
        local c=s.observation.counts
        local landed_on_wall=false
        for _,event in ipairs(s.observation.events) do
            if event.event=='land' and event.target==s.expected_wall_entindex then landed_on_wall=true end
        end
        s.report.expected_wall_entindex=s.expected_wall_entindex
        s.report.expected_wall_landed_sample=landed_on_wall
        s.report.natural_attack_observed=(c.record or 0)>0 and (c.launch or 0)>0 and (c.land or 0)>0
            and s.report.resolved.expected_wall_resolutions>0 and landed_on_wall
    end)
    if not ok then finish(s,error_code(err));return end
    finish(s,s.report.death_pipeline.passed and s.report.natural_attack_observed and 'completed'
        or (not s.report.death_pipeline.passed and 'single_native_attack_did_not_prove_death' or 'natural_attack_not_observed'))
end
local function attack_once(s)
    if not authorized(s) then finish(s,'scope_or_profile_changed');return end
    local ok,err=pcall(function()
        local r=formal(s);s.report.before_command=r;s.report.observation_before_command=observation(s)
        assert(r.formal_registration and r.committed and exact_actor(s) and live(s.unit),'exact_living_actor_required')
        if _G[OBS_KEY]~=s.observation or not valid(s.observation.observer)
            or s.observation.observer.survival_root_token~=s.observation.token then
            error('exact_observer_changed')
        end
        local hero=canonical(s) -- Query the current formal hero, never a cached old hero.
        s.command_hero=hero;s.command_hero_entindex=hero:entindex()
        local c=s.report.command;c.hero_entindex=s.command_hero_entindex;c.actor_entindex=s.entindex
        c.time=now();c.actor_health_before=read_number(s.unit,'GetHealth')
        c.hero_damage_min=read_number(hero,'GetBaseDamageMin');c.hero_damage_max=read_number(hero,'GetBaseDamageMax')
        c.calls=c.calls+1;c.native_PerformAttack=true
        -- Real native basic hit, no projectile delay, no fake hit, no extra
        -- orb/proc request. This explicitly skips cooldown for one death-chain
        -- check; it is not a sample of the hero's normal attack cadence.
        hero:PerformAttack(s.unit,false,false,true,true,false,false,true)
        c.returned=true;c.actor_health_after=read_number(s.unit,'GetHealth')
        c.actor_alive_after=exact_actor(s) and live(s.unit) or false
    end)
    if not ok then
        local reason=tostring(err):find('exact_living_actor_required',1,true) and 'exact_living_actor_required'
            or tostring(err):find('exact_observer_changed',1,true) and 'exact_observer_changed' or error_code(err)
        finish(s,reason);return
    end
    local key=s.task_prefix..':settle';s.tasks[#s.tasks+1]=key
    s.scheduler.after(s.settle_seconds,function() if _G[KEY]==s and not s.stopped then settle(s) end end,key)
end
function M.start(options)
    if not options or options.enabled~=true then return {ok=false,error='explicit_enable_required',enabled=false} end
    local previous=_G[KEY];if previous and not previous.stopped then return {ok=false,error='stop_exact_previous_probe_first'} end
    local old_observation=_G[OBS_KEY]
    if old_observation and old_observation.active then return {ok=false,error='stop_exact_previous_observer_first'} end
    local delay,wait=options.kill_after_seconds or 30,options.settle_seconds or 2
    if not finite(delay) or delay<5 or delay>40 or not finite(wait) or wait<1 or wait>5 then
        return {ok=false,error='bounded_delay_required'}
    end
    local pilot=require('tests/manual_formal_lane_pilot');local ps=_G.SURVIVAL_FORMAL_LANE_PILOT
    if not ps or ps.stopped or ps.used~=0 or ps.precache_proven~=true or ps.status~='ready'
        or not finite(ps.lifetime) or delay+wait+3>=ps.lifetime or pilot.authorize(ps.ticket)~=true then
        return {ok=false,error='already_prepared_ready_unused_pilot_with_time_budget_required'}
    end
    local bus=require('core/event_bus');local setup=require('systems/match_setup_service')
    local s={pilot=pilot,pilot_state=ps,ticket=ps.ticket,world=ps.world,guard=ps.guard,fixture=ps.fixture,
        owner=ps.player_id,variant=ps.variant,bus=bus,generation=bus.get_generation(),
        events=require('core/events'),session=setup.get_session_id(),match_mode=setup.get_mode(),
        scheduler=require('core/scheduler'),tasks={},previous_observation=old_observation,settle_seconds=wait}
    serial=serial+1;s.task_prefix='formal_lane_combat_probe:'..serial..':'..tostring(s)
    s.report={status='starting',passed=false,owner=s.owner,variant=s.variant,started_at=now(),
        kill_after_seconds=delay,settle_seconds=wait,clock='GameRules:GetGameTime',
        scope='one_tools_formal_actor_four_engine_owners',network_clients_verified=false,
        command={calls=0,native_PerformAttack=false,normal_attack_cadence_tested=false,
            use_cast_attack_orb=false,process_procs=false,skip_cooldown=true,ignore_invisibility=true,
            use_projectile=false,fake_attack=false,never_miss=true},
        resolved={event_name=require('combat/combat_events').DAMAGE_RESOLVED,
            semantics='final_filter_amount_before_native_HP_change_not_post_hit_health',
            counts={actor_outgoing=0,command_hero_to_actor=0},final_damage_sum={actor_outgoing=0,command_hero_to_actor=0},
            rejected_nonfinite=0,expected_wall_resolutions=0,events={},events_limit=64},cleanup={},
        wallet_delta_is_not_attributed_to_kill=true,formal_reward_profile='none_for_ordinary_wave_1',
        reward_grant_verified=false,persistent_write=false,FPS_gain_verified=false}
    _G[KEY]=s
    local ok,err=pcall(function()
        canonical(s);s.report.wallet_before=wallets(s)
        s.spawn_attempted=true;local birth=pilot.spawn({enabled=true})
        assert(birth and birth.ok and birth.committed and birth.formal_registration,'formal_birth_failed')
        s.entindex=birth.entindex;s.unit=EntIndexToHScript(s.entindex);s.report.birth=copy(birth)
        s.expected_wall_entindex=birth.native and birth.native.wall_entindex
        assert(authorized(s) and exact_actor(s) and live(s.unit),'exact_formal_actor_identity_failed')
        assert(finite(s.expected_wall_entindex) and birth.native.wall_AI==true,'formal_wall_AI_missing')
        assert(not s.unit:FindModifierByName(OBS_MOD),'unexpected_existing_observer')
        assert(_G[OBS_KEY]==old_observation,'observation_slot_changed_during_birth')
        local o={active=true,unit=s.unit,world=s.world,guard=s.guard,token={},started=now(),counts={},events={}}
        s.observation=o;_G[OBS_KEY]=o
        LinkLuaModifier(OBS_MOD,'tests/'..OBS_MOD,LUA_MODIFIER_MOTION_NONE)
        o.observer=s.unit:AddNewModifier(s.unit,nil,OBS_MOD,{})
        assert(valid(o.observer) and o.observer:GetParent()==s.unit,'native_observer_attach_failed')
        o.observer.survival_root_token=o.token
        s.damage_subscription=bus.subscribe(require('combat/combat_events').DAMAGE_RESOLVED,function(p) resolved(s,p) end)
        s.report.status='observing';s.report.entindex=s.entindex
        local key=s.task_prefix..':attack';s.tasks[#s.tasks+1]=key
        s.scheduler.after(delay,function() if _G[KEY]==s and not s.stopped then attack_once(s) end end,key)
        key=s.task_prefix..':watchdog';s.tasks[#s.tasks+1]=key
        s.scheduler.after(delay+wait+1,function()
            if _G[KEY]==s and not s.stopped then finish(s,'probe_watchdog') end
        end,key)
    end)
    if not ok then
        local reason='probe_start_failed'
        for _,code in ipairs({'formal_birth_failed','exact_formal_actor_identity_failed',
            'formal_wall_AI_missing','unexpected_existing_observer','native_observer_attach_failed',
            'observation_slot_changed_during_birth'}) do
            if tostring(err):find(code,1,true) then reason=code end
        end
        if reason=='probe_start_failed' then reason=error_code(err) end
        finish(s,reason)
    end
    return M.snapshot()
end
function M.snapshot()
    local s=_G[KEY]
    if not s then return {ok=true,enabled=false,status='not_started'} end
    local r=copy(s.report)
    if not s.stopped then r.observation=observation(s) end
    return {ok=r.status~='failed',enabled=not s.stopped and authorized(s),status=r.status,report=r}
end
function M.stop()
    local s=_G[KEY];if s and not s.stopped then finish(s,'stopped_by_caller') end
    return M.snapshot()
end
return M
