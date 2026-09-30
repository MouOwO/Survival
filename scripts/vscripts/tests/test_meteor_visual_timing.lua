package.path="scripts/vscripts/?.lua;"..package.path
Vector=function(x,y,z) return {x=x,y=y,z=z} end
local clock,particles,damage,sounds,slow=0,{},{},{},{}
local removed,fail_particle,fail_control,reenter=false,nil,false,nil
GameRules={GetGameTime=function() return clock end}
PATTACH_WORLDORIGIN=6
DOTA_UNIT_TARGET_TEAM_ENEMY=1;DOTA_UNIT_TARGET_HERO=2;DOTA_UNIT_TARGET_BASIC=4
DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES=8;FIND_ANY_ORDER=0;DAMAGE_TYPE_PURE=4
GetGroundPosition=function(v) return Vector(v.x,v.y,384) end
local caster={entindex=function() return 10 end,IsNull=function() return removed end,
    IsAlive=function() return true end,GetTeamNumber=function() return 2 end,
    GetAbsOrigin=function() return Vector(0,0,384) end,FindAbilityByName=function() return {} end}
local target={entindex=function() return 20 end,IsNull=function() return false end,
    IsAlive=function() return true end,GetTeamNumber=function() return 3 end,
    GetAbsOrigin=function() return Vector(128,192,384) end,GetHullRadius=function() return 24 end}
