-- Four exclusive contacts PER FACE. Front owners use a bounded navigation
-- hull and phased movement; rear bodies keep their configured collision hull.
local M = {}
local states = {}
local HALF, COUNT, ENGAGE_DISTANCE = 128, 4, 512
local FRONT_HULL, LANE_PITCH, CONTACT_NORMAL = 24, 48, 184
local STALL_SECONDS, POSITION_CACHE_SECONDS = 3, 2
local SETTLE_DISTANCE, WAIT_CLEARANCE, RETREAT_ALLOWANCE = 64, 8, 32
local function alive(u) return u and not u:IsNull() and u:IsAlive() end
local function distance(a,b)
    local x,y=a.x-b.x,a.y-b.y
    return math.sqrt(x*x+y*y)
end
local function now() return GameRules:GetGameTime() end
local function hull(u) return math.max(1,u:GetHullRadius()) end
local function valid(u) return u and not u:IsNull() end
local function valid_radius(value)
    local radius=tonumber(value)
    if radius and radius==radius and radius>=0 and radius<math.huge then return radius end
end
-- Keep the collision policy separate from a contact's temporary native hull.
-- A debug hull-scale change during contact must survive release/cleanup.
local function front_hull(claim)
    local unit=claim.unit
    local current=unit:GetHullRadius()
    local policy=valid_radius(unit.survival_monster_hull_radius)
    if policy and policy~=claim.policy_hull then
        claim.original_hull=policy
    elseif current~=claim.front_hull then
        claim.original_hull=current
    end
    claim.policy_hull=policy
    local radius=math.min(FRONT_HULL,claim.original_hull)
    if current~=radius then
        if not unit.SetHullRadius then return false end
        local ok=pcall(unit.SetHullRadius,unit,radius)
        local applied=unit:GetHullRadius()
        if not ok or applied~=radius then
            -- Do not reserve a slot on the assumption that a native mutation
            -- worked. Even a failing setter must not leak a partial adjustment.
            if applied~=current then pcall(unit.SetHullRadius,unit,current) end
            return false
        end
    end
    claim.front_hull=radius
    return true
end
local retire_claim,clear_state
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
-- arbitrary offset. A little navigation slack is needed at narrow gate edges.
function M.arrived(wall,unit,point,retained)
    local p=unit:GetAbsOrigin()
    return distance(p,point)<=(retained and 1 or SETTLE_DISTANCE)
        and math.abs(p.z-point.z)<=32
end
local function clear_point(wall,unit,point,check_radius)
    if math.abs(GetGroundHeight(point,unit)-wall:GetAbsOrigin().z)>128 then return false end
    -- Touching the terrain edge is valid; sample inside the hull instead of
    -- stepping exactly onto the next navigation cell at a narrow gate's edge.
    local radius=math.max(0,(check_radius or hull(unit))-1)
    for _,offset in ipairs({{0,0},{radius,0},{-radius,0},{0,radius},{0,-radius}}) do
        local sample=Vector(point.x+offset[1],point.y+offset[2],point.z)
        if not GridNav:IsTraversable(sample) or GridNav:IsBlocked(sample) then return false end
    end
    return true
end
local function safe_segment(unit,p,point,radius)
    local steps=math.max(1,math.ceil(distance(p,point)/16))
    radius=math.max(0,radius-1)
    for index,offset in ipairs({{0,0},{radius,0},{-radius,0},{0,radius},{0,-radius}}) do
        local cleared=false
        for step=0,steps do
            local t=step/steps
            local sample=Vector(p.x+(point.x-p.x)*t+offset[1],
                p.y+(point.y-p.y)*t+offset[2],point.z)
            local clear=GridNav:IsTraversable(sample) and not GridNav:IsBlocked(sample)
            -- Let an existing peripheral overlap leave. Never cross a new
            -- obstacle, reenter one, or align through an invalid center.
            if not clear and (index==1 or cleared or step==steps) then return false end
            cleared=cleared or clear
            if index==1 and math.abs(GetGroundHeight(sample,unit)-point.z)>32 then return false end
        end
    end
    return true
