package.path="scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;"..package.path
local time,tasks=0,{}
local mt={__add=function(a,b)return Vector(a.x+b.x,a.y+b.y,a.z+b.z)end}
Vector=function(x,y,z)return setmetatable({x=x,y=y,z=z},mt)end
GameRules={GetGameTime=function()return time end}
PATTACH_WORLDORIGIN=0
package.loaded['core/scheduler']={
    every=function(_,fn,id)tasks[id]=fn;return id end,
    cancel=function(id)tasks[id]=nil end,
}
local spawned,particles,released,sounds={},{},{},0
local fail_spawn,fail_particle=false,false
SpawnEntityFromTableSynchronous=function(class,kv)
    assert(class=='prop_dynamic' and kv.solid=='0','visual debris must never block rebuilding')
    if fail_spawn then return nil end
    local p={kv=kv}
    function p:IsNull()return self.removed==true end
    function p:SetAbsOrigin(v)self.position=v end
    function p:SetAngles(x,y,z)self.angles=Vector(x,y,z)end
    function p:SetModelScale(s)self.scale=s end
    spawned[#spawned+1]=p;return p
end
UTIL_Remove=function(p)p.removed=true end
EmitSoundOnLocationWithCaster=function(_,name)assert(name=='Hero_Crystal.CrystalNova');sounds=sounds+1 end
ParticleManager={
    CreateParticle=function(_,name,attach,entity)
        assert(attach==PATTACH_WORLDORIGIN and entity==nil)
        if fail_particle then error('simulated missing particle') end
        particles[#particles+1]={name=name,cp={}};return #particles
    end,
    SetParticleControl=function(_,id,cp,value)particles[id].cp[cp]=value end,
    DestroyParticle=function(_,id,immediate)particles[id].destroyed=true;particles[id].immediate=immediate end,
    ReleaseParticleIndex=function(_,id)assert(not released[id],'double particle release');released[id]=true end,
}
local fx=require('systems/wall_destruction_visual')
local function unit(stage)
    local u={position=Vector(512,-256,128),model=string.format('models/survival_buildings/wall_lv%02d.vmdl',stage or 1)}
    function u:IsNull()return self.removed==true end
    function u:GetAbsOrigin()return self.position end
    function u:GetModelName()return self.model end
    function u:GetModelScale()return 1 end
    function u:GetAnglesAsVector()return Vector(0,180,0)end
    function u:AddNoDraw()self.hidden=true end
    function u:RemoveNoDraw()self.hidden=false end
    return u
end
local function state(u)return {building_id='wall',unit=u}end
local function advance(t)
    time=t;local pending={};for id,fn in pairs(tasks)do pending[id]=fn end
    for id,fn in pairs(pending)do if fn()==false then tasks[id]=nil end end
end
local u=unit(10);local h=assert(fx.play(state(u)));local proxy=h.proxy
assert(u.hidden and proxy.scale==1 and proxy.angles.y==180)
assert(h.origin.z==128 and math.abs(h.height-504.0458)<.001)
assert(#particles==2 and particles[1].cp[0].z>128+h.height*.95,'charge must clear the opaque wall deck')
assert(fx.play(state(u))==nil,'duplicate death must not create another effect')
advance(.2);local x=proxy.position.x
advance(.7);assert(proxy.position.x~=x and proxy.angles.y==180,'wall must shake without changing its facing')
assert(u.position.x==512 and u.position.y==-256,'real unit/grid origin moved')
u.removed=true -- Corpse removal cannot cut the independent destruction short.
advance(.999);assert(not h.exploded and not proxy.removed and #particles==2)
advance(1.0);assert(h.exploded and proxy.removed and #particles==6 and sounds==1)
assert(particles[3].cp[0].x==512 and particles[4].cp[0].z==140,'burst lost world position')
advance(1.1);assert(#particles==6 and sounds==1,'explosion replayed')
advance(2.7);assert(fx.active_count()==0 and next(tasks)==nil)
for i=1,#particles do assert(released[i] and particles[i].destroyed)end

-- The defeat callback sees all server handles released before freezing GameTime.
time=4;local final=assert(fx.play(state(unit(1))));local wins=0
fx.after_burst(final,function()wins=wins+1;assert(fx.active_count()==0)end)
advance(4.99);assert(wins==0)
advance(5.0);assert(final.exploded and wins==0)
advance(5.46);assert(wins==1 and next(tasks)==nil)
assert(particles[#particles].immediate==false,'finite burst must finish naturally at game over')
advance(7);assert(wins==1)

-- Reset cancels delayed defeat; new sessions cannot inherit a winner callback.
time=10;local reset=assert(fx.play(state(unit())))
fx.after_burst(reset,function()error('stale defeat after reset')end)
fx.reset();advance(13);assert(fx.active_count()==0 and next(tasks)==nil)
assert(fx.play({building_id='main_city',unit=unit()})==nil)
assert(fx.play({building_id='wall',constructing=true,unit=unit()})==nil)
local disconnected=unit();disconnected.survival_disconnect_cleanup=true
assert(fx.play(state(disconnected))==nil)
fail_spawn=true;local fallback=unit();assert(fx.play(state(fallback))==nil and not fallback.hidden)
local immediate=0;fx.after_burst(nil,function()immediate=immediate+1 end);assert(immediate==1)
fail_spawn=false;fail_particle=true;time=15
local degraded=assert(fx.play(state(unit())))
advance(16);assert(degraded.exploded);advance(18);assert(fx.active_count()==0)
local preloaded={};PrecacheResource=function(kind,path)preloaded[#preloaded+1]={kind,path}end
fx.precache({});assert(#preloaded==8)
print('WALL_DESTRUCTION_VISUAL_PASS shake=1s burst_once world_origin no_collision corpse_independent cleanup defeat_delay reset failure')
