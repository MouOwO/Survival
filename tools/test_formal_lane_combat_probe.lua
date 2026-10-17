-- Real formal wave/pilot, event bus and root observer. Native APIs simulated;
-- no native-game death, attack cadence, rewards or FPS result is claimed.
package.path='scripts/vscripts/?.lua;'..package.path
local bus,events=require('core/event_bus'),require('core/events')
local pilot=require('tests/manual_formal_lane_pilot')
local probe=require('tests/manual_formal_lane_combat_probe')
check_probe_inert = _G.SURVIVAL_FORMAL_LANE_COMBAT_PROBE==nil and not probe.start().ok
assert(_G.SURVIVAL_FORMAL_LANE_PILOT==nil and not pilot.prepare().ok and not pilot.spawn().ok)
local checks=3
assert(check_probe_inert)
local function check(v,m) checks=checks+1;assert(v,m) end
local function copy(t) if type(t)~='table' then return t end local r={};for k,v in pairs(t) do r[k]=copy(v) end;return r end
local noop=function() end
local mode,time,session={},0,'formal_lane_test_session'
local tasks,precache,units,by_id,walls,profiles={}, {},{}, {},{},{}
local guard,fixture,game_state,client,tools_mode
local heroes,attack_calls,observer_destroyed={},0,0
local combat_events=require('combat/combat_events')
class=function(t) t.__index=t;return t end
LUA_MODIFIER_MOTION_NONE=0
LinkLuaModifier=function(name,path,motion) assert(name=='modifier_native_formal_lane_observer' and path=='tests/'..name and motion==0);require(path) end
local death_visuals,cleanups,spawns,clears,boss_rewards,winners=0,0,0,0,0,0
local flags={}
DOTA_GAMERULES_STATE_GAME_IN_PROGRESS=10;DOTA_GAMERULES_STATE_POST_GAME=11
DOTA_TEAM_GOODGUYS=2;DOTA_TEAM_BADGUYS=3
DOTA_UNIT_CAP_MOVE_GROUND=1;DOTA_UNIT_CAP_MELEE_ATTACK=1;DOTA_UNIT_CAP_RANGED_ATTACK=2
Vector=function(x,y,z) return {x=x,y=y,z=z} end
IsServer=function() return not client end;IsInToolsMode=function() return tools_mode end;GetMapName=function() return 'template_map' end
GameRules={GetGameModeEntity=function() return mode end,GetGameTime=function() return time end,
    State_Get=function() return game_state end,SetGameWinner=function() winners=winners+1 end}
local maximum={GetMaximumAttackSpeed=function() return 7 end};setmetatable(mode,{__index=maximum})
PlayerResource={IsValidPlayerID=function(_,id) return id>=0 and id<=3 end,GetPlayer=function(_,id) return {id=id} end,
    GetTeam=function() return 2 end,IsFakeClient=function() return true end}
