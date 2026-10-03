-- Four short-range contacts, chosen by path length. No FIFO, rear queue, or
-- spawn direction choosing the attack face before monsters reach the corridor.
local M = {}
local states = {}
local HALF, COUNT, ENGAGE_DISTANCE = 128, 4, 512
local STALL_SECONDS, POSITION_CACHE_SECONDS = 3, 2
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
-- Claim protection and the AI must agree on what reaching the front means.
-- A unit inside a 64-radius circle can still miss its lane by more than 20.
function M.arrived(wall,unit,point,retained)
    local p,w=unit:GetAbsOrigin(),wall:GetAbsOrigin()
    local dx,dy=math.abs(p.x-point.x),math.abs(p.y-point.y)
    local x_face=math.abs(point.x-w.x)>math.abs(point.y-w.y)
    local normal_error,lateral_error=x_face and dx or dy,x_face and dy or dx
    return normal_error<=(retained and 60 or 56) and lateral_error<=20
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
local function state_for(wall)
    local id=wall:entindex()
    local s=states[id]
    if not s or s.wall~=wall then
        s={wall=wall,claims={},positions={},retries={}}
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
    local retry_active=false
    for index,retry in pairs(s.retries) do
        if not alive(retry.unit) or stamp>=retry.until_time
            or distance(retry.unit:GetAbsOrigin(),origin)>ENGAGE_DISTANCE+64 then
            s.retries[index]=nil
        else retry_active=true end
    end
    local count=0
    for index,c in pairs(s.claims) do
        if not alive(c.unit) or stamp-c.updated>2
            or distance(c.unit:GetAbsOrigin(),origin)>ENGAGE_DISTANCE+64 then
            s.claims[index]=nil
        else count=count+1 end
    end
    if count==0 and not retry_active then s.face=nil end
    local own=s.claims[id]
    if own then
        own.updated=stamp
        own.arrived=M.arrived(wall,unit,own.point,own.arrived)
        local progressed=own.arrived or interrupted(unit) or moved(p,own.progress_position)
        if progressed then own.progress_position=p;own.progress_time=stamp end
        -- Refresh navigation only on the bounded cache cadence, not every tick.
        local clear=true
        if stamp-own.nav_checked>=POSITION_CACHE_SECONDS then
            own.nav_checked=stamp;clear=clear_point(wall,unit,own.point)
        end
        if interrupted(unit) or (clear and (own.arrived or stamp-own.progress_time<STALL_SECONDS)) then
            return {point=own.point,claimed=true}
        end
        -- A stalled reservation must not renew forever. Keep its attack face,
        -- and give this unit another point or let a waiting neighbour take over.
        s.claims[id]=nil;count=count-1
        s.retries[id]={unit=unit,key=own.key,until_time=stamp+STALL_SECONDS}
    end
    local retry=s.retries[id]
    local candidates={}
    for _,candidate in ipairs(positions(s,unit,stamp)) do
        -- Once the local front is engaged, replacements stay on that same
        -- reachable face instead of walking through the gate to the rear.
        if not s.face or candidate.key:sub(1,1)==s.face then
            candidates[#candidates+1]={point=candidate.point,key=candidate.key,
                distance=distance(p,candidate.point),skip=retry and retry.key==candidate.key}
        end
    end
    table.sort(candidates,function(a,b) return a.distance<b.distance end)
    local nearest=candidates[1]
    if not nearest then return nil end
    -- A closer monster can replace an unarrived reservation. Arrived attackers
    -- retain their contacts, so scheduler order cannot put a rear unit first.
    if count>=COUNT then
        local replace,best_gain
        for index,c in pairs(s.claims) do
            local old_distance=distance(c.unit:GetAbsOrigin(),c.point)
            local gain=old_distance-distance(p,c.point)
            c.arrived=M.arrived(wall,c.unit,c.point,c.arrived)
            if not c.arrived and not interrupted(c.unit) and gain>32 and (not best_gain or gain>best_gain) then
                replace=index;best_gain=gain
            end
        end
        if replace then s.claims[replace]=nil;count=count-1 end
    end
    -- Full front: approach locally through normal unit collision, never march
    -- to a numbered queue or reserve a lane from the spawn point.
    if count>=COUNT then return {point=nearest.point,claimed=false} end
    local best,best_path
    for _,c in ipairs(candidates) do
        if best_path and c.distance>best_path then break end
        local occupied=false
        for _,taken in pairs(s.claims) do
            if distance(taken.point,c.point)<hull(unit)+hull(taken.unit) then occupied=true;break end
        end
        if not occupied and not c.skip then
            local path=GridNav:FindPathLength(p,c.point)
            if path and path>=0 and (not best_path or path<best_path) then best,best_path=c,path end
        end
    end
    if not best then return {point=nearest.point,claimed=false} end
    s.face=best.key:sub(1,1)
    s.claims[id]={unit=unit,point=best.point,key=best.key,updated=stamp,
        progress_position=p,progress_time=stamp,nav_checked=stamp,
        arrived=M.arrived(wall,unit,best.point,false)}
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