FindUnitsInRadius=function(_,_,_,radius) assert(radius==756);return {target} end
package.loaded["systems/buff_manager"]={apply=function(_,unit,id,p)
    assert(unit==target and id=="debuff_hero_meteor_lava_move_slow" and p.value==-30);slow[unit]=true
end,remove=function(unit)slow[unit]=nil end}
package.loaded["systems/hero_exclusive_passive_service"]={runners={}}
package.loaded["core/sound_service"]={play=function(id) sounds[#sounds+1]={name=id,time=clock} end}
ParticleManager={CreateParticle=function(_,name,attach,owner)
    if name==fail_particle then error("fixture: visual resource unavailable") end
    assert(attach==6 and owner==caster)
    local id=#particles+1;particles[id]={name=name,controls={},created_at=clock,destroy=0,release=0};return id
end,SetParticleControl=function(_,id,cp,value)
    if fail_control and cp==1 then error("fixture: CP failure") end
    particles[id].controls[cp]=value
end,DestroyParticle=function(_,id,immediate)
    particles[id].destroy=particles[id].destroy+1;particles[id].immediate=immediate
    local callback=reenter;reenter=nil;if callback then callback() end
end,ReleaseParticleIndex=function(_,id) particles[id].release=particles[id].release+1 end}
local bus=require("core/event_bus");bus.reset()
bus.handle_request(require("combat/combat_events").DEAL_REQUEST,function(p)
    damage[#damage+1]={time=clock,amount=p.base_damage,kind=p.source_kind}
    assert(p.damage_type==DAMAGE_TYPE_PURE and p.tags.source_skill_id=="proto_meteor")
    return {ok=true}
end)
local service=require("systems/hero_passive_skill_service")
local scheduler=require("core/scheduler")
local definition=require("config/hero_passive_skill_definitions").by_id.proto_meteor
local fly="particles/survival/skills/meteor_cube_fall.vpcf"
local impact="particles/survival/skills/meteor_impact.vpcf"
local lava="particles/survival/skills/meteor_lava.vpcf"
local function context(level)
    return {attacker=caster,target=target,player_id=0,skill_id="proto_meteor",attack_id="fixture",
        level=level,attributes={all_attributes=100}}
end
local function advance(time)
    clock=time;service._test.sync_meteors();scheduler.think()
end
local function once(first)
    for id=first or 1,#particles do
        assert(particles[id].destroy==1 and particles[id].release==1,"particle must destroy/release once: "..id)
    end
end
for level=1,5 do
    service._test.clear_meteors();scheduler.clear();damage={};slow={};clock=0
    local first=#particles+1
    assert(service._test.runners.proto_meteor(context(level),definition))
    assert(not service._test.runners.proto_meteor(context(level),definition),"active cast blocks retrigger")
    advance(0)
    local fall=particles[first]
    assert(fall.name==fly and fall.controls[2].x==0.8)
    assert(fall.controls[0].z==1584 and fall.controls[1].z==-666)
    assert(math.abs(fall.controls[0].z+(fall.controls[1].z-fall.controls[0].z)*0.8/1.5-384)<0.0001,
        "angular model crosses actual ground exactly at unchanged impact time")
    advance(0.5);advance(0.799)
    assert(#damage==0,"never apply damage before 0.8 seconds")
    advance(0.8)
    assert(#damage==1 and damage[1].amount==300 and fall.destroy==1 and fall.immediate)
    local impacts,lavas,lava_id=0,0,nil
    for id=first,#particles do
        local p=particles[id]
        if p.name==impact then impacts=impacts+1;assert(p.controls[1].x==500) end
        if p.name==lava then
            lavas=lavas+1;lava_id=id
            assert(p.controls[1].x==500 and p.controls[1].y==(level==5 and 3.5 or 3),
                "one ground visual covers through the final meteor's own lava expiry")
        end
    end
    assert(impacts==1 and lavas==(level>=2 and 1 or 0))
    assert((slow[target]==true)==(level>=3),"slow tier threshold unchanged")
    advance(1.3);advance(1.8);advance(2.3);advance(2.8);advance(3.3);advance(3.8)
    if level==5 then
        assert(particles[lava_id].destroy==0,"first lava expiry must not remove the second meteor's shared visual")
        assert(service._test.meteor_locked("10"),"second meteor still owns its final half second")
        local lava_count=0
        for id=first,#particles do if particles[id].name==lava then lava_count=lava_count+1 end end
        assert(lava_count==1,"same-cast meteors must not create duplicate coplanar lava systems")
    end
    advance(4.3)
    local total=0;for _,hit in ipairs(damage) do total=total+hit.amount end
    assert(#damage==(level==1 and 1 or level==5 and 8 or 4))
    assert(total==(level==1 and 300 or level==5 and 1080 or 600),"tier damage totals unchanged")
    if level==5 then
        assert(damage[2].time==1.3 and math.abs(damage[2].amount-240)<0.0001)
        assert(damage[4].amount==80 and damage[6].amount==80 and damage[8].amount==80)
    end
    assert(not service._test.meteor_locked("10") and next(slow)==nil)
    advance(6);service._test.clear_meteors();service._test.clear_meteors();once(first)
    assert(scheduler.task_count()==0,"all cast/impact cleanup callbacks retired")
end
-- Effect allocation/control errors are presentation failures only.
for _,failure in ipairs({impact,lava,fly,"control"}) do
    clock=10;damage={};local first=#particles+1
    fail_particle=failure;fail_control=failure=="control"
    assert(service._test.runners.proto_meteor(context(2),definition))
    advance(10);advance(10.8);advance(11.8);advance(12.8);advance(13.8);advance(16)
    assert(#damage==4,"missing visual must preserve explosion and all three DoT ticks")
    service._test.clear_meteors();once(first)
    fail_particle=nil;fail_control=false
end
clock=20;local first=#particles+1
assert(service._test.runners.proto_meteor(context(5),definition));advance(20);advance(20.8)
reenter=function() service._test.clear_meteors() end
service._test.clear_meteors();service._test.clear_meteors();once(first)
assert(next(service._test.active_meteor_casts())==nil and scheduler.task_count()==0)
clock=25;first=#particles+1
assert(service._test.runners.proto_meteor(context(2),definition));advance(25);advance(25.8)
assert(service._test.active_meteor_casts()["10"].lava_particle,"shared ground exists before reentrant retirement")
reenter=function() service._test.clear_meteors() end
service._test.clear_meteors();service._test.clear_meteors();once(first)
clock=30;first=#particles+1
assert(service._test.runners.proto_meteor(context(2),definition));advance(30);advance(30.8)
local interrupted_lava=service._test.active_meteor_casts()["10"].lava_particle
removed=true;advance(30.9)
assert(particles[interrupted_lava].destroy==1 and particles[interrupted_lava].release==1)
assert(not service._test.meteor_locked("10"))
-- Already emitted impact flashes keep their independent short cleanup timer.
advance(32.1);once(first)
print("METEOR_VISUAL_TIMING_PASS 5 tiers, exact 0.8s crossing, 500 radius, 3s per-meteor damage / shared 3.5s dual visual, 80% second meteor, VFX failures, cleanup")