local manifest=require('config/generated/native_lane_pilot_manifest')
local kv={}
for _,r in ipairs(manifest.rows) do kv[r.source_unit_name]=copy(r.source_fields);kv[r.alias_unit_name]=copy(r.source_fields);kv[r.alias_unit_name].BaseClass='npc_dota_creep_lane' end
LoadKeyValues=function(name) return name=='scripts/npc/npc_units_custom.txt' and kv or {} end
PrecacheUnitByNameAsync=function(name,callback,owner) check(owner==-1,'Actual native precache signature');precache[#precache+1]=callback end
package.loaded['core/logger']={info=noop,warn=noop,error=noop}
package.loaded['core/scheduler']={after=function(delay,fn,key) tasks[key or tostring(fn)]={fn=fn,at=time+delay};return key end,every=function(delay,fn,key) tasks[key]={fn=fn,at=time+delay};return key end,
    cancel=function(key) tasks[key]=nil end,task_count=function() return 0 end}
package.loaded['systems/match_setup_service']={get_mode=function() return 'standard' end,get_session_id=function() return session end,
    is_mode_selected=function() return true end,selector_player_id=function() return 0 end}
package.loaded['systems/player_profile_service']={get_profile=function(id) return profiles[id] end,get_progression=function() return {loaded=true} end}
package.loaded['systems/startup_loading_service']={is_gameplay_ready=function() return true end}
local slot_rows=require('config/generated/player_slots').rows
local marker_names={}
for index,row in ipairs(slot_rows) do marker_names[row.wave_spawn_marker]={x=index*1000,y=index*200,z=32} end
local function marker(name)
    return {IsNull=function() return false end,GetAbsOrigin=function() return marker_names[name] or {x=64,y=128,z=32} end,
        GetName=function() return name end,GetForwardVector=function() return {x=0,y=1,z=0} end}
end
Entities={FindByName=function(_,_,name) return marker(name) end,FindAllByClassname=function() error('No global class scan allowed') end}
EntIndexToHScript=function(id) return by_id[id] end
UTIL_Remove=function(u) u.removed=true;by_id[u.id]=nil end
GetGroundHeight=function() return 0 end;FindClearSpaceForUnit=function(u,p) u.pos=copy(p) end
ListenToGameEvent=function() return 1 end;StopListeningToGameEvent=noop
package.loaded['core/team_alignment']={enforce=function(u,team) u.team=team end}
package.loaded['systems/player_context_service']={active_player_ids=function() return {0,1,2,3} end,
    is_owned_by=function(id,u) return u.survival_player_id==id or u.owner==id end,
    owner_player_id=function(u) return u.survival_player_id or u.owner end,
    slot=function(id) return slot_rows[id+1] end,max_players=function() return 4 end}
package.loaded['systems/wall_target_service']={reset=noop,set_change_listener=noop,preferred_wall=function(id) return walls[id].id end,
    wall_indices=function() local r={};for id,u in pairs(walls) do r[id]=u.id end;return r end,
    upsert=noop,navigation_changed=noop,resolve=function(_,id) return walls[id].id,{} end}
package.loaded['systems/asset_preload_service']={queue=function() return true end,status=function() return {status='ready'} end,
    STATE={READY='ready'},remaining_ready_count=function() return 0 end}
package.loaded['config/asset_catalog']={by_id={},model_paths_for_wave=function() return {} end}
package.loaded['config/monster_visual_config']={resolve=function() return nil end}
package.loaded['systems/monster_visual_service']={apply=noop,cleanup=function() cleanups=cleanups+1 end,on_death=function() death_visuals=death_visuals+1 end,
    queue_wave=noop,model_paths=function() return {} end}
package.loaded['systems/monster_hero_visual_service']={apply=function(u,definition,options)
    check(options.fresh_unit and options.formal_wave and options.wave_number==1,'Unchanged formal appearance path')
    if flags.appearance_throw then error('optional appearance error') end
end,on_death=function() death_visuals=death_visuals+1 end,clear=function() cleanups=cleanups+1 end}
package.loaded['systems/monster_corpse_lifecycle_service']={track=function(u) u.survival_monster_corpse=true end}
package.loaded['systems/archive_challenge_service']={begin=noop}
package.loaded['systems/multiplayer_player_service']={all_participants_defeated=function() return false end}
local next_unit_id=100
local function unit(name,p)
    next_unit_id=next_unit_id+1
    local u={id=next_unit_id,name=name,pos=copy(p),team=3,alive=true,hull=32,mods={},stats={}}
    by_id[u.id]=u;units[#units+1]=u
    function u:IsNull() return self.removed==true end;function u:IsAlive() return self.alive end;function u:entindex() return self.id end
    function u:GetUnitName() return self.name end;function u:GetClassname() return flags.class_wrong and 'npc_dota_hero' or (self.name:find('tools_lane',1,true) and 'npc_dota_creep_lane' or 'npc_dota_creature') end
    function u:IsRealHero() return false end;function u:GetTeamNumber() return self.team end
    function u:GetAttackTarget() local ai=self.mods.modifier_enemy_wall_ai;return ai and by_id[ai.wall_entindex] end
    function u:GetAbsOrigin() return self.pos end;function u:GetHullRadius() return self.hull end;function u:SetHullRadius(v) self.hull=v end
    function u:GetHealth() return self.stats.hp end;function u:GetMaxHealth() return self.stats.max end
    function u:GetBaseDamageMin() return self.stats.min end;function u:GetBaseDamageMax() return self.stats.maxd end
    function u:GetModelName() return self.stats.model end;function u:GetAttackCapability() return self.stats.cap end
    function u:SetBaseMaxHealth(v) self.stats.base_max=v end;function u:SetMaxHealth(v) self.stats.max=v end;function u:SetHealth(v) self.stats.hp=v end
    function u:SetBaseDamageMin(v) self.stats.min=v end;function u:SetBaseDamageMax(v) self.stats.maxd=v end
    function u:SetPhysicalArmorBaseValue(v) self.stats.armor=v end;function u:SetBaseMoveSpeed(v) self.stats.speed=v end
    function u:SetBaseAttackTime(v) self.stats.BAT=v end;function u:SetAttackCapability(v) self.stats.cap=v end
    function u:SetMoveCapability(v) self.stats.move=v end;function u:SetModelScale(v) self.stats.scale=v end
    function u:SetModel(v) self.stats.model=v end;function u:SetOriginalModel(v) self.stats.original=v end
    function u:FindAbilityByName() return nil end;function u:AddAbility() error('No new skills on ordinary source') end
    function u:HasModifier(name) return self.mods[name]~=nil end
    function u:FindModifierByName(name) return self.mods[name] end
    function u:AddNewModifier(_,_,name,params)
        if flags.stat_throw and name=='modifier_debug_attack_cap' then error('native modifier failed') end
        if flags.observer_attach_fail and name=='modifier_native_formal_lane_observer' then return nil end
        local m=copy(params or {});m.parent=self
        if name=='modifier_native_formal_lane_observer' then setmetatable(m,modifier_native_formal_lane_observer) end
        function m:IsNull() return self.removed==true end;function m:GetParent() return self.parent end
        function m:Destroy() assert(not self.removed);self.removed=true;self.parent.mods[name]=nil;observer_destroyed=observer_destroyed+1 end
        self.mods[name]=m;return m
    end
    return u
end
CreateUnitByName=function(name,p,clear,owner,controller,team)
    check(clear==false and owner==nil and controller==nil and team==3,'Original formal native birth signature')
    if flags.create_fail then return nil end
    return unit(name,p)
end
local wave=require('systems/wave_system')
local function reset()
    probe.stop();pilot.stop();bus.reset();tasks={};precache={};units={};by_id={};flags={};game_state=10;client=false;tools_mode=true
    guard={mode=mode};fixture={mode=mode,guard=guard,status='ready',write_isolated=true,ids={0,1,2,3},memory_profiles={}}
    walls={};profiles={};heroes={};attack_calls=0;observer_destroyed=0
    for id=0,3 do
        local u={id=40+id,owner=id};function u:IsNull() return false end;function u:IsAlive() return true end
        function u:entindex() return self.id end
        function u:GetPlayerOwnerID() return -1 end;function u:GetAbsOrigin() return {x=(id+1)*1000,y=(id+1)*200,z=32} end
        walls[id]=u;by_id[u.id]=u
        profiles[id]={account_id='isolated-'..id,revision=id+1,save={gameplay_stats={map_level=({1,9,17,24})[id+1]}}}
        fixture.memory_profiles[id]=copy(profiles[id])
    end
    _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION=guard;_G.SURVIVAL_FOUR_PLAYER_LIVE_PERF=fixture
    _G.SURVIVAL_FORMAL_LANE_PILOT=nil;_G.SURVIVAL_NATIVE_LANE_PILOT=nil
    _G.SURVIVAL_FORMAL_LANE_COMBAT_PROBE=nil;_G.SURVIVAL_ROOT_FORMAL_LANE_OBSERVATION=nil
    bus.handle_request(events.BUILDING_LIST_REQUEST,function(p) return {buildings={{building_id='wall',unit=walls[p.player_id],player_id=p.player_id}}} end)
    bus.handle_request(events.ROGUE_REWARD_OPEN_REQUEST,function() boss_rewards=boss_rewards+1 end)
    bus.subscribe(events.MONSTER_SPAWNED,function(p) spawns=spawns+1;check(p.monster_source=='wave' and p.member_role=='normal','Genuine original formal spawn payload') end)
    bus.subscribe('archive.final_wave_cleared',function() clears=clears+1 end)
    wave.init();check(wave.set_difficulty('N2'),'Real generated N2 configuration')
    wave.set_dev_mode(true)
    for id,u in pairs(walls) do bus.emit(events.BUILDING_CHANGED,{building_id='wall',player_id=id,entindex=u.id,unit=u}) end
end
local function ready(variant,id)
    local previous_units=#units
    local result=pilot.prepare({enabled=true,variant=variant,player_id=id or 0,lifetime_seconds=60})
    check(result.status=='preparing','No fake synchronous readiness')
    check(not pilot.spawn({enabled=true}).ok and #units==previous_units,'No native birth before cached callback')
    precache[#precache]();check(pilot.snapshot().precache_ready,'Actual preload completion gates formal entry')
end
local function hero(id)
    local u=unit('npc_dota_hero_fixture_'..id,{x=0,y=0,z=32})
    u.team=2;u.owner=id;u.survival_player_id=id;u.stats={hp=100000,max=100000,min=1000,maxd=1000}
    function u:IsRealHero() return true end
    function u:IsIllusion() return flags.hero_illusion==true end
    function u:IsClone() return false end
    function u:GetPlayerOwnerID() return self.owner end
    function u:PerformAttack(target,orb,procs,skip,ignore,projectile,fake,never_miss)
        attack_calls=attack_calls+1
        check(target==by_id[target.id] and target.survival_formal_lane_pilot_token~=nil,
            'Native command is directed only to exact own formal actor')
        check(orb==false and procs==false and skip==true and ignore==true and projectile==false
            and fake==false and never_miss==true,'Explicit single native death-check flags, no fake attack')
        if flags.attack_throw then error('simulated_native_PerformAttack_failed') end
        if flags.command_no_effect then return end
        local damage=flags.nonlethal and 1 or self.stats.min
        bus.emit(combat_events.DAMAGE_RESOLVED,{attacker_entindex=self.id,victim_entindex=target.id,
            engine_damage=damage,final_damage=damage,transaction_id=123})
        target.stats.hp=math.max(0,target.stats.hp-damage)
        if target.stats.hp<=0 then
            target.alive=false
            -- Simulated native adapter, not an event emitted by the new probe.
            bus.emit(events.ENGINE_ENTITY_KILLED,{victim=target,victim_entindex=target.id})
        end
    end
    heroes[id]=u;return u
end
local wallet_rows={}
local function scene(variant,owner)
    reset();time=0;wallet_rows={}
    for id=0,3 do
        hero(id);wallet_rows[id]={player_id=id,wood=1000+id*13,gold=500+id*17,
            population=26,max_population=600+id,version=1}
    end
    bus.handle_request(events.HERO_SUMMON_GET_REQUEST,function(p)
        return heroes[p.player_id] and {ok=true,unit=heroes[p.player_id]} or {ok=false}
    end)
    bus.handle_request(events.RESOURCE_GET_REQUEST,function(p)
        if flags.wallet_missing then return nil end
        return copy(wallet_rows[p.player_id])
    end)
    ready(variant or 'control',owner or 0)
end
local function current_unit() return by_id[probe.snapshot().report.entindex] end
local function task(suffix)
    for key,row in pairs(tasks) do
        if key:find('formal_lane_combat_probe:',1,true) and key:sub(-#suffix)==suffix then return key,row end
    end
    error('Expected task absent '..suffix)
end
local function run(suffix)
    local key,row=task(suffix);tasks[key]=nil;time=row.at;row.fn();return row.fn
end
local function natural(count,target)
    local u=current_unit();target=target or walls[u.survival_player_id]
    local observer=u:FindModifierByName('modifier_native_formal_lane_observer')
    for n=1,count do
        time=time+1
        local p={attacker=u,target=target,record=100+n}
        observer:OnAttackRecord(p);observer:OnAttack(p);observer:OnAttackLanded(p)
        bus.emit(combat_events.DAMAGE_RESOLVED,{attacker_entindex=u.id,victim_entindex=target.id,
            engine_damage=4,final_damage=4,transaction_id=n})
    end
end
local function no_tasks()
    for key in pairs(tasks) do check(not key:find('formal_lane_combat_probe:',1,true),'No surviving own timer') end
end

for _,variant in ipairs({'control','lane'}) do
    for owner=0,3 do
        scene(variant,owner)
        local before_count=#units;local stale={active=false,proof='prior_inactive_root_state'}
        _G.SURVIVAL_ROOT_FORMAL_LANE_OBSERVATION=stale
        local started=probe.start({enabled=true})
        check(started.ok and started.status=='observing' and #units==before_count+1,'Exactly one native formal spawn through actual pilot')
        local u=current_unit();local before=pilot.snapshot().report
        check(before.formal_registration and before.resource_session.alive==1 and before.population[owner+1].alive==1,
            'Formal population/session actually committed')
        check(not probe.start({enabled=true}).ok and #units==before_count+1,'Second concurrent start inert')
        natural(12);local initial=probe.snapshot()
        check(initial.report.observation.counts.record==12 and initial.report.observation.counts.launch==12
            and initial.report.observation.counts.land==12,'Original native observer methods count actual receiver calls')
        check(#initial.report.observation.events==32 and #initial.report.resolved.events==12,'Both diagnostic traces bounded')
        local old_alive=heroes[owner]
        -- The registered hero can be replaced normally before the one command.
        local new_hero=hero(owner)
        wallet_rows[owner].wood=wallet_rows[owner].wood+7 -- Independent income, not claimed kill bounty.
        run(':attack')
        check(attack_calls==1 and probe.snapshot().report.command.hero_entindex==new_hero.id
            and probe.snapshot().report.command.hero_entindex~=old_alive.id,'Current formal canonical hero is queried at command time')
        check(not u.alive and pilot.snapshot().report.natural_deaths==1,'Native API stub adapter reaches actual wave death handler')
        local deferred=select(2,task(':settle')).fn
        run(':settle');local result=probe.snapshot()
        check(result.ok and result.status=='completed' and result.report.passed,'Completed only after real formal counters are read')
        check(result.report.death_pipeline.passed and result.report.before_stop.natural_deaths==1
            and result.report.before_stop.killed==1 and result.report.before_stop.resource_session.released,'Pre-stop evidence retains native-death/session result')
        for _,r in ipairs(result.report.before_stop.population) do check(r.alive==0,'Four owner wave population returns to zero') end
        check(result.report.after_stop.killed==0 and result.report.after_stop.restored_baseline,'Stop restoration is separate from captured pre-stop evidence')
        check(result.report.resolved.counts.command_hero_to_actor==1 and result.report.resolved.counts.actor_outgoing==12,
            'Actual combat damage-filter event, not hero bridge, is counted')
        check(result.report.wallet_delta_is_not_attributed_to_kill and result.report.wallet_after[owner+1].wood
            ==result.report.wallet_before[owner+1].wood+7 and result.report.reward_grant_verified==false,'Independent wallet income remains honest/unattributed')
        check(result.report.command.calls==1 and result.report.command.normal_attack_cadence_tested==false,'No normal AS assertion from one PerformAttack')
        check(result.report.cleanup.own_unit_removed and result.report.cleanup.observation_slot_restored
            and _G.SURVIVAL_ROOT_FORMAL_LANE_OBSERVATION==stale and observer_destroyed==1,'Exact own observer/actor cleanup restores prior inactive slot')
        check(u.removed and wave._resource_snapshot_for_test().session_count==0,'No live actor or resource-session leak')
        deferred();probe.stop();check(attack_calls==1 and observer_destroyed==1,'Late settle/manual stop are idempotent')
        check(require('core/json_encoder').encode(result):find('final_filter_amount',1,true)~=nil,'Report is serializable with explicit pre-native-HP semantics')
        no_tasks()
    end
end

scene();local ps=_G.SURVIVAL_FORMAL_LANE_PILOT
ps.precache_proven=false;check(not probe.start({enabled=true}).ok and ps.used==0,'No birth before actual ready cache')
ps.precache_proven=true;ps.lifetime=30;check(not probe.start({enabled=true}).ok and ps.used==0,'Reject timing beyond pilot watchdog')
ps.lifetime=60;check(not probe.start({enabled=true,kill_after_seconds=100}).ok and ps.used==0,'Bounded timer rejects huge/nonfinite options')
check(not probe.start({enabled=true,kill_after_seconds=0/0}).ok and ps.used==0,'Reject NaN timer')
_G.SURVIVAL_ROOT_FORMAL_LANE_OBSERVATION={active=true}
check(not probe.start({enabled=true}).ok and ps.used==0,'Do not hijack root active observer')

scene();profiles[0].save.gameplay_stats.map_level=99
check(not probe.start({enabled=true}).ok and _G.SURVIVAL_FORMAL_LANE_PILOT.used==0,'Actual pilot profile guard rejects changed data')
scene();heroes[0]=nil
check(not probe.start({enabled=true}).ok and _G.SURVIVAL_FORMAL_LANE_PILOT.used==0,'Canonical preflight failure consumes no birth/actor')
scene();flags.wallet_missing=true
check(not probe.start({enabled=true}).ok and _G.SURVIVAL_FORMAL_LANE_PILOT.used==0,'Wallet unavailable consumes no actor and no save')
scene();flags.observer_attach_fail=true
check(not probe.start({enabled=true}).ok and pilot.snapshot().report.unit_removed,'Failed observer attach cleans only committed own transaction')
scene();local foreign={active=true,token={},foreign=true}
bus.subscribe(events.MONSTER_SPAWNED,function() _G.SURVIVAL_ROOT_FORMAL_LANE_OBSERVATION=foreign end)
local collision=probe.start({enabled=true})
check(not collision.ok and collision.report.reason=='observation_slot_changed_during_birth'
    and collision.report.cleanup.own_unit_removed and _G.SURVIVAL_ROOT_FORMAL_LANE_OBSERVATION==foreign,
    'Spawn callback changing observation slot is preserved, never hijacked')

for _,change in ipairs({'guard','session','bus','profile','world','client','tools','observer','hero_owner','hero_missing','actor_reused','actor_token','pilot_replaced'}) do
    scene();check(probe.start({enabled=true}).ok,'Negative scope case starts: '..change)
    natural(2);local u=current_unit();local old_mode=mode
    local _,pending=task(':attack');local late=pending.fn
    if change=='guard' then _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION={mode=mode}
    elseif change=='session' then session='new_session'
    elseif change=='bus' then bus.reset()
    elseif change=='profile' then profiles[2].revision=999
    elseif change=='world' then mode={}
    elseif change=='client' then client=true
    elseif change=='tools' then tools_mode=false
    elseif change=='observer' then _G.SURVIVAL_ROOT_FORMAL_LANE_OBSERVATION={active=true,foreign=true}
    elseif change=='hero_owner' then heroes[0].owner=1
    elseif change=='hero_missing' then heroes[0]=nil
    elseif change=='actor_reused' then by_id[u.id]={id=u.id,IsNull=function() return false end}
    elseif change=='actor_token' then u.survival_formal_lane_pilot_token={}
    elseif change=='pilot_replaced' then _G.SURVIVAL_FORMAL_LANE_PILOT={ticket={},stopped=false,used=0}
    end
    run(':attack');local result=probe.snapshot()
    check(not result.ok and result.status=='failed' and attack_calls==0,'Changed scope/identity never issues command: '..change)
    if change=='actor_reused' or change=='actor_token' or change=='world' then
        check(not u.removed,'Refuse removal without native pointer/token/world proof: '..change)
    end
    if change=='pilot_replaced' then
        check(not u.removed and _G.SURVIVAL_FORMAL_LANE_PILOT.used==0
            and result.report.cleanup.pilot_stop_refused,'Never stop or spend a replacement formal pilot')
        _G.SURVIVAL_FORMAL_LANE_PILOT=nil
    end
    late();check(attack_calls==0,'Queued late callback cannot perform native action: '..change)
    -- Restore only mocked world identifiers so next independent test starts cleanly.
    mode=old_mode;session='formal_lane_test_session';client=false;tools_mode=true
end

for _,flag in ipairs({'nonlethal','command_no_effect','attack_throw'}) do
    scene();probe.start({enabled=true});natural(2);flags[flag]=true
    run(':attack');if flag~='attack_throw' then run(':settle') end
    local result=probe.snapshot()
    check(not result.ok and result.report.command.calls==1 and attack_calls==1,'One unsuccessful native command never retries: '..flag)
    check(result.report.before_stop==nil or result.report.before_stop.natural_deaths==0,'No forged death proof on unsuccessful hit: '..flag)
    check(result.report.after_stop.natural_deaths==0 and result.report.cleanup.own_unit_removed,'Alive stop does not create engine death: '..flag)
    no_tasks()
end

scene();probe.start({enabled=true});natural(1);run(':watchdog')
check(not probe.snapshot().ok and attack_calls==0 and probe.snapshot().report.reason=='probe_watchdog','Own watchdog bounds an unexecuted phase without native actions')

scene();probe.start({enabled=true});local u=current_unit();local observer=u.mods.modifier_native_formal_lane_observer
observer:OnAttackRecord({attacker=heroes[1],target=walls[0],record=1})
observer:OnAttackLanded({attacker=heroes[1],target=u,record=1})
bus.emit(events.COMBAT_DAMAGE_RESOLVED,{attacker=u,victim=walls[0],actual_damage=999,final_damage=999})
bus.emit(combat_events.DAMAGE_RESOLVED,{attacker_entindex=heroes[2].id,victim_entindex=u.id,engine_damage=4,final_damage=4})
bus.emit(combat_events.DAMAGE_RESOLVED,{attacker_entindex=u.id,victim_entindex=walls[0].id,engine_damage=0/0,final_damage=math.huge})
local r=probe.snapshot().report
check((r.observation.counts.land or 0)==0 and r.resolved.counts.actor_outgoing==0
    and r.resolved.counts.command_hero_to_actor==0 and r.resolved.rejected_nonfinite==1,'Wrong receiver/hero bridge/other hero/nonfinite cannot manufacture native proof')
natural(100);r=probe.snapshot().report
check(r.observation.counts.record==100 and #r.observation.events==32 and #r.resolved.events==64,'Bounded samples do not truncate scalar event totals')
probe.stop();check(attack_calls==0 and probe.snapshot().report.before_stop==nil,'Manual stop never invents successful native death')

scene();probe.start({enabled=true});run(':attack');run(':settle')
check(not probe.snapshot().ok and probe.snapshot().report.death_pipeline.passed
    and probe.snapshot().report.reason=='natural_attack_not_observed','A successful forced single hit alone cannot prove natural AI attacks')
scene();probe.start({enabled=true});natural(2,walls[3]);run(':attack');run(':settle')
check(not probe.snapshot().ok and probe.snapshot().report.death_pipeline.passed
    and not probe.snapshot().report.expected_wall_landed_sample,'Unrelated wall land/filter events cannot prove original wall target')
scene();probe.start({enabled=true});natural(2);run(':attack');profiles[1].revision=999;run(':settle')
check(not probe.snapshot().ok and probe.snapshot().report.reason=='scope_or_profile_changed'
    and probe.snapshot().report.cleanup.own_unit_removed,'Late changed profile forbids proof yet exact own actor is cleaned')
print('PASS formal lane combat probe '..checks..' checks; simulated native APIs; no native/FPS/reward claim')
