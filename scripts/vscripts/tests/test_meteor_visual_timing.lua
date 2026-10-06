package.path="scripts/vscripts/?.lua;"..package.path
Vector=function(x,y,z) return {x=x,y=y,z=z} end
local clock,particles,damage,sounds,slow=0,{},{},{},{}
local removed,fail_particle,fail_control,reenter=false,nil,false,nil
local world,create_mode,control_mode,forced_id,create_reenter={},nil,nil,nil,nil
local control_reenter
local destroy_mode,release_mode=nil,nil
local target_alive,target_removed,target_position=true,false,Vector(128,192,384)
local impact_path="particles/survival/skills/meteor_phoenix_impact.vpcf"
local kill_on_hit,require_impact_before_deal=false,false
local last_query_position
GameRules={GetGameTime=function() return clock end,GetGameModeEntity=function() return world end}
PATTACH_WORLDORIGIN=6
DOTA_UNIT_TARGET_TEAM_ENEMY=1;DOTA_UNIT_TARGET_HERO=2;DOTA_UNIT_TARGET_BASIC=4
DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES=8;FIND_ANY_ORDER=0;DAMAGE_TYPE_PURE=4
GetGroundPosition=function(v) return Vector(v.x,v.y,384) end
local caster={entindex=function() return 10 end,IsNull=function() return removed end,
    IsAlive=function() return true end,GetTeamNumber=function() return 2 end,
    GetAbsOrigin=function() return Vector(0,0,384) end,FindAbilityByName=function() return {} end}
local target={entindex=function() return 20 end,IsNull=function() return target_removed end,
    IsAlive=function() return target_alive end,GetTeamNumber=function() return 3 end,
    GetAbsOrigin=function() return target_position end,GetHullRadius=function() return 24 end}
FindUnitsInRadius=function(_,position,_,radius)
    assert(radius==756);last_query_position=Vector(position.x,position.y,position.z);return {target}
