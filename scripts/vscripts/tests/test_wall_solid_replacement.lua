-- Real allocator and modifier state contract. No mock can shrink a hull,
-- teleport an actor, or phase an entrant to make this acceptance pass.
-- Native collision/path movement is verified separately in Tools.
package.path='scripts/vscripts/?.lua;'..package.path
Vector=function(x,y,z) return {x=x,y=y,z=z or 384} end
local clock,paths,queries,neighbours=0,0,0,{}
GameRules={GetGameTime=function() return clock end}
GetGroundHeight=function() return 384 end
GridNav={IsTraversable=function() return true end,IsBlocked=function(_,p)
    return math.abs(p.x)<128 and math.abs(p.y)<128
end,FindPathLength=function(_,a,b)
    paths=paths+1
    return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)
end}
DOTA_UNIT_TARGET_TEAM_BOTH=3;DOTA_UNIT_TARGET_BASIC=1;DOTA_UNIT_TARGET_HERO=2
DOTA_UNIT_TARGET_FLAG_INVULNERABLE=1;DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES=2
FIND_ANY_ORDER=0
FindUnitsInRadius=function(team,point,cache,radius)
    assert(team==3 and radius==512,'admission queries must remain local')
    queries=queries+1;return neighbours
end
local function unit(id,x,y,radius)
    local u={p=Vector(x,y,384),radius=radius or 32}
    function u:entindex() return id end
    function u:IsNull() return false end
    function u:IsAlive() return not self.dead end
    function u:GetAbsOrigin() return self.p end
    function u:GetHullRadius() return self.radius end
    function u:GetPaddedCollisionRadius() return self.radius+10 end
    function u:GetTeamNumber() return 3 end
    function u:SetHullRadius() error('contacts must never resize a native body') end
    function u:SetAbsOrigin() error('contacts must never teleport to a reservation') end
    return u
end
package.loaded['systems/wall_navigation_service']={}
local contact=require('systems/wall_melee_contact')
local wall=unit(1,0,0,128)
local function point(face,normal,lateral)
    if face==1 then return Vector(-normal,lateral) end
    if face==2 then return Vector(normal,lateral) end
    if face==3 then return Vector(lateral,-normal) end
    return Vector(lateral,normal)
end
local lanes={-132,-44,44,132}
local next_id=10
local function actor(face,normal,lateral,radius)
    local p=point(face,normal,lateral);next_id=next_id+1
    return unit(next_id,p.x,p.y,radius)
