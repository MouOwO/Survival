-- Real wave factory, event bus and generated N2 rows; only engine/services mocked.
package.path='scripts/vscripts/?.lua;'..package.path
local bus,events=require('core/event_bus'),require('core/events')
local pilot=require('tests/manual_formal_lane_pilot')
assert(_G.SURVIVAL_FORMAL_LANE_PILOT==nil and not pilot.prepare().ok and not pilot.spawn().ok)
local checks=3
local function check(v,m) checks=checks+1;assert(v,m) end
local function copy(t) if type(t)~='table' then return t end local r={};for k,v in pairs(t) do r[k]=copy(v) end;return r end
local noop=function() end
local mode,time,session={},0,'formal_lane_test_session'
local tasks,precache,units,by_id,walls,profiles={}, {},{}, {},{},{}
local guard,fixture,game_state,client,tools_mode
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
package.loaded['core/scheduler']={after=function(_,fn,key) tasks[key or tostring(fn)]=fn end,every=function(_,fn,key) tasks[key]=fn end,
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
        local m=copy(params or {});m.parent=self
        function m:IsNull() return false end;function m:GetParent() return self.parent end
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
    pilot.stop();bus.reset();tasks={};precache={};units={};by_id={};flags={};game_state=10;client=false;tools_mode=true
    guard={mode=mode};fixture={mode=mode,guard=guard,status='ready',write_isolated=true,ids={0,1,2,3},memory_profiles={}}
    walls={};profiles={}
    for id=0,3 do
        local u={id=40+id,owner=id};function u:IsNull() return false end;function u:IsAlive() return true end
        function u:GetPlayerOwnerID() return -1 end;function u:GetAbsOrigin() return {x=(id+1)*1000,y=(id+1)*200,z=32} end
        walls[id]=u;by_id[u.id]=u
        profiles[id]={account_id='isolated-'..id,revision=id+1,save={gameplay_stats={map_level=({1,9,17,24})[id+1]}}}
        fixture.memory_profiles[id]=copy(profiles[id])
    end
    _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION=guard;_G.SURVIVAL_FOUR_PLAYER_LIVE_PERF=fixture
    _G.SURVIVAL_FORMAL_LANE_PILOT=nil;_G.SURVIVAL_NATIVE_LANE_PILOT=nil
    bus.handle_request(events.BUILDING_LIST_REQUEST,function(p) return {buildings={{building_id='wall',unit=walls[p.player_id],player_id=p.player_id}}} end)
    bus.handle_request(events.ROGUE_REWARD_OPEN_REQUEST,function() boss_rewards=boss_rewards+1 end)
    bus.subscribe(events.MONSTER_SPAWNED,function(p) spawns=spawns+1;check(p.monster_source=='wave' and p.member_role=='normal','Genuine original formal spawn payload') end)
    bus.subscribe('archive.final_wave_cleared',function() clears=clears+1 end)
    wave.init();check(wave.set_difficulty('N2'),'Real generated N2 configuration')
    wave.set_dev_mode(true)
    for id,u in pairs(walls) do bus.emit(events.BUILDING_CHANGED,{building_id='wall',player_id=id,entindex=u.id,unit=u}) end
end
local function ready(variant,id)
    local result=pilot.prepare({enabled=true,variant=variant,player_id=id or 0})
    check(result.status=='preparing','No fake synchronous readiness')
    check(not pilot.spawn({enabled=true}).ok and #units==0,'No native birth before cached callback')
    precache[#precache]();check(pilot.snapshot().precache_ready,'Actual preload completion gates formal entry')
end
for _,variant in ipairs({'control','lane'}) do
    reset();ready(variant,2)
    local before=bus.request(events.WAVE_STATE_GET_REQUEST,{})
    local result=pilot.spawn({enabled=true})
    if not result.ok then print('FORMAL_LANE_FAILURE '..require('core/json_encoder').encode(result)) end
    check(result.ok and result.formal_registration and #units==1 and result.alive==1 and result.pending==0,'Single genuine formal registry entry')
    local u=units[1]
    check(u.survival_player_id==2 and u.survival_is_wave_monster and u.survival_monster_role=='normal','Formal player ownership and role')
    check(u.stats.hp==400 and u.stats.min==4 and u.stats.maxd==4 and u.stats.BAT==1 and u.stats.speed==400,'Actual N2 W1 numeric setters preserved')
    check(u:HasModifier('modifier_debug_attack_cap') and u:HasModifier('modifier_survival_hero_attack_range'),'Both variants preserve conservative cap/range')
    check(u.mods.modifier_enemy_wall_ai.wall_target_player_id==2 and u.mods.modifier_enemy_wall_ai.wall_entindex==walls[2].id,'Original wall AI receives exact owned target')
    check(wave._resource_snapshot_for_test().session_count==1,'Single original resource session held while alive')
    local count=#units;check(not pilot.spawn({enabled=true}).ok and #units==count,'No second formal birth')
    local previous_deaths=death_visuals
    u.alive=false;bus.emit(events.ENGINE_ENTITY_KILLED,{victim=u,victim_entindex=u.id})
    local killed=pilot.snapshot().report
    check(not killed.formal_registration and killed.alive==0 and killed.killed==1 and killed.natural_deaths==1,'Real engine death goes through original on_killed')
    check(death_visuals==previous_deaths+2 and killed.resource_session.released,'Original death visuals and session closure')
    bus.emit(events.ENGINE_ENTITY_KILLED,{victim=u,victim_entindex=u.id})
    check(pilot.snapshot().report.natural_deaths==1 and death_visuals==previous_deaths+2,'Duplicate death does not duplicate settlement')
    local stopped=pilot.stop().report
    check(stopped.closed and stopped.unit_removed and stopped.restored_baseline,'Only own corpse cleanup and counter restore')
    local after=bus.request(events.WAVE_STATE_GET_REQUEST,{})
    check(after.current_wave==before.current_wave and after.alive==0 and stopped.pending==0 and after.status==before.status,'Prior dev wave state restored')
    check(wave._resource_snapshot_for_test().session_count==0,'No leaked resource session')
    for _,p in ipairs(stopped.population) do check(p.alive==0,'All other owner population unchanged') end
end
reset();ready('lane',1);pilot.spawn({enabled=true});local u=units[1];local old_deaths=death_visuals
local stopped=pilot.stop().report
check(stopped.restored_baseline and stopped.unit_removed and stopped.natural_deaths==0 and death_visuals==old_deaths,'Alive stop does not forge death/rewards')
bus.emit(events.ENGINE_ENTITY_KILLED,{victim=u,victim_entindex=u.id});check(death_visuals==old_deaths,'Late native death after owned removal ignored')
for _,reason in ipairs({'create_fail','class_wrong','stat_throw'}) do
    reset();ready('lane');flags[reason]=true
    local result=pilot.spawn({enabled=true})
    check(not result.ok and result.restored_baseline and result.resource_session.released and result.alive==0 and result.pending==0,'Partial failed birth cleans own counters/session: '..reason)
    check(#units==0 or units[1].removed,'Partial own native entity removed')
end
reset();ready('control');session='changed_session';check(not pilot.spawn({enabled=true}).ok and #units==0,'Session change blocks formal birth')
session='formal_lane_test_session'
reset();ready('control');fixture.memory_profiles[0].revision=999
check(not pilot.spawn({enabled=true}).ok and #units==0,'Profile change blocks birth')
reset();ready('control');guard.mode={};check(not pilot.spawn({enabled=true}).ok and #units==0,'Guard-world change blocks birth')
reset();ready('control');client=true;check(not pilot.spawn({enabled=true}).ok and #units==0,'Client cannot create formal case')
client=false
reset();ready('control');wave.set_dev_mode(false)
check(not pilot.spawn({enabled=true}).ok and #units==0,'Normal active wave mode cannot be captured')
check(pilot.snapshot().report.no_birth_admitted and pilot.snapshot().report.unit_removed,'Preflight failure has a proved empty actor budget')
reset();ready('lane');pilot.spawn({enabled=true});local gone=units[1];local prior_deaths=death_visuals
UTIL_Remove(gone);local invalid=pilot.stop().report
check(invalid.unit_removed and invalid.alive==0 and invalid.pending==0 and invalid.resource_session.released,'Invalid native victim cannot strand formal population/session')
check(invalid.restored_baseline and invalid.natural_deaths==0 and death_visuals==prior_deaths,'Invalid-victim cleanup does not forge kills')
bus.emit(events.ENGINE_ENTITY_KILLED,{victim=gone,victim_entindex=gone.id})
check(death_visuals==prior_deaths,'Late swallowed native death cannot double-clean or award')
reset();ready('control');pilot.spawn({enabled=true});wave.set_dev_mode(true)
local generation_changed=pilot.stop().report
check(generation_changed.unit_removed and not generation_changed.restored_baseline and generation_changed.current_wave==1,'External wave generation cannot be overwritten by restoring an old baseline')
check(generation_changed.alive==0 and generation_changed.resource_session.released,'Generation change still releases only own formal record')
reset();ready('lane');pilot.spawn({enabled=true});local active_state=_G.SURVIVAL_FORMAL_LANE_PILOT
tasks[active_state.timeout_task]();check(pilot.snapshot().report.unit_removed,'Bounded lifetime collects only the pilot actor')
check(clears==0 and boss_rewards==0 and winners==0,'Ordinary nonfinal pilot cannot grant boss/final rewards or end game')
print('FORMAL_NATIVE_LANE_PILOT_PASS '..checks..' checks; real factory/bus/N2 rows; both variants; exact ownership, legacy cap/range, real death idempotence, partial-failure and session cleanup; simulated engine only')
