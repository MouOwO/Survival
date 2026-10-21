package.path = "scripts/vscripts/?.lua;" .. package.path
require("tests/development_release_profile")
-- Offline engine-boundary simulation. Production wave scheduling/factories,
-- player context, collision policy, navigation boundary, contacts and wall AI.
-- Native MOVE acceptance, delayed phase, straight-line terrain/hull movement
-- and attack notification are simulated; this does not certify Workshop physics.
package.path = 'scripts/vscripts/?.lua;' .. package.path
io.stdout:setvbuf('no')
local MODE = arg[1]=='final' and 'final' or (arg[1]=='negative' and 'negative' or (arg[1]=='portal-negative' and 'portal-negative' or 'baseline'))
local OUT = MODE=='baseline' and arg[1] or arg[2]
OUT = OUT or 'output/four_player_stress_20261012'
local STEM = 'wave_wall_'..MODE
if MODE=='negative' then
    package.preload['systems/wave_system']=assert(loadfile(OUT..'/baseline_source/scripts/vscripts/systems/wave_system.lua'))
    package.preload['modifiers/modifier_enemy_wall_ai']=assert(loadfile(OUT..'/baseline_source/scripts/vscripts/modifiers/modifier_enemy_wall_ai.lua'))
end
if MODE=='portal-negative' then
    package.preload['systems/wall_target_service']=assert(loadfile(OUT..'/wall_target_portal_bounds_negative.lua'))
end
local noop = function() end
local clock, serial, mode = 0, 0, {}
local entities, monsters, walls, markers, controllers = {}, {}, {}, {}, {}
local emitted, ticks, failures, round = {}, {}, {}, nil
local nav_queries, paths, collisions = 0, 0, 0
local can_path_queries, center_path_queries = 0, 0
local spacing_samples, min_sample_rear_gap, min_sample_front_gap = 0, math.huge, math.huge
local function copy(p) return Vector(p.x,p.y,p.z) end
local function distance(a,b) local x,y=a.x-b.x,a.y-b.y;return math.sqrt(x*x+y*y) end
Vector=function(x,y,z) return {x=x,y=y,z=z or 0} end
DOTA_TEAM_GOODGUYS,DOTA_TEAM_BADGUYS=2,3
DOTA_UNIT_CAP_MELEE_ATTACK,DOTA_UNIT_CAP_RANGED_ATTACK=1,2
DOTA_UNIT_CAP_MOVE_GROUND,DOTA_UNIT_CAP_MOVE_FLY=1,2
DOTA_UNIT_ORDER_ATTACK_TARGET,DOTA_UNIT_ORDER_MOVE_TO_POSITION=2,3
MODIFIER_STATE_ROOTED,MODIFIER_STATE_DISARMED,MODIFIER_STATE_NO_UNIT_COLLISION=4,5,6
MODIFIER_ATTRIBUTE_PERMANENT,LUA_MODIFIER_MOTION_NONE=7,0
DOTA_GAMERULES_STATE_POST_GAME=8
IsServer,IsInToolsMode=function() return true end,function() return true end
class=function(t) return t end;LinkLuaModifier=noop
GameRules={GetGameTime=function() return clock end,State_Get=function() return 7 end,
    GetGameModeEntity=function() return mode end}
GetGroundHeight=function() return 384 end
GetMapName=function() return 'offline_four_player_geometry' end
PlayerResource={IsValidPlayerID=function(_,id) return id>=0 and id<=3 end,
    GetPlayer=function(_,id) return id>=0 and id<=3 and {id=id} end,
    GetTeam=function() return 2 end,IsFakeClient=function() return true end}
