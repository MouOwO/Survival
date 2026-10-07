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

-- All persistent model appearances survive the same switch which still filters
-- optional combat bursts. Use the production catalog, including Io's body.
service.set_reduced(0,true)
service.set_reduced(1,true)
local checked, seen = 0, {}
for _,asset in ipairs(require("config/asset_catalog").rows) do
 for _,effect in ipairs(asset.enabled ~= false and asset.environment_particles or {}) do
  local path=type(effect)=="table" and effect.path or effect
  if not seen[path] then
   seen[path]=true
   local prior=serial
   local handle=pm:CreateParticle(path,1,{})
   assert(serial==prior+1 and particles[serial].audience=="all", "model body filtered: "..path)
   local native_handle=serial
   pm:SetParticleControl(handle,1,321)
   service.set_reduced(0,false)
   service.set_reduced(0,true)
   assert(serial==native_handle and not particles[native_handle].destroyed, "body recreated by toggle: "..path)
   pm:DestroyParticle(handle,true);pm:ReleaseParticleIndex(handle)
   assert(particles[native_handle].destroyed and particles[native_handle].released)
   checked=checked+1
  end
 end
end
assert(checked > 0, "catalog must contain appearance particles")
local prior=serial
local combat=pm:CreateParticle("optional_tower_hit",1,{})
assert(serial==prior, "optional combat filtering was disabled")
pm:DestroyParticle(combat,true);pm:ReleaseParticleIndex(combat)
print("MODEL_PARTICLE_VISIBILITY_PASS: "..checked.." catalog appearances remain visible; combat remains filtered")
