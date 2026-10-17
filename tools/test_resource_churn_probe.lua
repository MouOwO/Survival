package.path='scripts/vscripts/?.lua;'..package.path
local time,w=0,{}
GameRules={GetGameTime=function() return time end,GetGameModeEntity=function() return w end}
function IsInToolsMode() return true end
function IsServer() return true end
function GetMapName() return 'template_map' end
SURVIVAL_REAL_GAME_STRESS_ISOLATION={mode=w}
local tasks={}
package.loaded['core/scheduler']={after=function(_,fn,id) tasks[id]=fn end,cancel=function(id) tasks[id]=nil end}
local id=0
ParticleManager={CreateParticle=function(_,path) if path=='invalid' then return -1 end; id=id+1; return id,nil,'tail' end,
    DestroyParticle=function() return 'destroy' end,ReleaseParticleIndex=function() return nil,'released' end,
    SetParticleControl=function(_,_,_,value) if value=='fail' then error('native_failure') end end,
    SetParticleControlEnt=function() end}
function CreateUnitByName(name) return {name=name},nil,4 end
function SpawnEntityFromTableSynchronous(name) return {class=name} end
function UTIL_Remove() return false,nil,7 end
local original=ParticleManager.CreateParticle
local p=require('tests/manual_resource_churn_probe')
assert(ParticleManager.CreateParticle==original and next(tasks)==nil,'require must be inert')
assert(not pcall(p.start,{}),'explicit enable required')
p.start({enabled=true,duration_seconds=10})
local a,b,c=ParticleManager:CreateParticle('hit'); assert(a==1 and b==nil and c=='tail')
ParticleManager:DestroyParticle(a,true)
local x,y=ParticleManager:ReleaseParticleIndex(a); assert(x==nil and y=='released')
local unit,nilvalue,tail=CreateUnitByName('test_unit'); assert(unit.name=='test_unit' and nilvalue==nil and tail==4)
local f,n,z=UTIL_Remove(unit); assert(f==false and n==nil and z==7)
assert(ParticleManager:CreateParticle('invalid')==-1)
local ok,e=pcall(ParticleManager.SetParticleControl,ParticleManager,1,0,'fail'); assert(not ok and tostring(e):find('native_failure'))
local s=p.snapshot(); assert(s.peak_observed_particle_handles==1 and s.outstanding_observed_particle_handles==0 and s.invalid_particle_results==1)
assert(s.calls.CreateParticle==2 and s.paths.CreateParticle.hit==1 and s.errors.SetParticleControl==1)
local foreign=function() return 'foreign' end; ParticleManager.DestroyParticle=foreign
local final=p.stop('done'); assert(final.restore_conflicts[1]=='DestroyParticle' and ParticleManager.DestroyParticle==foreign)
assert(ParticleManager.CreateParticle==original and next(tasks)==nil)
p.start({enabled=true,duration_seconds=1}); w={}; CreateUnitByName('other_world')
assert(p.snapshot().calls.CreateUnitByName==nil,'other world must bypass diagnostic bookkeeping')
p.stop('world_changed')
SURVIVAL_REAL_GAME_STRESS_ISOLATION={mode=w}
p.start({enabled=true,duration_seconds=1});time=1;tasks.manual_resource_churn_probe()
assert(SURVIVAL_RESOURCE_CHURN_LAST_REPORT.reason=='bounded_duration' and not p.snapshot().active)
assert(ParticleManager.CreateParticle==original and next(tasks)==nil)
print('RESOURCE_CHURN_PROBE_PASS: inert, opt-in, return arity, native exceptions, ownership, foreign hooks, world boundary, bounded restoration')
