-- Four exclusive short-range contacts. Admitted units use phased ground
-- movement; everyone else waits behind the front instead of filling its gaps.
local M = {}
local states = {}
local HALF, COUNT, ENGAGE_DISTANCE = 128, 4, 512
local STALL_SECONDS, POSITION_CACHE_SECONDS = 3, 2
local SETTLE_DISTANCE, WAIT_CLEARANCE, RETREAT_ALLOWANCE = 64, 8, 32
local function alive(u) return u and not u:IsNull() and u:IsAlive() end
local function distance(a,b)
    local x,y=a.x-b.x,a.y-b.y
    return math.sqrt(x*x+y*y)
end
local function now() return GameRules:GetGameTime() end
local function hull(u) return math.max(1,u:GetHullRadius()) end
local function interrupted(u)
    return (u.IsStunned and u:IsStunned())
        or (u.IsCommandRestricted and u:IsCommandRestricted())
        or (u.IsRooted and u:IsRooted())
end
local function moved(a,b)
    local x,y=a.x-b.x,a.y-b.y
    return x*x+y*y>=64
end
-- Arrival is only an opportunity to settle, never permission to root at an
-- arbitrary offset. Four diameter-64 units in a 256 gate have ZERO slack.
function M.arrived(wall,unit,point,retained)
    local p=unit:GetAbsOrigin()
    return distance(p,point)<=(retained and 1 or SETTLE_DISTANCE)
        and math.abs(p.z-point.z)<=32
end
local function clear_point(wall,unit,point)
    if math.abs(GetGroundHeight(point,unit)-wall:GetAbsOrigin().z)>128 then return false end
    -- Touching the terrain edge is valid; sample inside the hull instead of
    -- stepping exactly onto the next navigation cell at a narrow gate's edge.
    local radius=math.max(0,hull(unit)-1)
    for _,offset in ipairs({{0,0},{radius,0},{-radius,0},{0,radius},{0,-radius}}) do
        local sample=Vector(point.x+offset[1],point.y+offset[2],point.z)
        if not GridNav:IsTraversable(sample) or GridNav:IsBlocked(sample) then return false end
    end
    return true
end
-- A single bounded alignment on entry, not a per-frame movement controller.
-- Sample the short segment (including the hull) so alignment cannot cross a
-- cliff, newly built obstruction, or the wall itself. External control wins.
function M.settle(wall,unit,point)
    if not M.arrived(wall,unit,point,false) or interrupted(unit)
        or (unit.IsCurrentlyHorizontalMotionControlled and unit:IsCurrentlyHorizontalMotionControlled())
        or (unit.IsCurrentlyVerticalMotionControlled and unit:IsCurrentlyVerticalMotionControlled()) then return false end
    local s=states[wall:entindex()]
    local claim=s and s.claims[unit:entindex()]
    if not claim or claim.unit~=unit or claim.point~=point then return false end
    if not clear_point(wall,unit,point) then return false end
    local p=unit:GetAbsOrigin()
    local length=distance(p,point)
    if length>0.01 then
        if not unit.SetAbsOrigin then return false end
        local steps=math.max(1,math.ceil(length/16))
        local radius=math.max(0,hull(unit)-1)
        for index,offset in ipairs({{0,0},{radius,0},{-radius,0},{0,radius},{0,-radius}}) do
            local cleared=false
            for step=0,steps do
                local t=step/steps
                local sample=Vector(p.x+(point.x-p.x)*t+offset[1],
                    p.y+(point.y-p.y)*t+offset[2],point.z)
                local clear=GridNav:IsTraversable(sample) and not GridNav:IsBlocked(sample)
                -- A native-valid center can already have its hull over a bank.
                -- Allow that existing overlap to leave, never a new penetration
                -- or reentry after it clears. The center is always navigable.
                if not clear and (index==1 or cleared or step==steps) then return false end
                cleared=cleared or clear
                if index==1 and math.abs(GetGroundHeight(sample,unit)-point.z)>32 then return false end
            end
        end
        unit:SetAbsOrigin(Vector(point.x,point.y,point.z))
    end
    claim.arrived=M.arrived(wall,unit,point,true)
    return claim.arrived
end

local function contact_back_edge(origin,point,radius)
    return math.max(math.abs(point.x-origin.x),math.abs(point.y-origin.y))+radius
