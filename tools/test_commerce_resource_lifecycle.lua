package.path='scripts/vscripts/?.lua;'..package.path
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
        IsNull=function(s)return s.null end,IsAlive=function(s)return s.alive end,
        GetTeamNumber=function()return 2 end,GetAbsOrigin=function()return {x=0,y=0,z=0} end,
        GetStrength=function()return 2 end,GetAgility=function()return 3 end,GetIntellect=function()return 5 end,
        entindex=function(s)return s.id end,SetHullRadius=function()end,SetAttackCapability=function()end,
        AddNewModifier=function()end,RemoveSelf=function(s)s.removals=s.removals+1;s.null=true end}
end
for id=0,3 do owners[id]=true;owned[id]=true;heroes[id]=unit(id);walls[id]=unit(id) end
package.loaded['systems/player_context_service']={is_defeated=function(id)return not owners[id] end,
    active_player_ids=function()local ids={};for id=0,3 do if owners[id] then ids[#ids+1]=id end end;return ids end}
package.loaded['systems/commerce_effects']={owned=function(id,key)
    return owned[id] and (key=='orbital' or key=='lottery_immortal_slaying_sword_array') or false
end,invalidate=function()end}
package.loaded['systems/worker_system']={refresh_commerce_capacity=function()end}
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
bus.handle_request(events.HERO_SUMMON_GET_REQUEST,function(p)return {unit=heroes[p.player_id]}end)
local runtime=require('systems/commerce_runtime')
local function register_walls()for id=0,3 do if walls[id] then bus.emit(events.BUILDING_CREATED,{player_id=id,building_id='wall',unit=walls[id]}) end end end
local function tick()assert(tasks.commerce_runtime());clock=clock+1 end
local function sums()
    local d,r,n=0,0,0
    for _,p in pairs(particles) do d=d+p.destroy;r=r+p.release end
    for _,u in ipairs(cannons) do n=n+u.removals end
    return d,r,n
end
runtime.init();register_walls();tick()
assert(created==4 and #cannons==4,'four owners retain their individual visuals')
for i=1,5 do tick() end
assert(created==4 and #cannons==4,'healthy persistent visuals are reused')
local before_d,before_r,before_n=sums()
owners[0]=false;bus.emit(events.PLAYER_DEFEATED,{player_id=0})
assert(particles[1].destroy==1 and particles[1].release==1 and cannons[1].removals==1,'defeat explicitly releases excluded owner')
for i=2,4 do assert(particles[i].release==0 and cannons[i].removals==0,'other owners untouched') end
bus.emit(events.PLAYER_DEFEATED,{player_id=0});tick()
assert(created==4 and particles[1].release==1 and cannons[1].removals==1,'repeated defeat is idempotent')
local oldhero=heroes[1];heroes[1]=nil
runtime.orbital(1,'nothing')
bus.emit(events.HERO_REMOVED,{player_id=1,unit=oldhero})
assert(particles[2].release==1 and cannons[2].removals==0,'hero removal releases aura, retains wall cannon')
heroes[1]=unit(1);tick();local replacement_aura=created
runtime.orbital(1,'wave:1');local shot=tasks.commerce_orbital_1;assert(shot)
bus.emit(events.HERO_REMOVED,{player_id=1,unit=oldhero})
assert(particles[replacement_aura].release==0 and tasks.commerce_orbital_1==shot,'late old-hero event cannot erase new aura/orbit')
bus.emit(events.HERO_REMOVED,{player_id=1,unit=heroes[1]})
assert(particles[replacement_aura].release==1 and not tasks.commerce_orbital_1,'exact orbital owner removal cancels its task')
tick()
local oldwall=walls[2];bus.emit(events.BUILDING_DESTROYED,{player_id=2,building_id='wall',unit=oldwall})
assert(cannons[3].removals==1 and particles[3].release==0,'wall lifecycle affects cannon only')
walls[2]=unit(2);bus.emit(events.BUILDING_CREATED,{player_id=2,building_id='wall',unit=walls[2]});tick()
local replacement_cannon=cannons[#cannons]
bus.emit(events.BUILDING_DESTROYED,{player_id=2,building_id='wall',unit=oldwall})
assert(replacement_cannon.removals==0,'stale wall cannot retire new cannon')
walls[2]=unit(2);bus.emit(events.BUILDING_CREATED,{player_id=2,building_id='wall',unit=walls[2]});tick()
assert(replacement_cannon.removals==1 and cannons[#cannons].removals==0,'direct wall replacement refreshes only its cannon anchor')
owned[3]=false;tick()
assert(particles[4].release==1 and cannons[4].removals==1,'revoked entitlement releases resources')
owned[3]=true;tick()
local old_tick=tasks.commerce_runtime
local oldshot;runtime.orbital(2,'wave:1');oldshot=tasks.commerce_orbital_2
local pending={};for id,p in pairs(particles) do if p.release==0 then pending[#pending+1]=id end end
local live_cannons={};for _,u in ipairs(cannons) do if not u.null then live_cannons[#live_cannons+1]=u end end
failures.destroy=true;failures.release=true
runtime.init();failures={}
for _,id in ipairs(pending) do assert(particles[id].destroy==1 and particles[id].release==1,'Destroy failure still attempts Release once') end
for _,u in ipairs(live_cannons) do assert(u.removals==1,'same-world init retires owned cannon') end
assert(old_tick()==false and oldshot()==false,'stale callbacks cannot run after reset')
local count=0;for _ in pairs(listeners) do count=count+1 end;assert(count==1,'init has one native action listener')
register_walls();tick()
local d,r,n=sums();current_world={};runtime.init()
local d2,r2,n2=sums();assert(d2==d and r2==r and n2==n,'new world must never release potentially reused old particle IDs/entities')
-- Fallback native managers with no unregister API still keep one delegating listener.
CustomGameEventManager={RegisterListener=function()listener_count=listener_count+1 end}
runtime.init();local one=listener_count;runtime.init();assert(listener_count==one,'nil listener token cannot cause repeated registration')
CustomGameEventManager={RegisterListener=function()listener_count=listener_count+1;return listener_count end,
    UnregisterListener=function()return false end}
runtime.init();local rejected_listener_count=listener_count;runtime.init()
assert(listener_count==rejected_listener_count,'rejected unregister retains the original delegating listener')
print('COMMERCE_RESOURCE_LIFECYCLE_PASS: four owners, steady reuse, defeat, exact hero/wall, entitlement, failures, init, old-world handles, callback and listener ownership')
