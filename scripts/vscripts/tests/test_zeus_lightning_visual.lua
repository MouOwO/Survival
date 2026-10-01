package.path="scripts/vscripts/?.lua;"..package.path
Vector=function(x,y,z) return {x=x,y=y,z=z} end
local now, particles, hits, marked, fail = 0, {}, {}, {}, false
GameRules={GetGameTime=function() return now end}
PATTACH_WORLDORIGIN=6;PATTACH_ABSORIGIN_FOLLOW=1
DOTA_UNIT_TARGET_TEAM_ENEMY=1;DOTA_UNIT_TARGET_HERO=2;DOTA_UNIT_TARGET_BASIC=4
DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES=8;FIND_CLOSEST=1;DAMAGE_TYPE_PURE=4
GetGroundPosition=function(p) return Vector(p.x,p.y,384) end
local function unit(id,team)
    return {entindex=function() return id end,IsNull=function() return false end,
        IsAlive=function() return true end,GetTeamNumber=function() return team end,
        GetAbsOrigin=function() return Vector(id,80,454) end,FindAbilityByName=function() return {} end}
end
local caster,target=unit(10,2),unit(20,3)
FindUnitsInRadius=function(_,_,_,radius) assert(radius==400); return {target} end
package.loaded["systems/buff_manager"]={
    apply=function(_,t,id,p) assert(p.duration==3);marked[t]=true end,
    has=function(t) return marked[t] end,remove=function() end}
package.loaded["systems/hero_exclusive_passive_service"]={runners={}}
package.loaded["core/sound_service"]={play=function() end}
ParticleManager={
    CreateParticle=function(_,name,attach,owner)
        local id=#particles+1;particles[id]={name=name,cp={},owner=owner};return id
    end,
    SetParticleControl=function(_,id,cp,value)
        if fail then error("injected optional visual failure") end
        particles[id].cp[cp]=value
    end,
    DestroyParticle=function(_,id,immediate) particles[id].destroyed=true;particles[id].immediate=immediate end,
    ReleaseParticleIndex=function(_,id) particles[id].released=(particles[id].released or 0)+1 end,
}
local bus=require("core/event_bus");bus.reset()
bus.handle_request(require("combat/combat_events").DEAL_REQUEST,function(p)
    hits[#hits+1]={amount=p.base_damage,time=now};return {ok=true}
end)
local service=require("systems/hero_passive_skill_service")
local scheduler=require("core/scheduler")
local storm=require("systems/disruptor_storm_visual")
local definition=require("config/hero_passive_skill_definitions").by_id.proto_chain_lightning
local config=require("config/generated/tower_lightning_effects").by_id
for level=1,5 do
    for _, failure in ipairs({false,true}) do
        now=0;particles={};hits={};marked={};fail=failure;scheduler.clear()
        service._test.runners.proto_chain_lightning({attacker=caster,target=target,player_id=0,
            skill_id="proto_chain_lightning",attack_id="test",level=level,attributes={all_attributes=100}},definition)
        now=0.12;scheduler.think();now=0.24;scheduler.think()
        local total=0;for _,hit in ipairs(hits) do total=total+hit.amount end
        assert(total==(level==5 and 900 or 300), "visual failure must not alter fury damage or repeat reduction/marks")
        if level==5 then assert(hits[2].time==0.12 and hits[4].time==0.24) end
        assert(#particles==(failure and level==5 and 3 or 1), "same-target triple hit must reuse one storm")
        for _,p in ipairs(particles) do
            if not failure then
                assert(not p.destroyed and not p.released, "live storm must retain ownership until deadline")
                assert(p.name==config.strike.particle_name and p.name:find('disruptor_2022_immortal_static_storm',1,true))
                assert(p.cp[0].z==384 and p.cp[1].x==400 and p.cp[1].y==1 and p.cp[2].x==1.2,
                    "storm uses exact gameplay radius and terrain position")
            else assert(p.destroyed and p.released==1, "failed partial effect must be cleaned") end
        end
        now=1.19;scheduler.think()
        if not failure then assert(not particles[1].destroyed) end
        now=1.2;scheduler.think()
        for _,p in ipairs(particles) do assert(p.destroyed and p.released==1) end
        if not failure then assert(particles[1].immediate==false, "natural storm endcap should fade") end
        storm.clear();storm.clear()
    end
end
fail=false;particles={};now=2
local a=storm.play(caster,Vector(1,2,500),125,2)
local b=storm.play(caster,Vector(50,60,500),750,3)
assert(particles[1].cp[1].x==125 and particles[2].cp[1].x==750)
assert(storm.play(caster,Vector(90,100,500),125,2,a)==a and #particles==2,
    "repeated hit must move existing storm without creating another system")
storm.clear();storm.clear()
assert(particles[1].released==1 and particles[2].released==1 and scheduler.task_count()==0)
local precached={}
PrecacheResource=function(kind,name) assert(kind=="particle" and not precached[name]);precached[name]=true end
require("systems/zeus_lightning_visual").precache({})
for _,row in pairs(config) do
    for _,key in ipairs({"particle_name","impact_particle","cast_particle"}) do
        if row[key] then assert(precached[row[key]]) end
    end
end
print("LIGHTNING_STORM_VISUAL_PASS: native immortal R, exact radius, triple-hit reuse, lifetime, five fury tiers damage/timing, cleanup, precache")