end
local function waiting_point(wall,unit,source,front_edge)
    local point=source.point
    local origin=wall:GetAbsOrigin()
    local dx,dy=point.x-origin.x,point.y-origin.y
    local x_axis=math.abs(dx)>math.abs(dy)
    local sign=(x_axis and dx or dy)<0 and -1 or 1
    local radius=hull(unit)
    if front_edge<=0 then front_edge=contact_back_edge(origin,point,radius) end
    -- Leave one body diameter plus a small margin, not a fixed empty row.
    -- Use the whole front's rear edge so a larger adjacent contact is safe too.
    local normal=front_edge+radius+WAIT_CLEARANCE
    local current=unit:GetAbsOrigin()
    local inside=sign*(x_axis and current.x-origin.x or current.y-origin.y)<normal
    -- A unit retreating out of the front can stop short of its MOVE goal.
    -- Only that unit needs extra retreat; rear arrivals must not inherit it.
    local cache=source.wait_points
    if not cache or cache.front_edge~=front_edge then
        cache={front_edge=front_edge};source.wait_points=cache
    end
    local points=cache[radius]
    if not points then points={};cache[radius]=points end
    local key=inside and 2 or 1
    if points[key]~=nil then return points[key] end
    if inside then normal=normal+RETREAT_ALLOWANCE end
    local p
    -- A larger waiter may not fit the small attacker's outer lane.
    local lateral_limit=math.max(0,HALF-radius)
    if x_axis then
        p=Vector(origin.x+sign*normal,
            origin.y+math.max(-lateral_limit,math.min(lateral_limit,dy)),point.z)
    else
        p=Vector(origin.x+math.max(-lateral_limit,math.min(lateral_limit,dx)),
            origin.y+sign*normal,point.z)
    end
    p.z=GetGroundHeight(p,unit)
    -- At bends the full setback may be outside the path. Keep the unit at its
    -- current position rather than give it an unreachable/front-row wait goal.
    points[key]=clear_point(wall,unit,p) and p or false
    return points[key]
end
local function state_for(wall)
    local id=wall:entindex()
    local s=states[id]
    if not s or s.wall~=wall then
        s={wall=wall,claims={},positions={},retries={},failed={},retry_sweep=0}
        states[id]=s
    end
    return s
