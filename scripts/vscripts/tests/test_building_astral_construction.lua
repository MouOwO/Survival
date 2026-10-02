package.path="scripts/vscripts/?.lua;"..package.path
local clock=10
GameRules={GetGameTime=function()return clock end}
Vector=function(x,y,z)return {x=x,y=y,z=z} end
PATTACH_WORLDORIGIN=0
class=function(value)return value or {} end
IsServer=function()return true end
MODIFIER_STATE_INVULNERABLE,MODIFIER_STATE_UNSELECTABLE=1,2
MODIFIER_STATE_DISARMED,MODIFIER_STATE_NO_HEALTH_BAR=3,4
local messages,particles,health_messages={},{},{}
local health_writes=0
CustomNetTables={SetTableValue=function(_,name,key,value)
    if name=="survival_hero_health_bar" then
        health_messages[key]=value;health_writes=health_writes+1
    else assert(name=="survival_ui_state");messages[key]=value end
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
local unit={hidden=false,hull=128,health=100}
function unit:IsNull()return false end
function unit:entindex()return 12 end
function unit:GetAbsOrigin()return Vector(64,128,32) end
function unit:GetTeamNumber()return 2 end
function unit:AddNoDraw()self.hidden=true end
function unit:RemoveNoDraw()self.hidden=false end
function unit:SetRenderAlpha(value)self.alpha=value end
function unit:SetHullRadius()error("visuals must not change collision")end
function unit:GetHealth()return self.health end
function unit:GetMaxHealth()return 100 end
function unit:IsAlive()return true end
function unit:HasModifier(name)return name=="modifier_building_under_construction" and self.constructing end
-- No IsNoDraw API: construction state alone must suppress the custom bar.
local bar_class=require("modifiers/modifier_single_health_bar")
local bar=setmetatable({GetParent=function()return unit end,StartIntervalThink=function()end},{__index=bar_class})
function unit:FindModifierByName(name)if name=="modifier_single_health_bar" then return bar end end
bar:OnCreated();assert(health_messages.unit_12.health==100)
local native_state=require("modifiers/modifier_building_under_construction"):CheckState()
assert(native_state[MODIFIER_STATE_NO_HEALTH_BAR] and native_state[MODIFIER_STATE_INVULNERABLE])
unit.constructing=true;unit.health=1
local definitions=require("config/generated/building_construction_rules")
local visual=require("systems/building_construction_visual_service")
for _,row in ipairs(definitions.rows) do
    assert(row.build_loop_particle:find("obsidian_destroyer_prison.vpcf",1,true))
    assert(row.build_complete_particle:find("obsidian_destroyer_prison_end.vpcf",1,true))
end
local state=visual.start(unit,definitions.by_id.wall)
assert(unit.hidden and unit.hull==128 and #particles==1)
assert(health_messages.unit_12.removed==1,"construction start immediately removes the custom bar")
local before=health_writes
for value=2,99 do unit.health=value;bar:OnIntervalThink() end
assert(health_writes==before,"construction health changes must not publish hidden bars")
local data=messages.construction_12
assert(data.text=="建造中" and data.start==10 and data.duration==3 and data.x==64)
clock=12.9
assert(unit.hidden,"model stays hidden until authoritative complete")
clock=13
unit.constructing=false;unit.health=100
assert(visual.complete(state) and not unit.hidden and unit.hull==128)
assert(health_messages.unit_12.health==100 and not health_messages.unit_12.removed,
    "completion immediately restores the custom health bar")
assert(messages.construction_12.removed==1 and particles[1].destroyed and particles[1].released)
assert(#particles==2 and particles[2].released and not particles[2].destroyed)
assert(not visual.complete(state),"completion is idempotent")
unit.constructing=true
state=visual.start(unit,definitions.by_id.wall)
assert(visual.cancel(state) and unit.hidden and messages.construction_12.removed==1)
assert(health_messages.unit_12.removed==1,"cancellation must not reveal a health bar")
fail=true
state=visual.start(unit,definitions.by_id.wall)
assert(unit.hidden and messages.construction_12.text=="建造中","particle errors must never reveal unfinished model")
visual.cancel(state)
assert(visual._active_count_for_test()==0)
print("ASTRAL_CONSTRUCTION_PASS: native W, world anchor, hidden until complete, progress, collision untouched, cancel and particle failure")
