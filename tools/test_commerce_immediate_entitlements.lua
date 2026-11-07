package.path='scripts/vscripts/?.lua;'..package.path
package.loaded['config/test_access']={enabled=false}
local bus=require('core/event_bus');local events=require('core/events')
if arg[1] then package.preload['systems/commerce_runtime']=assert(loadfile(arg[1])) end
local current_world,clock={},0
GameRules={GetGameModeEntity=function()return current_world end,GetGameTime=function()return clock end}
local tasks,cancelled={},{}
package.loaded['core/scheduler']={every=function(_,f,key)tasks[key]=f end,
    cancel=function(key)cancelled[key]=(cancelled[key] or 0)+1;tasks[key]=nil end}
local owners,heroes,walls,owned={}, {}, {}, {}
local next_entity=100
local function unit(id)
    next_entity=next_entity+1
    return {id=next_entity,survival_player_id=id,null=false,alive=true,removals=0,
        IsNull=function(s)return s.null end,IsAlive=function(s)return s.alive end,HasModifier=function(s)return s.constructing==true end,
        GetMaxHealth=function()return 100 end,GetTeamNumber=function()return 2 end,GetAbsOrigin=function()return {x=0,y=0,z=0} end,
        GetStrength=function()return 2 end,GetAgility=function()return 3 end,GetIntellect=function()return 5 end,
        entindex=function(s)return s.id end,SetHullRadius=function()end,SetAttackCapability=function()end,
        AddNewModifier=function()end,RemoveSelf=function(s)s.removals=s.removals+1;s.null=true end}