end
package.loaded["systems/buff_manager"]={apply=function(_,unit,id,p)
    assert(unit==target and id=="debuff_hero_meteor_lava_move_slow" and p.value==-30);slow[unit]=true
end,remove=function(unit)slow[unit]=nil end}
package.loaded["systems/hero_exclusive_passive_service"]={runners={}}
package.loaded["core/sound_service"]={play=function(id) sounds[#sounds+1]={name=id,time=clock} end}
ParticleManager={CreateParticle=function(_,name,attach,owner)
    if name==fail_particle then error("fixture: visual resource unavailable") end
    assert(attach==6 and (owner==caster or (name==impact_path and owner==nil)))
    if name==impact_path and create_mode then
        if create_mode=="nil" then return nil end
        if create_mode=="false" then return false end
        if create_mode=="negative" then return -1 end
        if create_mode=="fractional" then return 1.5 end
        if create_mode=="nan" then return 0/0 end
        if create_mode=="infinity" then return math.huge end
    end
    local id=forced_id or #particles+1;forced_id=nil
    particles[id]={name=name,owner=owner,world=world,controls={},created_at=clock,destroy=0,release=0}
    local callback=create_reenter;create_reenter=nil;if callback then callback(id) end
    return id
end,SetParticleControl=function(_,id,cp,value)
    if fail_control and cp==1 then error("fixture: CP failure") end
    if particles[id].name==impact_path and control_mode then
        if control_mode=="false" or (control_mode=="cp3_false" and cp==3) then return false end
        if control_mode=="throw" or (control_mode=="cp3_throw" and cp==3) then error("fixture: Phoenix CP failure") end
    end
    particles[id].controls[cp]=value
    local callback=control_reenter;control_reenter=nil;if callback then callback(id) end
end,DestroyParticle=function(_,id,immediate)
    particles[id].destroy=particles[id].destroy+1;particles[id].immediate=immediate
    local callback=reenter;reenter=nil;if callback then callback() end
    if destroy_mode=="throw" then error("fixture: destroy failure") end
    if destroy_mode=="false" then return false end
end,ReleaseParticleIndex=function(_,id)
    particles[id].release=particles[id].release+1
    if release_mode=="throw" then error("fixture: release failure") end
    if release_mode=="false" then return false end
end}
local bus=require("core/event_bus");bus.reset()
bus.handle_request(require("combat/combat_events").DEAL_REQUEST,function(p)
    if require_impact_before_deal and not p.tags.is_secondary_effect then
        local found=false
        for _,particle in pairs(particles) do
            if particle.name==impact_path and particle.created_at==clock and particle.controls[0] then found=true end
        end
        assert(found,"complete Phoenix impact must exist before fatal damage removes the target")
    end
    damage[#damage+1]={time=clock,amount=p.base_damage,kind=p.source_kind,secondary=p.tags.is_secondary_effect}
    assert(p.damage_type==DAMAGE_TYPE_PURE and p.tags.source_skill_id=="proto_meteor")
    if kill_on_hit then target_alive=false;target_removed=true end
    return {ok=true}
end)
local service=require("systems/hero_passive_skill_service")
local scheduler=require("core/scheduler")
local impact_visual=require("systems/meteor_phoenix_impact_visual")
local definition=require("config/hero_passive_skill_definitions").by_id.proto_meteor
local fly="particles/survival/skills/meteor_phoenix_fall.vpcf"
local impact=impact_path
local function assert_damage_schedule(level,started_at)
    local expected=level==1 and {{0.4,300,false}}
        or level==5 and {{0.4,300,false},{0.9,240,false},{1.4,100,true},{1.9,80,true},
            {2.4,100,true},{2.9,80,true},{3.4,100,true},{3.9,80,true}}
        or {{0.4,300,false},{1.4,100,true},{2.4,100,true},{3.4,100,true}}
    assert(#damage==#expected)
    for index,hit in ipairs(expected) do
        assert(math.abs(damage[index].time-started_at-hit[1])<0.0001
            and math.abs(damage[index].amount-hit[2])<0.0001 and damage[index].secondary==hit[3],
            "each original impact/lava clock, damage and secondary tag remains unchanged: "..index)
    end
end
local lava="particles/survival/skills/meteor_lava.vpcf"
assert(impact_visual.duration()==8,"full native seven-second tail has an eight-second cleanup bound")
assert(impact_visual.spec().maximum_radius==500)
for level=1,5 do assert(definition.trigger_chance[level]==0.12 and definition.radius[level]==500) end
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
    require_impact_before_deal=true
    local first=#particles+1
    assert(service._test.runners.proto_meteor(context(level),definition))
    assert(not service._test.runners.proto_meteor(context(level),definition),"active cast blocks retrigger")
    advance(0)
    local fall=particles[first]
    assert(fall.name==fly and fall.controls[2].x==0.4)
    assert(fall.controls[0].z==1584 and fall.controls[1].z==384)
    assert(math.abs(fall.controls[0].z+(fall.controls[1].z-fall.controls[0].z)*0.4/0.4-384)<0.0001,
        "Phoenix egg reaches actual ground at the faster impact time")
    advance(0.2);advance(0.399)
    assert(#damage==0,"never apply damage before 0.4 seconds")
    advance(0.4)
    assert(#damage==1 and damage[1].amount==300 and fall.destroy==1 and fall.immediate)
    local impacts,lavas,lava_id=0,0,nil
    for id=first,#particles do
        local p=particles[id]
        if p.name==impact then
            impacts=impacts+1
            assert(p.controls[0].x==128 and p.controls[0].y==192 and p.controls[0].z==384)
            assert(p.controls[1].x==1 and p.controls[1].y==1 and p.controls[1].z==1,
                "native CP1 keeps its unit preset; fixed 500 radius is authored in all native layers")
            assert(p.controls[3].x==128 and p.controls[3].y==192 and p.controls[3].z==484,
                "world-space CP3 preserves a vertical normal at the hit point")
            assert(p.controls[60]==nil and p.controls[61]==nil and p.controls[62]==nil)
        end
        if p.name==lava then
            lavas=lavas+1;lava_id=id
            assert(p.controls[1].x==500 and p.controls[1].y==(level==5 and 3.5 or 3),
                "one ground visual covers through the final meteor's own lava expiry")
        end
    end
    assert(impacts==1 and lavas==(level>=2 and 1 or 0))
    assert((slow[target]==true)==(level>=3),"slow tier threshold unchanged")
    advance(0.5);advance(0.899)
    assert(#damage==1,"second meteor must retain its half-second impact gap")
    advance(0.9);advance(1.4);advance(1.9);advance(2.4);advance(2.9);advance(3.4)
    if level==5 then
        assert(particles[lava_id].destroy==0,"first lava expiry must not remove the second meteor's shared visual")
        assert(service._test.meteor_locked("10"),"second meteor still owns its final half second")
        local lava_count=0
        for id=first,#particles do if particles[id].name==lava then lava_count=lava_count+1 end end
        assert(lava_count==1,"same-cast meteors must not create duplicate coplanar lava systems")
    end
    advance(3.9)
    local total=0;for _,hit in ipairs(damage) do total=total+hit.amount end
    assert(#damage==(level==1 and 1 or level==5 and 8 or 4))
    assert(total==(level==1 and 300 or level==5 and 1080 or 600),"tier damage totals unchanged")
    if level==5 then
        assert(damage[2].time==0.9 and math.abs(damage[2].amount-240)<0.0001)
        assert(damage[4].amount==80 and damage[6].amount==80 and damage[8].amount==80)
    end
    assert(not service._test.meteor_locked("10") and next(slow)==nil)
    local impact_ids={}
    for id=first,#particles do
        assert(particles[id].name~="particles/survival/skills/meteor_impact.vpcf",
            "the old custom explosion root must never be emitted")
        if particles[id].name==impact then impact_ids[#impact_ids+1]=id end
    end
    assert(#impact_ids==(level==5 and 2 or 1))
    assert_damage_schedule(level,0)
    advance(8.399)
    assert(particles[impact_ids[1]].destroy==0,"complete native tail survives cast unlock and legacy 1.2s cutoff")
    advance(8.4)
    assert(particles[impact_ids[1]].destroy==1 and not particles[impact_ids[1]].immediate)
    if level==5 then
        assert(particles[impact_ids[2]].destroy==0,"second meteor owns an independent full tail")
        advance(8.899);assert(particles[impact_ids[2]].destroy==0)
        advance(8.9);assert(particles[impact_ids[2]].destroy==1 and not particles[impact_ids[2]].immediate)
    end
    advance(10);service._test.clear_meteors();service._test.clear_meteors();once(first)
    assert(scheduler.task_count()==0,"all cast/impact cleanup callbacks retired")
end
require_impact_before_deal=false
-- Effect allocation/control errors are presentation failures only.
for _,failure in ipairs({impact,lava,fly,"control"}) do
    clock=10;damage={};local first=#particles+1
    fail_particle=failure;fail_control=failure=="control"
    assert(service._test.runners.proto_meteor(context(2),definition))
    advance(10);advance(10.4);advance(11.4);advance(12.4);advance(13.4);advance(16)
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
-- Already emitted full native impacts keep their independent cleanup timer.
advance(39);once(first)
removed=false
-- A fatal hit cannot consume a world-positioned effect, and movement after
-- trigger cannot retarget either the burst or the damage search.
clock=40;damage={};first=#particles+1
target_position=Vector(4096,-3072,384);require_impact_before_deal=true
assert(service._test.runners.proto_meteor(context(1),definition))
target_position=Vector(4200,-2900,384) -- moved, still inside the original fixed impact area
advance(40);kill_on_hit=true;advance(40.4);kill_on_hit=false
local fatal_impact
for id=first,#particles do if particles[id].name==impact then fatal_impact=particles[id] end end
assert(#damage==1 and damage[1].amount==300 and target_removed)
assert(last_query_position.x==4096 and last_query_position.y==-3072)
assert(fatal_impact and fatal_impact.controls[0].x==4096 and fatal_impact.controls[0].y==-3072)
assert(fatal_impact.controls[3].x==4096 and fatal_impact.controls[3].y==-3072 and fatal_impact.controls[3].z==484,
    "a distant moved target leaves both impact position and vertical normal at the trigger snapshot")
assert(fatal_impact.controls[1].x==1 and fatal_impact.controls[1].y==1 and fatal_impact.controls[1].z==1)
assert(not service._test.meteor_locked("10") and fatal_impact.destroy==0,
    "a level-one fatal hit unlocks gameplay while its full impact tail remains")
advance(48.399);assert(fatal_impact.destroy==0)
advance(48.4);once(first)
target_alive=true;target_removed=false;target_position=Vector(128,192,384)
require_impact_before_deal=false

-- Only the new impact helper is injected with invalid engine returns; existing
-- fall and lava behavior and both tiers' complete damage schedules stay real.
local strict_cases={"nil","false","negative","fractional","nan","infinity","cp_false","cp_throw","cp3_false","cp3_throw"}
for _,level in ipairs({2,5}) do
    for _,failure in ipairs(strict_cases) do
        clock=60;damage={};first=#particles+1
        create_mode=failure:find("cp_",1,true) and nil or failure
        control_mode=failure=="cp_false" and "false" or failure=="cp_throw" and "throw"
            or failure=="cp3_false" and "cp3_false" or failure=="cp3_throw" and "cp3_throw" or nil
        assert(service._test.runners.proto_meteor(context(level),definition))
        for _,offset in ipairs({0,0.4,0.5,0.9,1.4,1.9,2.4,2.9,3.4,3.9}) do advance(60+offset) end
        local total=0;for _,hit in ipairs(damage) do total=total+hit.amount end
        assert(#damage==(level==5 and 8 or 4) and total==(level==5 and 1080 or 600),
            "strict visual failure preserves each damage clock: "..failure)
        assert(next(impact_visual.active())==nil and not service._test.meteor_locked("10") and next(slow)==nil)
        assert_damage_schedule(level,60)
        service._test.clear_meteors();once(first)
        create_mode=nil;control_mode=nil
    end
end

-- Clear revokes ownership before callbacks; no reentrant allocation survives.
clock=80;first=#particles+1
local visual_id=assert(impact_visual.impact(Vector(128,192,384),caster,500))
local nested_id,nested_reason
reenter=function()
    impact_visual.clear()
    nested_id,nested_reason=impact_visual.impact(Vector(128,192,384),caster,500)
end
impact_visual.clear();impact_visual.clear();once(first)
assert(nested_id==nil and nested_reason=="visuals_clearing" and next(impact_visual.active())==nil)

-- A same-world reset during allocation rolls back the temporary ID exactly once.
first=#particles+1
create_reenter=function() impact_visual.clear() end
assert(not impact_visual.impact(Vector(128,192,384),caster,500));once(first)
assert(next(impact_visual.active())==nil and scheduler.task_count()==0)

-- Independent cleanup attempts survive false/throw returns without double calls.
for _,mode in ipairs({"false","throw"}) do
    for _,method in ipairs({"destroy","release"}) do
        first=#particles+1
        visual_id=assert(impact_visual.impact(Vector(128,192,384),caster,500))
        destroy_mode=method=="destroy" and mode or nil
        release_mode=method=="release" and mode or nil
        assert(impact_visual.release(visual_id,true)==false)
        impact_visual.release(visual_id,true);impact_visual.clear();once(first)
        destroy_mode=nil;release_mode=nil
    end
end

-- Old-world timers and rollback must not touch a reused integer ID.
clock=100
local old_visual_id=assert(impact_visual.impact(Vector(128,192,384),caster,500))
local old_record=impact_visual.active()[old_visual_id]
local reused_id=old_record.particle
local old_particle=particles[reused_id]
world={};clock=101;forced_id=reused_id
local new_visual_id=assert(impact_visual.impact(Vector(200,200,384),caster,500))
local new_particle=particles[reused_id]
assert(new_particle~=old_particle)
clock=108;scheduler.think()
assert(impact_visual.active()[old_visual_id]==nil and impact_visual.active()[new_visual_id])
assert(new_particle.destroy==0 and new_particle.release==0,
    "a stale visual timer cannot destroy or release the new world's reused ID")
clock=109;scheduler.think()
assert(new_particle.destroy==1 and new_particle.release==1)

clock=120
visual_id=assert(impact_visual.impact(Vector(128,192,384),caster,500))
local transitioning_id=impact_visual.active()[visual_id].particle
local transitioning_particle=particles[transitioning_id]
local replacement
reenter=function()
    world={};forced_id=transitioning_id
    local replacement_id=assert(impact_visual.impact(Vector(300,300,384),caster,500))
    replacement=particles[impact_visual.active()[replacement_id].particle]
end
impact_visual.release(visual_id,true)
assert(transitioning_particle.destroy==1 and transitioning_particle.release==0)
assert(replacement and replacement.destroy==0 and replacement.release==0,
    "Destroy switching world must skip Release on the new owner's ID")
impact_visual.clear()
assert(replacement.destroy==1 and replacement.release==1)

for _,phase in ipairs({"create","cp"}) do
    clock=140
    local overwritten
    local function switch_world(id)
        world={};overwritten={name="fresh-world-owner",destroy=0,release=0};particles[id]=overwritten
    end
    if phase=="create" then create_reenter=switch_world else control_reenter=switch_world end
    assert(not impact_visual.impact(Vector(128,192,384),caster,500))
    assert(overwritten and overwritten.destroy==0 and overwritten.release==0,
        "allocation/CP rollback must not touch new-world ownership")
    impact_visual.clear()
end
assert(next(impact_visual.active())==nil and scheduler.task_count()==0)
print("METEOR_VISUAL_TIMING_PASS 5 tiers, 0.4s fall, 300/600/1080 damage and clocks, unchanged 500 radius/lava/slow/second meteor; complete independent 8s tails, fatal snapshot, strict engine failures, clear reentry, world ID reuse")
