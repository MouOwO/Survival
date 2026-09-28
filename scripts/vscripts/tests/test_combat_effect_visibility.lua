package.path="scripts/vscripts/?.lua;"..package.path
local clock,serial=0,0
GameRules={GetGameTime=function()return clock end}
local players={[0]={id=0},[1]={id=1}}
PlayerResource={IsValidPlayerID=function(_,id)return players[id]~=nil end,GetPlayer=function(_,id)return players[id]end}
local particles={}
ParticleManager={}
function ParticleManager:CreateParticle(path,attach,owner)
 serial=serial+1;particles[serial]={path=path,audience="all"};return serial
end
function ParticleManager:CreateParticleForPlayer(path,attach,owner,player)
 local id=self:CreateParticle(path,attach,owner);particles[id].audience=player.id;return id
end
function ParticleManager:SetParticleControl(id,point,value)
 assert(particles[id] and not particles[id].destroyed,"native handle only")
 particles[id][point]=value
end
function ParticleManager:DestroyParticle(id)
 assert(particles[id] and not particles[id].destroyed,"no duplicate destruction")
 particles[id].destroyed=true
end
function ParticleManager:ReleaseParticleIndex(id)
 assert(particles[id] and not particles[id].released,"no duplicate release")
 particles[id].released=true
end
local service=require("systems/combat_effect_visibility")
local pm=service.manager()
local a=pm:CreateParticle("hero_area",1,{})
pm:SetParticleControl(a,1,123)
assert(serial==1 and particles[1].audience=="all")
service.set_reduced(0,true)
assert(particles[1].destroyed and particles[1].released)
assert(serial==2 and particles[2].audience==1 and particles[2][1]==123)
local b=pm:CreateParticle("tower_hit",1,{})
pm:SetParticleControl(b,1,456);pm:ReleaseParticleIndex(b)
assert(particles[3].audience==1 and particles[3].released)
service.set_reduced(1,true)
assert(particles[2].destroyed and serial==3,"all reduced: no cosmetic particles")
local c=pm:CreateParticle("tower_lightning",1,{})
pm:SetParticleControl(c,1,789)
service.set_reduced(0,false)
assert(serial==5 and particles[4].audience==0 and particles[5].audience==0)
local count=0
for i=4,5 do if particles[i][1]==789 then count=count+1 end end
assert(count==1,"persistent controls restored when effects re-enabled")
pm:DestroyParticle(a,true);pm:ReleaseParticleIndex(a)
pm:DestroyParticle(a,true);pm:ReleaseParticleIndex(a)
pm:DestroyParticle(c,true);pm:ReleaseParticleIndex(c)
pm:DestroyParticle(b,true);pm:ReleaseParticleIndex(b)
print("COMBAT_EFFECT_VISIBILITY_PASS: two viewers isolated, immediate persistent switch, controls restored, all-reduced allocation zero, idempotent lifecycle")

local deleted=false
local owner={IsNull=function()return deleted end}
local d=pm:CreateParticle("persistent_owner",1,owner)
deleted=true
local before=serial
service.set_reduced(1,false)
assert(serial==before,"removed owners are not reattached to effects")
pm:DestroyParticle(d,true);pm:ReleaseParticleIndex(d)