end
for id=0,3 do owners[id]=true;owned[id]=true;heroes[id]=unit(id);walls[id]=unit(id) end
package.loaded['systems/player_context_service']={is_defeated=function(id)return not owners[id] end,
    active_player_ids=function()local ids={};for id=0,3 do if owners[id] then ids[#ids+1]=id end end;return ids end}
local entitlement,capacity,spawn,lookups,hero_reads,levels,research_writes={},{},{},{},{},{},{}
for id=0,3 do entitlement[id]={};levels[id]={};research_writes[id]=0 end
local ownership_reads=0
package.loaded['systems/commerce_effects']={owned=function(id,key)
 ownership_reads=ownership_reads+1;return entitlement[id][key]==true
end,invalidate=function()end}
package.loaded['systems/worker_system']={refresh_commerce_capacity=function(id)capacity[id]=(capacity[id] or 0)+1 end,
 commerce_spawn_immortal=function(id,city)spawn[id]=(spawn[id] or 0)+1;return true end}
package.loaded['systems/gameplay_phase_guard']={post_clear_frozen=function()return false end}
package.loaded['config/buildings_config']={arrow_tower={unit_name='npc_test_cannon'}}
package.loaded['combat/damage_service']={Deal=function()error('No target damage should occur in lifecycle fixture')end}
local particles,cannons,created={}, {}, 0
local failures={}
ParticleManager={CreateParticle=function(_,path,attach,u)
    created=created+1;particles[created]={unit=u,destroy=0,release=0};return created
end,DestroyParticle=function(_,p)particles[p].destroy=particles[p].destroy+1;if failures.destroy then error('native destroy failure') end end,
ReleaseParticleIndex=function(_,p)particles[p].release=particles[p].release+1;if failures.release then error('native release failure') end end}
CreateUnitByName=function(name,pos,clear,wall,owner,team)
    assert(name=='npc_test_cannon' and wall==owner and team==2)
    local u=unit(owner.survival_player_id);cannons[#cannons+1]=u;return u
end
CustomNetTables={SetTableValue=function()end};PlayerResource={IsValidPlayerID=function(_,id)return id>=0 and id<=3 end}
local listeners,listener_count={},0
CustomGameEventManager={RegisterListener=function(_,name,fn)listener_count=listener_count+1;listeners[listener_count]=fn;return listener_count end,
    UnregisterListener=function(_,id)listeners[id]=nil end}
FindUnitsInRadius=function()return {} end
PATTACH_ABSORIGIN_FOLLOW=1;DOTA_UNIT_CAP_NO_ATTACK=0;DOTA_UNIT_TARGET_TEAM_ENEMY=1
DOTA_UNIT_TARGET_HERO=1;DOTA_UNIT_TARGET_BASIC=2;DOTA_UNIT_TARGET_FLAG_NONE=0;FIND_ANY_ORDER=0;DAMAGE_TYPE_PHYSICAL=1
bus.handle_request(events.HERO_SUMMON_GET_REQUEST,function(p)hero_reads[p.player_id]=(hero_reads[p.player_id] or 0)+1;return {unit=heroes[p.player_id]}end)
local cities={};for id=0,3 do cities[id]=unit(id) end
bus.handle_request(events.BUILDING_LIST_REQUEST,function(p)local id=p.player_id;lookups[id]=(lookups[id] or 0)+1
 return {buildings=cities[id] and {{building_id='main_city',unit=cities[id]}} or {}} end)
bus.handle_request(events.RESEARCH_STATE_GET_REQUEST,function(p)return {levels=levels[p.player_id]}end)
bus.handle_request(events.RESEARCH_LEVEL_SET_REQUEST,function(p)
 levels[p.player_id][p.tech_id]=p.level;research_writes[p.player_id]=research_writes[p.player_id]+1;return {ok=true} end)
local runtime=require('systems/commerce_runtime')
local function register_walls()for id=0,3 do if walls[id] then bus.emit(events.BUILDING_CREATED,{player_id=id,building_id='wall',unit=walls[id]}) end end end
local function tick()assert(tasks.commerce_runtime());clock=clock+1 end
local function sums()
    local d,r,n=0,0,0
    for _,p in pairs(particles) do d=d+p.destroy;r=r+p.release end
    for _,u in ipairs(cannons) do n=n+u.removals end
    return d,r,n
end

local checks=0;local function check(ok,why) checks=checks+1;assert(ok,why) end
local function grant(id)
 entitlement[id]={immortal=true,lumber_fury=true,lumberyard=true,lottery_immortal_slaying_sword_array=true,
 sovereign=true,orbital=true,flame_wall=true}
end
local damage=0;ApplyDamage=function()damage=damage+1 end
local enemy=unit(2);enemy.survival_is_wave_monster=true
FindUnitsInRadius=function()return {enemy} end
runtime.init();register_walls();grant(2)
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=2,revision=2,reason='archive_commerce_purchase'})
if arg[2]=='baseline' then
 check(research_writes[2]==0 and spawn[2]==nil and created==0 and #cannons==0,'baseline reproduces pending effects without timer')
 check(clock==0,'paused fake game time has not advanced')
 tick();check(research_writes[2]==2 and spawn[2]==1 and created==1 and #cannons==1,'same authoritative ownership applies only after timer')
 print('COMMERCE_IMMEDIATE_BASELINE_REPRODUCED checks='..checks);return
end
check(clock==0 and not capacity[0] and not capacity[1] and not capacity[3],'profile edge only reconciles selected owner without tick')
check(levels[2]['RS-06']==5 and levels[2]['RS-08']==5 and research_writes[2]==2,'two research grants immediate')
check(capacity[2]==1 and spawn[2]==1,'capacity and immortal immediate')
check(created==1 and #cannons==1 and cannons[1].survival_visual_only,'owner visuals immediate')
check(heroes[2].survival_commerce_title and not heroes[0].survival_commerce_title,'title belongs only to purchaser')
check(damage==0,'profile changes never execute periodic flame damage')
local reads=ownership_reads;local hr=hero_reads[2]
for i=1,100 do bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=2,revision=2+i,reason='archive_online_checkpoint'}) end
check(capacity[2]==1 and spawn[2]==1 and created==1 and #cannons==1 and research_writes[2]==2,'duplicate unchanged entitlements no grants/native recreation')
check(lookups[2]==1 and hero_reads[2]==hr,'duplicate events do not scan buildings or request heroes')
local repeated_reads=ownership_reads-reads
check(repeated_reads==1400,'fixed scalar ownership reads: 14 per unchanged event independent of inventory/world size')
grant(0);bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0,revision=2,reason='archive_lottery_draw'})
check(capacity[0]==1 and spawn[0]==1 and research_writes[0]==2 and research_writes[2]==2,'second guest isolated from first owner')
check(created==2 and #cannons==2 and lookups[0]==1,'guest receives own resources')
entitlement[2]={};bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=2,revision=104,reason='profile_replace'})
check(particles[1].release==1 and cannons[1].removals==1 and particles[2].release==0 and cannons[2].removals==0,'entitlement revoke retires only affected owner visuals')
check(damage==0,'all profile event paths leave periodic damage untouched')
cities[1]=nil;entitlement[1]={immortal=true};bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=1,revision=2})
enemy.survival_player_id=0
for i=1,5 do tick() end
check(damage==5,'periodic damage remains once per tick, never on profile edge')
check(lookups[1]==1 and spawn[1]==nil,'missing city uses one initial index lookup, no repeated list scans')
cities[1]=unit(1);bus.emit(events.BUILDING_CREATED,{player_id=1,building_id='main_city',unit=cities[1]});tick()
check(lookups[1]==1 and spawn[1]==1,'later city event fills index without scene rescan')
local before_capacity=capacity[3] or 0;owners[3]=false;grant(3);bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=3,revision=2})
check((capacity[3] or 0)==before_capacity and spawn[3]==nil,'defeated owner ignored')
local oldtick=tasks.commerce_runtime;local before=research_writes[3]
current_world={};owners[3]=true;bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=3,revision=3})
check(research_writes[3]==before,'old world subscription does not touch new world')
runtime.init();check(oldtick()==false,'old scheduled callback invalid after init')
print('COMMERCE_IMMEDIATE_PASS checks='..checks..' duplicate_events=100 ownership_reads='..repeated_reads..' duplicate_building_reads=0 duplicate_hero_reads=0 real_http=0 native_fps=NOT_MEASURED')
