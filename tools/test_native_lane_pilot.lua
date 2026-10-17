package.path='scripts/vscripts/?.lua;'..package.path
local probe=require('tests/manual_native_lane_pilot')
assert(_G.SURVIVAL_NATIVE_LANE_PILOT==nil)
assert(not probe.prepare().ok and not probe.create().ok and probe.snapshot().enabled==false)
local checks=3
local function check(v,message) checks=checks+1;assert(v,message) end
local function copy(t) if type(t)~='table' then return t end local r={};for k,v in pairs(t) do r[k]=copy(v) end;return r end
local mode,session,time,game_state={},{},0,10
session='native_lane_test_session'
local manifest=require('config/generated/native_lane_pilot_manifest')
local bus,events=require('core/event_bus'),require('core/events')
local registry,tasks,callbacks,removed={}, {},{},{}
local kv,profiles,walls,active={}, {},{}, {0,1,2,3}
local fixture,guard
local created,precaches,orders,mutations,emits=0,0,0,0,0
local flags={}
local original_emit=bus.emit
bus.emit=function(...) emits=emits+1;return original_emit(...) end
IsServer=function() return not flags.client end;IsInToolsMode=function() return not flags.production end
GetMapName=function() return flags.wrong_map and 'wrong_map' or 'template_map' end
DOTA_GAMERULES_STATE_GAME_IN_PROGRESS=10;DOTA_TEAM_GOODGUYS=2;DOTA_TEAM_BADGUYS=3
GameRules={GetGameModeEntity=function() return mode end,GetGameTime=function() return time end,State_Get=function() return game_state end}
Vector=function(x,y,z) return {x=x,y=y,z=z} end
PlayerResource={IsValidPlayerID=function(_,id) return id>=0 and id<=3 end,
    GetPlayer=function(_,id) return {id=id} end,GetTeam=function() return 2 end}
package.loaded['systems/match_setup_service']={get_mode=function() return 'standard' end,get_session_id=function() return session end}
package.loaded['systems/player_context_service']={active_player_ids=function() return active end,
    is_owned_by=function(id,u) return u.owner==id end}
