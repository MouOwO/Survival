package.path="scripts/vscripts/?.lua;"..package.path
local clock=10
GameRules={GetGameTime=function()return clock end}
Vector=function(x,y,z)return {x=x,y=y,z=z} end
PATTACH_WORLDORIGIN=0
local messages,particles={},{}
CustomNetTables={SetTableValue=function(_,name,key,value)
    assert(name=="survival_ui_state");messages[key]=value
end}
local fail=false
ParticleManager={
    CreateParticle=function(_,path,attach,owner)
        assert(attach==PATTACH_WORLDORIGIN and owner==nil,"astral visual must not inherit hidden building rendering")
        if fail then error("test missing optional particle") end
        particles[#particles+1]={path=path};return #particles
    end,
    SetParticleControl=function(_,id,cp,point) assert(cp==0);particles[id].point=point end,
    DestroyParticle=function(_,id,immediate) assert(immediate);particles[id].destroyed=true end,
    ReleaseParticleIndex=function(_,id) particles[id].released=true end,
}
local unit={hidden=false,hull=128}
function unit:IsNull()return false end
function unit:entindex()return 12 end
function unit:GetAbsOrigin()return Vector(64,128,32) end
function unit:GetTeamNumber()return 2 end
function unit:AddNoDraw()self.hidden=true end
function unit:RemoveNoDraw()self.hidden=false end
function unit:SetRenderAlpha(value)self.alpha=value end
function unit:SetHullRadius()error("visuals must not change collision")end
local definitions=require("config/generated/building_construction_rules")
local visual=require("systems/building_construction_visual_service")
for _,row in ipairs(definitions.rows) do
    assert(row.build_loop_particle:find("obsidian_destroyer_prison.vpcf",1,true))
    assert(row.build_complete_particle:find("obsidian_destroyer_prison_end.vpcf",1,true))
end
local state=visual.start(unit,definitions.by_id.wall)
assert(unit.hidden and unit.hull==128 and #particles==1)
local data=messages.construction_12
assert(data.text=="建造中" and data.start==10 and data.duration==3 and data.x==64)
clock=12.9
assert(unit.hidden,"model stays hidden until authoritative complete")
clock=13
assert(visual.complete(state) and not unit.hidden and unit.hull==128)
assert(messages.construction_12.removed==1 and particles[1].destroyed and particles[1].released)
assert(#particles==2 and particles[2].released and not particles[2].destroyed)
assert(not visual.complete(state),"completion is idempotent")
state=visual.start(unit,definitions.by_id.wall)
assert(visual.cancel(state) and unit.hidden and messages.construction_12.removed==1)
fail=true
state=visual.start(unit,definitions.by_id.wall)
assert(unit.hidden and messages.construction_12.text=="建造中","particle errors must never reveal unfinished model")
visual.cancel(state)
assert(visual._active_count_for_test()==0)
print("ASTRAL_CONSTRUCTION_PASS: native W, world anchor, hidden until complete, progress, collision untouched, cancel and particle failure")
