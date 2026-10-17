-- Real worker/queue/resource/multiplayer services and event bus. Native death
-- is asynchronous, then ordinary player cleanup removes its pending victim.
package.path='scripts/vscripts/?.lua;'..package.path
local noop=function() end
package.loaded['systems/technology_stat_manager']={get=function() return {final={lumberjack={}}} end}
package.loaded['systems/player_profile_service']={get_profile=function(id)
    return {save={gameplay_stats={initial_wood=1000000,initial_gold=1000000,initial_population_cap=500+id}}}
end}
package.loaded['systems/rogue_effect_state_service']={numeric=function() return 0 end}
package.loaded['core/modifier_registry']={ensure=function() return true end}
local online_finals={}
package.loaded['systems/online_time_service']={disconnect=function(id) online_finals[id]=(online_finals[id] or 0)+1 end}
package.loaded['systems/gameplay_phase_guard']={post_clear_frozen=function() return false end}
DOTA_TEAM_GOODGUYS,DOTA_TEAM_BADGUYS=2,3
DOTA_UNIT_TARGET_TEAM_BOTH,DOTA_UNIT_TARGET_ALL,DOTA_UNIT_TARGET_FLAG_NONE,FIND_ANY_ORDER=3,55,0,0
DOTA_UNIT_CAP_NO_ATTACK,DOTA_UNIT_CAP_MELEE_ATTACK,DOTA_UNIT_CAP_RANGED_ATTACK=0,1,2
local vector={__add=function(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end}
Vector=function(x,y,z) return setmetatable({x=x,y=y,z=z or 0},vector) end
local now=0
GameRules={GetGameTime=function() return now end}
GridNav={IsTraversable=function() return true end,IsBlocked=function() return false end}
GetGroundHeight=function() return 128 end;FindUnitsInRadius=function() return {} end
FindClearSpaceForUnit,RandomFloat=noop,function() return 0 end
local bus,events=require('core/event_bus'),require('core/events')
local scheduler=require('core/scheduler')
local multiplayer=require('systems/multiplayer_player_service')
local context=require('systems/player_context_service')
local resources=require('systems/resource_system')
local workers=require('systems/worker_system')
local units,cities,buildings,pending_deaths,changed,cleaned,errors={},{},{},{},{},{},{}
local force_kill_mode='async'
local original_print=print
print=function(message)
    if tostring(message):find('[EventBus] handler error',1,true) or tostring(message):find('[Scheduler] task failed',1,true) then
        errors[#errors+1]=message
    end
end
package.loaded['systems/worker_visual_service']={
    apply=noop,
    cleanup=function(unit) if unit then cleaned[unit]=(cleaned[unit] or 0)+1 end end,
}
local function upvalue(wanted)
    local seen={}
    local function visit(fn)
        if type(fn)~='function' or seen[fn] then return nil end;seen[fn]=true
        for i=1,100 do
            local key,value=debug.getupvalue(fn,i);if not key then break end
            if key==wanted then return value end
            if type(value)=='function' then local found=visit(value);if found~=nil then return found end end
        end
    end
    for _,fn in pairs(workers) do local found=visit(fn);if found~=nil then return found end end
    error('Missing real worker upvalue '..wanted)
end
local function wallet(id) return bus.request(events.RESOURCE_GET_REQUEST,{player_id=id}) end
local function list(id) return bus.request(events.WORKER_LIST_REQUEST,{player_id=id}) end
local function cache_count(id)
    local count=0;for _,entry in pairs(upvalue('workers')) do if entry.player_id==id then count=count+1 end end;return count
end
local function entity(id,index,city)
    local u={id=id,index=index,alive=true,abilities={},position=Vector(id*3000,0,128)}
    function u:IsNull() return self.removed==true end
    function u:IsAlive() return self.alive end
    function u:IsRealHero() return false end
    function u:entindex() return self.index end
    function u:GetAbsOrigin() return self.position end
    function u:GetHullRadius() return city and 128 or 0 end
    function u:GetTeamNumber() return 2 end
    function u:GetPlayerOwnerID() return self.id end
    function u:HasModifier() return false end
    function u:FindModifierByName() return nil end
    function u:FindAbilityByName(name) return self.abilities[name] end
    function u:AddAbility(name)
        local a={level=0};function a:GetLevel() return self.level end;function a:SetLevel(v) self.level=v end
        function a:GetAbilityName() return name end;self.abilities[name]=a;return a
    end
    function u:RemoveAbility(name) self.abilities[name]=nil end
    function u:SetControllableByPlayer(owner) self.id=owner end
    function u:ForceKill()
        self.kill_calls=(self.kill_calls or 0)+1;self.alive=false
        if force_kill_mode=='immediate' then
            bus.emit(events.ENGINE_ENTITY_KILLED,{victim=self,victim_entindex=self.index})
        else pending_deaths[#pending_deaths+1]={victim=self,victim_entindex=self.index} end
    end
    function u:Stop() end
    local modifier=setmetatable({IsNull=function() return false end},{__index=function() return noop end})
    function u:AddNewModifier() return modifier end
    setmetatable(u,{__index=function(_,key) if key:match('^Set') or key=='Script_SetAttackRange' then return noop end end})
    return u
end
PlayerResource={IsValidPlayerID=function(_,id) return id>=0 and id<=3 end,GetPlayer=function(_,id) return id>=0 and id<=3 and {} end,
    GetTeam=function() return 2 end,GetSelectedHeroEntity=function() return nil end}
HeroList={GetAllHeroes=function() return {} end}
Entities={FindAllByClassname=function() return units end}
UTIL_Remove=function(u) u.removed=true end
CreateUnitByName=function(name,position)
    local u=entity(0,100+#units,false);u.position=position
    units[#units+1]=u;return u
end
EntIndexToHScript=function(index)
    for _,u in ipairs(units) do if u.index==index and not u.removed then return u end end
    return buildings[index] and buildings[index].unit
end
local function reset()
    scheduler.clear();bus.reset();context._reset_for_test();multiplayer._reset_for_test()
    now=0;units,cities,buildings,pending_deaths,changed,cleaned,errors={},{},{},{},{},{},{}
    online_finals={};force_kill_mode='async'
    resources.init();workers.init()
    for id=0,3 do
        multiplayer.mark_connected(id);bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=id})
        local city=entity(id,10+id,true);cities[id]=city
        buildings[city.index]={unit=city,entindex=city.index,player_id=id,team=2,building_id='main_city',level=5}
        -- Other assets/reservations remain occupied; a worker cleanup may not
        -- force the entire account population to zero or alter its cap.
        assert(bus.request(events.RESOURCE_TRY_SPEND_REQUEST,{player_id=id,population=19+id}).ok)
    end
    bus.handle_request(events.BUILDING_QUERY_REQUEST,function(p) return buildings[p.entindex] end)
    bus.handle_request(events.BUILDING_LIST_REQUEST,function(p) return {ok=true,buildings={buildings[cities[p.player_id].index]}} end)
    bus.subscribe(events.WORKER_CHANGED,function(p) if p.removed then changed[#changed+1]=p end end)
end
local function train(id,level)
    local result,err=bus.request(events.WORKER_TRAIN_REQUEST,{city=cities[id],player_id=id,
        training_id=string.format('train_lumberjack_%02d',level)})
    assert(not err,err);assert(result and result.ok);return result
end
local function tick(time) now=time;scheduler.think() end
local function flush_swallowed_deaths()
    -- Mirrors cleanup_remaining_units: the native body was removed before an
    -- asynchronous entity_killed delivery. No useful death callback survives.
    for _,pending in ipairs(pending_deaths) do assert(pending.victim.removed) end
    pending_deaths={}
end
local function ordinary_late_death(u)
    bus.emit(events.ENGINE_ENTITY_KILLED,{victim=nil,victim_entindex=u.index})
    bus.emit(events.ENGINE_ENTITY_KILLED,{victim=u,victim_entindex=u.index})
end
local function fixture_with_workers_and_queue()
    reset()
    for id=0,3 do train(id,1) end;tick(1)
    for id=0,3 do train(id,2) end;tick(2)
    local owner_units={}
    for id=0,3 do owner_units[id]={};for _,r in ipairs(list(id)) do owner_units[id][#owner_units[id]+1]=r.unit end
        assert(#owner_units[id]==2 and cache_count(id)==2)
    end
    -- One paid active job and one uncharged wait item belong only to owner0.
    local before=wallet(0);train(0,3);train(0,4)
    local spent=wallet(0)
    local delta={wood=before.wood-spent.wood,gold=before.gold-spent.gold,population=spent.population-before.population}
    assert(delta.population>0 and upvalue('training_queue'):reserved(0,'train_lumberjack_04')==1)
    return owner_units,before,delta
end

local roster,before,delta=fixture_with_workers_and_queue()
local survivor={};for id=1,3 do survivor[id]=wallet(id) end
assert(multiplayer.defeat(0,'wall_destroyed'))
flush_swallowed_deaths()
assert(#list(0)==0,'Native bodies disappear independently of logical retirement')
assert(wallet(0).population==19,
    'DEFEAT_POPULATION_RACE: cached workers must release their actual population before native victims disappear')
assert(cache_count(0)==0 and #changed==2 and wallet(0).max_population==before.max_population)
assert(wallet(0).wood==before.wood and wallet(0).gold==before.gold,'Only the paid pending job refunds currency')
assert(upvalue('training_queue'):reserved(0,'train_lumberjack_03')==0 and upvalue('training_queue'):reserved(0,'train_lumberjack_04')==0)
for _,u in ipairs(roster[0]) do assert(u.kill_calls==1 and cleaned[u]==1);ordinary_late_death(u) end
bus.emit(events.PLAYER_DEFEATED,{player_id=0});bus.emit(events.PLAYER_DISCONNECTED,{player_id=0,defeat_cleanup=true})
assert(wallet(0).population==19 and cache_count(0)==0 and #changed==2 and online_finals[0]==1)
for id=1,3 do assert(#list(id)==2 and cache_count(id)==2 and wallet(id).population==survivor[id].population
    and wallet(id).wood==survivor[id].wood and wallet(id).gold==survivor[id].gold) end
tick(3);assert(#list(0)==0 and cache_count(0)==0,'Cancelled queue callbacks cannot respawn defeated workers')
assert(#errors==0,table.concat(errors,'\n'))

-- Synchronous native callbacks also see retirement and cannot refund twice.
roster,before,delta=fixture_with_workers_and_queue();force_kill_mode='immediate'
assert(multiplayer.defeat(0,'wall_destroyed'))
assert(wallet(0).population==19 and cache_count(0)==0 and #changed==2)
for _,u in ipairs(roster[0]) do assert(u.kill_calls==1 and cleaned[u]==1) end
assert(#errors==0,table.concat(errors,'\n'))

-- Ordinary death keeps its established cleanup; an invalid cached corpse
-- must still retire on disconnect without requiring a live victim handle.
roster,before,delta=fixture_with_workers_and_queue()
local u=roster[1][1];local own_before=wallet(1).population
local population=upvalue('workers')[u.index].population
u.alive=false;bus.emit(events.ENGINE_ENTITY_KILLED,{victim=u,victim_entindex=u.index})
assert(wallet(1).population==own_before-population and cache_count(1)==1 and cleaned[u]==1)
ordinary_late_death(u);assert(wallet(1).population==own_before-population and cleaned[u]==1)
local stale=roster[1][2];stale.removed=true
bus.emit(events.PLAYER_DISCONNECTED,{player_id=1,defeat_cleanup=true})
assert(wallet(1).population==20 and cache_count(1)==0 and cleaned[stale]==1 and not stale.kill_calls)
assert(cache_count(0)==2 and cache_count(2)==2 and cache_count(3)==2)
assert(#errors==0,table.concat(errors,'\n'))
print=original_print
print('WORKER_DEFEAT_POPULATION_CLEANUP_PASS: real worker/queue/resource/multiplayer lifecycle; asynchronous kill/remove swallowing; synchronous logical population and quota retirement; paid-only queue refund; repeated cleanup/late deaths; native reentry; invalid victims; ordinary death retained; four-owner isolation and other-asset reservation preservation')