end
local function positions(s,unit,stamp)
    local radius=hull(unit)
    local cached=s.positions[radius]
    if cached and stamp-cached.updated<POSITION_CACHE_SECONDS then return cached.points end
    local p=s.wall:GetAbsOrigin()
    local result={}
    -- Four Hull32 monsters fit in a 256-wide face without intersecting.
    -- Larger hulls use fewer positions; mixed hulls still share the same claims.
    local count=math.max(1,math.min(COUNT,math.floor(HALF/radius)))
    for side=1,4 do
        for lane=1,count do
            local along=(lane-(count+1)*0.5)*radius*2
            -- Keep endpoints outside the engine's inflated navigation cell.
            local normal=HALF+radius+32
            local x,y
            if side<=2 then x=(side==1 and -normal or normal);y=along
            else x=along;y=(side==3 and -normal or normal) end
            local point=Vector(p.x+x,p.y+y,p.z)
            point.z=GetGroundHeight(point,unit)
            if clear_point(s.wall,unit,point) then result[#result+1]={point=point,key=side..":"..lane} end
        end
    end
    s.positions[radius]={points=result,updated=stamp}
    return result
end
function M.release(wall_index,unit_index)
    local s=states[tonumber(wall_index)]
    if s then
        s.claims[tonumber(unit_index)]=nil
        s.retries[tonumber(unit_index)]=nil
        s.failed[tonumber(unit_index)]=nil
    end
end
function M.clear(wall_index) states[tonumber(wall_index)]=nil end
function M.reset() states={} end

function M.resolve(wall,unit)
    if not alive(wall) or not alive(unit) then return nil end
    local p,origin=unit:GetAbsOrigin(),wall:GetAbsOrigin()
    local id=unit:entindex()
    if distance(p,origin)>ENGAGE_DISTANCE then M.release(wall:entindex(),id);return nil end
    local s=state_for(wall)
    local stamp=now()
    -- Sweep failed reservations once per wall, not once per waiting monster.
    if stamp>=s.retry_sweep then
        s.retry_sweep=stamp+POSITION_CACHE_SECONDS
        for index,retry in pairs(s.retries) do
            if not alive(retry.unit) or stamp>=retry.until_time then s.retries[index]=nil end
        end
        for index,failed in pairs(s.failed) do
            if not alive(failed.unit) or stamp>=failed.until_time then s.failed[index]=nil end
        end
    end
    local count,front_edge=0,0
    for index,c in pairs(s.claims) do
        if not alive(c.unit) or stamp-c.updated>2
            or distance(c.unit:GetAbsOrigin(),origin)>ENGAGE_DISTANCE+64 then
            s.claims[index]=nil
        else
            count=count+1
            front_edge=math.max(front_edge,contact_back_edge(origin,c.point,hull(c.unit)))
        end
    end
    if count==0 and next(s.retries)==nil then s.face=nil end
    local own=s.claims[id]
    if own then
        own.updated=stamp
        own.arrived=M.arrived(wall,unit,own.point,true)
        local progressed=own.arrived or interrupted(unit) or moved(p,own.progress_position)
        if progressed then own.progress_position=p;own.progress_time=stamp end
        -- Refresh navigation only on the bounded cache cadence, not every tick.
        local clear=true
        if stamp-own.nav_checked>=POSITION_CACHE_SECONDS then
            own.nav_checked=stamp;clear=clear_point(wall,unit,own.point)
        end
        if clear and (interrupted(unit) or own.arrived or stamp-own.progress_time<STALL_SECONDS) then
            return {point=own.point,claimed=true}
        end
        -- A stalled reservation must not renew forever. Keep its attack face,
        -- and give this unit another point or let a waiting neighbour take over.
        s.claims[id]=nil;count=count-1
        front_edge=0
        for _,c in pairs(s.claims) do
            front_edge=math.max(front_edge,contact_back_edge(origin,c.point,hull(c.unit)))
        end
        s.retries[id]={unit=unit,key=own.key,until_time=stamp+STALL_SECONDS}
    end
    local retry=s.retries[id]
    if retry and stamp>=retry.until_time then s.retries[id]=nil;retry=nil end
    -- Bounded hot path: inspect at most four claims; no sorting, path searches
    -- or per-waiter queue scans. Wait geometry is checked once per cached size.
    if count>=COUNT then
        local nearest,best_distance
        for _,c in pairs(s.claims) do
            local d=distance(p,c.point)
            if not best_distance or d<best_distance then nearest,best_distance=c,d end
        end
        return {point=waiting_point(wall,unit,nearest,front_edge) or p,claimed=false}
    end
    local failed=s.failed[id]
    if failed and stamp<failed.until_time and not moved(p,failed.position) then
        return {point=failed.point or p,claimed=false}
    end
    s.failed[id]=nil
    local candidates={}
    for _,candidate in ipairs(positions(s,unit,stamp)) do
        -- Once the local front is engaged, replacements stay on that same
        -- reachable face instead of walking through the gate to the rear.
        if not s.face or candidate.key:sub(1,1)==s.face then
            candidates[#candidates+1]={point=candidate.point,key=candidate.key,source=candidate,
                distance=distance(p,candidate.point),skip=retry and retry.key==candidate.key}
        end
    end
    table.sort(candidates,function(a,b) return a.distance<b.distance end)
    local nearest=candidates[1]
    -- No reachable contact must not fall back to unrestricted native attacks.
    if not nearest then return {point=p,claimed=false} end
    -- No mid-move stealing: an admitted unit can traverse the crowd, so taking
    -- its claim would briefly phase both the old and new owner of one contact.
    local best,best_path,path_tested
    for _,c in ipairs(candidates) do
        if best_path and c.distance>best_path then break end
        local occupied=false
        for _,taken in pairs(s.claims) do
            if distance(taken.point,c.point)<hull(unit)+hull(taken.unit) then occupied=true;break end
        end
        if not occupied and not c.skip then
            path_tested=true
            local path=GridNav:FindPathLength(p,c.point)
            if path and path>=0 and (not best_path or path<best_path) then best,best_path=c,path end
        end
    end
    if not best then
        local source=nearest.source
        local wait_point=waiting_point(wall,unit,source,front_edge)
        if path_tested then
            s.failed[id]={unit=unit,position=Vector(p.x,p.y,p.z),point=wait_point,
                until_time=stamp+POSITION_CACHE_SECONDS}
        end
        return {point=wait_point or p,claimed=false}
    end
    s.face=best.key:sub(1,1)
    s.claims[id]={unit=unit,point=best.point,key=best.key,updated=stamp,
        progress_position=p,progress_time=stamp,nav_checked=stamp,
        arrived=M.arrived(wall,unit,best.point,true)}
    return {point=best.point,claimed=true}
end

function M.attack_range(unit,wall)
    -- Only called after claiming/reaching a face contact. Native buildings use
    -- a different attack-distance allowance from their padded navigation hull.
    -- Cover the actual center distance so the rooted contact can always attack;
    -- physical reach is bounded by the contact position, never this property.
    return math.ceil(distance(unit:GetAbsOrigin(),wall:GetAbsOrigin())+8)
end
return M
