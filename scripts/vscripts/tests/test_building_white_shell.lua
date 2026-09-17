package.path="scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;"..package.path
local time=0
GameRules={GetGameTime=function() return time end}
local tasks={}
package.loaded["core/scheduler"]={
    every=function(_,fn,id) tasks[id]=fn;return id end,
    cancel=function(id) tasks[id]=nil end,
}
local created,removed={},{}
local fail_spawn=false
SpawnEntityFromTableSynchronous=function(class,kv)
    assert(class=="prop_dynamic" and kv.solid=="0" and kv.disableshadows=="1")
    assert(kv.model:find("_white_shell.vmdl",1,true))
    if fail_spawn then return nil end
    local entity={kv=kv,alpha=255}
    function entity:IsNull() return self.removed==true end
    function entity:SetAbsOrigin(pos) self.origin=pos end
    function entity:SetAngles(_,yaw) self.yaw=yaw end
    function entity:SetModelScale(scale) self.scale=scale end
    function entity:SetRenderAlpha(alpha) self.alpha=alpha end
    function entity:SetMaterialGroup(group) self.material_group=group end
    function entity:SetParent() error("white shell must not inherit hidden parent's visibility") end
    created[#created+1]=entity;return entity
end
UTIL_Remove=function(entity)
    assert(not entity.removed,"white shell removed twice")
    entity.removed=true;removed[#removed+1]=entity
end
local shell=require("systems/building_white_shell")
local unit={origin={x=64,y=-320,z=128},alive=true,no_draw=true,model="models/survival_buildings/main_city_lv01.vmdl"}
function unit:IsNull() return false end
function unit:IsAlive() return self.alive end
function unit:GetAbsOrigin() return self.origin end
function unit:GetModelName() return self.model end
function unit:GetModelScale() return 1 end
function unit:GetAnglesAsVector() return {x=0,y=-90,z=0} end
local def={levels={[1]={model_scale=1,model_yaw=0}}}
local hold=assert(shell.create(unit,def,3,false))
assert(hold.entity.origin==unit.origin and hold.entity.yaw==0 and hold.entity.alpha==255)
assert(hold.entity.scale==1.006 and unit.no_draw,"hidden source did not produce independent white geometry")
assert(hold.entity.kv.origin=="64.000000 -320.000000 128.000000","white shell lost world Z")
time=.5;assert(tasks[hold.task_id]())
assert(hold.entity.alpha==255,"hold phase pulses instead of staying white")
unit.origin={x=128,y=64,z=192};assert(tasks[hold.task_id]())
assert(hold.entity.origin==unit.origin,"relocated building left white shell behind")
shell.destroy(hold);shell.destroy(hold)
assert(#removed==1 and tasks[hold.task_id]==nil)
unit.model="models/survival_buildings/main_city_lv02.vmdl"
local reveal=assert(shell.create(unit,def,3,true))
assert(reveal.entity.kv.model:find("main_city_lv02_white_shell",1,true),"reveal bound the old level")
local callback=tasks[reveal.task_id]
local prior=0
for _,dt in ipairs({0,.2,.4,.6,.8,1.0,1.2,1.4}) do
    time=.5+dt;assert(callback())
    local step=tonumber((reveal.entity.material_group or "reveal_00"):match("(%d+)$"))
    assert(step>=prior and step<=shell.reveal_steps,"reveal curtain reversed direction")
    assert(reveal.entity.alpha==255,"curtain was replaced by whole-building fading")
    prior=step
end
time=2.1;assert(callback()==false and reveal.entity.removed)
assert(shell._active_count_for_test()==0)
local dead=assert(shell.create(unit,def,3,false))
unit.alive=false;assert(tasks[dead.task_id]()==false and dead.entity.removed)
unit.alive=true
local reset=assert(shell.create(unit,def,3,false));shell.reset()
assert(reset.entity.removed and next(tasks)==nil)
fail_spawn=true;assert(shell.create(unit,def,3,false)==nil and shell._active_count_for_test()==0)
print("BUILDING_WHITE_SHELL_PASS world_origin hidden_source south_geometry top_down_material_groups death reset failure")