end
local function exit_front(s,claim,radius)
    local unit,wall=claim.unit,s.wall
    if radius<=claim.front_hull or not alive(unit) or not valid(wall) or not unit.SetAbsOrigin
        or (unit.IsStunned and unit:IsStunned())
        or (unit.IsCommandRestricted and unit:IsCommandRestricted())
        or (unit.IsCurrentlyHorizontalMotionControlled and unit:IsCurrentlyHorizontalMotionControlled())
        or (unit.IsCurrentlyVerticalMotionControlled and unit:IsCurrentlyVerticalMotionControlled()) then return end
    local p=unit:GetAbsOrigin()
    if distance(p,claim.point)>SETTLE_DISTANCE or clear_point(wall,unit,p,radius) then return end
    local origin=wall:GetAbsOrigin()
    local x_axis=claim.face<=2
    local sign=(claim.face==1 or claim.face==3) and -1 or 1
    local normal=math.max(sign*(x_axis and p.x-origin.x or p.y-origin.y),HALF+radius+32)
    local along=x_axis and p.y-origin.y or p.x-origin.x
    -- This is one short collision correction on exit, not movement on a
    -- timer. Restore larger bodies outside the wall and any narrow bank.
    for step=0,8 do
        local lateral=(along<0 and -1 or 1)*math.max(0,math.abs(along)-step*16)
        local point=x_axis and Vector(origin.x+sign*normal,origin.y+lateral,p.z)
            or Vector(origin.x+lateral,origin.y+sign*normal,p.z)
        point.z=GetGroundHeight(point,unit)
        if distance(p,point)<=128 and clear_point(wall,unit,point,radius)
            and safe_segment(unit,p,point,radius) then unit:SetAbsOrigin(point);return end
        if lateral==0 then return end
    end
end
retire_claim=function(s,id)
    local claim=s.claims[id]
    if not claim then return end
    s.claims[id]=nil
    local face=s.faces[claim.face]
    face.claims[id]=nil;face.slots[claim.lane]=nil;face.count=face.count-1
    local unit=claim.unit
    -- Death still leaves a valid corpse entity; restore it too. Preserve an
    -- external native hull change instead of replacing it with an old backup.
    if valid(unit) and unit.SetHullRadius and unit:GetHullRadius()==claim.front_hull then
        local policy=valid_radius(unit.survival_monster_hull_radius)
        local radius=(policy and policy~=claim.policy_hull) and policy or claim.original_hull
        if radius~=claim.front_hull then
            exit_front(s,claim,radius)
            pcall(unit.SetHullRadius,unit,radius)
        end
    end
end
clear_state=function(s)
    for id in pairs(s.claims) do retire_claim(s,id) end
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
        if not safe_segment(unit,p,point,hull(unit)) then return false end
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
    local stamp=now()
    if not cache or cache.front_edge~=front_edge or stamp-cache.updated>=POSITION_CACHE_SECONDS then
        cache={front_edge=front_edge,updated=stamp};source.wait_points=cache
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
        if s then clear_state(s) end
        s={wall=wall,claims={},faces={},positions={},retries={},failed={},retry_sweep=0}
        for side=1,4 do s.faces[side]={claims={},slots={},count=0} end
        states[id]=s
    end
    return s
