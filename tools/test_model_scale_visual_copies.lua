-- Exercise the real shell, wall death, guardian and title services together.
package.path="scripts/vscripts/?.lua;"..package.path
local now,serial=0,0
local tasks,spawned,particles={},{},{}
package.loaded["core/scheduler"]={
    every=function(_,callback,id)tasks[id]=callback;return id end,
    cancel=function(id)tasks[id]=nil end,
}
local vector_mt={__add=function(a,b)return Vector(a.x+b.x,a.y+b.y,a.z+b.z)end}
Vector=function(x,y,z)return setmetatable({x=x,y=y,z=z},vector_mt)end
GameRules={GetGameTime=function()return now end}
PATTACH_WORLDORIGIN=0
local function near(a,b,label)assert(math.abs(a-b)<1e-8,(label or "scale")..": "..tostring(a).." vs "..tostring(b))end
local function entity(name,model)
    serial=serial+1
    local e={index=serial,name=name,model=model,scale=1,origin=Vector(100,200,384),angles={y=90}}
    function e:IsNull()return self.removed end
    function e:IsAlive()return not self.dead end
    function e:entindex()return self.index end
    function e:GetUnitName()return self.name end
    function e:GetModelName()return self.model end
    function e:GetModelScale()return self.scale end
    function e:SetModelScale(v)self.scale=v end
    function e:GetAbsOrigin()return self.origin end
    function e:SetAbsOrigin(v)self.origin=v end
    function e:GetAnglesAsVector()return self.angles end
    function e:SetAngles(x,y,z)self.angles={x=x,y=y,z=z}end
    function e:SetLocalAngles(x,y,z)self.local_angles={x=x,y=y,z=z}end
    function e:SetOwner(v)self.owner=v end
    function e:SetParent(v)self.parent=v end
    function e:SetLocalOrigin(v)self.offset=v end
    function e:FollowEntity(v)self.follow=v end
    function e:ResetSequence(v)self.sequence=v end
    function e:SetCycle(v)self.cycle=v end
    function e:SetMaterialGroup(v)self.material=v end
    function e:SetRenderAlpha(v)self.alpha=v end
    function e:AddNoDraw()self.hidden=true end
    function e:RemoveNoDraw()self.hidden=false end
    function e:HasModifier()return false end
    return e
end
SpawnEntityFromTableSynchronous=function(class,values)
    assert(class=="prop_dynamic" and values.solid=="0","copies remain visual props without collision")
    local e=entity(class,values.model);spawned[#spawned+1]=e;return e
end
UTIL_Remove=function(e)e.removed=true end
DoEntFireByInstanceHandle=function(e,input,value)assert(input=="SetPlaybackRate" and value=="0");e.frozen=true end
ParticleManager={CreateParticle=function(_,path)local id=#particles+1;particles[id]={path=path,cp={}};return id end,
    SetParticleControl=function(_,id,cp,value)particles[id].cp[cp]=value end,
    DestroyParticle=function(_,id)particles[id].destroyed=true end,
    ReleaseParticleIndex=function(_,id)particles[id].released=true end}
local scale=require("visual/model_scale")
local shells=require("systems/building_white_shell")
local death=require("systems/wall_destruction_visual")
local shell_models=require("config/generated/building_white_shells")
local death_models=require("config/generated/wall_destruction_models")
local wall_model
for model in pairs(death_models)do if shell_models[model]then wall_model=model;break end end
assert(wall_model,"a real configured wall model has both shell and destruction visuals")
local wall=entity("building_wall",wall_model);wall.survival_building_id="wall"
assert(scale.apply(wall,2,"wall"))
local configured=assert(shells.create(wall,{id="wall",levels={{model_scale=2}}},3,false))
near(configured.entity.scale,2*2/3*1.006,"authored shell scale reduced once")
assert(configured.entity.origin.x==100 and configured.entity.origin.y==200 and configured.entity.origin.z==384,
    "world position is not scaled")
shells.destroy(configured)
local copied=assert(shells.create(wall,{id="wall",levels={{}}},3,false))
near(copied.entity.scale,wall.scale*1.006,"current shell fallback already contains final factor")
shells.destroy(copied)
local tower=entity("building_arrow_tower",wall_model);tower.survival_building_id="arrow_tower"
scale.apply(tower,1.8,"arrow_tower")
local tower_shell=assert(shells.create(tower,{id="arrow_tower",levels={{model_scale=1.8}}},3,false))
near(tower_shell.entity.scale,1.8*1.006,"tower shell retains exemption")
assert(scale.ensure(tower_shell.entity));near(tower_shell.entity.scale,1.8*1.006,"tower shell guard remains idempotent")
shells.destroy(tower_shell)

local dying=assert(death.play({unit=wall,building_id="wall"}))
near(dying.proxy.scale,wall.scale,"death proxy copies final wall scale")
near(dying.height,death_models[wall_model]*wall.scale,"destruction height follows the smaller wall")
assert(dying.origin.x==100 and dying.origin.y==200 and dying.origin.z==384)
near(particles[1].cp[1].x,128*wall.scale,"existing particle radius follows final scale")
death.reset();assert(death.active_count()==0)

local guardians=require("systems/challenge_guardian_visual_service")
for name,definition in pairs(guardians._definitions)do
    local owner=entity(name,"challenge.vmdl");scale.apply(owner,1)
    assert(guardians.apply(owner));local body=owner.survival_guardian_visual.body
    near(body.scale,definition.scale*2/3,"guardian prop scale")
    near(body.offset.x,definition.offset[1]*2/3,"guardian local x")
    near(body.offset.y,definition.offset[2]*2/3,"guardian local y")
    near(body.offset.z,definition.offset[3]*2/3,"guardian local z")
    assert(body.parent==owner and body.frozen and owner.origin.x==100)
    local before=#spawned;assert(guardians.apply(owner));assert(#spawned==before)
    guardians.clear(owner);assert(body.removed)
end

local titles=require("systems/title_model_service")
local hero=entity("npc_dota_hero_drow_ranger","hero.vmdl");scale.apply(hero,1.2)
local info=assert(titles.sync(0,hero,"peak_perfection"))
local body=spawned[#spawned]
near(body.scale,.48*2/3,"title prop scale");near(body.offset.z,285*2/3,"title local offset")
near(info.height,285*2/3,"title published height");near(info.width,178.4*2/3,"title published width")
local before=#spawned;assert(titles.sync(0,hero,"peak_perfection"));assert(#spawned==before)
titles.init();now=.5;tasks.title_mesh_update();near(body.offset.z,190,"title update retains reduced offset")
titles.clear(0);assert(body.removed)
print("MODEL_SCALE_VISUAL_COPIES_PASS configured/current shells, exempt tower, wall corpse+particles, guardian offsets and title mesh metadata; no world-position or collision changes")
