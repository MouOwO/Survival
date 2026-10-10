-- Actual AI and actual release helper; mock only native entities/timers.
package.path = "scripts/vscripts/?.lua;" .. package.path
local root = arg[1] or "."
local registry = {}
class = function(value) return value end
IsServer = function() return true end
local vector = {}
vector.__index = vector
function vector:Length2D() return math.sqrt(self.x * self.x + self.y * self.y) end
vector.__sub = function(a,b) return setmetatable({x=a.x-b.x,y=a.y-b.y,z=a.z-b.z},vector) end
Vector = function(x,y,z) return setmetatable({x=x,y=y,z=z},vector) end
EntIndexToHScript = function(id) return registry[id] end
local methods = dofile(root .. "/scripts/vscripts/modifiers/modifier_practice_monster_ai.lua")
local STAGING, AI = "modifier_challenge_11_staging", "modifier_practice_monster_ai"
local function entity(id, x, staged)
    local u = {id=id,position=Vector(x or 0,0,0),modifiers={},force_calls=0,move_calls=0,
        attack_capability=2,health=100,alive=true}
    if staged then u.modifiers[STAGING] = true end
    function u:IsNull() return self.removed == true end
    function u:IsAlive() return self.alive end
    function u:entindex() return self.id end
    function u:GetAbsOrigin() return self.position end
    function u:HasModifier(name) return self.modifiers[name] ~= nil end
    function u:FindModifierByName(name) return self.modifiers[name] end
    function u:RemoveModifierByName(name) self.modifiers[name] = nil end
    function u:SetForceAttackTarget(target) self.force_calls=self.force_calls+1;self.target=target end
    function u:MoveToPosition(point) self.move_calls=self.move_calls+1;self.destination=point end
    registry[id] = u
    return u
end
local function attach(u, hero)
    local ai = setmetatable({parent=u,intervals={}}, {__index=methods})
    function ai:GetParent() return self.parent end
    function ai:IsNull() return self.removed == true end
    function ai:StartIntervalThink(period) self.intervals[#self.intervals+1]=period end
    u.modifiers[AI]=ai
    ai:OnCreated({hero_entindex=hero:entindex(),home_x=0,home_y=0,home_z=0,aggro_radius=700,leash_radius=1200})
    return ai
end
local f=assert(io.open(root .. "/scripts/vscripts/systems/challenge_session_service.lua", "rb"))
local source=f:read("*a");f:close()
local first=assert(source:find("local function release_challenge_11_unit",1,true))
local last=assert(source:find("local function prepare_challenge_11",first,true))
local env=setmetatable({challenge_11_staging=STAGING,valid=function(u)return u and not u:IsNull()end},{__index=_G})
local chunk=assert(loadstring(source:sub(first,last-1).."\nreturn release_challenge_11_unit"))
setfenv(chunk,env);local release=chunk()

-- Four owners with ten displayed stages each. No staging timer or attack order;
-- release only the chosen stage and retain all exact native display handles.
local all,heroes = {},{}
for owner=0,3 do
    heroes[owner]=entity(100+owner,20,false)
    all[owner]={}
    for stage=1,10 do
        local u=entity(1000+owner*100+stage,0,true)
        local ai=attach(u,heroes[owner])
        all[owner][stage]={unit=u,ai=ai}
        assert(#ai.intervals==0 and u.force_calls==0 and u.move_calls==0)
        ai:OnIntervalThink() -- even a stale/manual callback cannot issue orders
        assert(u.force_calls==0 and u.move_calls==0)
        assert(ai:Resume()==false and #ai.intervals==0, "still staged must not wake")
    end
end
for stage=1,10 do for owner=0,3 do
    local r=all[owner][stage];local u,ai=r.unit,r.ai
    -- Reproduce the prior staging thinker setting a target before native release
    -- clears it. The explicit resume must also reset Lua's remembered state.
    ai.has_target=true;ai.returning_home=true;u.target=heroes[owner]
    release(u)
    assert(not u:HasModifier(STAGING) and #ai.intervals==1 and ai.intervals[1]==0.5)
    assert(u.target==nil and ai.has_target==false and ai.returning_home==false and ai.staging==false)
    ai:OnIntervalThink()
    assert(u.target==heroes[owner] and ai.has_target==true, "nearby activation must attack again")
    local orders=u.force_calls;ai:OnIntervalThink();assert(u.force_calls==orders, "normal order suppression retained")
    assert(u.attack_capability==2 and u.health==100 and not u.removed)
    if stage<10 then assert(#all[owner][stage+1].ai.intervals==0 and all[owner][stage+1].unit:HasModifier(STAGING)) end
end end

-- Active practice leash behavior is unchanged, including reset and reacquire.
local u=entity(9000,0,false);local hero=entity(9001,30,false);local ai=attach(u,hero)
assert(#ai.intervals==1 and ai.intervals[1]==0.5)
ai:OnIntervalThink();assert(u.target==hero and ai.has_target)
u.position=Vector(2000,0,0);ai:OnIntervalThink()
assert(u.target==nil and ai.returning_home and u.move_calls==1)
ai:OnIntervalThink();assert(u.move_calls==1, "ordinary repeated home orders remain suppressed")
u.position=Vector(0,0,0);ai:OnIntervalThink();assert(u.target==hero and not ai.returning_home)
ai:OnDestroy();local count=#ai.intervals;local orders=u.force_calls
assert(u.target==nil and ai:Resume()==false);ai:OnIntervalThink()
assert(#ai.intervals==count and u.force_calls==orders, "destroyed modifier cannot wake or order")

-- Removed/dead units and removed AI handles never gain a resumed interval.
for _,reason in ipairs({"removed","dead","expired_modifier"}) do
    local v=entity(9100,0,true);local a=attach(v,hero)
    if reason=="removed" then v.removed=true
    elseif reason=="dead" then v.alive=false
    else a.removed=true;a:OnDestroy() end
    release(v)
    assert(#a.intervals==0, reason.." must not gain a timer")
end
-- Expired staging restriction can be explicitly released normally, and an old
-- AI instance with nil staging flags must have its stale target flags repaired.
local v=entity(9200,0,true);local a=attach(v,hero)
v:RemoveModifierByName(STAGING);a.staging=nil;a.has_target=true;a.returning_home=true
release(v);a:OnIntervalThink();assert(v.target==hero and #a.intervals==1)
-- Repeated release performs the same one-time native clear/reset as before;
-- StartIntervalThink replaces the same modifier timer rather than adding one.
release(v);assert(v.target==nil and not a.has_target);a:OnIntervalThink();assert(v.target==hero)
-- Legacy/unavailable AI retains the original release's native clear fallback.
local legacy=entity(9300,0,true);legacy.modifiers[AI]={IsNull=function()return false end}
legacy.target=hero;release(legacy);assert(not legacy:HasModifier(STAGING) and legacy.target==nil)
local no_ai=entity(9400,0,true);no_ai.target=hero;release(no_ai);assert(no_ai.target==nil)
print("PRACTICE_STAGING_PASS: 4 owners x10 displayed stages, no staging interval/orders, near release target reset, ordinary practice leash, destroyed/dead/expired/null and legacy/reset behavior; native handles/HP/cap unchanged")
