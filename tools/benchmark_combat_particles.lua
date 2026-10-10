-- Standalone Lua only; native API is counted, not simulated as retained tables.
assert(not GameRules, "Run outside the game")
package.path = "scripts/vscripts/?.lua;" .. package.path
local clock, native_id, creates, controls, releases = 0, 0, 0, 0, 0
local housekeeping={}
package.loaded["core/scheduler"]={every=function(delay,fn,id) housekeeping[id]={delay=delay,fn=fn,next_at=delay} end,
    cancel=function(id) housekeeping[id]=nil end}
CustomGameEventManager={RegisterListener=function() end}
GameRules = {GetGameTime=function() return clock end}
PlayerResource = {IsValidPlayerID=function(_,id) return id==0 end,
    GetPlayer=function() return {} end}
ParticleManager = {
    CreateParticle=function() native_id=native_id+1;creates=creates+1;return native_id end,
    SetParticleControl=function() controls=controls+1 end,
    DestroyParticle=function() end,
    ReleaseParticleIndex=function() releases=releases+1 end,
}
local service = assert(loadfile(arg[1] or "scripts/vscripts/systems/combat_effect_visibility.lua"))()
service.init()
local pm = service.manager()
local function retained()
    for i=1,30 do
        local name,value=debug.getupvalue(pm.CreateParticle,i)
        if not name then break end
        if name=="records" then local n=0;for _ in pairs(value) do n=n+1 end;return n end
    end
    error("Records unavailable")
end
collectgarbage("collect")
local base, started = collectgarbage("count"), os.clock()
for i=1,60000 do
    clock=i/500
    local id=pm:CreateParticle("particles/test_hit.vpcf",0,nil)
    pm:SetParticleControl(id,0,i);pm:SetParticleControl(id,1,i)
    pm:ReleaseParticleIndex(id)
    for _,task in pairs(housekeeping) do
        if clock>=task.next_at then task.fn();task.next_at=clock+task.delay end
    end
    if i==10000 or i==30000 or i==60000 then
        collectgarbage("collect")
        print(string.format("PARTICLE_BURSTS n=%d records=%d heap_kib=%.1f cpu_s=%.4f creates=%d releases=%d",
            i,retained(),collectgarbage("count")-base,os.clock()-started,creates,releases))
    end
end
local owned={}
for i=1,256 do owned[i]=pm:CreateParticle("particles/test_beam.vpcf",0,nil) end
collectgarbage("collect")
base,started=collectgarbage("count"),os.clock()
for tick=1,900 do
    for _,id in ipairs(owned) do
        pm:SetParticleControl(id,0,tick);pm:SetParticleControl(id,1,tick);pm:SetParticleControl(id,9,tick)
    end
end
print(string.format("PARTICLE_CONTROLS updates=%d cpu_s=%.4f controls=%d",256*900*3,os.clock()-started,controls))
for _,id in ipairs(owned) do pm:DestroyParticle(id,true);pm:ReleaseParticleIndex(id) end
print("PARTICLE_FINAL records="..retained())
