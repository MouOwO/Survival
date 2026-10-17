-- Real wave/pilot factory, bus, four consumers and corrosive modifier. Engine
-- services are mocked; "legacy" loads exact pre-change consumer backups.
package.path='scripts/vscripts/?.lua;'..package.path
class=function(t) return t end
local legacy=arg and arg[1]=='legacy'
local bus,events=require('core/event_bus'),require('core/events')
local pilot=require('tests/manual_formal_lane_pilot')
assert(_G.SURVIVAL_FORMAL_LANE_PILOT==nil and not pilot.prepare().ok and not pilot.spawn().ok)
local checks=3
local function check(v,m) checks=checks+1;assert(v,m) end
local function copy(t) if type(t)~='table' then return t end local r={};for k,v in pairs(t) do r[k]=copy(v) end;return r end
local noop=function() end
local mode,time,session={},0,'formal_lane_test_session'
local scans,creature_results=0,nil
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
Entities={FindByName=function(_,_,name) return marker(name) end,FindAllByClassname=function(_,name)
    check(name=='npc_dota_creature','Consumers keep original creature class scan')
    scans=scans+1
    if creature_results then return creature_results end
    local result={}
    for _,u in ipairs(units) do if not u:IsNull() and u:GetClassname()==name then result[#result+1]=u end end
    return result
end}
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
    function u:GetUnitName() return self.name end;function u:GetClassname() return self.class_override or (flags.class_wrong and 'npc_dota_hero' or (self.name:find('tools_lane',1,true) and 'npc_dota_creep_lane' or 'npc_dota_creature')) end
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
    function u:GetAttackTarget() return self.target end
    function u:ForceKill()
        self.kills=(self.kills or 0)+1;self.alive=false
        bus.emit(events.ENGINE_ENTITY_KILLED,{victim=self,victim_entindex=self.id})
    end
    function u:HasModifier(name) return self.mods[name]~=nil end
    function u:FindModifierByName(name) return self.mods[name] end
    function u:AddNewModifier(_,_,name,params)
        if flags.stat_throw and name=='modifier_debug_attack_cap' then error('native modifier failed') end
        local m=copy(params or {});m.parent=self
        function m:IsNull() return false end;function m:GetParent() return self.parent end
        self.mod_calls=self.mod_calls or {};self.mod_calls[name]=(self.mod_calls[name] or 0)+1
        if name=='modifier_research_armor_reduction' then
            function m:AddArmorReduction(value,record,source)
                self.calls=(self.calls or 0)+1;self.value=value;self.record=record;self.source=source
            end
        end
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
    creature_results=nil
    guard={mode=mode};fixture={mode=mode,guard=guard,status='ready',write_isolated=true,ids={0,1,2,3},memory_profiles={}}
    walls={};profiles={}
    for id=0,3 do
        local u={id=40+id,owner=id};function u:IsNull() return false end;function u:IsAlive() return true end
        function u:GetPlayerOwnerID() return -1 end;function u:GetAbsOrigin() return {x=(id+1)*1000,y=(id+1)*200,z=32} end
        function u:GetTeamNumber() return 2 end
        u.survival_player_id=id
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

local effects={}
package.loaded['systems/rogue_effect_state_service']={
    add_effect=function(id,key) effects[id]=effects[id] or {};effects[id][key]=true end,
    has_effect=function(id,key) return effects[id] and effects[id][key]==true end,
    numeric=function(_,key) return key=='builder_peaceful_wood_per_hit' and 2 or 0 end,
}
package.loaded['systems/harvest_feedback_service']={reset=noop,add=noop,queue=noop}
package.loaded['core/particle_manager']={show_green_number=noop}
package.loaded['systems/tree_damage_rules']={is_allowed_tree_attacker=function(u) return u.allowed==true end}
RandomFloat=function() return 99 end
if legacy then
    local base='output/formal_native_lane_pilot_20261013/registry_view_adapter/backups/'
    package.loaded['systems/rogue_effect_registry']=assert(loadfile(base..'rogue_effect_registry.lua'))()
    package.loaded['systems/tree_system']=assert(loadfile(base..'tree_system.lua'))()
    assert(loadfile(base..'item_survival_rogue_actions.lua'))()
else require('items/item_survival_rogue_actions') end
local rogue=require('systems/rogue_effect_registry')
local tree_service=require('systems/tree_system')
local lane_view=require('systems/registered_wave_lane_view')
require('modifiers/modifier_rogue_reward_effects')
local corrosive=rogue.get('owned_target_attacker_armor_reduction')
local slow=rogue.get('wall_attacker_attack_speed_pct')
local cases=0
local function case(name,fn) fn();cases=cases+1;print('LANE_REGISTRY_CASE_PASS '..name) end
local function born(owner,variant)
    reset();effects={};ready(variant or 'lane',owner or 0)
    local result=pilot.spawn({enabled=true})
    check(result.ok and result.formal_registration,'Genuine current private wave registry registration')
    return units[1]
end
local function foreign(name,class_name,owner)
    local u=unit(name or 'unrelated_lane',{})
    u.class_override=class_name or 'npc_dota_creep_lane';u.survival_player_id=owner or 0
    u.survival_is_wave_monster=true
    -- Matching public self-fields do not create private registry membership.
    u.survival_formal_lane_pilot_token=_G.SURVIVAL_FORMAL_LANE_PILOT and _G.SURVIVAL_FORMAL_LANE_PILOT.ticket
    return u
end
local function apply_both(owner)
    check(corrosive.apply({player_id=owner or 0,effect={effect_type='owned_target_attacker_armor_reduction'},params={value=-1}}),'Actual corrosive apply')
    check(slow.apply({player_id=owner or 0,params={value=-15}}),'Actual global slow apply')
end
local function harvest_setup()
    local tree={IsNull=function() return false end,GetHealth=function() return 1000 end}
    local worker={allowed=true,IsNull=function() return false end}
    local wood={}
    bus.handle_request(events.GRID_OCCUPY_REQUEST,function() return {ok=true} end)
    bus.handle_request(events.RESOURCE_ADD_REQUEST,function(p) wood[p.player_id]=(wood[p.player_id] or 0)+p.wood;return {ok=true} end)
    tree_service.init();tree_service._reset_for_test(1,tree,0)
    local function harvest(id,advance)
        if advance~=false then time=time+.1 end
        tree_service._reset_for_test(1,tree,id)
        bus.emit(events.TREE_HIT,{player_id=id,team=2,attacker=worker,target=tree,source='lumberjack',base_lumber_efficiency=3})
        return wood[id]
    end
    return harvest
end
local item_serial=800
local function bomb()
    item_serial=item_serial+1
    local id=item_serial
    local caster={IsNull=function() return false end,RemoveItem=function(self) self.removed=(self.removed or 0)+1 end}
    local item=setmetatable({},{__index=item_survival_rogue_nuclear_bomb})
    function item:SetActivated(v) self.activated=v end;function item:GetCaster() return caster end
    function item:IsNull() return false end;function item:entindex() return id end
    item:OnSpellStart();item:OnSpellStart()
    local key='rogue_nuclear_bomb:'..id
    check(tasks[key] and item.activated==false,'Actual once-only nuclear task and activation')
    return function() local result=tasks[key]();if result==false then tasks[key]=nil end;return result end,caster
end
local function dead(u)
    u.alive=false;bus.emit(events.ENGINE_ENTITY_KILLED,{victim=u,victim_entindex=u.id})
end
local function cleanup_callback()
    local snapshot=wave._registered_lane_view_snapshot_for_test()
    check(snapshot.task and tasks[snapshot.task],'Owned corpse cleanup task')
    return tasks[snapshot.task],snapshot.task
end
local function run_cleanup()
    local fn,key=cleanup_callback();time=time+.25
    local result=fn();if result==false then tasks[key]=nil end
    return result
end

case('registered_legacy_negative_or_adapted_all_four',function()
    local u=born(2);local creature=foreign('plain_creature','npc_dota_creature',1)
    apply_both(0)
    check(creature:HasModifier('modifier_rogue_corrosive_shield_attack') and creature:HasModifier('modifier_rogue_enemy_attack_speed'),'Legacy creature modifiers stay')
    check(u:HasModifier('modifier_rogue_corrosive_shield_attack')==not legacy,'Actual registered lane corrosive old miss/new inclusion')
    check(u:HasModifier('modifier_rogue_enemy_attack_speed')==not legacy,'Actual registered lane slow old miss/new inclusion')
    u.target=walls[0];local harvest=harvest_setup()
    check(harvest(0)==(legacy and 5 or 3),'Actual registered owner2 lane targets owner0 wall: old peaceful5/new3')
    local execute,caster=bomb();local pending=execute();if pending~=false then execute() end
    check(creature.kills==1 and (u.kills or 0)==(legacy and 0 or 1),'Actual nuke old lane0/new lane1; creature1')
    check(caster.removed==1,'Actual item removal once')
end)
if legacy then
    print('REGISTERED_LANE_LEGACY_NEGATIVE_PASS '..checks..' checks; four real consumers miss actual formal registered lane; engine simulated')
    return
end

case('creature_array_preserved_append_dedup_no_adoption',function()
    local u=born(0)
    local c=foreign('c','npc_dota_creature',1);c.alive=false
    local invalid=foreign('invalid','npc_dota_creature',1);invalid.removed=true
    local input={c,invalid,c,u}
    local out=lane_view.append(input)
    check(out==input and #out==4 and out[1]==c and out[2]==invalid and out[3]==c and out[4]==u,'Original array/order/duplicates/dead/invalid preserved; appended lane dedup')
    input={c,invalid,c};out=lane_view.append(input)
    check(out~=input and #input==3 and #out==4 and out[4]==u,'Append copies only when needed and never mutates original')
    out[4]=nil;check(lane_view.append({})[1]==u,'Returned array cannot mutate private registry')
    for _,class_name in ipairs({'npc_dota_creep_lane','npc_dota_hero','npc_dota_worker','npc_dota_creature'}) do
        local fake=foreign('matching_preview',class_name,0)
        fake.survival_formal_lane_pilot_token=u.survival_formal_lane_pilot_token
        fake.survival_is_challenge_monster=true
        local result=lane_view.append({})
        check(#result==1 and result[1]==u and result[1]~=fake,'Public markers never admit unrelated lane/hero/worker/preview')
    end
end)

case('global_slow_and_actual_corrosive_victim_owner',function()
    local u=born(2);apply_both(0)
    check(u.mods.modifier_rogue_enemy_attack_speed.value==-15,'Slow from owner0 applies owner2 lane globally')
    local m=setmetatable({parent=u},{__index=modifier_rogue_corrosive_shield_attack})
    function m:GetParent() return self.parent end
    m:OnCreated(u.mods.modifier_rogue_corrosive_shield_attack)
    m:OnAttack({attacker=u,target=walls[2],record=1})
    check(not u.mods.modifier_research_armor_reduction,'Lane owner2 victim without effect does not proc owner0 shield')
    m:OnAttack({attacker=u,target=walls[0],record=2});m:OnAttack({attacker=u,target=walls[0],record=2})
    check(u.mods.modifier_research_armor_reduction.calls==1 and u.mods.modifier_research_armor_reduction.source=='corrosive_shield','Real modifier uses target owner0 and preserves duplicate-record guard')
    check(u.mods.modifier_research_armor_reduction.record==2 and u.mods.modifier_research_armor_reduction.value==require('config/armor_balance').from_war3_linear(1),'Exact original corrosive magnitude and attack record retained')
    u.mods.modifier_research_armor_reduction=nil
    effects[0]=nil;effects[2]={owned_target_attacker_armor_reduction=true}
    m:OnAttack({attacker=u,target=walls[0],record=3})
    check(not u.mods.modifier_research_armor_reduction,'Unowned victim never treated as lane owner')
end)

case('cross_owner_wall_and_frame_cache_alive_contract',function()
    local u=born(2);u.target=walls[1];local harvest=harvest_setup();local before=scans
    check(harvest(1)==3,'Lane owner2 attacking owner1 suppresses owner1 peaceful bonus')
    check(harvest(0,false)==5 and scans==before+1,'Same-frame wall target set shared; unattacked owner0 bonus survives')
    u.target=walls[0]
    check(harvest(0)==8,'Next frame observes real target switch to owner0')
    u.alive=false
    check(harvest(0)==13,'Dead valid lane ignored by original tree alive check before registry death event')
end)

case('dead_valid_registry_retired_modifiers_revive_and_native_remove',function()
    local u=born(3);local c=foreign('dead_creature','npc_dota_creature',0);c.alive=false
    dead(u)
    check(wave._registered_lane_view_snapshot_for_test().pending==1,'Real natural death preserved exact corpse even without prior view')
    local result=lane_view.append({c})
    check(#result==2 and result[1]==c and result[2]==u,'Engine dead creature plus unregistered dead-valid formal lane retained')
    apply_both(0)
    check(u:HasModifier('modifier_rogue_corrosive_shield_attack') and u:HasModifier('modifier_rogue_enemy_attack_speed'),'Rogue valid-only dead corpse semantics retained')
    check(c:HasModifier('modifier_rogue_corrosive_shield_attack') and c:HasModifier('modifier_rogue_enemy_attack_speed'),'Original dead creature not filtered')
    local execute=bomb();execute();check(not u.kills and not c.kills,'Nuke original alive contract skips both corpses')
    time=time+10000;check(run_cleanup()==.25 and lane_view.append({})[1]==u,'No TTL/cap discards valid corpse')
    u.alive=true;check(lane_view.append({})[1]==u,'Same-handle revival remains consumer-visible')
    UTIL_Remove(u);check(#lane_view.append({})==0,'Native IsNull immediately excludes removed corpse')
    check(run_cleanup()==false,'Removed final entry ends cleanup task')
    local snapshot=wave._registered_lane_view_snapshot_for_test()
    check(snapshot.pending==0 and not snapshot.task,'Cleanup references drained and task stops')
end)

case('death_exact_identity_and_index_reuse_late_event',function()
    local u=born(1);local fake=foreign('fake','npc_dota_creep_lane',1)
    bus.emit(events.ENGINE_ENTITY_KILLED,{victim=fake,victim_entindex=u.id})
    check(lane_view.append({})[1]==u and wave._registered_lane_view_snapshot_for_test().pending==0,'Wrong victim handle cannot retire exact live registry member')
    dead(u);local replacement=foreign('new_lane','npc_dota_creep_lane',1)
    local replacement_old_id=replacement.id;replacement.id=u.id;by_id[replacement_old_id]=nil;by_id[u.id]=replacement
    check(#lane_view.append({})==0,'Old valid handle rejected after index recycled; new marker-only unit not adopted')
    bus.emit(events.ENGINE_ENTITY_KILLED,{victim=u,victim_entindex=u.id})
    check(not replacement:IsNull() and replacement.alive,'Late old death cannot destroy new same-index entity')
    check(run_cleanup()==false and wave._registered_lane_view_snapshot_for_test().pending==0,'Index-reused corpse history released precisely')
end)

case('dead_valid_prune_retains_body_without_forging_kill',function()
    local u=born(1);u.alive=false
    local before=bus.request(events.WAVE_STATE_GET_REQUEST,{})
    bus.emit(events.BUILDING_CHANGED,{building_id='wall',player_id=1,entindex=walls[1].id,unit=walls[1]})
    local after=bus.request(events.WAVE_STATE_GET_REQUEST,{})
    check(after.alive==0 and after.killed==before.killed,'Actual target-update prune keeps existing no-settlement behavior')
    check(wave._registered_lane_view_snapshot_for_test().pending==1 and lane_view.append({})[1]==u,'Valid body pruned before engine death still visible to original valid-only scans')
    apply_both(0)
    check(u:HasModifier('modifier_rogue_corrosive_shield_attack') and u:HasModifier('modifier_rogue_enemy_attack_speed'),'Both real rogue consumers include pruned body')
    UTIL_Remove(u);check(run_cleanup()==false,'Pruned body history ends on actual native removal')
end)

case('known_existing_index_only_late_death_boundary_preserved',function()
    local old=born(0);dead(old);pilot.stop()
    next_unit_id=old.id-1
    local successor=born(1)
    check(successor.id==old.id and successor~=old,'Actual factory registers a distinct successor at reused index')
    bus.emit(events.ENGINE_ENTITY_KILLED,{victim=old,victim_entindex=old.id})
    check(bus.request(events.WAVE_STATE_GET_REQUEST,{}).alive==1 and lane_view.append({})[1]==successor,'Late precise old death leaves successor registry intact')
    bus.emit(events.ENGINE_ENTITY_KILLED,{victim_entindex=old.id})
    check(bus.request(events.WAVE_STATE_GET_REQUEST,{}).alive==0 and successor.alive and #lane_view.append({})==0,'Existing index-only death path still unregisters living successor: explicit unresolved boundary')
    check(wave._registered_lane_view_snapshot_for_test().pending==0,'Adapter never turns the live wrongly-unregistered successor into a corpse')
end)

case('current_identity_owner_team_class_native_handle_bounds',function()
    local u=born(2)
    u.survival_player_id=1;check(#lane_view.append({})==0,'Current registry owner mismatch rejected');u.survival_player_id=2
    u.team=2;check(#lane_view.append({})==0,'Wrong native team rejected');u.team=3
    u.class_override='npc_dota_hero';check(#lane_view.append({})==0,'Native class mismatch rejected');u.class_override=nil
    local original=by_id[u.id];by_id[u.id]=nil;check(#lane_view.append({})==0,'Native handle absent rejected');by_id[u.id]=original
    local saved=_G.SURVIVAL_FORMAL_LANE_PILOT
    _G.SURVIVAL_FORMAL_LANE_PILOT={ticket={},world=mode,bus=bus,generation=bus.get_generation(),player_id=2}
    check(#lane_view.append({})==0,'Hand-filled global pilot never substitutes exact ticket/registry proof')
    _G.SURVIVAL_FORMAL_LANE_PILOT=saved;check(lane_view.append({})[1]==u,'Exact restored native member still eligible')
end)

case('next_wave_spawn_generation_does_not_drop_member',function()
    local u=born(0);check(lane_view.append({})[1]==u,'Initial formal member eligible')
    wave.set_dev_mode(true) -- Real public method advances the spawn generation.
    check(lane_view.append({})[1]==u,'Still-registered earlier member survives changed wave spawn generation')
    dead(u);check(lane_view.append({})[1]==u,'Death after later generation keeps valid corpse')
end)

case('forced_alive_stop_and_disconnect_create_no_corpse',function()
    local u=born(1);lane_view.append({});pilot.stop()
    check(u:IsNull() and wave._registered_lane_view_snapshot_for_test().pending==0,'Alive exact stop removed original unit without retaining corpse')
    local empty={};check(lane_view.append(empty)==empty,'Stopped empty view returns input directly')
    u=born(2);lane_view.append({});bus.emit(events.PLAYER_DISCONNECTED,{player_id=2})
    check(u:IsNull() and wave._registered_lane_view_snapshot_for_test().pending==0,'Owner forced removal creates no corpse history')
    check(#lane_view.append({})==0,'Disconnected unit cannot survive view')
end)

case('init_world_bus_generation_and_old_callback_ownership',function()
    local u=born(0);dead(u);local old_fn,old_task=cleanup_callback()
    bus.reset();wave.init() -- Normal same-world bootstrap clears request handlers.
    check(not tasks[old_task] and old_fn()==false,'Same-world init cancels old exact task and revokes callback')
    check(#lane_view.append({})==0 and wave._registered_lane_view_snapshot_for_test().pending==0,'Init clears old registry/body view')
    u=born(1);dead(u);old_fn,old_task=cleanup_callback()
    local old_mode=mode;mode={}
    local input={foreign('c','npc_dota_creature',0)}
    check(lane_view.append(input)==input and not tasks[old_task],'World replacement cancels old view task without filtering creature input')
    check(old_fn()==false,'Old-world queued callback rejected');mode=old_mode
    u=born(1);dead(u);old_fn,old_task=cleanup_callback();bus.reset()
    check(lane_view.append(input)==input and not tasks[old_task] and old_fn()==false,'Bus generation change rejects and cancels old body epoch')
    local new_u=born(2);dead(new_u);local new_fn,new_task=cleanup_callback()
    check(old_fn()==false and tasks[new_task]==new_fn and wave._registered_lane_view_snapshot_for_test().pending==1,'Old callback cannot retire a newly initialized same-world store')
end)

case('bus_module_pointer_replace_and_probe_guard_body_semantics',function()
    local u=born(0);dead(u);local old_fn,old_task=cleanup_callback()
    local saved=package.loaded['core/event_bus']
    package.loaded['core/event_bus']={get_generation=function() return {} end}
    local input={}
    check(lane_view.append(input)==input and not tasks[old_task] and old_fn()==false,'Bus module identity replacement cancels old exact epoch')
    package.loaded['core/event_bus']=saved
    u=born(2);dead(u)
    local previous_guard=_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION
    _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION={mode=mode}
    check(lane_view.append({})[1]==u,'Same-world/bus valid corpse remains after Tools guard replaced, matching original creature contract')
    _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION=previous_guard
    UTIL_Remove(u);check(run_cleanup()==false,'Guard-only change never prevents corpse reference release')
end)

case('nuke_batch_revalidation_boss_protection_and_no_duplicate',function()
    local u=born(0);local c=foreign('plain','npc_dota_creature',1)
    local boss=foreign('boss','npc_dota_creature',1);boss.survival_is_boss=true
    local unrelated=foreign('unrelated','npc_dota_creep_lane',1)
    local execute,caster=bomb();execute();u.alive=false;execute()
    check(c.kills==1 and not u.kills and not boss.kills and not unrelated.kills,'Nuke preserves collect/batch live revalidation and boss/unrelated exclusion')
    check(caster.removed==1,'Nuke item cleanup unchanged')
end)

case('default_empty_and_budgeted_corpse_cleanup',function()
    reset();local input={};local before=scans
    for _=1,50 do check(lane_view.append(input)==input,'Default no formal lane returns exact original array') end
    check(scans==before and wave._registered_lane_view_snapshot_for_test().pending==0,'Adapter adds no global scan or cleanup task by default')
    local view=lane_view.new(function() return nil end)
    local tracked={}
    for i=1,130 do
        local u=foreign('budget_lane'..i,'npc_dota_creep_lane',0);u.alive=false;tracked[i]=u
        view:retire({unit=u,entindex=u.id,player_id=0})
    end
    local snapshot=view:snapshot();check(snapshot.pending==130 and tasks[snapshot.task],'No live/body cap; one budgeted task')
    local fn=tasks[snapshot.task]
    for _,u in ipairs(tracked) do UTIL_Remove(u) end
    check(fn()==.25 and view:snapshot().pending==66,'First cleanup processes exactly64 records')
    check(fn()==.25 and view:snapshot().pending==2,'Second cleanup fixed64 budget')
    check(fn()==false and view:snapshot().pending==0 and not view:snapshot().task,'Final two clear and task stops')
end)

case('native_validation_reentry_revokes_old_view',function()
    reset()
    local u=foreign('reentry_lane','npc_dota_creep_lane',0)
    local record={unit=u,entindex=u.id,player_id=0}
    local view=lane_view.new(function() return record end)
    function u:IsNull() view:reset();return false end
    local input={}
    check(view:append(input)==input,'Reset reentered in native identity cannot append stale unit')
    view=lane_view.new(function() return nil end)
    function u:IsNull() return false end
    function u:IsAlive() view:reset();return false end
    view:retire(record)
    check(view:snapshot().pending==0 and not view:snapshot().task,'Reset in native death validation cannot attach stale history/task')
    function u:IsNull() return false end
    view=lane_view.new(function() return record end)
    local getter=GameRules.GetGameModeEntity;local queries=0
    GameRules.GetGameModeEntity=function()
        queries=queries+1;if queries==2 then view:reset() end;return mode
    end
    check(view:append(input)==input and queries==2,'Reset in final same-world scope getter cannot return prior stale additions')
    GameRules.GetGameModeEntity=getter
end)

print('REGISTERED_LANE_BUSINESS_PASS '..cases..' cases '..checks..' checks; actual formal registry/factory/bus, all four consumers, native modifier owner contract; simulated engine only')