end
local function positions(s,unit,stamp)
    local radius=math.min(FRONT_HULL,hull(unit))
    local cached=s.positions[radius]
    if cached and stamp-cached.updated<POSITION_CACHE_SECONDS then return cached.points end
    local p=s.wall:GetAbsOrigin()
    local result={}
    -- Fixed slots do not change with model size or hull debug multipliers.
    -- Diameter 48, lanes +/-72 and +/-24 leave 32 units of lateral slack.
    for side=1,4 do
        for lane=1,COUNT do
            local along=(lane-(COUNT+1)*0.5)*LANE_PITCH
            -- Keep endpoints outside the engine's inflated navigation cell.
            local normal=CONTACT_NORMAL
            local x,y
            if side<=2 then x=(side==1 and -normal or normal);y=along
            else x=along;y=(side==3 and -normal or normal) end
            local point=Vector(p.x+x,p.y+y,p.z)
            point.z=GetGroundHeight(point,unit)
            if clear_point(s.wall,unit,point,radius) then
                result[#result+1]={point=point,key=side..":"..lane,face=side,lane=lane}
            end
        end
    end
    s.positions[radius]={points=result,updated=stamp}
    return result
end
function M.release(wall_index,unit_index)
    local s=states[tonumber(wall_index)]
    if s then
        retire_claim(s,tonumber(unit_index))
        s.retries[tonumber(unit_index)]=nil
        s.failed[tonumber(unit_index)]=nil
    end
end
function M.clear(wall_index)
    local id=tonumber(wall_index)
    if states[id] then clear_state(states[id]);states[id]=nil end
end
function M.reset()
    for _,s in pairs(states) do clear_state(s) end
    states={}
end

local function face_for(p,origin)
    local dx,dy=p.x-origin.x,p.y-origin.y
    if math.abs(dx)>=math.abs(dy) then return dx<0 and 1 or 2 end
    return dy<0 and 3 or 4
end
local function clean_face(s,side,origin,stamp)
    local face=s.faces[side]
    local front_edge=0
    for id,c in pairs(face.claims) do
        if not alive(c.unit) or stamp-c.updated>2
            or distance(c.unit:GetAbsOrigin(),origin)>ENGAGE_DISTANCE+64 then
            retire_claim(s,id)
        else
            front_edge=math.max(front_edge,contact_back_edge(origin,c.point,hull(c.unit)))
        end
    end
    return front_edge
end
local function nearest_claim(face,p)
    local nearest,best_distance
    for _,c in pairs(face.claims) do
        local d=distance(p,c.point)
        if not best_distance or d<best_distance then nearest,best_distance=c,d end
    end
    return nearest
end
local function waiting_plan(unit,p,side,front_edge,point)
    return {point=point or p,claimed=false,wait_face=side,wait_envelope=front_edge,
        wait_radius=hull(unit),waiting_blocked=not point}
end

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
        -- Orphan cleanup stays bounded by sixteen owners, regardless of the
        -- number of monsters waiting behind any face. No whole-map search.
        for side=1,4 do clean_face(s,side,origin,stamp) end
    end
    local own=s.claims[id]
    if own and own.unit~=unit then retire_claim(s,id);own=nil end
    local side=own and own.face or face_for(p,origin)
    local retry=s.retries[id]
    if retry and retry.unit==unit and stamp<retry.until_time then side=retry.face
    else s.retries[id]=nil;retry=nil end
    local front_edge=clean_face(s,side,origin,stamp)
    local face=s.faces[side]
    own=s.claims[id]
    if own then
        own.updated=stamp
        own.arrived=M.arrived(wall,unit,own.point,true)
        local progressed=own.arrived or interrupted(unit) or moved(p,own.progress_position)
        if progressed then own.progress_position=p;own.progress_time=stamp end
        -- Refresh navigation only on the bounded cache cadence, not every tick.
        local clear=front_hull(own)
        if stamp-own.nav_checked>=POSITION_CACHE_SECONDS then
            own.nav_checked=stamp;clear=clear and clear_point(wall,unit,own.point)
        end
        if clear and (interrupted(unit) or own.arrived or stamp-own.progress_time<STALL_SECONDS) then
            return {point=own.point,claimed=true}
        end
        -- A stalled reservation must not renew forever. Keep this unit's face,
        -- and give this unit another point or let a waiting neighbour take over.
        retire_claim(s,id)
        front_edge=clean_face(s,side,origin,stamp)
        retry={unit=unit,key=own.key,face=side,until_time=stamp+STALL_SECONDS}
        s.retries[id]=retry
    end
    -- Bounded hot path: inspect at most four claims; no sorting, path searches
    -- or per-waiter queue scans. Wait geometry is checked once per cached size.
    if face.count>=COUNT then
        local nearest=nearest_claim(face,p)
        return waiting_plan(unit,p,side,front_edge,waiting_point(wall,unit,nearest,front_edge))
    end
    local failed=s.failed[id]
    if failed and failed.unit==unit and failed.face==side
        and failed.front_edge==front_edge and stamp<failed.until_time and not moved(p,failed.position) then
        return waiting_plan(unit,p,side,front_edge,failed.point)
    end
    s.failed[id]=nil
    local available=positions(s,unit,stamp)
    local function candidates_for(other_faces)
        local result={}
        for _,candidate in ipairs(available) do
            if (candidate.face==side)~=other_faces then
                result[#result+1]={point=candidate.point,key=candidate.key,source=candidate,
                    face=candidate.face,lane=candidate.lane,distance=distance(p,candidate.point),
                    skip=retry and retry.key==candidate.key}
            end
        end
        table.sort(result,function(a,b) return a.distance<b.distance end)
        return result
    end
    local candidates=candidates_for(false)
    local nearest=candidates[1]
    -- No mid-move stealing: an admitted unit can traverse the crowd, so taking
    -- its claim would briefly phase both the old and new owner of one contact.
    local function choose(list)
        local best,best_path,path_tested
        for _,c in ipairs(list) do
            if best_path and c.distance>best_path then break end
            local target_face=s.faces[c.face]
            -- Each face has its own four stable keys. A full near face must
            -- wait locally, never walk to the rear to become a fifth attacker.
            if target_face.count<COUNT and not target_face.slots[c.lane] and not c.skip then
                path_tested=true
                local path=GridNav:FindPathLength(p,c.point)
                if path and path>=0 and (not best_path or path<best_path) then best,best_path=c,path end
            end
        end
        return best,path_tested
    end
    local best,path_tested=choose(candidates)
    -- With no engaged local front, an entirely unreachable approach may use
    -- another genuinely reachable face. Never override a local queue/cooldown.
    if not best and face.count==0 and not retry and (path_tested or not nearest) then
        local others=candidates_for(true)
        for other_side=1,4 do
            if other_side~=side then clean_face(s,other_side,origin,stamp) end
        end
        local tested
        best,tested=choose(others);path_tested=path_tested or tested
    end
    if not best then
        local source=nearest_claim(face,p) or (nearest and nearest.source)
        local wait_point=source and waiting_point(wall,unit,source,front_edge)
        if path_tested then
            s.failed[id]={unit=unit,face=side,front_edge=front_edge,position=Vector(p.x,p.y,p.z),point=wait_point,
                until_time=stamp+POSITION_CACHE_SECONDS}
        end
        return waiting_plan(unit,p,side,front_edge,wait_point)
    end
    local claim={unit=unit,point=best.point,key=best.key,face=best.face,lane=best.lane,updated=stamp,
        original_hull=unit:GetHullRadius(),
        policy_hull=valid_radius(unit.survival_monster_hull_radius),
        progress_position=p,progress_time=stamp,nav_checked=stamp,
        arrived=M.arrived(wall,unit,best.point,true)}
    if not front_hull(claim) then
        s.failed[id]={unit=unit,face=side,front_edge=front_edge,position=Vector(p.x,p.y,p.z),
            until_time=stamp+POSITION_CACHE_SECONDS}
        return waiting_plan(unit,p,side,front_edge,nil)
    end
    s.claims[id]=claim
    local target_face=s.faces[best.face]
    target_face.claims[id]=claim;target_face.slots[best.lane]=id;target_face.count=target_face.count+1
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
