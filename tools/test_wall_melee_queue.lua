-- Rear allocation against a bounded native navigation oracle. Physical MOVE
-- and the four attack contacts remain the responsibility of their real AI.
package.path="scripts/vscripts/?.lua;"..package.path
Vector=function(x,y,z) return {x=x,y=y,z=z or 384} end
local clock,nav_queries,path_queries,shape,side=0,0,0,"open",1
GameRules={GetGameTime=function() return clock end}
GetGroundHeight=function() return 384 end
local function norm(point)
    local value=side<=2 and point.x or point.y
    return (side==1 or side==3) and -value or value
end
local function along(point) return side<=2 and point.y or point.x end
local function terrain(point)
    if shape=="blocked" then return false end
    if shape=="narrow" and math.abs(along(point))>=192 then return false end
    if shape=="single_disconnected" and (math.abs(norm(point)-290)>31 or math.abs(along(point))>31) then return false end
    if shape=="courtyard" and norm(point)<350 and math.abs(along(point))>180 then return false end
    return not (math.abs(point.x)<128 and math.abs(point.y)<128)
end
GridNav={
    IsTraversable=function(_,point) nav_queries=nav_queries+1;return terrain(point) end,
    IsBlocked=function(_,point) nav_queries=nav_queries+1;return not terrain(point) end,
    FindPathLength=function(_,from,to)
        path_queries=path_queries+1
        if shape=="disconnected" or shape=="single_disconnected" or norm(to)<128 or norm(from)<0 then return -1 end
        return math.sqrt((from.x-to.x)^2+(from.y-to.y)^2)
    end,
}
local queue=require("systems/wall_melee_queue")
local function actor(id,x,y,hull)
    local unit={point=Vector(x,y,384),radius=hull or 32}
    function unit:entindex() return id end
    function unit:IsNull() return false end
    function unit:IsAlive() return not self.dead end
    function unit:GetAbsOrigin() return self.point end
    function unit:GetHullRadius() return self.radius end
    function unit:GetPaddedCollisionRadius() return self.radius+10 end
    function unit:SetAbsOrigin() error("rear queue must not teleport") end
    function unit:SetHullRadius() error("rear queue must not shrink hulls") end
    return unit