EntIndexToHScript=function(id) return entities[id] end
Entities={FindByName=function(_,_,name) return markers[name] end,
    FindAllByClassname=function() local r={};for _,u in pairs(entities) do r[#r+1]=u end;return r end}
-- Density lanes are local gate fixtures. Primary spawn/target probes use open
-- terrain except the actual wall squares and explicitly unreachable wall.
local local_gates=false
local function terrain(p)
    if not local_gates then return true end
    for _,w in ipairs(walls) do
        if math.abs(p.y-w.p.y)<128 and p.x<=w.p.x+128 then return true end
    end
    return false
end
GridNav={IsTraversable=function(_,p) nav_queries=nav_queries+1;return terrain(p) end,
    IsBlocked=function(_,p)
        nav_queries=nav_queries+1
        for _,w in ipairs(walls) do if w:IsAlive() and math.abs(p.x-w.p.x)<128 and math.abs(p.y-w.p.y)<128 then return true end end
        return false
    end,FindPathLength=function(_,a,b)
        paths=paths+1
        for _,w in ipairs(walls) do if w.unreachable and distance(b,w.p)<600 then return -1 end end
        return distance(a,b)
    end}
GridNav.CanFindPath=function(_,a,b)
    can_path_queries=can_path_queries+1
    for _,w in ipairs(walls) do
        if distance(b,w.p)<128 then center_path_queries=center_path_queries+1;return false end
    end
    return GridNav:FindPathLength(a,b)>=0
end
local ai
local function controller(u,params)
    local m=setmetatable({stack=0},{__index=ai})
    function m:GetParent() return u end
    function m:GetStackCount() return self.stack end
    function m:SetStackCount(v) self.stack=v end
    function m:StartIntervalThink(interval) self.interval=interval;self.next_think=clock+(interval==0 and .05 or interval) end
    function m:ForceRefresh() if self.OnRefresh then self:OnRefresh({}) end;u.phase_refresh_pending=true end
    m.SetHasCustomTransmitterData,m.SendBuffRefreshToClients=noop,noop
    u.ai=m;controllers[#controllers+1]=m;m:OnCreated(params);return m
end
local function unit(name,p,team)
    serial=serial+1
    local u={id=serial,name=name,p=copy(p),team=team or 3,radius=32,original_radius=32,
        modifiers={},abilities={},orders=0,stops=0,corrections=0,hits=0,next_attack=0,attack_range=128,
        attack_capability=1,speed=240,move_distance=0,collision_blocks=0}
    function u:entindex() return self.id end
    function u:IsNull() return self.removed==true end
    function u:IsAlive() return not self.dead and not self.removed end
    function u:GetAbsOrigin() return self.p end
    function u:SetAbsOrigin(p) self.p=copy(p);self.corrections=self.corrections+1 end
    function u:GetHullRadius() return self.radius end
    function u:SetHullRadius(v) self.radius=v end
    function u:GetPaddedCollisionRadius() return self.radius+10 end
    function u:GetTeamNumber() return self.team end
    function u:SetTeam(v) self.team=v end
    function u:SetTeamNumber(v) self.team=v end
    function u:GetPlayerOwnerID() return self.survival_player_id or -1 end
    function u:GetUnitName() return self.name end
    function u:GetForwardVector() return Vector(0,1,0) end
    function u:GetAttackCapability() return self.attack_capability end
    function u:SetAttackCapability(v) self.attack_capability=v end
    function u:GetMoveCapability() return self.move_capability or 1 end
    function u:SetMoveCapability(v) self.move_capability=v end
    function u:Script_SetAttackRange(v) self.attack_range=v end
    function u:Script_GetAttackRange() return self.attack_range+(self.ai and self.ai.contact_range_delta or 0) end
    function u:GetAttacksPerSecond() return 1 end
    function u:SetBaseMoveSpeed(v) self.speed=v end
    function u:GetForceAttackTarget() return self.force end
    function u:SetForceAttackTarget(v) self.force=v end
    function u:IsStunned() return self.stunned==true end
    function u:IsCommandRestricted() return false end
    function u:IsRooted() return self.ai and self.ai:CheckState()[MODIFIER_STATE_ROOTED] end
    function u:IsDisarmed() return self.ai and self.ai:CheckState()[MODIFIER_STATE_DISARMED] end
    function u:IsInvulnerable() return false end
    function u:IsIdle() return self.order==nil end
    function u:Stop() self.stops=self.stops+1;self.order=nil end
    function u:HasModifier(name) return self.modifiers[name]~=nil end
    function u:FindModifierByName(name) return self.modifiers[name] end
    function u:RemoveModifierByName(name) self.modifiers[name]=nil end
    function u:AddNewModifier(_,_,name,params)
        local m=name=='modifier_enemy_wall_ai' and controller(self,params) or params
        self.modifiers[name]=m;return m
    end
    function u:FindAbilityByName(name) return self.abilities[name] end
    function u:AddAbility(name) local a={};a.SetLevel=noop;self.abilities[name]=a;return a end
    for _,name in ipairs({'SetBaseMaxHealth','SetMaxHealth','SetHealth','SetBaseDamageMin','SetBaseDamageMax',
        'SetPhysicalArmorBaseValue','SetBaseAttackTime','SetModel','SetOriginalModel','SetModelScale','SetSize','SetAcquisitionRange'}) do u[name]=noop end
    entities[u.id]=u;return u
end
CreateUnitByName=function(name,p,_,_,_,team)
    local u=unit(name,p,team);monsters[#monsters+1]=u;return u
end
-- Native placement does not set contact coordinates. Gate density formation
-- below explicitly resets only initial spawns, never an AI destination.
FindClearSpaceForUnit=function(u,p) u.p=copy(p) end
UTIL_Remove=function(u) u.removed=true end
ListenToGameEvent=function() return 1 end;StopListeningToGameEvent=noop
ExecuteOrderFromTable=function(order)
    local u=assert(entities[order.UnitIndex]);u.orders=u.orders+1
    u.order={OrderType=order.OrderType,TargetIndex=order.TargetIndex,Position=order.Position and copy(order.Position)}
end
-- Only external account/cosmetic/asset boundaries are replaced. No target,
-- routing, wave definitions, scheduling, factories or collision code is mocked.
package.loaded['systems/asset_preload_service']={queue=function() return true end,
    status=function() return {status='ready'} end,STATE={READY='ready',FAILED='failed',RETIRED='retired'}}
package.loaded['config/asset_catalog']={for_model=function() return nil end}
package.loaded['config/monster_visual_config']={resolve=function() return nil end}
package.loaded['systems/monster_visual_service']={cleanup=noop,apply=noop,queue_wave=noop}
package.loaded['systems/monster_hero_visual_service']={apply=noop,on_death=noop,clear=noop}
package.loaded['systems/monster_corpse_lifecycle_service']={track=noop}
package.loaded['systems/match_setup_service']={is_mode_selected=function() return true end,
    get_mode=function() return 'standard' end,selector_player_id=function() return 0 end}
package.loaded['systems/startup_loading_service']={is_gameplay_ready=function() return true end}
package.loaded['systems/player_profile_service']={get_progression=function(id)
    return {loaded=true,clear_counts={n5=1,n6=1,n7=1,n8=1,n9=1},archive_level=id*3+1}
end}
package.loaded['systems/multiplayer_player_service']={is_defeated=function() return false end,
    all_participants_defeated=function() return false end,defeat=noop}
-- Explicit engine-map fixture. Legal building lawns extend beyond the four
-- +/-2400 portal coordinates; full 4x4 footprints must fit these real bounds.
package.loaded['config/grid_placement_config']={cell_size=64,
    build_bounds={min_x=-4096,max_x=4096,min_y=-4096,max_y=4096}}
local bus=require('core/event_bus')
local events=require('core/events')
local scheduler=require('core/scheduler')
local context=require('systems/player_context_service')
local contact=require('systems/wall_melee_contact')
local target_service=require('systems/wall_target_service')
local navigation=require('systems/wall_navigation_service')
ai=require('modifiers/modifier_enemy_wall_ai')
local wave=require('systems/wave_system')
local actual_archetypes=require('config/generated/monster_archetypes')
local function upvalue(wanted)
    local seen={}
    local function visit(fn)
        if type(fn)~='function' or seen[fn] then return end;seen[fn]=true
        for i=1,math.huge do local name,value=debug.getupvalue(fn,i);if not name then break end
            if name==wanted then return value end
            if type(value)=='function' then local r=visit(value);if r~=nil then return r end end
        end
    end
    for _,fn in pairs(wave) do local value=visit(fn);if value~=nil then return value end end
    error('Missing production upvalue '..wanted)
end
local function check(ok,code,detail)
    round.checks=round.checks+1
    if not ok then
        local f={round=round.id,code=code,detail=detail};round.failures[#round.failures+1]=f;failures[#failures+1]=f
    end
end
local function reset()
    contact.reset();navigation.clear_all();scheduler.clear();bus.reset();context._reset_for_test()
    clock,serial=0,0;entities,monsters,walls,markers,controllers={},{},{},{},{}
    emitted,ticks={},{};nav_queries,paths,collisions=0,0,0;local_gates=false
    can_path_queries,center_path_queries=0,0
    spacing_samples,min_sample_rear_gap,min_sample_front_gap=0,math.huge,math.huge
    local marker_xy={{2400,0},{0,-2400},{-2400,0},{0,2400}}
    for id=0,3 do markers[context.slot(id).wave_spawn_marker]=unit('marker',Vector(marker_xy[id+1][1],marker_xy[id+1][2],384),2) end
    wave.init();assert(wave.set_difficulty(round.difficulty))
    bus.subscribe(events.MONSTER_SPAWNED,function(p)
        emitted[#emitted+1]={id=p.entindex,owner=p.player_id,time=clock,source=p.monster_source}
        if p.monster_source=='wave' then local k=string.format('%.2f',clock);ticks[k]=(ticks[k] or 0)+1 end
    end)
end
local function add_wall(owner,p)
    local w=unit('npc_survival_wall',p,2);w.radius=128;w.survival_player_id=owner;w.survival_building_id='wall'
    walls[#walls+1]=w;context.register_unit(owner,w,'stress_wall')
    bus.emit(events.BUILDING_CREATED,{building_id='wall',player_id=owner,entindex=w.id,unit=w})
    return w
end
local function phased(u) return u.native_phased==true end
local function move(u,goal,dt)
    if u:IsRooted() then return end
    local remaining=distance(u.p,goal);if remaining<=32 then return end
    local step=math.min(u.speed*dt,remaining-32)
    local np=Vector(u.p.x+(goal.x-u.p.x)*step/remaining,u.p.y+(goal.y-u.p.y)*step/remaining,384)
    if not terrain(np) then return end
    for _,w in ipairs(walls) do if w:IsAlive() and math.abs(np.x-w.p.x)<128+u.radius and math.abs(np.y-w.p.y)<128+u.radius then return end end
    if not phased(u) then for _,other in ipairs(monsters) do
        if other~=u and other:IsAlive() and not phased(other) and distance(np,other.p)<u.radius+other.radius-.01 then
            collisions=collisions+1;u.collision_blocks=u.collision_blocks+1;return
        end
    end end
    u.move_distance=u.move_distance+distance(u.p,np);u.p=np
end
local function frame(dt,physics)
    clock=math.floor((clock+dt)*1000+.5)/1000;scheduler.think()
    if not physics then return end
    for _,u in ipairs(monsters) do if u.phase_refresh_pending then u.native_phased=u.ai:CheckState()[MODIFIER_STATE_NO_UNIT_COLLISION]==true;u.phase_refresh_pending=false end end
    for _,m in ipairs(controllers) do if m:GetParent():IsAlive() and m.next_think and clock+.0001>=m.next_think then
        m.next_think=clock+(m.interval==0 and .05 or m.interval);m:OnIntervalThink()
    end end
    for _,u in ipairs(monsters) do if u:IsAlive() and u.order then
        if u.order.OrderType==3 then move(u,u.order.Position,dt)
        else local w=entities[u.order.TargetIndex]
            if w and w:IsAlive() then
                if distance(u.p,w.p)>u:Script_GetAttackRange()+.01 then move(u,w.p,dt)
                elseif not u:IsDisarmed() and clock>=u.next_attack then u.hits=u.hits+1;u.next_attack=clock+1;u.ai:OnAttackStart({attacker=u,target=w}) end
            end
        end
    end end
    if math.floor(clock*20+.5)%10==0 then
        spacing_samples=spacing_samples+1
        for i=1,#monsters do local a=monsters[i]
            if a:IsAlive() and not phased(a) and a.ai.ai_state~='attack' then
                for j=1,#monsters do local b=monsters[j]
                    if a~=b and b:IsAlive() then local gap=distance(a.p,b.p)-a.radius-b.radius
                        if b.ai.ai_state=='attack' then min_sample_front_gap=math.min(min_sample_front_gap,gap)
                        elseif j>i and not phased(b) then min_sample_rear_gap=math.min(min_sample_rear_gap,gap) end
                    end
                end
            end
        end
    end
end
local function run(seconds,physics) for i=1,math.floor(seconds/.05+.5) do frame(.05,physics) end end
local function spawn_probe()
    reset()
    local xy=round.scenario=='A' and {{1800,-900},{-900,-1800},{-1800,900},{900,1800}} or {{1200,-1800},{1200,-1200},{1200,-600},{1200,-200}}
    for _,owner in ipairs(round.order) do add_wall(owner,Vector(xy[owner+1][1],xy[owner+1][2],384)) end
    assert(wave.debug_spawn_wave_for_players(19,round.order));run(95,false)
    local counts,targets={},{}
    for _,u in ipairs(monsters) do
        counts[u.survival_player_id]=(counts[u.survival_player_id] or 0)+1
        targets[u.survival_player_id]=u.ai.wall_entindex
        check(u.survival_navigation_type=='ground' and u.radius==32,'wave_collision_setup',{id=u.id,radius=u.radius,navigation=u.survival_navigation_type})
    end
    local expected=0;for _,row in ipairs(upvalue('waves')[19].batches) do expected=expected+row.monster_count end
    for id=0,3 do check(counts[id]==expected,'four_lane_count',{player=id,expected=expected,actual=counts[id]}) end
    local distribution={};for _,count in pairs(ticks) do distribution[tostring(count)]=(distribution[tostring(count)] or 0)+1 end
    check(distribution['4']==expected and not distribution['1'] and not distribution['16'],'spawn_tick_four_total',{distribution=distribution,per_lane=expected})
    round.spawn={configured_per_lane=expected,total=#monsters,tick_distribution=distribution,
        markers={'east','south','west','north'},targets=targets,spawn_rule='one configured unit per active lane per spawn_interval; four total per tick'}
    if round.scenario=='B' then
        local wrong=0;for _,u in ipairs(monsters) do if math.abs(u.p.x-2400)>.01 then wrong=wrong+1 end end
        check(wrong==0,'shared_defense_spawn_routing_missing',{non_east_spawns=wrong,total=#monsters,expected='wall group in east shared defense, wall-based portal routing'})
    end
end
local function fallback_probe(kind)
    reset()
    local original=add_wall(0,Vector(0,0,384))
    local nearest=add_wall(1,Vector(-900,0,384))
    local farther=add_wall(2,Vector(-1600,0,384))
    local hidden=unit('npc_survival_wall_collision_barrier',Vector(-950,-80,384),2)
    hidden.survival_wall_collision_barrier=true;hidden.survival_wall_entindex=original.id
    -- Enter the public production formal-wave API and observe its first real
    -- scheduled spawn. Isolate that body by cancelling the remaining fixture
    -- schedule, then set only its non-contact initial test position.
    assert(wave.debug_spawn_wave_for_players(1,{0}));run(3.1,false);scheduler.clear()
    local u=assert(monsters[1]);u.p=Vector(-1050,0,384)
    if kind=='unreachable' then original.unreachable=true
    elseif kind=='outside_defense' then original.p=Vector(12000,12000,384)
    elseif kind=='destroyed' then original.dead=true;bus.emit(events.BUILDING_DESTROYED,{building_id='wall',player_id=0,entindex=original.id,unit=original}) end
    for i=1,12 do u.ai:OnIntervalThink();clock=clock+.5 end
    check(u.ai.wall_entindex==nearest.id,'wall_fallback_'..kind,{unit=u.id,original=original.id,expected=nearest.id,actual=u.ai.wall_entindex,state=u.ai.ai_state,near_path=GridNav:FindPathLength(u.p,nearest.p),farther=farther.id})
    check(u.ai.wall_entindex~=hidden.id,'hidden_collision_wall_not_targeted',{hidden=hidden.id,target=u.ai.wall_entindex})
    round.fallback[#round.fallback+1]={kind=kind,expected=nearest.id,actual=u.ai.wall_entindex,owner=u.survival_player_id,state=u.ai.ai_state}
end
local function crowd_probe(shared_wall)
    reset();local_gates=true
    local wall_by_owner={}
    for _,owner in ipairs(round.order) do
        local w=shared_wall and wall_by_owner[round.order[1]] or nil
        if not w then w=add_wall(owner,Vector(0,(owner-1.5)*1200,384)) end
        wall_by_owner[owner]=w
    end
    -- Four lane spawns still use the public production wave API. For the
    -- isolated same-wall contact test, one wall event per real player owner
    -- deliberately binds the identical wall handle to all four channels.
    if shared_wall then for id=0,3 do bus.emit(events.BUILDING_CREATED,{building_id='wall',player_id=id,entindex=wall_by_owner[id].id,unit=wall_by_owner[id]}) end end
    assert(wave.debug_spawn_wave_for_players(19,round.order));run(95,false)
    local definition={unit_name='npc_stress_endless',model_path='stress.vmdl',endless=true,movement_type='ground',attack_type='melee',move_speed=240,attack_range=128}
    for id=0,3 do for i=1,30 do assert(wave.spawn_challenge_monster({health=200,attack=2},definition,id)) end end
    local per_owner={}
    local ordered={};for _,owner in ipairs(round.order) do for _,u in ipairs(monsters) do if u.survival_player_id==owner then ordered[#ordered+1]=u end end end
    monsters=ordered
    local bywall={}
    for _,u in ipairs(monsters) do
        local w=wall_by_owner[u.survival_player_id];bywall[w.id]=bywall[w.id] or {};local actors=bywall[w.id];actors[#actors+1]=u
        local n=#actors
        -- Only initial starting rows are supplied to the engine fixture.
        -- No actor is assigned a production contact point by this test.
        local row=math.floor((n-1)/3);local ys={-72,0,72}
        local seed_x,seed_y=math.random(0,8),math.random(-2,2)
        u.p=Vector(w.p.x-320-row*80-seed_x,w.p.y+ys[(n-1)%3+1]+seed_y,384)
        u.initial_p=copy(u.p);u.speed=240;per_owner[u.survival_player_id]=(per_owner[u.survival_player_id] or 0)+1
        u.original_owner=u.survival_player_id
        if n==1 then u.p=Vector(w.p.x-224-seed_x,w.p.y-42+seed_y,384)
        elseif n==2 then u.p=Vector(w.p.x-224-seed_x,w.p.y+42+seed_y,384) end
    end
    controllers={};for _,u in ipairs(monsters) do controllers[#controllers+1]=u.ai end
    run(8,true)
    local metrics={total=#monsters,shared_wall=shared_wall,front=0,hits=0,waiting=0,approach=0,
        moved=0,collisions=collisions,corrections=0,min_rear_front_gap=1000000,min_rear_gap=1000000,
        front_owners={},wall_front_counts={},nav_queries=nav_queries,path_queries=paths}
    local front,rear={},{}
    for _,u in ipairs(monsters) do if u:IsAlive() then
        metrics.hits=metrics.hits+u.hits;metrics.moved=metrics.moved+u.move_distance;metrics.corrections=metrics.corrections+u.corrections
        if u.ai.ai_state=='attack' then front[#front+1]=u;metrics.front=metrics.front+1;metrics.front_owners[#metrics.front_owners+1]=u.survival_player_id
            local k=tostring(u.ai.wall_entindex);metrics.wall_front_counts[k]=(metrics.wall_front_counts[k] or 0)+1
            check(u.hits>0,'front_actually_hits',{id=u.id,state=u.ai.ai_state,p=u.p})
            check(u.radius==24 and phased(u),'front_hull_and_native_phase',{id=u.id,radius=u.radius,phase=phased(u)})
        else rear[#rear+1]=u;if u.ai.ai_state=='waiting' then metrics.waiting=metrics.waiting+1 elseif u.ai.ai_state=='approach' then metrics.approach=metrics.approach+1 end end
        check(u.survival_player_id~=nil,'monster_owner_kept',{id=u.id})
    end end
    local expected=shared_wall and 4 or 16
    check(#front==expected,'density_front_hit_count',{expected=expected,actual=#front,total=#monsters,shared_wall=shared_wall})
    for _,w in ipairs(walls) do check(metrics.wall_front_counts[tostring(w.id)]==4,'wall_has_four_independent_contacts',{wall=w.id,actual=metrics.wall_front_counts[tostring(w.id)]}) end
    local occupied={}
    for _,u in ipairs(front) do local k=u.ai.wall_entindex..':'..u.p.y;check(not occupied[k],'contact_cross_claim',{id=u.id,key=k});occupied[k]=true end
    for _,r in ipairs(rear) do
        check(r.hits==0,'rear_does_not_hit',{id=r.id,hits=r.hits,state=r.ai.ai_state})
        if r.ai.ai_state=='waiting' then check(r:IsDisarmed() and not phased(r) and r.radius==32,'rear_keeps_physical_queue',{id=r.id,radius=r.radius,phase=phased(r)}) end
        for _,f in ipairs(front) do local gap=distance(r.p,f.p)-r.radius-f.radius;metrics.min_rear_front_gap=math.min(metrics.min_rear_front_gap,gap) end
    end
    for i=1,#rear do for j=i+1,#rear do if not phased(rear[i]) and not phased(rear[j]) then
        metrics.min_rear_gap=math.min(metrics.min_rear_gap,distance(rear[i].p,rear[j].p)-rear[i].radius-rear[j].radius)
    end end end
    check(metrics.min_rear_front_gap>=-.01,'rear_front_physical_spacing',{minimum_gap=metrics.min_rear_front_gap})
    check(metrics.min_rear_gap>=-.01,'rear_neighbor_physical_spacing',{minimum_gap=metrics.min_rear_gap})
    check(spacing_samples>=15 and min_sample_rear_gap>=-.01 and min_sample_front_gap>=-.01,
        'density_spacing_over_time',{samples=spacing_samples,rear_min=min_sample_rear_gap,front_min=min_sample_front_gap})
    metrics.spacing_samples=spacing_samples;metrics.sample_rear_min=min_sample_rear_gap;metrics.sample_front_min=min_sample_front_gap
    check(metrics.moved>0 and collisions>0,'density_real_movement_and_neighbor_blocks',{moved=metrics.moved,blocks=collisions})
    local stable_orders,stable_stops,stable_corrections=0,0,0
    for _,u in ipairs(monsters) do stable_orders=stable_orders+u.orders;stable_stops=stable_stops+u.stops;stable_corrections=stable_corrections+u.corrections end
    local stable_paths=target_service._snapshot_for_test().path_queries
    local stable_observations=target_service._snapshot_for_test().observations
    -- Hold positions for stable-observation checks. Attack events continue;
    -- this isolates AI work from ordinary arrivals changing native goals.
    for frame_index=1,4 do
        clock=clock+.5
        for _,u in ipairs(monsters) do
            if u.ai.ai_state=='attack' then u.ai:OnAttackStart({attacker=u,target=entities[u.ai.wall_entindex]}) end
            u.ai:OnIntervalThink()
        end
    end
    local after_orders,after_stops,after_corrections=0,0,0
    for _,u in ipairs(monsters) do after_orders=after_orders+u.orders;after_stops=after_stops+u.stops;after_corrections=after_corrections+u.corrections end
    metrics.stable_orders=after_orders-stable_orders;metrics.stable_stops=after_stops-stable_stops
    metrics.stable_coordinates=after_corrections-stable_corrections
    metrics.stable_resolver_paths=target_service._snapshot_for_test().path_queries-stable_paths
    metrics.stable_resolver_observations=target_service._snapshot_for_test().observations-stable_observations
    check(metrics.stable_resolver_paths==0 and metrics.stable_orders==0 and metrics.stable_stops==0 and metrics.stable_coordinates==0,
        'stable_density_no_query_or_order_amplification',{orders=metrics.stable_orders,stops=metrics.stable_stops,coordinates=metrics.stable_coordinates,resolver_paths=metrics.stable_resolver_paths})
    check(metrics.stable_resolver_observations<=5,'shared_wall_observation_is_bounded',{observations=metrics.stable_resolver_observations,total=#monsters})
    -- Kill one live contact per wall. Real AI/contact service must promote a
    -- waiting body without changing its player lane ownership.
    local kill_candidates={};local before={};for _,f in ipairs(front) do before[f.id]=true
        kill_candidates[f.ai.wall_entindex]=kill_candidates[f.ai.wall_entindex] or {};table.insert(kill_candidates[f.ai.wall_entindex],f)
    end
    for _,candidates in pairs(kill_candidates) do candidates[math.random(1,#candidates)].dead=true end
    run(5,true)
    local replacement_hits=0;for _,u in ipairs(monsters) do if not before[u.id] and u.ai.ai_state=='attack' and u.hits>0 then replacement_hits=replacement_hits+1 end end
    for _,u in ipairs(monsters) do check(u.survival_player_id==u.original_owner,'owner_unchanged_after_replacement',{id=u.id,expected=u.original_owner,actual=u.survival_player_id}) end
    check(replacement_hits==(shared_wall and 1 or 4),'density_death_replacement_hits',{expected=shared_wall and 1 or 4,actual=replacement_hits})
    metrics.replacement_hits=replacement_hits;round.crowds[#round.crowds+1]=metrics
end
local function target_edges()
    reset()
    local own=add_wall(0,Vector(0,0,384))
    local near=add_wall(1,Vector(-900,0,384))
    assert(wave.debug_spawn_wave_for_players(1,{0}));run(3.1,false);scheduler.clear()
    local u=monsters[1];u.p=Vector(-1050,0,384);u.stunned=true
    local before_stops=u.stops
    own.dead=true;bus.emit(events.BUILDING_DESTROYED,{building_id='wall',player_id=0,entindex=own.id,unit=own})
    u.ai:HandleDeath({unit=own})
    u.ai:OnIntervalThink()
    check(u.ai.wall_entindex==own.id and u.stops==before_stops,'target_reselection_waits_for_control',{target=u.ai.wall_entindex,stops=u.stops})
    u.stunned=false;clock=clock+.5;u.ai:OnIntervalThink()
    check(u.ai.wall_entindex==near.id,'target_recovers_after_control',{target=u.ai.wall_entindex,expected=near.id})
    own.dead=false;own.p=Vector(-1400,0,384)
    bus.emit(events.BUILDING_CREATED,{building_id='wall',player_id=0,entindex=own.id,unit=own})
    clock=clock+.5;u.ai:OnIntervalThink()
    check(u.ai.wall_entindex==own.id,'reachable_owner_wall_restores_priority',{target=u.ai.wall_entindex,expected=own.id})
    own.p=Vector(3008,0,384);clock=clock+.5;u.ai:OnIntervalThink()
    check(u.ai.wall_entindex==own.id,'legal_wall_outside_portals_keeps_owner_priority',{target=u.ai.wall_entindex,expected=own.id,wall=own.p})
    own.p=Vector(3968,0,384);clock=clock+.5;u.ai:OnIntervalThink()
    check(u.ai.wall_entindex==own.id,'maximum_legal_wall_footprint_keeps_owner_priority',{target=u.ai.wall_entindex,expected=own.id,wall=own.p})
    own.p=Vector(3969,0,384);clock=clock+.5;u.ai:OnIntervalThink()
    check(u.ai.wall_entindex==near.id,'wall_footprint_crossing_bounds_is_excluded',{target=u.ai.wall_entindex,expected=near.id,wall=own.p})
    own.p=Vector(12000,12000,384);clock=clock+.5;u.ai:OnIntervalThink()
    check(u.ai.wall_entindex==near.id,'moved_wall_reselection_without_scan',{target=u.ai.wall_entindex,expected=near.id})
    local hidden=add_wall(2,Vector(-1024,0,384));hidden.survival_wall_collision_barrier=true
    bus.emit(events.BUILDING_CHANGED,{building_id='wall',player_id=2,entindex=hidden.id,unit=hidden})
    local constructing=add_wall(3,Vector(-1100,0,384));constructing.modifiers.modifier_building_under_construction={}
    bus.emit(events.BUILDING_CHANGED,{building_id='wall',player_id=3,entindex=constructing.id,unit=constructing})
    clock=clock+.5;u.ai:OnIntervalThink()
    check(u.ai.wall_entindex==near.id,'hidden_and_construction_targets_excluded',{target=u.ai.wall_entindex,hidden=hidden.id,constructing=constructing.id})
    hidden.survival_wall_collision_barrier=nil;bus.emit(events.BUILDING_CHANGED,{building_id='wall',player_id=2,entindex=hidden.id,unit=hidden})
    bus.emit(events.PLAYER_DEFEATED,{player_id=2,reason='fixture'})
    clock=clock+.5;u.ai:OnIntervalThink()
    check(u.ai.wall_entindex==near.id,'defeated_wall_excluded_without_owner_change',{target=u.ai.wall_entindex,owner=u.survival_player_id})
    check(u.survival_player_id==0 and upvalue('player_populations')[0].alive==1,'fallback_preserves_lane_population',{owner=u.survival_player_id,alive=upvalue('player_populations')[0].alive})
    local before=target_service._snapshot_for_test()
    for i=1,20 do bus.emit(events.BUILDING_CHANGED,{building_id='wall',player_id=1,entindex=near.id,unit=near}) end
    local after=target_service._snapshot_for_test()
    check(before.generation==after.generation,'duplicate_wall_events_are_deduplicated',{before=before.generation,after=after.generation})
    near.dead=true;bus.emit(events.BUILDING_DESTROYED,{building_id='wall',player_id=1,entindex=near.id,unit=near})
    local destroyed_generation=target_service._snapshot_for_test().generation
    for pass=1,20 do bus.emit(events.BUILDING_DESTROYED,{building_id='wall',player_id=1,entindex=near.id,unit=near}) end
    check(target_service._snapshot_for_test().generation==destroyed_generation,'duplicate_wall_destruction_is_deduplicated',
        {before=destroyed_generation,after=target_service._snapshot_for_test().generation})
    clock=clock+.5;u.ai:OnIntervalThink()
    local empty_queries=target_service._snapshot_for_test().path_queries
    for pass=1,6 do clock=clock+.5;u.ai:OnIntervalThink() end
    check(u.ai.wall_entindex==-1 and target_service._snapshot_for_test().path_queries==empty_queries,
        'missing_target_backoff_avoids_repeated_path_queries',{target=u.ai.wall_entindex,queries=target_service._snapshot_for_test().path_queries-empty_queries})
    near.dead=false;bus.emit(events.BUILDING_CREATED,{building_id='wall',player_id=1,entindex=near.id,unit=near})
    clock=clock+.5;u.ai:OnIntervalThink()
    check(u.ai.wall_entindex==near.id,'missing_target_recovers_on_new_wall',{target=u.ai.wall_entindex,expected=near.id})
    check(can_path_queries>0 and center_path_queries==0,'can_find_path_uses_wall_edges',{queries=can_path_queries,wall_center_queries=center_path_queries})
    markers[context.slot(3).wave_spawn_marker]=nil
    local routed=wave.debug_spawn_wave_for_players(1,{1})
    check(not routed,'incomplete_routing_layout_fails_closed',{accepted=routed})
    round.target_edges={before=before,after=after}
end
local function json(v)
    if v==nil then return 'null' elseif type(v)=='boolean' or type(v)=='number' then return tostring(v)
    elseif type(v)=='string' then return '"'..v:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n'):gsub('\r','\\r')..'"'
    elseif type(v)=='table' then
        local isarray=true;local n=0;for k in pairs(v) do if type(k)~='number' or k<1 or k%1~=0 then isarray=false end;n=n+1 end
        if n==0 then return '[]' end
        if isarray and n>0 and #v==n then local r={};for i=1,#v do r[#r+1]=json(v[i]) end;return '['..table.concat(r,',')..']' end
        local keys={};for k in pairs(v) do keys[#keys+1]=k end;table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
        local r={};for _,k in ipairs(keys) do r[#r+1]=json(tostring(k))..':'..json(v[k]) end;return '{'..table.concat(r,',')..'}'
    end;error('JSON unsupported '..type(v))
end
local seeds={12011,12037,12071,12109,12143}
local levels={1,3,6,9,10}
local personal_levels={{1,9,17,24},{3,12,20,30},{7,16,28,34},{8,18,25,32},{10,19,26,33}}
local orders={{0,1,2,3},{3,2,1,0},{1,3,0,2},{2,0,3,1},{3,0,2,1}}
local result={suite='four_player_wave_wall_'..MODE,engine='Lua 5.1 offline',production_changes=MODE=='final',
    boundaries={'native movement is straight-line engine fixture, 32-unit MOVE stop radius','phase states apply next simulated server frame',
        'primary spawn/target probes use actual configured marker coordinates','density fixture supplies initial non-contact 360-body gate rows',
        'no actual Workshop pathfinder, native entity bounds, damage filter or rendering certification',
        'personal map levels and profiles are fixture metadata in this domain; archive/stat behavior is verified by the other domain',
        'profile readiness, assets, cosmetics and corpse visuals are external stubs'},rounds={}}
for _,scenario in ipairs({'A','B'}) do for i=1,5 do
    round={id=scenario..i,scenario=scenario,seed=seeds[i]+(scenario=='B' and 1000 or 0),difficulty='N'..levels[i],map_levels=personal_levels[i],order=orders[i],
        checks=0,failures={},fallback={},crowds={},profiles={1,4,7,10},sole_defender=(i-1)%4,
        tower_owners=scenario=='B' and {(i-1)%4} or {0,1,2,3}}
    math.randomseed(round.seed)
    spawn_probe();for _,kind in ipairs({'unreachable','outside_defense','destroyed'}) do fallback_probe(kind) end
    crowd_probe(false);if scenario=='B' then crowd_probe(true) end
    if MODE=='final' or MODE=='portal-negative' then target_edges() end
    round.passed=#round.failures==0;result.rounds[#result.rounds+1]=round
    print(string.format('FOUR_PLAYER_WAVE_WALL_ROUND %s seed=%d %s checks=%d failures=%d',round.id,round.seed,round.difficulty,round.checks,#round.failures))
end end
result.failures=failures;result.failed_rounds=0;for _,r in ipairs(result.rounds) do if not r.passed then result.failed_rounds=result.failed_rounds+1 end end
local file=assert(io.open(OUT..'/'..STEM..'.json','wb'));file:write(json(result));file:close()
local minimal={};local codes={};for _,f in ipairs(failures) do if not codes[f.code] then minimal[#minimal+1]=f;codes[f.code]=true end end
file=assert(io.open(OUT..'/'..STEM..'_minimal_failures.json','wb'));file:write(json(minimal));file:close()
print('FOUR_PLAYER_WAVE_WALL_COMPLETE rounds='..#result.rounds..' failed='..result.failed_rounds..' minimal='..#minimal)