end
local fronts={}
for face=1,4 do
    fronts[face]={}
    for _,lateral in ipairs(lanes) do
        local u=actor(face,400,lateral)
        local plan=assert(contact.resolve(wall,u,face))
        assert(plan.claimed,'each physically separate face contact must be admitted')
        local expected=point(face,184,lateral)
        assert(plan.point.x==expected.x and plan.point.y==expected.y,'padded body spacing must remain88')
        u.p=plan.point;neighbours[#neighbours+1]=u
        assert(contact.settle(wall,u,plan.point),'actual clear contact must settle without position writes')
        fronts[face][#fronts[face]+1]=u
    end
end
assert(queries==1,'same-observation arrivals must share one local body snapshot')
local all_paths=paths
for face=1,4 do
    local rear=actor(face,400,0)
    assert(not contact.resolve(wall,rear,face).claimed,'a fifth owner may not enter a full face')
end
assert(paths==all_paths,'full faces perform no path searches for ordinary waiters')

-- A rear actor receives the newly free key, but the live red-circled blocker
-- remains a real obstacle. Merely owning the key never counts as arrival.
local victim=fronts[1][2]
victim.dead=true
clock=.5
local rear=actor(1,248,-44)
neighbours[#neighbours+1]=rear
local refill=assert(contact.resolve(wall,rear,1))
assert(refill.claimed and refill.point.y==-44,'death releases only its own contact')
local before=queries
assert(not contact.settle(wall,rear,refill.point),'a second row64 behind the goal may not attack through the front')
assert(queries==before,'distant arrivals do not scan neighbours')
local blocker=actor(1,200,-44)
neighbours[#neighbours+1]=blocker
rear.p=point(1,216,-44)
clock=1
assert(not contact.settle(wall,rear,refill.point),'a nearby live body must prevent overlapping lock-in')
blocker.dead=true
assert(contact.settle(wall,rear,refill.point),'after the real blocker dies, native acceptance at32 can settle')
assert(rear.p.x==-216,'settlement must retain the actual MOVE stop position')
local retained_paths,retained_queries=paths,queries
for pass=1,3 do
    clock=1+pass*.25
    for face=1,4 do
        for _,u in ipairs(fronts[face]) do
            if u:IsAlive() then assert(contact.resolve(wall,u,face).claimed) end
        end
    end
    assert(contact.resolve(wall,rear,1).claimed)
end
assert(paths==retained_paths and queries==retained_queries,
    'stable owners must issue no new path or local body queries')
contact.reset()
for face=1,4 do for _,u in ipairs(fronts[face]) do assert(u.radius==32) end end
assert(rear.radius==32 and not contact.restore_hull(rear,true),'cleanup has no temporary hull to restore')

-- A larger configured body gets fewer legal contacts, never a tactical body.
neighbours={};clock=0
local large1=actor(1,400,-132,64)
local a=assert(contact.resolve(wall,large1,1));assert(a.claimed and large1.radius==64)
local large2=actor(1,400,-44,64)
local b=assert(contact.resolve(wall,large2,1));assert(b.claimed and b.point.y>=44 and large2.radius==64)
local large3=actor(1,400,132,64)
assert(not contact.resolve(wall,large3,1).claimed,'a large body must wait when all remaining physical contacts conflict')
contact.reset()

-- Exercise the production state table: all old legacy flags are harmless.
local env=setmetatable({},{__index=_G});env._G=env
env.class=function(t) return t end;env.LinkLuaModifier=function() end
env.MODIFIER_STATE_ROOTED=4;env.MODIFIER_STATE_DISARMED=5;env.MODIFIER_STATE_NO_UNIT_COLLISION=6
env.require=function(name) if name=='systems/wall_melee_contact' then return contact end return{} end
local chunk=assert(loadfile('scripts/vscripts/modifiers/modifier_enemy_wall_ai.lua'));setfenv(chunk,env)
local ai=chunk()
local m=setmetatable({no_unit_collision=true},{__index=ai})
function m:GetStackCount() return self.stack end
for mode=0,6 do
    m.stack=mode
    local state=m:CheckState()
    assert(not state[6],'no AI state may phase through another live body')
    assert(not not state[4]==(mode==2 or mode==6),'only stationary attack modes own a root')
end
-- The isolated Tools adapter must reproduce the same state on the client,
-- where its server-only implementation handle is deliberately unavailable.
local adapter_chunk=assert(loadfile('scripts/vscripts/tests/wall_native_redesign_ai.lua'))
setfenv(adapter_chunk,env)
local adapter=adapter_chunk()
local parent={IsNull=function() return false end}
local test_adapter=setmetatable({no_unit_collision=true},{__index=adapter})
function test_adapter:GetParent() return parent end
function test_adapter:GetStackCount() return self.stack end
for _,server in ipairs({false,true}) do
    env.IsServer=function() return server end
    for _,implementation in ipairs({'absent','present'}) do
        parent.survival_native_ai_impl=implementation=='present' and ai or nil
        for mode=0,6 do
            test_adapter.stack=mode
            local state=test_adapter:CheckState()
            assert(not state[6],'client or missing-implementation fallback must never phase any contact mode')
            assert(not not state[4]==(mode==2 or mode==6),'adapter root must match the production state contract')
            assert(not not state[5]==(mode==1 or mode==3 or mode==4 or mode==5),'adapter disarm must match production')
        end
    end
end
print('WALL_SOLID_REPLACEMENT_PASS four faces, exclusive death vacancy, blocked body arrival, native32 acceptance, immutable hulls and positions, zero phase modes, stable bounded work')