end
local function fixture(count,radii)
    clock=0
    local state,wall,units={},{},{}
    wall=actor(1,0,0,128)
    for index=1,count do
        local x=side==1 and -1000 or (side==2 and 1000 or 0)
        local y=side==3 and -1000 or (side==4 and 1000 or 0)
        units[index]=actor(index+1,x,y,radii and radii[(index-1)%#radii+1])
    end
    return state,wall,units
end
local function fill(state,wall,units,edge)
    for tick=1,50 do
        clock=(tick-1)*0.5
        local before=path_queries
        for _,unit in ipairs(units) do
            if not unit.dead then queue.reserve(state,wall,unit,side,edge or 226,clock) end
        end
        assert(path_queries-before<=8,"native rear paths exceeded the shared half-second budget")
        local count=0
        for _,unit in ipairs(units) do if queue.peek(state,unit) then count=count+1 end end
        local live=0;for _,unit in ipairs(units) do if not unit.dead then live=live+1 end end
        if count==live then return end
    end
    error("rear allocation never completed")
end
local function verify(state,units)
    local columns,depths,points={},{},{}
    for _,unit in ipairs(units) do if not unit.dead then
        local point=assert(queue.peek(state,unit))
        local key=point.x..":"..point.y
        assert(not points[key],"two bodies share a rear goal")
        points[key]=true;columns[along(point)]=true;depths[norm(point)]=true
        assert(norm(point)>=226+unit:GetPaddedCollisionRadius()+8,"rear goal intrudes into the front")
        assert(math.abs(along(point))<=600 and norm(point)<=1300,"rear grid exceeded its bounded area")
        assert(terrain(point),"goal is off native terrain")
        for _,other in ipairs(units) do if other~=unit and not other.dead then
            local p=assert(queue.peek(state,other))
            local spacing=unit:GetPaddedCollisionRadius()+other:GetPaddedCollisionRadius()+4
            assert((point.x-p.x)^2+(point.y-p.y)^2>=spacing^2-0.01,"native padded goals overlap")
        end end
    end end
    local nc,nd=0,0;for _ in pairs(columns) do nc=nc+1 end;for _ in pairs(depths) do nd=nd+1 end
    return nc,nd
end

for _,count in ipairs({60,90}) do
    shape="open"
    local state,wall,units=fixture(count)
    fill(state,wall,units)
    local columns,depths=verify(state,units)
    assert(columns>4 and depths>1,"wide rear was funnelled into four columns or one depth")
    local lateral_actor
    for _,unit in ipairs(units) do
        local point,owned_side=queue.peek(state,unit)
        assert(owned_side==1,"rear reservation lost its approach face")
        if math.abs(point.y)>math.abs(point.x) then lateral_actor=unit end
    end
    assert(lateral_actor,"wide fixture must reach a goal outside its Cartesian nearest face")
    lateral_actor.point=queue.peek(state,lateral_actor)
    local _,owned_side=queue.peek(state,lateral_actor)
    assert(owned_side==1,"lateral movement must not change the reserved physical approach face")
    local saved={}
    for _,unit in ipairs(units) do saved[unit]=queue.peek(state,unit) end
    local before_nav,before_paths=nav_queries,path_queries
    for tick=1,100 do
        clock=clock+0.1
        for _,unit in ipairs(units) do
            assert(queue.reserve(state,wall,unit,1,226,clock)==saved[unit],"stable waiting goal moved")
        end
    end
    assert(nav_queries==before_nav and path_queries==before_paths,"stable rear repeated navigation work")
end

for rotation=2,4 do
    side=rotation;shape="open"
    local state,wall,units=fixture(60)
    fill(state,wall,units)
    local columns,depths=verify(state,units)
    assert(columns>4 and depths>1,"rotated rear was funnelled into four columns")
end
side=1
shape="narrow"
local state,wall,units=fixture(4)
for index,along in ipairs({-132,-44,44,132}) do units[index].point=Vector(-400,along,384) end
for _,unit in ipairs(units) do
    local point=assert(queue.reserve(state,wall,unit,1,258,clock))
    assert(point.y==unit.point.y,"native four-column corridor was staggered into only three rear columns")
end
local columns,depths=verify(state,units)
assert(columns==4 and depths==1,"a 384-wide rear must retain all four native 88-spaced columns")

-- Native MOVE stops on the near side of an outward retreat. Give an
-- intruder 32 extra units, then keep its chosen goal after it becomes safe.
shape="open"
state,wall,units=fixture(1)
units[1].point=Vector(-280,-44,384)
local retreat=assert(queue.reserve(state,wall,units[1],1,258,clock))
assert(norm(retreat)>=258+42+8+32,"intruder retreat omitted the native stopping margin")
assert(norm(retreat)-32>=258+42+8,"native stopping would leave an intruder inside the front")
units[1].point=Vector(-360,-44,384)
assert(queue.reserve(state,wall,units[1],1,258,clock)==retreat,
    "becoming safe pulled a stable retreat goal back toward the front")

shape="courtyard"
state,wall,units=fixture(60)
fill(state,wall,units)
columns,depths=verify(state,units)
assert(columns>4 and depths>1,"a narrow gate must use its wider rear courtyard")
for _,unit in ipairs(units) do
    local point=queue.peek(state,unit)
    if norm(point)<350 then assert(math.abs(point.y)<=149,"full hull crossed the narrow bank") end
end

shape="open"
state,wall,units=fixture(35,{20,32,48})
fill(state,wall,units)
verify(state,units)

-- A large rear boss only affects its own clearance. Once it leaves, a new
-- ordinary body starts at the normal front envelope rather than inheriting
-- the largest radius ever observed by this wall's queue.
for _,cleanup in ipairs({"release","death"}) do
    state,wall,units=fixture(1,{96})
    local boss=units[1]
    local boss_goal=assert(queue.reserve(state,wall,boss,1,0,clock))
    if cleanup=="release" then queue.release(state,boss:entindex())
    else boss.dead=true;clock=clock+2.5 end
    local ordinary=actor(100,-1000,0,32)
    local ordinary_goal=assert(queue.reserve(state,wall,ordinary,1,0,clock))
    assert(norm(ordinary_goal)==290 and norm(ordinary_goal)<norm(boss_goal),
        "a former large rear body left permanent clearance for subsequent small monsters")
end

-- A large actor's most recent observation must not enlarge a small actor's
-- promotion envelope either; their actual front edge is still the same.
state,wall,units=fixture(30)
fill(state,wall,units,0)
local small_near=queue.peek(state,units[1])
local small_deep
for _,unit in ipairs(units) do
    if norm(queue.peek(state,unit))>norm(small_near)+1 then small_deep=unit;break end
end
local large_rear=actor(10000,-1000,0,96)
assert(queue.reserve(state,wall,large_rear,1,0,clock))
queue.release(state,units[1]:entindex());units[1].dead=true
clock=clock+0.5
assert(queue.peek(state,small_deep)==small_near,
    "a large rear actor's last observation prevented an ordinary body from moving into its safe gap")

-- A released near goal belongs first to the oldest deeper waiter. Its native
-- MOVE destination advances without moving the actor or reshuffling others.
state,wall,units=fixture(30)
fill(state,wall,units)
local old_goal=queue.peek(state,units[1])
local next_waiter
for _,unit in ipairs(units) do
    local point=queue.peek(state,unit)
    if norm(point)>norm(old_goal)+1 then next_waiter=unit;break end
end
assert(next_waiter)
queue.release(state,units[1]:entindex());units[1].dead=true
clock=clock+0.5
local moved=queue.reserve(state,wall,next_waiter,1,226,clock)
assert(moved==old_goal,"release did not gently promote the earliest deeper waiter")
assert(next_waiter:GetAbsOrigin().x==-1000,"promotion teleported a rear actor")

state,wall,units=fixture(30)
fill(state,wall,units)
old_goal=queue.peek(state,units[1])
for _,unit in ipairs(units) do
    if norm(queue.peek(state,unit))>norm(old_goal)+1 then next_waiter=unit;break end
end
local retained_goal=queue.peek(state,next_waiter)
next_waiter.point=Vector(-200,retained_goal.y,384)
queue.release(state,units[1]:entindex());units[1].dead=true
clock=clock+0.5
assert(queue.peek(state,next_waiter)==retained_goal,
    "promotion assigned an intruder a nearer goal without native stopping clearance")

-- The far-side contact branch only peeks at existing queues. A selected
-- distant waiter must still receive its nearer goal after the next vacancy.
state,wall,units=fixture(90)
fill(state,wall,units)
local far,far_goal
for _,unit in ipairs(units) do
    local point=queue.peek(state,unit)
    if norm(point)>512 then far,far_goal=unit,point;break end
end
assert(far)
for _,unit in ipairs(units) do
    local point=queue.peek(state,unit)
    if unit~=far and point and norm(point)<norm(far_goal) then
        queue.release(state,unit:entindex());unit.dead=true
    end
end
clock=clock+0.5
assert(norm(queue.peek(state,far))<norm(far_goal),"a distant peek-only waiter remained stranded behind 512")

state,wall,units=fixture(30)
fill(state,wall,units)
old_goal=queue.peek(state,units[1]);units[1].dead=true
clock=clock+2.5
for _,unit in ipairs(units) do if not unit.dead then queue.reserve(state,wall,unit,1,226,clock) end end
local occupied=false
for _,unit in ipairs(units) do if not unit.dead and queue.peek(state,unit)==old_goal then occupied=true end end
assert(occupied,"dead rear body did not free and refill a nearer waiting goal")
wall.point.y=64
assert(queue.peek(state,units[2])==nil,"wall relocation retained stale rear coordinates")
assert(queue.reserve(state,wall,units[2],1,226,clock),"moved wall failed to build a new rear")
state.rear_queue_geometry_revision=1
assert(queue.peek(state,units[2])==nil,"explicit geometry change retained stale rear candidates")

shape="blocked"
state,wall,units=fixture(1)
assert(not queue.reserve(state,wall,units[1],1,0,clock))
local before_nav,before_paths=nav_queries,path_queries
for _=1,100 do assert(not queue.reserve(state,wall,units[1],1,0,clock)) end
assert(nav_queries==before_nav and path_queries==before_paths,"blocked geometry was rescanned for every waiter")

shape="disconnected"
state,wall,units=fixture(20)
local before=path_queries
for _=1,10 do for _,unit in ipairs(units) do
    assert(not queue.reserve(state,wall,unit,1,0,0),"unreachable terrain acquired a rear reservation")
end end
assert(path_queries-before<=8,"failed destinations bypassed the shared native-path budget")
assert(not queue.peek(state,units[1]))

shape="single_disconnected"
state,wall,units=fixture(1)
before=path_queries
assert(not queue.reserve(state,wall,units[1],1,0,0))
assert(path_queries-before==1,"single-goal fixture must exercise one failed native route")
for _,stamp in ipairs({0.1,0.5,1,1.5,1.9}) do
    assert(not queue.reserve(state,wall,units[1],1,0,stamp))
end
assert(path_queries-before==1,"a failed goal was queried again before its two-second backoff")
assert(not queue.reserve(state,wall,units[1],1,0,2.1))
assert(path_queries-before==2,"a failed native route never retried after its bounded backoff")
print("WALL_MELEE_QUEUE_PASS 60/90 unique wide rear goals, narrow gate/wide court, mixed padded hulls, stable queries=0, release/death promotion, relocation, blocked/disconnected terrain and bounded native paths")
