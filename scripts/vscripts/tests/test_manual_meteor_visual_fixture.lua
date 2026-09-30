-- Simulation uses the production meteor runner, particles and scheduler.
package.path = "scripts/vscripts/?.lua;" .. package.path
local now, world, units, particles, pending_load = 0, {}, {}, {}, nil
local vector_mt = {}
Vector = function(x,y,z) return setmetatable({x=x,y=y,z=z},vector_mt) end
vector_mt.__add = function(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
GameRules = {GetGameTime=function()return now end,GetGameModeEntity=function()return world end}
local tools_mode, occupied, blocked = true, false, false
IsServer = function() return true end
IsInToolsMode = function() return tools_mode end
GetGroundHeight = function() return 384 end
GetGroundPosition = function(p) return Vector(p.x,p.y,384) end
GridNav = {IsTraversable=function()return not blocked end,IsBlocked=function()return blocked end}
DOTA_TEAM_GOODGUYS=2;DOTA_UNIT_TARGET_TEAM_ENEMY=1;DOTA_UNIT_TARGET_TEAM_BOTH=3
DOTA_UNIT_TARGET_FLAG_INVULNERABLE=1;DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES=2
DOTA_UNIT_TARGET_HERO=4;DOTA_UNIT_TARGET_BASIC=8;DOTA_UNIT_TARGET_BUILDING=16
DOTA_UNIT_CAP_NO_ATTACK=0;DOTA_UNIT_CAP_MOVE_NONE=0;FIND_ANY_ORDER=0;PATTACH_WORLDORIGIN=6
FindUnitsInRadius = function(_,_,_,_,team)
    if team == DOTA_UNIT_TARGET_TEAM_ENEMY then return {} end
    if occupied then return {{}} end
    local result={}
    for _,unit in ipairs(units) do if not unit.removed then result[#result+1]=unit end end
    return result
end
package.loaded["systems/unit_health_bar_service"]={exclude=function(unit)unit.bar_excluded=true end}
package.loaded["systems/buff_manager"]={apply=function()error("preview must not apply debuffs")end,
    remove=function()error("preview must not remove debuffs")end}
package.loaded["systems/hero_exclusive_passive_service"]={runners={}}
package.loaded["core/sound_service"]={play=function()end}
PrecacheUnitByNameAsync=function(name,callback,pid)
    assert(name=="asset_proxy_monster_juggernaut" and pid==-1)
    pending_load=callback
end
local function unit(id,point)
    local u={id=id,point=point}
    function u:IsNull()return self.removed==true end
    function u:IsAlive()return not self.removed end
    function u:entindex()return self.id end
    function u:GetAbsOrigin()return self.point end
    function u:GetTeamNumber()return DOTA_TEAM_GOODGUYS end
    function u:SetAbsOrigin(p)self.point=p end
    function u:FindAbilityByName()return nil end
    for _,method in ipairs({"SetIdleAcquire","SetAcquisitionRange","SetAttackCapability",
        "SetMoveCapability","SetHullRadius","SetDayTimeVisionRange","SetNightTimeVisionRange",
        "AddNewModifier","AddNoDraw"}) do u[method]=function()end end
    return u
end
CreateUnitByName=function(name,point,_,owner,hero,team)
    assert(name=="asset_proxy_monster_juggernaut" and not owner and not hero and team==2)
    local u=unit(#units+1,point);units[#units+1]=u;return u
end
UTIL_Remove=function(u) assert(not u.removed);u.removed=true end
ParticleManager={
    CreateParticle=function(_,name,attach,owner)
        assert(attach==6)
        local id=#particles+1
        particles[id]={name=name,owner=owner,cp={}}
        return id
    end,
    SetParticleControl=function(_,id,cp,value)particles[id].cp[cp]=value end,
    DestroyParticle=function(_,id)assert(not particles[id].destroyed);particles[id].destroyed=true end,
    ReleaseParticleIndex=function(_,id)assert(particles[id].destroyed);particles[id].released=true end,
}
local bus=require("core/event_bus")
local emitted=0
bus.emit=function()emitted=emitted+1 end
bus.handle_request(require("combat/combat_events").DEAL_REQUEST,function()error("empty preview cannot deal damage")end)
local service=require("systems/hero_passive_skill_service")
local scheduler=require("core/scheduler")
local definition=require("config/hero_passive_skill_definitions").by_id.proto_meteor
local fixture_api=require("tests/manual_meteor_visual_review")
local function advance(seconds)
    for _=1,math.floor(seconds/0.05+0.5) do now=now+0.05;scheduler.think() end
end
tools_mode=false
assert(not fixture_api.run().ok)
tools_mode,blocked=true,true
assert(not fixture_api.run().ok)
blocked,occupied=false,true
assert(not fixture_api.run().ok)
occupied=false
local cancelled=fixture_api.run()
assert(cancelled.phase=="loading" and #units==0)
fixture_api.cleanup();pending_load()
assert(#units==0,"cancelled async request cannot spawn proxies")
-- Another real meteor cast must survive fixture cleanup untouched.
local external_caster=unit(9000,Vector(9000,9000,384))
local external_target=unit(9001,Vector(9000,9000,384))
assert(service._test.runners.proto_meteor({attacker=external_caster,target=external_target,
    level=5,player_id=-1,skill_id="proto_meteor",attack_id="other-cast",
    attributes={all_attributes=0}},definition))
local fixture=fixture_api.run({level=1,count=3})
pending_load();pending_load()
assert(#units==2 and fixture.casts_started==1,"one caster and target, duplicate callback safe")
local active=service._test.active_meteor_casts()[fixture.caster_key]
assert(active.context.player_id==-1 and active.context.attributes.all_attributes==0)
assert(active.radius==500 and active.fall_duration==0.8 and active.move_slow_pct==0)
assert(definition.lava_move_slow_pct[5]==30,"preview cannot mutate production definition")
assert(fixture_api.cleanup().pending)
advance(2.4)
assert(fixture.finished and fixture.casts_started==1 and units[1].removed and units[2].removed)
assert(service._test.active_meteor_casts()["9000"],"cleanup must not clear another caster")
advance(3)
assert(next(service._test.active_meteor_casts())==nil)
for _,p in ipairs(particles)do assert(p.destroyed and p.released)end
local repeat_fixture=fixture_api.run({level=5,count=2})
pending_load()
assert(repeat_fixture.casts_started==1)
advance(10.5)
assert(repeat_fixture.finished and repeat_fixture.phase=="complete"
    and repeat_fixture.casts_started==2,"bounded repeats use real cast cooldown")
assert(emitted==0,"empty isolated real runner must not emit global skill/equipment/hero events")
for _,u in ipairs(units)do assert(u.removed and u.bar_excluded)end
for _,p in ipairs(particles)do assert(p.destroyed and p.released)end
assert(scheduler.task_count()==0)
fixture_api.cleanup()
local stale=fixture_api.run()
world={};pending_load();stale:cleanup()
assert(#units==4,"old-world async request must not create proxies")
print("MANUAL_METEOR_FIXTURE_PASS real_runner/timing/zero_stats/no_events/isolated_cleanup/repeats/async/world")
