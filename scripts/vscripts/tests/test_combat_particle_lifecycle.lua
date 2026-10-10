package.path="scripts/vscripts/?.lua;"..package.path
local world,time,next_id={},0,0
local tasks={}
GameRules={GetGameTime=function() return time end,GetGameModeEntity=function() return world end}
package.loaded["core/scheduler"]={cancel=function(id) tasks[id]=nil end}
CustomGameEventManager={RegisterListener=function() end}
local players={[0]={},[1]={},[2]={}}
PlayerResource={IsValidPlayerID=function(_,id) return players[id]~=nil end,
    GetPlayer=function(_,id) return players[id] end}
local native,fail,reenter={}
ParticleManager={
    CreateParticle=function()
        if fail then return -1 end
        next_id=next_id+1;native[next_id]={};return next_id
    end,
    CreateParticleForPlayer=function(self,...)
        return self:CreateParticle(...)
    end,
    SetParticleControl=function(_,id,cp,value)
        assert(native[id] and not native[id].released,"released/recycled native ID controlled")
        native[id][cp]=value
    end,
    SetParticleControlEnt=function(_,id,cp,entity,attach,name,position,follow)
        assert(native[id] and not native[id].released)
        native[id].binding={cp,entity,attach,name,position,follow}
    end,
    DestroyParticle=function(_,id)
        assert(not native[id].destroyed,"duplicate native destruction")
        native[id].destroyed=true
        if reenter then local fn=reenter;reenter=nil;fn() end
    end,
    ReleaseParticleIndex=function(_,id)
        assert(not native[id].released,"duplicate native release")
        native[id].released=true
    end,
}
local service=require("systems/combat_effect_visibility")
service.init()
local pm=service.manager()
local burst=pm:CreateParticle("hit",0,nil)
pm:SetParticleControl(burst,0,1);pm:ReleaseParticleIndex(burst)
assert(service.debug_snapshot().owned_records==0)
pm:SetParticleControl(burst,0,999);pm:DestroyParticle(burst,true);pm:ReleaseParticleIndex(burst)
assert(native[1][0]==1 and not native[1].destroyed,"released finite burst finishes naturally")
fail=true
assert(not pcall(pm.CreateParticle,pm,"invalid",0,nil),"invalid native ID must be surfaced to tower retries")
assert(service.debug_snapshot().owned_records==0)
fail=false
local id=pm:CreateParticle("beam",0,{})
for i=1,1000 do pm:SetParticleControl(id,1,i) end
pm:SetParticleControlEnt(id,0,{},2,"head",{},true)
service.set_reduced(0,true)
assert(service.debug_snapshot().owned_native_handles==2)
for n=3,next_id do assert(native[n][1]==1000 and native[n].binding[6]==true,"latest controls and argument count replayed") end
-- A release reentered from a viewer switch must not spawn orphan children.
reenter=function() pm:ReleaseParticleIndex(id) end
service.set_reduced(0,false)
assert(service.debug_snapshot().owned_records==0)
for _,p in pairs(native) do assert(p.released,"switch reentry left an owned native handle") end
local old=pm:CreateParticle("old_world",0,nil)
local old_native=next_id
world={};service.init()
assert(not native[old_native].released and not native[old_native].destroyed,"old-world IDs cannot be reused for cleanup")
pm:DestroyParticle(old,true);pm:ReleaseParticleIndex(old)
assert(service.debug_snapshot().owned_records==0)
local same=pm:CreateParticle("same_world",0,nil)
local same_native=next_id
service.init()
assert(native[same_native].released and native[same_native].destroyed,"same-world reset cleans live ownership")
assert(service.debug_snapshot().owned_records==0)
print("COMBAT_PARTICLE_LIFECYCLE_PASS: immediate release, invalid native IDs, latest control replay, switch reentry, world reset")