package.loaded['systems/player_profile_service']={get_profile=function(id) return profiles[id] end}
package.loaded['core/scheduler']={after=function(_,cb,id) tasks[id]=cb;return id end,cancel=function(id) tasks[id]=nil end}
LoadKeyValues=function(path) assert(path=='scripts/npc/npc_units_custom.txt');return kv end
EntIndexToHScript=function(id) return registry[id] end
UTIL_Remove=function(u) removed[#removed+1]=u;u.removed=true;registry[u.index]=nil end
ExecuteOrderFromTable=function() orders=orders+1 end
PrecacheUnitByNameAsync=function(name,cb,owner)
    check(owner==-1,'Explicit native third argument required')
    precaches=precaches+1
    if flags.precache_fail then error('engine secret not exported') end
    callbacks[#callbacks+1]=cb
end
local unit_serial=100
local function raw_unit(name)
    unit_serial=unit_serial+1
    local row
    for _,r in ipairs(manifest.rows) do if r.source_unit_name==name or r.alias_unit_name==name then row=r end end
    local u={index=unit_serial,name=name,class=name==row.alias_unit_name and 'npc_dota_creep_lane' or 'npc_dota_creature',
        model=row.source_fields.Model,health=200,max_health=200}
    registry[u.index]=u
    function u:IsNull() return self.removed==true end;function u:IsAlive() return self.health>0 end
    function u:entindex() return self.index end;function u:GetUnitName() return flags.wrong_name and 'unexpected_raw_unit' or self.name end
    function u:GetClassname() return flags.wrong_class and 'npc_dota_hero' or self.class end
    function u:GetModelName() return flags.wrong_model and 'invalid_model' or self.model end
    function u:IsBaseNPC() return true end;function u:IsRealHero() return false end;function u:IsHero() return false end
    function u:IsCreep() return self.class=='npc_dota_creep_lane' end;function u:IsCreature() return self.class=='npc_dota_creature' end
    function u:IsOther() return false end;function u:GetTeamNumber() return 3 end;function u:GetPlayerOwnerID() return -1 end
    function u:GetHealth() return self.health end;function u:GetMaxHealth() return self.max_health end
    function u:GetBaseDamageMin() return flags.nan_damage and 0/0 or 10 end;function u:GetBaseDamageMax() return 10 end
    function u:GetBaseMoveSpeed() return 250 end;function u:GetAttackCapability() return 1 end
    for _,method in ipairs({'GetBaseAttackTime','GetAttackSpeed','GetSecondsPerAttack','GetAttacksPerSecond','GetAttackAnimationPoint'}) do
        u[method]=function(_,bool)
            if flags.legacy_cadence and bool~=nil then error(method..' called with 2 arguments - expected 1') end
            if not flags.legacy_cadence then assert(bool==false,'native requires bool') end
            if flags.cadence_error then error('arbitrary native failure, do not fallback') end
            return 1
        end
    end
    function u:GetAbilityCount() return flags.invalid_ability_count and 1000 or 1 end
    function u:GetAbilityByIndex(slot)
        assert(slot==0)
        return {IsNull=function() return false end,GetAbilityName=function() return 'twin_gate_portal_warp' end,
            GetLevel=function() return 1 end,IsPassive=function() return false end,IsHidden=function() return true end,
            GetIntrinsicModifierName=function() return nil end}
    end
    function u:FindAllModifiers() return {{IsNull=function() return false end,GetName=function() return 'modifier_single_health_bar' end}} end
    function u:GetAttackTarget() return nil end
    function u:SetHealth() mutations=mutations+1;error('No numeric mutation') end
    function u:SetModel() mutations=mutations+1;error('No visual mutation') end
    if flags.formal_return then u.survival_is_wave_monster=true end
    return u
end
CreateUnitByName=function(name,position,clear,owner,controller,team)
    created=created+1
    check(clear==false and owner==nil and controller==nil and team==3,'Exact native creation signature')
    check(position.x==100 and position.y==200 and position.z==384,'Explicit position preserved')
    if flags.create_fail then error('native failure') end
    return raw_unit(name)
end
bus.handle_request(events.BUILDING_LIST_REQUEST,function(p)
    local u=walls[p.player_id]
    return {buildings=u and {{building_id='wall',unit=u,player_id=p.player_id,constructing=false}} or {}}
end)
local function reset()
    probe.stop();_G.SURVIVAL_NATIVE_LANE_PILOT=nil
    flags={};active={0,1,2,3};game_state=10;session='native_lane_test_session'
    kv={}
    for _,row in ipairs(manifest.rows) do
        kv[row.source_unit_name]=copy(row.source_fields)
        kv[row.alias_unit_name]=copy(row.source_fields);kv[row.alias_unit_name].BaseClass='npc_dota_creep_lane'
    end
    guard={mode=mode};fixture={mode=mode,guard=guard,status='ready',ids={0,1,2,3},memory_profiles={}}
    profiles={};walls={};tasks={};callbacks={}
    for id=0,3 do
        local profile={account_id='isolated-'..id,revision=id+10,save={gameplay_stats={map_level=({1,9,17,24})[id+1]}}}
        fixture.memory_profiles[id]=copy(profile);profiles[id]=profile
        local u={owner=id,index=40+id}
        function u:IsNull() return false end;function u:IsAlive() return true end
        function u:GetPlayerOwnerID() return self.native_owner or -1 end
        walls[id]=u
    end
    _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION=guard;_G.SURVIVAL_FOUR_PLAYER_LIVE_PERF=fixture
end
local function prepare(options)
    local r=probe.prepare(options or {enabled=true})
    check(r.status=='preparing' and not r.precache_ready,'Asynchronous precache not fake ready')
    callbacks[#callbacks]();check(probe.snapshot().precache_ready,'Actual precache callback admits readiness')
end
local function create()
    return probe.create({enabled=true,position={x=100,y=200,z=384}})
end
local function native_numeric_kv()
    -- Match the archived native LoadKeyValues evidence: all 15 numeric fields
    -- are numbers; ArmorPhysical is rounded through IEEE float32.
    for _,row in ipairs(manifest.rows) do
        for _,name in ipairs({row.source_unit_name,row.alias_unit_name}) do
            for key,value in pairs(kv[name]) do
                if tonumber(value) then kv[name][key]=tonumber(value) end
            end
            kv[name].ArmorPhysical=0.33333298563957
        end
    end
end
local function both_native_fields(field,value)
    local row=manifest.rows[1]
    kv[row.source_unit_name][field]=value;kv[row.alias_unit_name][field]=value
end
reset();native_numeric_kv();prepare({enabled=true,variant='control'});check(probe.snapshot().precache_ready,'Archived native numeric KV and float32 rounding accepted')
reset();native_numeric_kv();prepare({enabled=true,variant='lane'});check(probe.snapshot().precache_ready,'Same numeric contract admits alias')
for _,field in ipairs({'Level','ConsideredHero','HasInventory','StatusHealth','StatusMana','AttackDamageMin',
    'AttackDamageMax','AttackRange','MovementSpeed','MagicalResistance','VisionDaytimeRange','VisionNighttimeRange'}) do
    reset();native_numeric_kv();both_native_fields(field,tonumber(manifest.rows[1].source_fields[field])+1e-10)
    check(not probe.prepare({enabled=true}).ok,'Integer field does not gain a tolerance: '..field)
end
for _,value in ipairs({0.33333,0.333333+2^-25,0.333333-2^-25,math.huge,0/0,'nan',true}) do
    reset();native_numeric_kv();both_native_fields('ArmorPhysical',value)
    check(not probe.prepare({enabled=true}).ok,'Incorrect or nonfinite float is rejected')
end
reset();native_numeric_kv();kv[manifest.rows[1].alias_unit_name].ArmorPhysical=0.333333
check(not probe.prepare({enabled=true}).ok,'Independent within-half-ULP source/alias values cannot drift')
for _,field in ipairs({'BaseClass','Model','MovementCapabilities','AttackCapabilities','BoundsHullName'}) do
    reset();native_numeric_kv();kv[manifest.rows[1].alias_unit_name][field]=field=='BaseClass' and 'npc_dota_creature' or 'changed'
    check(not probe.prepare({enabled=true}).ok,'String field stays exact: '..field)
end
reset();native_numeric_kv();both_native_fields('UnknownScale',1)
check(not probe.prepare({enabled=true}).ok,'Unknown numeric field cannot enter a wildcard schema')
reset();native_numeric_kv();kv[manifest.rows[1].source_unit_name].StatusHealth=nil
check(not probe.prepare({enabled=true}).ok,'Missing numeric key rejected')
reset();native_numeric_kv();profiles[0].save.gameplay_stats.map_level='1'
check(not probe.prepare({enabled=true}).ok,'Numeric KV equivalence cannot loosen profile numeric types')
reset();native_numeric_kv();fixture.memory_profiles[0].save.gameplay_stats.ratio=0.333333
profiles[0].save.gameplay_stats.ratio=0.33333298563957
check(not probe.prepare({enabled=true}).ok,'Float KV tolerance cannot loosen profile values')
reset()
local initial_created,initial_precaches=created,precaches
for _,reason in ipairs({'client','production','wrong_map'}) do
    flags[reason]=true;check(not probe.prepare({enabled=true}).ok,'Reject non-Tools scope');flags[reason]=nil
end
check(created==initial_created and precaches==initial_precaches,'Rejected scope has no loader side effects')
for _,field in ipairs({'AttackRange','Model','Ability1'}) do
    reset();kv[manifest.rows[1].alias_unit_name][field]='extra-field-change'
    local r=probe.prepare({enabled=true});check(not r.ok and r.reason=='alias_KV_unknown_or_changed','Extra alias KV mutation rejected')
end
reset();profiles[0].revision=999;check(not probe.prepare({enabled=true}).ok,'Real profile fallthrough rejected')
reset();walls[1].native_owner=2;check(not probe.prepare({enabled=true}).ok,'Different valid native owner rejected')
reset();walls[2]=nil;check(not probe.prepare({enabled=true}).ok,'Missing completed wall rejected')
reset();active={0,1,2};check(not probe.prepare({enabled=true}).ok,'Not four active owners rejected')
reset();game_state=11;check(not probe.prepare({enabled=true}).ok,'Postgame rejected before precache')
reset();check(not probe.prepare({enabled=true,lifetime_seconds=61}).ok,'Lifetime is strictly bounded')
reset();probe.prepare({enabled=true});before=created
check(not create().ok and created==before,'No birth before genuine precache callback')
callbacks[1]();check(not probe.create({enabled=true,position={x=0/0,y=0,z=0}}).ok and probe.snapshot().budget_used==0,'Invalid position cannot consume or create')
reset();prepare();check(not probe.prepare({enabled=true}).ok,'Do not overwrite live preparation')
check(create().ok,'Ready creation accepted')
local first=_G.SURVIVAL_NATIVE_LANE_PILOT.unit;local snap=probe.snapshot()
check(snap.status=='created' and snap.readback.raw_unregistered and snap.budget_used==1,'Raw creation only, budget1')
check(snap.readback.getters.BAT.value==1 and snap.readback.abilities[1].name.value=='twin_gate_portal_warp','Native numeric and ability observations')
check(not snap.formal_registration and not snap.formal_rewards_verified and not snap.native_basic_attack_verified and not snap.FPS_gain_verified,'No invented completion claims')
local before=created;check(not create().ok and created==before,'Second creation blocked')
local stopped=probe.stop();check(stopped.removed and first.removed,'Exact own raw entity removed')
local before_removed=#removed;probe.stop();check(#removed==before_removed,'Idempotent exact cleanup')
reset();prepare({enabled=true,variant='control',archetype_id='dwarf_white_rifle'})
local control=create();check(control.ok and control.expected_class=='npc_dota_creature' and control.readback.getters.model.value=='models/heroes/hoodwink/hoodwink.vmdl','Second source and unchanged control class')
reset();prepare();flags.legacy_cadence=true;check(create().ok,'Only known legacy arity fallback accepted')
for _,reason in ipairs({'wrong_class','wrong_name','wrong_model','nan_damage','invalid_ability_count','cadence_error'}) do
    reset();prepare();flags[reason]=true
    local prior=#removed;local r=create()
    check(not r.ok and r.stopped and r.removed and #removed==prior+1,'Failed native readback collects exact own entity: '..reason)
    check(r.readback and r.readback.getters.health.value==200,'Retain available native readback after safe failed birth cleanup')
end
reset();prepare();flags.create_fail=true;check(not create().ok and probe.snapshot().budget_used==1,'Create failure consumes attempt budget')
reset();flags.precache_fail=true;check(not probe.prepare({enabled=true}).ok and not probe.snapshot().enabled,'Failed native precache rejects')
reset();local r=probe.prepare({enabled=true});local callback=callbacks[1];_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION={mode=mode}
callback();check(not probe.snapshot().enabled and not probe.snapshot().precache_ready,'Late precache after guard replacement rejected')
reset();prepare();session='changed-session';before=created;check(not create().ok and created==before,'Cross-session creation rejected')
reset();prepare();profiles[3].save.gameplay_stats.map_level=100;before=created;check(not create().ok and created==before,'Changed owner profile blocks create')
reset();prepare();bus.reset();before=created;check(not create().ok and created==before,'Bus generation change blocks create')
bus.handle_request(events.BUILDING_LIST_REQUEST,function(p) return {buildings={{building_id='wall',unit=walls[p.player_id],player_id=p.player_id}}} end)
reset();prepare();create();local s=_G.SURVIVAL_NATIVE_LANE_PILOT;local u=s.unit
u.survival_native_lane_pilot_token={};before_removed=#removed
check(probe.stop().cleanup_refused and #removed==before_removed,'Foreign token refuses cleanup')
check(not probe.prepare({enabled=true}).ok,'Cannot bypass leaked owned budget')
u.survival_native_lane_pilot_token=s.token;probe.stop()
reset();prepare();create();s=_G.SURVIVAL_NATIVE_LANE_PILOT;u=s.unit;local old_mode=mode;mode={};before_removed=#removed
check(probe.stop().cleanup_refused and #removed==before_removed,'New-world cleanup does not delete old handles')
mode=old_mode;probe.stop()
reset();prepare();create();s=_G.SURVIVAL_NATIVE_LANE_PILOT;u=s.unit;registry[u.index]={}
before_removed=#removed;check(probe.stop().cleanup_refused and #removed==before_removed,'Entity index reuse cannot remove another handle')
registry[u.index]=u;probe.stop()
reset();prepare();create();s=_G.SURVIVAL_NATIVE_LANE_PILOT;u=s.unit
local remove_native=UTIL_Remove;local requested=0
UTIL_Remove=function() requested=requested+1 end
local pending=probe.stop();check(pending.cleanup_requested and not pending.removed,'Removal request is not fabricated completed removal')
probe.stop();check(requested==1 and not probe.prepare({enabled=true}).ok,'Pending asynchronous removal cannot duplicate requests or reset budget')
remove_native(u);check(probe.snapshot().removed,'Later native removal confirmed by actual invalid handle')
UTIL_Remove=remove_native
reset();prepare();create();s=_G.SURVIVAL_NATIVE_LANE_PILOT;tasks[s.timeout_task]();check(probe.snapshot().removed,'Bounded lifetime cleans own unit')
reset();probe.prepare({enabled=true});s=_G.SURVIVAL_NATIVE_LANE_PILOT;tasks[s.precache_task]();callbacks[1]()
check(s.stopped and not s.ready,'Timed-out precache never reactivates')
reset();probe.prepare({enabled=true});local old_callback=callbacks[1];probe.stop()
probe.prepare({enabled=true});local replacement=_G.SURVIVAL_NATIVE_LANE_PILOT;old_callback()
check(replacement.status=='preparing' and not replacement.ready,'Old native callback cannot promote replacement generation')
callbacks[2]();check(replacement.ready,'New native callback retains own generation')
reset();prepare();flags.formal_return=true;before_removed=#removed
check(not create().ok and #removed==before_removed,'Never claim or remove returned formal foreign unit')
check(orders==0 and mutations==0 and emits==0,'No commands, gameplay setters, fabricated events, formal rewards or writes')
print('NATIVE_LANE_PILOT_PASS '..checks..' checks; default inert; exact 4-owner scope; full KV; native arity; one-unit budget; bounded exact cleanup; raw-only claims')
