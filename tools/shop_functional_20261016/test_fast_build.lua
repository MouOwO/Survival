-- Native Lua 5.1 regression: execute production placement/construction functions
-- with engine handles mocked, plus the complete production upgrade process.
-- Run from the addon root. Optional first arg selects a construction baseline.
package.path = 'scripts/vscripts/?.lua;' .. package.path
local function read(path)
    local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return (s:gsub('\r\n','\n'))
end
local source=read(arg[1] or 'scripts/vscripts/systems/building_system.lua')
local function between(s, first, last)
    local a=assert(s:find(first,1,true),first)
    local b=assert(s:find(last,a+#first,true),last)
    return s:sub(a,b-1)
end
local function compile(code,env)
    local f=assert(loadstring(code,'@production_building_entry'));setfenv(f,env);return f()
end
local events=require('core/events')
local checks=0
local world
local function noop() end
local function vec(x,y,z) return {x=x,y=y,z=z} end
local function unit(id,player)
    local u={id=id,survival_player_id=player,alive=true,modifiers={},health=1000}
    function u:IsNull() return false end
    function u:IsAlive() return self.alive end
    function u:entindex() return self.id end
    function u:SetOwner(owner) self.owner=owner end
    function u:AddNewModifier(_,_,name) self.modifiers[name]=true end
    function u:HasModifier(name) return self.modifiers[name] end
    function u:RemoveModifierByName(name) self.modifiers[name]=nil end
    function u:SetHullRadius(radius) self.radius=radius end
    function u:GetMaxHealth() return 1000 end
    function u:SetHealth(health) self.health=health end
    function u:SetAbsOrigin(origin) self.origin=origin end
    function u:GetAbsOrigin() return self.origin end
    function u:SetControllableByPlayer(player,enabled) self.control={player,enabled} end
    function u:FindAbilityByName() return nil end
    return u
end
local defs={}
for _,id in ipairs({'farm','wall','arrow_tower','hero_altar','gold_mine',
    'building_research_lab','building_advanced_research_lab','building_challenge'}) do
    defs[id]={id=id,display_name=id,unit_name='building_'..id,max_count=7,
        footprint={x=2,y=2},build_time=3,population_cost=1}
end
defs.wall.build_once=true
defs.hero_altar.unlock_city_level=3
defs.building_advanced_research_lab.requires_building_id='building_research_lab'
package.loaded['systems/player_context_service']={is_defeated=function(p) return world.defeated[p] end}
-- Use the real entitlement check, backed by independent saved ownership.
package.loaded['systems/player_profile_service']={
    get_content_inventory_count=function(p,id) return (world.inventory[p] or {})[id] or 0 end,
}
package.loaded['systems/commerce_effects']=nil
local env=setmetatable({print=noop},{__index=_G})
env.events=events;env.config=defs;env.DOTA_TEAM_GOODGUYS=2
env.valid_entity=function(u) return u and not u:IsNull() end
env.team_alignment={enforce=noop};env.grid_config={cell_size=64}
env.rogue_effect_state={numeric=function() return 0 end,consume_numeric=function(p,key,count)
    world.consumed=(world.consumed or 0)+count
end}
env.pending_unique_count=function() return 0 end
env.count_for=function(p,id) return (world.counts[p] or {})[id] or 0 end
env.building_limit_reached=function(d,count) return count>=d.max_count end
env.main_city_level=function() return world.city_level end
env.has_completed_building=function(p,id) return env.count_for(p,id)>0 end
env.building_cost_quote={for_player=function(d,p)
    return {wood=100,gold=20,population=1,mine_slots=1,free_altar=false,free_wall=false}
end}
env.buildings={};env.wall_ever_built={}
env.change_count=function(p,id,n)
    world.counts[p]=world.counts[p] or {};world.counts[p][id]=env.count_for(p,id)+n
end
env.release_pending_unique_build=noop;env.publish_building_counts=noop
env.level_display_name=function(d) return d.display_name end
env.arrow_data=function() return {record_id='first',skill_ids={}} end
env.anchor_building=function(u,p) u.survival_fixed_position=p end
env.apply_initial_stats=noop;env.apply_hull_radius=noop;env.add_building_abilities=function() end
env.clear_build_task=function(caster) caster.survival_build_task=nil end
env.wall_collision_barrier_service={create=noop,clear=noop}
env.dev_wall_stats={apply=noop};env.tower_skills={apply=noop}
env.completion_level_data=function(d) return d end
env.building_visual={apply=function(u) world.model_applies=world.model_applies+1 end}
env.building_population={grant_level=function() world.population_grants=world.population_grants+1 end}
env.building_sound={construction_started=function() world.start_sounds=world.start_sounds+1 end,
    construction_completed=function() world.complete_sounds=world.complete_sounds+1 end}
env.construction_visual={start=function() world.shells=world.shells+1;return {} end,
    complete=function(state) if state then world.shells=world.shells-1 end end,
    cancel=function(state) if state then world.shells=world.shells-1 end end}
env.builder_presentation={construction_started=function() world.channels=world.channels+1 end,
    construction_finished=function() world.channels=0 end}
env.release_grid_for_state=function() world.grid_released=world.grid_released+1 end
env.release_population=function() world.population_released=world.population_released+1 end
env.rollback_build_cooldown=function() world.cooldown_rollback=world.cooldown_rollback+1 end
env.public_state=function(s) return {player_id=s.player_id,building_id=s.building_id,unit=s.unit} end
env.notify=function(p,message,level) world.notifications[#world.notifications+1]={p,message,level} end
env.GameRules={GetGameTime=function() return world.now end}
env.CreateUnitByName=function(name,position,_,caster)
    world.creations=world.creations+1
    if world.fail_create then return nil end
    local u=unit(100+world.creations,caster.survival_player_id)
    u.origin=position;world.last=u;return u
end
env.scheduler={every=function(delay,callback,key)
    world.repeats[#world.repeats+1]={delay=delay,callback=callback,key=key}
end,after=function(delay,callback,key) world.recovery[#world.recovery+1]={delay=delay,callback=callback,key=key} end}
env.event_bus={request=function(event,p)
    if event==events.BUILDER_GET_REQUEST then
        if p.player_id~=p.caster.survival_player_id then return {ok=false,error='builder_not_owned'} end
        return {ok=true,player_id=p.player_id,builder=p.caster}
    elseif event==events.GRID_CAN_PLACE_REQUEST then
        if world.grid_blocked then return {ok=false,error='blocked'} end
        return {ok=true,grid_x=5,grid_y=7,world_position=vec(320,448,0)}
    elseif event==events.RESOURCE_CAN_SPEND_REQUEST or event==events.RESOURCE_TRY_SPEND_REQUEST then
        local funds=world.accounts[p.player_id]
        if funds.wood<p.wood or funds.gold<p.gold or funds.population<p.population then
            return {ok=false,error='insufficient_resources'}
        end
        if event==events.RESOURCE_TRY_SPEND_REQUEST then
            funds.wood=funds.wood-p.wood;funds.gold=funds.gold-p.gold
            funds.population=funds.population-p.population;world.spends=world.spends+1
        end
        return {ok=true}
    elseif event==events.RESOURCE_ADD_REQUEST then
        local funds=world.accounts[p.player_id]
        funds.wood=funds.wood+(p.wood or 0);funds.gold=funds.gold+(p.gold or 0)
        world.refunds=world.refunds+1;return {ok=true}
    elseif event==events.RESOURCE_RELEASE_POP_REQUEST then
        world.accounts[p.player_id].population=world.accounts[p.player_id].population+p.population
        world.population_released=world.population_released+1;return {ok=true}
    end
    return {ok=true}
end,emit=function(event,p)
    world.emitted[#world.emitted+1]={event=event,payload=p}
    if event==events.BUILDING_CREATED then
        world.created_events=world.created_events+1
        assert(not p.unit:HasModifier('modifier_building_under_construction'))
    end
end}
local start=compile(between(source,'local function can_place(','local function queue_building(')
    ..'\nreturn start_building',env)
local function reset()
    world={now=10,city_level=5,inventory={},defeated={},counts={},accounts={},
        creations=0,spends=0,refunds=0,created_events=0,model_applies=0,population_grants=0,
        shells=0,channels=0,start_sounds=0,complete_sounds=0,grid_released=0,population_released=0,
        cooldown_rollback=0,repeats={},recovery={},notifications={},emitted={}}
    env.buildings={};env.wall_ever_built={}
    for p=0,3 do world.accounts[p]={wood=1000,gold=500,population=10} end
end
local function build(p,id)
    return start({player_id=p,caster=unit(p+1,p),building_id=id or 'farm',position=vec(320,448,0)})
end
-- Every initial building type reaches completion immediately, with one spend
-- and one authoritative CREATED event, while retaining the real owned marker.
for id in pairs(defs) do
    reset();world.inventory[0]={commerce_p032=1};world.counts[0]={building_research_lab=1}
    local result=build(0,id)
    assert(result.ok and result.build_time==0 and result.pending==false and result.constructing==false,id)
    assert(world.spends==1 and world.created_events==1 and world.population_grants==1,id)
    assert(world.accounts[0].wood==900 and world.accounts[0].gold==480,id)
    assert(world.last.health==1000 and world.last.control[1]==0,id)
    assert(#world.repeats==0 and world.shells==0 and world.channels==0 and world.start_sounds==0,id)
    assert(world.complete_sounds==1 and #world.recovery==1,id)
    checks=checks+1
end
-- The fast privilege is scoped to its owner, not the shared Dota team.
reset();world.inventory[0]={commerce_p032=1}
local first=build(0);local second=build(1)
assert(first.pending==false and second.pending and second.build_time==3)
assert(world.created_events==1 and world.spends==2 and #world.repeats==1)
assert(world.last.health==1 and world.shells==1)
world.now=11;assert(world.repeats[1].callback()==true and world.created_events==1)
world.now=13;assert(world.repeats[1].callback()==false and world.created_events==2)
assert(world.last.health==1000 and world.shells==0)
checks=checks+1
-- Permission cannot bypass resources, population, limit, city/research gates,
-- defeated-player rules or occupied placement. No entity or charge is created.
for _,kind in ipairs({'wood','gold','population','limit','city','prerequisite','grid','defeated'}) do
    reset();world.inventory[0]={commerce_p032=1};local id='farm'
    if kind=='wood' or kind=='gold' or kind=='population' then world.accounts[0][kind]=0 end
    if kind=='limit' then world.counts[0]={farm=7} end
    if kind=='city' then id='hero_altar';world.city_level=1 end
    if kind=='prerequisite' then id='building_advanced_research_lab' end
    if kind=='grid' then world.grid_blocked=true end
    if kind=='defeated' then world.defeated[0]=true end
    local r=build(0,id)
    assert(not r.ok and world.creations==0 and world.spends==0 and world.refunds==0,kind)
    checks=checks+1
end
-- An untrusted player ID cannot borrow a teammate's builder/entitlement.
reset();world.inventory[0]={commerce_p032=1}
local denied=start({player_id=0,caster=unit(2,1),building_id='farm',position=vec(1,2,0)})
assert(not denied.ok and world.creations==0 and world.spends==0);checks=checks+1
-- Creation failure refunds the original cost/population for fast owners too.
reset();world.inventory[0]={commerce_p032=1};world.fail_create=true
assert(not build(0).ok and world.spends==1 and world.refunds==1)
assert(world.accounts[0].wood==1000 and world.accounts[0].gold==500 and world.accounts[0].population==10)
checks=checks+1
-- Ordinary construction death still refunds exactly once, never grants stats.
reset();assert(build(1).pending);world.last.alive=false
assert(world.repeats[1].callback()==false and world.refunds==1 and world.grid_released==1)
assert(world.created_events==0 and world.population_grants==0 and world.cooldown_rollback==1)
assert(world.repeats[1].callback()==false and world.refunds==1);checks=checks+1

-- Exercise the actual upgrade process and real entitlement helper. Engine
-- particles/assets are mocked; lifecycle and callbacks run unmodified.
local scheduled,particle_calls,played={},{},0
package.loaded['core/scheduler']={after=function(delay,callback,id)
    scheduled[#scheduled+1]={delay=delay,callback=callback,id=id};return id
end,cancel=noop}
package.loaded['systems/building_warp_effects']={create=function() particle_calls[#particle_calls+1]=true end,
    destroy=noop,is_shell=function() return false end,is_white=function() return false end,reset_shells=noop}
package.loaded['systems/building_upgrade_effect']={play=function() played=played+1 end}
package.loaded['systems/asset_preload_service']={queue=function() return true,'queued' end}
package.loaded['core/logger']={info=noop}
package.loaded['systems/building_upgrade_process']=nil
local process=require('systems/building_upgrade_process')
for _,p in ipairs({0,1,2,3}) do
    reset();scheduled={};particle_calls={};played=0;world.inventory[0]={commerce_p032=1}
    local u=unit(300+p,p);local completed,cancelled=0,0
    local r=process.begin(u,{duration=1,target_level=2,definition={},
        on_complete=function() completed=completed+1;u.level=2 end,
        on_cancel=function() cancelled=cancelled+1 end})
    assert(r.ok and r.target_level==2)
    if p==0 then
        assert(r.pending==false and r.duration==0 and completed==1 and u.level==2)
        assert(not process.is_active(u) and not u.survival_upgrade_in_progress)
        assert(#scheduled==0 and #particle_calls==0 and played==1)
        assert(not process.cancel_by_entindex(u:entindex()) and cancelled==0)
    else
        assert(r.pending and r.duration==1 and completed==0 and process.is_active(u))
        assert(#scheduled==1 and scheduled[1].delay==1)
        scheduled[1].callback();scheduled[1].callback()
        assert(completed==1 and played==1 and not process.is_active(u))
    end
    checks=checks+1
end
-- Normal delayed upgrades still cancel once when destroyed, and can be reused.
reset();scheduled={};local u=unit(500,1);local complete,cancel=0,0
process.begin(u,{duration=1,on_complete=function() complete=complete+1 end,
    on_cancel=function() cancel=cancel+1 end})
u.alive=false;scheduled[1].callback();scheduled[1].callback()
assert(cancel==1 and complete==0 and not process.is_active(u));checks=checks+1
print('FAST_BUILD_PASS '..checks..' cases: zero-time construction/upgrades, all building kinds, ownership, prerequisites, resources, limits, refund and lifecycle')
