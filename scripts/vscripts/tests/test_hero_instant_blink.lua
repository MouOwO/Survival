package.path='scripts/vscripts/?.lua;'..package.path
local vec={};vec.__index=vec
function Vector(x,y,z)return setmetatable({x=x,y=y,z=z or 0},vec)end
function vec.__add(a,b)return Vector(a.x+b.x,a.y+b.y,a.z+b.z)end
function vec.__sub(a,b)return Vector(a.x-b.x,a.y-b.y,a.z-b.z)end
function vec.__mul(a,b)return Vector(a.x*b,a.y*b,a.z*b)end
function vec:Length2D()return math.sqrt(self.x*self.x+self.y*self.y)end
function vec:Normalized()return self*(1/self:Length2D())end
class=function(t)return t end
IsServer=function()return true end
UF_SUCCESS=0;UF_FAIL_CUSTOM=1;PATTACH_WORLDORIGIN=0
local forbidden, blocked, displaced=false,false,false
package.loaded['systems/forbidden_region_service']={validate_hero_position=function()return not forbidden end}
local queried={}
GridNav={IsTraversable=function(_,p)
    queried[#queried+1]=p.x
    -- A wall lies between origin and destination; endpoints are walkable.
    return p.x<200 or p.x>600
end,IsBlocked=function()return blocked end}
GetGroundHeight=function(p)return p.x>600 and 128 or 0 end
FindClearSpaceForUnit=function(u,p)
    if displaced then u:SetAbsOrigin(Vector(400,0,0)) end
end
local jobs={},effects,cleaned,sounds,dodges
effects=0;cleaned=0;sounds=0;dodges=0
package.loaded['core/scheduler']={after=function(_,f)jobs[#jobs+1]=f end}
ParticleManager={CreateParticle=function()effects=effects+1;return effects end,
    SetParticleControl=function()end,DestroyParticle=function()end,
    ReleaseParticleIndex=function()cleaned=cleaned+1 end}
ProjectileManager={ProjectileDodge=function()dodges=dodges+1 end}
local hero={pos=Vector(0,0,0),survival_hero_id='test',writes=0,
    IsNull=function()return false end,GetAbsOrigin=function(s)return s.pos end,
    SetAbsOrigin=function(s,p)s.pos=p;s.writes=s.writes+1 end,
    Stop=function()end,EmitSound=function()sounds=sounds+1 end,
    StopSound=function()sounds=sounds-1 end,
    AddNewModifier=function()error('instant blink must not create a motion modifier')end}
local ability=require('abilities/ability_survival_hero_ball_lightning')
local cursor=Vector(2000,0,0)
local a=setmetatable({refunds=0,cooldowns=0},{__index=ability})
function a:GetCaster()return hero end
function a:GetCursorPosition()return cursor end
function a:RefundManaCost()self.refunds=self.refunds+1 end
function a:EndCooldown()self.cooldowns=self.cooldowns+1 end
assert(a:CastFilterResultLocation(cursor)==UF_SUCCESS)
a:OnSpellStart()
assert(hero.pos.x==800 and hero.pos.z==128 and hero.writes==1)
assert(dodges==1 and effects==2 and a.refunds==0)
for _,x in ipairs(queried)do assert(x==800,'must not test intermediate terrain') end
for _,f in ipairs(jobs)do f() end;jobs={}
assert(cleaned==effects and sounds==0)
hero.pos=Vector(0,0,0);hero.writes=0;blocked=true
assert(a:CastFilterResultLocation(cursor)==UF_FAIL_CUSTOM)
a:OnSpellStart();assert(hero.writes==0 and a.refunds==1)
blocked=false;forbidden=true
a:OnSpellStart();assert(hero.writes==0 and a.refunds==2)
forbidden=false;displaced=true
a:OnSpellStart();assert(hero.pos.x==0 and a.refunds==3 and a.cooldowns==1)
displaced=false;cursor=Vector(0,0,0)
a:OnSpellStart();assert(a.refunds==4)
print('HERO_INSTANT_BLINK_PASS: direct wall crossing, range 800, cliff height, no motion controller, blocked/forbidden rejection, failed landing rollback/refund, effect cleanup')
