-- Four exclusive contacts per face. Native movement and fixed collision
-- bodies remain active throughout approach, waiting, attack and replacement.
local M = {}
local states = {}
local navigation = require('systems/wall_navigation_service')
local rear_queue = require('systems/wall_melee_queue')
local HALF, COUNT, ENGAGE_DISTANCE = 128, 4, 512
-- Hull32 has padded radius42. Four centers fit a384 stair without shrinking
-- any body; terrain may reject an outer contact on an offset placement.
local LANE_PITCH, CONTACT_NORMAL = 88, 184
local CONTACT_SHIFT_LIMIT, CONTACT_SHIFT_STEP = 192, 4
local STALL_SECONDS, POSITION_CACHE_SECONDS = 3, 2
local PATH_STEP_SECONDS, PATHS_PER_STEP = 0.5, 16
local SETTLE_DISTANCE, WAIT_CLEARANCE = 36, 8
local MAX_NATIVE_ROUTE = ENGAGE_DISTANCE*3
local function alive(u) return u and not u:IsNull() and u:IsAlive() end
local function distance(a,b)
    local x,y=a.x-b.x,a.y-b.y
    return math.sqrt(x*x+y*y)
end
local function now() return GameRules:GetGameTime() end
local function hull(u) return math.max(1,u:GetHullRadius()) end
local function body_radius(u)
    local radius=hull(u)
    return math.max(radius,u.GetPaddedCollisionRadius and u:GetPaddedCollisionRadius() or radius+10)
end
local function valid(u) return u and not u:IsNull() end
function M.recovery_radius(wall,unit) return hull(unit) end
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
-- Native MOVE can stop32 short. The old64 tolerance also admitted a second
-- row behind a live blocker. Never teleport an entrant into its reserved slot.
function M.arrived(wall,unit,point,retained)
    local p=unit:GetAbsOrigin()
    return distance(p,point)<=(retained and 48 or SETTLE_DISTANCE)
        and math.abs(p.z-point.z)<=32
end
function M.entry_ready(wall,unit,point)
    -- Legacy API: every route retains native unit and terrain collision.
    return true
end
local function clear_point(wall,unit,point,check_radius,ground_move)
    if not ground_move and math.abs(GetGroundHeight(point,unit)-wall:GetAbsOrigin().z)>128 then return false end
    -- Touching the terrain edge is valid; sample inside the hull instead of
    -- stepping exactly onto the next navigation cell at a narrow gate's edge.
    local radius=math.max(0,(check_radius or hull(unit))-1)
    for _,offset in ipairs({{0,0},{radius,0},{-radius,0},{0,radius},{0,-radius}}) do
        local sample=Vector(point.x+offset[1],point.y+offset[2],point.z)
        if not GridNav:IsTraversable(sample) or GridNav:IsBlocked(sample) then return false end
    end
    return true
end
local function safe_segment(unit,p,point,radius,ground_move)
    local steps=math.max(1,math.ceil(distance(p,point)/16))
    radius=math.max(0,radius-1)
    for index,offset in ipairs({{0,0},{radius,0},{-radius,0},{0,radius},{0,-radius}}) do
        local cleared,previous_ground=false,nil
        for step=0,steps do
            local t=step/steps
            local sample=Vector(p.x+(point.x-p.x)*t+offset[1],
                p.y+(point.y-p.y)*t+offset[2],point.z)
            local clear=GridNav:IsTraversable(sample) and not GridNav:IsBlocked(sample)
            -- Let an existing peripheral overlap leave. Never cross a new
            -- obstacle, reenter one, or align through an invalid center.
            if not clear and (index==1 or cleared or step==steps) then return false end
            cleared=cleared or clear
            if index==1 then
                local ground=GetGroundHeight(sample,unit)
                -- Native MOVE follows a continuous stair. Validate each
                -- adjacent terrain sample rather than one flat-height chord.
                local reference=ground_move and (previous_ground or p.z) or point.z
                if math.abs(ground-reference)>32 then return false end
                previous_ground=ground
            end
        end
    end
    return true
end
retire_claim=function(s,id)
    local claim=s.claims[id]
    if not claim then return end
    s.claims[id]=nil
    local face=s.faces[claim.face]
    face.claims[id]=nil;face.slots[claim.lane]=nil;face.count=face.count-1
    face.replacement_priority=true;face.priority_dirty=true
    face.priority_owner,face.priority_candidate=nil,nil
    s.count=s.count-1;s.revision=s.revision+1
end
clear_state=function(s)
    for id in pairs(s.claims) do retire_claim(s,id) end
    rear_queue.reset(s)
end
-- Only admission checks real bodies, after native MOVE has actually reached
-- a contact. Cache one local snapshot per wall/observation; a dense queue must
-- not cause one neighbour query per waiting monster. No actor is phase-exempt.
local function bodies_clear(wall,unit,point)
    if type(FindUnitsInRadius)~='function' then return true end
    local s=states[wall:entindex()]
    local stamp=math.floor(now()/PATH_STEP_SECONDS)
    local snapshot=s and s.bodies
    if not snapshot or snapshot.stamp~=stamp then
        local flags=(DOTA_UNIT_TARGET_FLAG_INVULNERABLE or 0)+(DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES or 0)
        snapshot={stamp=stamp,units=FindUnitsInRadius(unit:GetTeamNumber(),wall:GetAbsOrigin(),nil,ENGAGE_DISTANCE,
            DOTA_UNIT_TARGET_TEAM_BOTH,DOTA_UNIT_TARGET_BASIC+DOTA_UNIT_TARGET_HERO,flags,FIND_ANY_ORDER,false)}
        if s then s.bodies=snapshot end
    end
    local radius=hull(unit)
    for _,other in ipairs(snapshot.units) do
        if other~=unit and other~=wall and alive(other) then
            -- Native Hull0 builders/visual carriers occupy no physical body.
            -- Positive monster hulls remain solid regardless of old AI flags.
            local other_radius=other:GetHullRadius()
            if other_radius>0 then
                local limit=radius+other_radius
                if distance(point,other:GetAbsOrigin())<limit-.5 then return false end
            end
        end
    end
    return true
end
-- Compatibility hook for existing observers. Contacts never mutate hulls,
-- so release/death/cleanup has no temporary radius to restore.
function M.restore_hull(unit,force) return false end

function M.settle(wall,unit,point)
    if not M.arrived(wall,unit,point,false) or interrupted(unit)
        or (unit.IsCurrentlyHorizontalMotionControlled and unit:IsCurrentlyHorizontalMotionControlled())
        or (unit.IsCurrentlyVerticalMotionControlled and unit:IsCurrentlyVerticalMotionControlled()) then return false end
    local s=states[wall:entindex()]
    local claim=s and s.claims[unit:entindex()]
    if not claim or claim.unit~=unit or claim.point~=point then return false end
    local p=unit:GetAbsOrigin()
    if not clear_point(wall,unit,p) or not clear_point(wall,unit,point)
        or not safe_segment(unit,p,point,hull(unit))
        or not bodies_clear(wall,unit,p) then return false end
    claim.arrived=true;claim.settled=true
    return true
end

-- An intruding body may move back to its waiting goal, using ordinary native
-- collision. If live rear bodies block that MOVE it waits or takes a real detour.
function M.can_retreat(wall,unit,point)
    if not point or interrupted(unit)
        or (unit.IsCurrentlyHorizontalMotionControlled and unit:IsCurrentlyHorizontalMotionControlled())
        or (unit.IsCurrentlyVerticalMotionControlled and unit:IsCurrentlyVerticalMotionControlled()) then return false end
    return clear_point(wall,unit,point,nil,true)
        and safe_segment(unit,unit:GetAbsOrigin(),point,hull(unit),true)
end

local function contact_back_edge(origin,point,radius,face)
    local normal=face<=2 and point.x-origin.x or point.y-origin.y
    if face==1 or face==3 then normal=-normal end
    return normal+radius
end
local function waiting_point(wall,unit,source,front_edge)
    local s=states[wall:entindex()]
    if not s or not source then return nil end
    return rear_queue.reserve(s,wall,unit,source.face,front_edge,now())
end
local function state_for(wall)
    local id=wall:entindex()
    local s=states[id]
    local p=wall:GetAbsOrigin()
    local revision=tonumber(wall.survival_wall_relocation_revision) or 0
    if not s or s.wall~=wall or s.wall_revision~=revision
        or s.origin.x~=p.x or s.origin.y~=p.y or s.origin.z~=p.z then
        if s then clear_state(s) end
        s={wall=wall,claims={},waiters={},faces={},positions={},staging={},retries={},failed={},retry_sweep=0,
            count=0,revision=0,layout=navigation.contact_layout and navigation.contact_layout(wall),
            origin=Vector(p.x,p.y,p.z),wall_revision=revision,path_limit=PATHS_PER_STEP}
        s.lane_pitch=LANE_PITCH
        for side=1,4 do s.faces[side]={claims={},slots={},count=0} end
        states[id]=s
    end
    return s
end
local positions,face_for
local function forget_waiter(s,id,retain_queue)
    if not retain_queue then rear_queue.release(s,id) end
    local record=s.waiters[id]
    if not record then return end
    s.waiters[id]=nil
    local face=s.faces[record.face]
    if face.priority_owner==record.unit then
        face.priority_owner,face.priority_candidate=nil,nil;face.priority_dirty=true
    end
end
local function observe_waiter(s,unit,side,stamp)
    local id=unit:entindex()
    local record=s.waiters[id]
    if record and (record.unit~=unit or record.face~=side) then forget_waiter(s,id);record=nil end
    if not record then
        record={unit=unit,face=side};s.waiters[id]=record
        local face=s.faces[side]
        if not face.priority_owner then face.priority_dirty=true end
    end
    record.updated=stamp
end
local function eligible_waiter(s,record,side,stamp)
    local u=record and record.unit
    if not alive(u) or record.face~=side or s.claims[u:entindex()]
        or stamp-record.updated>2 then return false end
    local owner=u.survival_wall_contact_owner
    if owner and owner.wall_entindex~=s.wall:entindex() then return false end
    local p=u:GetAbsOrigin()
    if distance(p,s.wall:GetAbsOrigin())>ENGAGE_DISTANCE or interrupted(u)
        or (u.IsCurrentlyHorizontalMotionControlled and u:IsCurrentlyHorizontalMotionControlled())
        or (u.IsCurrentlyVerticalMotionControlled and u:IsCurrentlyVerticalMotionControlled()) then return false end
    local retry=s.retries[u:entindex()]
    if retry and retry.unit==u and stamp<retry.until_time then return false end
    local failed=s.failed[u:entindex()]
    if failed and failed.unit==u and stamp<failed.until_time and not moved(p,failed.position) then return false end
    return true,p
end
-- A nearby body may already hold an unfulfilled route around the wall. A
-- real vacancy on its physical face may take precedence over that farther
-- route; a settled attacker or a body already around the corner is untouched.
local function eligible_route_owner(s,claim,side,stamp,point)
    local u=claim and claim.unit
    if not alive(u) or claim.settled or claim.face==side
        or s.claims[u:entindex()]~=claim or stamp-claim.updated>2 then return false end
    local owner=u.survival_wall_contact_owner
    if owner and owner.wall_entindex~=s.wall:entindex() then return false end
    local p=u:GetAbsOrigin()
    if distance(p,s.wall:GetAbsOrigin())>ENGAGE_DISTANCE
        or face_for(p,s.wall:GetAbsOrigin())~=side or interrupted(u)
        or (u.IsCurrentlyHorizontalMotionControlled and u:IsCurrentlyHorizontalMotionControlled())
        or (u.IsCurrentlyVerticalMotionControlled and u:IsCurrentlyVerticalMotionControlled()) then return false end
    local retry=s.retries[u:entindex()]
    if retry and retry.unit==u and retry.face==side and stamp<retry.until_time then return false end
    local failed=s.failed[u:entindex()]
    if failed and failed.unit==u and failed.face==side
        and stamp<failed.until_time and not moved(p,failed.position) then return false end
    if point and distance(p,point)+SETTLE_DISTANCE>=distance(p,claim.point) then return false end
    return true,p
end
local function vacant_candidate(s,unit,candidate)
    local face=s.faces[candidate.face]
    if face.slots[candidate.lane] then return false end
    for _,claim in pairs(s.claims) do
        if claim.unit~=unit and distance(candidate.point,claim.point)<hull(unit)+hull(claim.unit)+4 then
            return false
        end
    end
    return true
end
-- Only a vacated contact enables replacement priority. Maintain observations
-- in O(1); scan this wall's already observed local waiters once per vacancy,
-- stalled owner or invalid nominee. Stable full queues never enter this code.
local function replacement_owner(s,side,stamp)
    local face=s.faces[side]
    if not face.replacement_priority then return nil end
    local owner=face.priority_owner
    if owner then
        local record=s.waiters[owner:entindex()]
        if record and record.unit==owner and eligible_waiter(s,record,side,stamp) then return owner end
        local claim=s.claims[owner:entindex()]
        local candidate=face.priority_candidate
        if claim and claim.unit==owner and candidate and vacant_candidate(s,owner,candidate)
            and eligible_route_owner(s,claim,side,stamp,candidate.point) then return owner end
        face.priority_owner,face.priority_candidate=nil,nil;face.priority_dirty=true
    end
    if not face.priority_dirty then return nil end
    face.priority_dirty=false
    local nearest,nearest_candidate,best_distance,best_id,by_radius
    by_radius={}
    local function consider(unit,p,claim)
            local id=unit:entindex()
            local radius=hull(unit)
            local size_key=radius..":"..body_radius(unit)
            local candidates=by_radius[size_key]
            if not candidates then
                candidates={};by_radius[size_key]=candidates
                for _,candidate in ipairs(positions(s,unit,stamp)) do
                    if candidate.face==side and not face.slots[candidate.lane] then
                        local blocker
                        for _,other in pairs(s.claims) do
                            if distance(candidate.point,other.point)<radius+hull(other.unit)+4 then
                                if blocker then blocker=true;break end
                                blocker=other.unit
                            end
                        end
                        -- Cache this geometry once per radius, not once per
                        -- waiting monster. Only the sole displaced owner's
                        -- own reservation may be released by its transfer.
                        if blocker~=true then
                            candidates[#candidates+1]={source=candidate,blocker=blocker}
                        end
                    end
                end
            end
            for _,cached in ipairs(candidates) do
                local candidate=cached.source
                local point=candidate.point
                local dx,dy=p.x-point.x,p.y-point.y
                local d=dx*dx+dy*dy
                local nearer=not claim or distance(p,point)+SETTLE_DISTANCE<distance(p,claim.point)
                if nearer and (not cached.blocker or cached.blocker==unit)
                    and (not best_distance or d<best_distance or (d==best_distance and id<best_id)) then
                    nearest,nearest_candidate,best_distance,best_id=unit,candidate,d,id
                end
            end
    end
    for id,record in pairs(s.waiters) do
        local eligible,p=eligible_waiter(s,record,side,stamp)
        if eligible then consider(record.unit,p)
        elseif not alive(record.unit) or stamp-record.updated>2
            or distance(record.unit:GetAbsOrigin(),s.wall:GetAbsOrigin())>ENGAGE_DISTANCE then
            forget_waiter(s,id,alive(record.unit))
        end
    end
    -- At most sixteen registered claim owners, never a map/body search.
    for _,claim in pairs(s.claims) do
        local eligible,p=eligible_route_owner(s,claim,side,stamp)
        if eligible then consider(claim.unit,p,claim) end
    end
    face.priority_owner,face.priority_candidate=nearest,nearest_candidate
    return nearest
end
positions=function(s,unit,stamp)
    local radius=hull(unit)
    local padded_radius=body_radius(unit)
    local by_padding=s.positions[radius]
    local cached=by_padding and by_padding[padded_radius]
    if cached and stamp-cached.updated<POSITION_CACHE_SECONDS then return cached.points end
    local p=s.wall:GetAbsOrigin()
    local result={}
    -- Fixed keys never move when a model changes. Full physical hulls filter
    -- terrain, and neighbouring reservations must fit their padded bodies.
    for side=1,4 do
        local layout=s.layout
        local allowed=not layout or not layout.gate
            or (layout.axis==1 and side<=2) or (layout.axis==2 and side>=3)
        -- Keep a valid authored row unchanged. Moving a wall by one or two
        -- cells can reject several original contacts while the same stair
        -- still fits four native bodies. Fit that partial row on real terrain
        -- without depending on a recognized rectangular doorway.
        local checked={}
        local normal=math.max(CONTACT_NORMAL,HALF+radius+24)
        local function endpoint(along)
            if checked[along]~=nil then return checked[along] end
            local x,y
            if side<=2 then x=(side==1 and -normal or normal);y=along
            else x=along;y=(side==3 and -normal or normal) end
            local point=Vector(p.x+x,p.y+y,p.z)
            point.z=GetGroundHeight(point,unit)
            checked[along]=clear_point(s.wall,unit,point,radius) and point or false
            return checked[along]
        end
        local row,count,valid_along={},0,0
        if allowed then
            for lane=1,COUNT do
                local point=endpoint((lane-(COUNT+1)*0.5)*s.lane_pitch)
                row[lane]=point
                if point then
                    count=count+1
                    valid_along=valid_along+(lane-(COUNT+1)*0.5)*s.lane_pitch
                end
            end
        end
        local center,pitch=0,s.lane_pitch
        if count>0 and count<COUNT and padded_radius*2<=s.lane_pitch then
            local direction=valid_along>=0 and 1 or -1
            local minimum_pitch=math.max(s.lane_pitch-4,padded_radius*2)
            local repaired=false
            local function continuous(low,high)
                for along,point in pairs(checked) do
                    if point==false and along>=low and along<=high then return false end
                end
                local previous=endpoint(low)
                if not previous then return false end
                -- Four valid endpoints alone can straddle an unwalkable bank
                -- or a thin divider. The whole fitted row must be one native
                -- corridor, with no sideways cliff or blocked body samples.
                for along=low+CONTACT_SHIFT_STEP,high,CONTACT_SHIFT_STEP do
                    local point=endpoint(along)
                    if not point or math.abs(point.z-previous.z)>32 then return false end
                    previous=point
                end
                local last=endpoint(high)
                return last and math.abs(last.z-previous.z)<=32
            end
            -- Prefer the smallest displacement, then the wider safe pitch.
            -- Inspect both signs so a surviving off-center endpoint cannot
            -- send the repair towards a disconnected neighbouring floor.
            for offset=0,CONTACT_SHIFT_LIMIT,CONTACT_SHIFT_STEP do
                for _,sign in ipairs(offset==0 and {direction} or {direction,-direction}) do
                    local shift=sign*offset
                    for trial_pitch=s.lane_pitch,minimum_pitch,-2 do
                        -- Reject bad outer endpoints before checking the middle.
                        local first=endpoint(shift-1.5*trial_pitch)
                        local last=first and endpoint(shift+1.5*trial_pitch)
                        if last then
                            local second=endpoint(shift-.5*trial_pitch)
                            local third=second and endpoint(shift+.5*trial_pitch)
                            if third and continuous(shift-1.5*trial_pitch,shift+1.5*trial_pitch) then
                                row={first,second,third,last};center,pitch=shift,trial_pitch
                                repaired=true;break
                            end
                        end
                    end
                    if repaired then break end
                end
                if repaired then break end
            end
        end
        local low,high=center-COUNT*pitch*.5,center+COUNT*pitch*.5
        for lane=1,COUNT do
            if row[lane] then
                result[#result+1]={point=row[lane],key=side..":"..lane,face=side,lane=lane,
                    lateral_center=center,lateral_min=low,lateral_max=high,lane_pitch=pitch}
            end
        end
    end
    if not by_padding then by_padding={};s.positions[radius]=by_padding end
    by_padding[padded_radius]={points=result,updated=stamp}
    return result
end
-- Shared read-only candidates for target reachability. This performs cached
-- terrain filtering only: no reservation, hull mutation, path query or order.
function M.approach_points(wall,unit)
    if not alive(wall) or not alive(unit) then return {} end
    return positions(state_for(wall),unit,now())
end
function M.release(wall_index,unit_index)
    local s=states[tonumber(wall_index)]
    if s then
        retire_claim(s,tonumber(unit_index))
        forget_waiter(s,tonumber(unit_index))
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

face_for=function(p,origin)
    local dx,dy=p.x-origin.x,p.y-origin.y
    if math.abs(dx)>=math.abs(dy) then return dx<0 and 1 or 2 end
    return dy<0 and 3 or 4
end
local function path_budget(s,stamp)
    local step=math.floor(stamp/PATH_STEP_SECONDS)
    if s.path_step~=step then s.path_step=step;s.paths_left=PATHS_PER_STEP end
    return s.paths_left
end
local function grant_claim(s,unit,source,p,stamp)
    local id=unit:entindex()
    local claim={unit=unit,point=source.point,key=source.key,face=source.face,lane=source.lane,updated=stamp,
        lateral_center=source.lateral_center,lateral_min=source.lateral_min,
        lateral_max=source.lateral_max,lane_pitch=source.lane_pitch or s.lane_pitch,
        progress_position=p,progress_time=stamp,nav_checked=stamp,arrived=false,
        physical_face=face_for(p,s.wall:GetAbsOrigin())}
    s.claims[id]=claim
    forget_waiter(s,id)
    local face=s.faces[source.face]
    face.claims[id]=claim;face.slots[source.lane]=id;face.count=face.count+1
    face.priority_owner,face.priority_candidate=nil,nil;face.priority_dirty=true
    if claim.physical_face~=claim.face then
        local physical=s.faces[claim.physical_face]
        if physical.replacement_priority and not physical.priority_owner then physical.priority_dirty=true end
    end
    s.count=s.count+1;s.revision=s.revision+1
    return claim
end
local function clean_face(s,side,origin,stamp)
    local face=s.faces[side]
    local front_edge=0
    for id,c in pairs(face.claims) do
        local p=alive(c.unit) and c.unit:GetAbsOrigin()
        if not p or stamp-c.updated>2
            or distance(p,origin)>ENGAGE_DISTANCE+64 then
            retire_claim(s,id,p~=nil)
        else
            -- Native MOVE may stop short of its contact. Rear goals must
            -- clear the settled physical body, not its former nominal goal.
            front_edge=math.max(front_edge,contact_back_edge(origin,
                c.settled and p or c.point,body_radius(c.unit),side))
        end
    end
    return front_edge
end
local function transfer_to_near_vacancy(s,unit,own,p,stamp)
    if own.settled then return nil end
    local side=face_for(p,s.wall:GetAbsOrigin())
    local face=s.faces[side]
    if own.physical_face~=side then
        own.physical_face=side
        if face.replacement_priority and not face.priority_owner then face.priority_dirty=true end
    end
    if side==own.face or not face.replacement_priority or face.count>=COUNT then return nil end
    clean_face(s,side,s.wall:GetAbsOrigin(),stamp)
    local vacant=false
    for _,candidate in ipairs(positions(s,unit,stamp)) do
        if candidate.face==side and not face.slots[candidate.lane] then vacant=true;break end
    end
    -- Three terrain-valid slots occupied is already a full partial face.
    -- Do not rescan its waiters whenever another remote lease is renewed.
    if not vacant then return nil end
    if replacement_owner(s,side,stamp)~=unit then return nil end
    local candidate=face.priority_candidate
    if not candidate or not eligible_route_owner(s,own,side,stamp,candidate.point)
        or not vacant_candidate(s,unit,candidate) or path_budget(s,stamp)<=0 then return nil end
    s.paths_left=s.paths_left-1
    local path=GridNav:FindPathLength(p,candidate.point)
    if not clear_point(s.wall,unit,candidate.point) or not path or path<0 or path>MAX_NATIVE_ROUTE
        or path+SETTLE_DISTANCE>=distance(p,own.point) then
        -- A rejected shortcut must not destroy a valid in-flight reservation.
        s.failed[unit:entindex()]={unit=unit,face=side,position=Vector(p.x,p.y,p.z),
            until_time=stamp+POSITION_CACHE_SECONDS}
        face.priority_owner,face.priority_candidate=nil,nil;face.priority_dirty=true
        return nil
    end
    retire_claim(s,unit:entindex())
    s.retries[unit:entindex()],s.failed[unit:entindex()]=nil,nil
    return grant_claim(s,unit,candidate,p,stamp)
end
local function nearest_claim(face,p)
    local nearest,best_distance
    for _,c in pairs(face.claims) do
        local d=distance(p,c.point)
        if not best_distance or d<best_distance then nearest,best_distance=c,d end
    end
    return nearest
end
local function waiting_plan(wall,unit,p,side,front_edge,point)
    local origin=wall:GetAbsOrigin()
    local normal=side<=2 and p.x-origin.x or p.y-origin.y
    if side==1 or side==3 then normal=-normal end
    local radius=hull(unit)
    return {point=point or p,claimed=false,wait_face=side,wait_envelope=front_edge,
        wait_radius=radius,waiting_blocked=not point,
        wait_queue_key=point and string.format('%.17g:%.17g:%.17g',point.x,point.y,point.z) or nil,
        -- A missing rear endpoint does not authorize passing any live body.
        wait_retreat=front_edge>0 and normal<front_edge+body_radius(unit)+WAIT_CLEARANCE-0.01 or false}
end

-- A retreat is an ordinary native MOVE to a legal rear point. Do not search
-- for a phase exit through a crowd, reserve artificial escape bodies, or keep
-- extending it to force passage. A blocked rear is allowed to remain blocked.
function M.retreat_point(wall,unit,plan,minimum_normal)
    local point=plan.point
    if point and clear_point(wall,unit,point,nil,true) then return point end
end
function M.rear_clear(wall,unit) return true end
function M.extend_retreat(wall,unit,plan,goal) return nil,false end

-- A real front vacancy can wake a rear owner beyond the local admission
-- circle. Cache at most four faces per body geometry, never per waiting actor.
-- A full partial terrain row (e.g. three valid keys) is not a vacancy.
local function distant_front_vacancy(s,unit,side,stamp)
    local face=s.faces[side]
    if not face or face.count>=COUNT then return false end
    local radius,padding=hull(unit),body_radius(unit)
    local geometry=s.positions[radius] and s.positions[radius][padding]
    local by_radius=s.distant_vacancies
    if not by_radius then by_radius={};s.distant_vacancies=by_radius end
    local by_padding=by_radius[radius]
    if not by_padding then by_padding={};by_radius[radius]=by_padding end
    local faces=by_padding[padding]
    if not faces then faces={};by_padding[padding]=faces end
    local cached=faces[side]
    if cached and cached.revision==s.revision and cached.geometry==geometry then return cached.available end
    -- Refresh candidates only after a real occupancy/geometry change. Stable
    -- far waiters never expire/rebuild the shared terrain cache themselves.
    local available=false
    for _,candidate in ipairs(positions(s,unit,stamp)) do
        if candidate.face==side and not face.slots[candidate.lane] then available=true;break end
    end
    faces[side]={revision=s.revision,geometry=s.positions[radius][padding],available=available}
    return available
end

function M.resolve(wall,unit,preferred_face)
    if not alive(wall) or not alive(unit) then return nil end
    local p,origin=unit:GetAbsOrigin(),wall:GetAbsOrigin()
    local id=unit:entindex()
    if distance(p,origin)>ENGAGE_DISTANCE then
        local s=state_for(wall)
        retire_claim(s,id)
        local point,queue_side=rear_queue.peek(s,unit)
        local route=unit.survival_wall_route
        local verified=route and route.wall==wall and route.point
            and route.revision==(tonumber(wall.survival_wall_relocation_revision) or 0)
        local side=preferred_face or queue_side or face_for(p,origin)
        -- Rear destinations extend into the real courtyard. Keep those
        -- reservations outside the small attack-admission area so they do
        -- not collapse back into the four verified front waypoints.
        -- Only retain a real overflow reservation. A verified path is not a
        -- reason to put a first arrival in the rear queue: on a stair its
        -- first legal rear point can remain outside ENGAGE_DISTANCE forever.
        if point then
            local stamp=now()
            local front_edge=clean_face(s,side,origin,stamp)
            if verified and distant_front_vacancy(s,unit,side,stamp) then
                -- Keep the original rear reservation while routing. Only a
                -- successful local grant_claim releases it; simultaneous far
                -- waiters must not churn/schedule the entire rear queue.
                return {point=route.point,claimed=false,routing=true}
            end
            point=rear_queue.reserve(s,wall,unit,side,front_edge,stamp) or point
            return waiting_plan(wall,unit,p,side,front_edge,point)
        end
        M.release(wall:entindex(),id)
        if verified then
            -- Formal target selection has already checked this real contact's
            -- route. Keep ordinary collision while moving there; reservation
            -- and final entry still happen only inside the local contact area.
            return {point=route.point,claimed=false,routing=true}
        end
        local layout=navigation.contact_layout and navigation.contact_layout(wall)
        -- A distant attack-target order may stop at a blocked square or plan
        -- a whole-map detour around a full doorway. Stage outside the near
        -- face using native MOVE, including open/partly exposed walls; actual
        -- contact admission will choose a reachable face inside 512.
        local side=preferred_face or face_for(p,origin)
        local x_axis=side<=2
        local lateral=x_axis and p.y or p.x
        local center=x_axis and origin.y or origin.x
        local radius=hull(unit)
        local low,high=center-HALF+radius,center+HALF-radius
        if layout and layout.gate then low,high=layout.min+radius,layout.max-radius end
        lateral=math.max(low,math.min(high,lateral))
        local sign=(side==1 or side==3) and -1 or 1
        local state,stamp=state_for(wall),now()
        if stamp>=(state.staging_sweep or 0) then
            state.staging_sweep=stamp+POSITION_CACHE_SECONDS
            for cached_radius,entries in pairs(state.staging) do
                for cached_key,cached in pairs(entries) do
                    if stamp-cached.updated>=POSITION_CACHE_SECONDS then entries[cached_key]=nil end
                end
                if not next(entries) then state.staging[cached_radius]=nil end
            end
        end
        local stages=state.staging[radius]
        if not stages then stages={};state.staging[radius]=stages end
        local key=side..":"..string.format("%.17g",lateral)
        local stage=stages[key]
        if not stage or stamp-stage.updated>=POSITION_CACHE_SECONDS then
            local point=x_axis and Vector(origin.x+sign*320,lateral,origin.z)
                or Vector(lateral,origin.y+sign*320,origin.z)
            point.z=GetGroundHeight(point,unit)
            if not clear_point(wall,unit,point,radius,true) then
                local best,best_distance
                for _,candidate in ipairs(M.approach_points(wall,unit)) do
                    local length=distance(p,candidate.point)
                    if (not best_distance or length<best_distance)
                        and clear_point(wall,unit,candidate.point,radius,true) then
                        best,best_distance=candidate.point,length
                    end
                end
                point=best
            end
            stage={point=point,updated=stamp};stages[key]=stage
        end
        -- Unknown/legacy callers may use native chase if every safe staging
        -- point is blocked. Never park them forever at a bad MOVE.
        if not stage.point then return nil end
        return {point=stage.point,claimed=false,routing=true}
    end
    local s=state_for(wall)
    local stamp=now()
    -- Sweep failed reservations once per wall, not once per waiting monster.
    if stamp>=s.retry_sweep then
        s.retry_sweep=stamp+POSITION_CACHE_SECONDS
        for index,retry in pairs(s.retries) do
            if not alive(retry.unit) or stamp>=retry.until_time then s.retries[index]=nil end
        end
        for index,failed in pairs(s.failed) do
            if not alive(failed.unit) or stamp>=failed.until_time then
                local face=s.faces[failed.face]
                if face and face.replacement_priority then face.priority_dirty=true end
                s.failed[index]=nil
            end
        end
        -- Orphan cleanup stays bounded by sixteen owners, regardless of the
        -- number of monsters waiting behind any face. No whole-map search.
        for side=1,4 do clean_face(s,side,origin,stamp) end
    end
    local own=s.claims[id]
    if own and own.unit~=unit then retire_claim(s,id);own=nil end
    if preferred_face~=1 and preferred_face~=2 and preferred_face~=3 and preferred_face~=4 then
        preferred_face=nil
    end
    local queued_point,queue_side=rear_queue.peek(s,unit)
    local side=own and own.face or preferred_face or queue_side or face_for(p,origin)
    local retry=s.retries[id]
    if retry and retry.unit==unit and stamp<retry.until_time then side=retry.face
    else s.retries[id]=nil;retry=nil end
    local front_edge=clean_face(s,side,origin,stamp)
    local face=s.faces[side]
    own=s.claims[id]
    if own then
        own.updated=stamp
        local transferred=transfer_to_near_vacancy(s,unit,own,p,stamp)
        if transferred then return {point=transferred.point,claimed=true} end
        -- Exact coordinates alone do not authorize a body-blocked contact.
        -- Only successful settlement may renew a stationary attack lease.
        own.arrived=own.settled and M.arrived(wall,unit,own.point,true) or false
        local progressed=own.arrived or interrupted(unit) or moved(p,own.progress_position)
        if progressed then own.progress_position=p;own.progress_time=stamp end
        -- Refresh navigation only on the bounded cache cadence, not every tick.
        local clear=true
        if stamp-own.nav_checked>=POSITION_CACHE_SECONDS then
            own.nav_checked=stamp;clear=clear and clear_point(wall,unit,own.point)
        end
        if clear and (interrupted(unit) or own.arrived or stamp-own.progress_time<STALL_SECONDS) then
            return {point=own.point,claimed=true}
        end
        -- A stalled reservation must not renew forever. Keep this unit's face,
        -- and give this unit another point or let a waiting neighbour take over.
        retire_claim(s,id,true)
        front_edge=clean_face(s,side,origin,stamp)
        retry={unit=unit,key=own.key,face=side,until_time=stamp+STALL_SECONDS}
        s.retries[id]=retry
    end
    observe_waiter(s,unit,side,stamp)
    -- A sealed gate owns only its approach end. On open ground, a full face
    -- may route to another free face instead of holding every later arrival.
    -- Once all sixteen contacts are held, the normal waiting path remains
    -- constant work and does not search any routes or scan the waiting crowd.
    if face.count>=COUNT and (preferred_face or queue_side or retry or s.count>=COUNT*4) then
        local nearest=nearest_claim(face,p)
        return waiting_plan(wall,unit,p,side,front_edge,waiting_point(wall,unit,nearest,front_edge))
    end
    local failed=s.failed[id]
    if failed and failed.unit==unit and failed.face==side
        and failed.revision==s.revision and failed.front_edge==front_edge
        and stamp<failed.until_time and not moved(p,failed.position) then
        return waiting_plan(wall,unit,p,side,front_edge,queued_point or failed.point)
    end
    s.failed[id]=nil
    path_budget(s,stamp)
    if s.paths_left<=0 then
        local source=nearest_claim(face,p)
        return waiting_plan(wall,unit,p,side,front_edge,
            source and waiting_point(wall,unit,source,front_edge))
    end
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
    -- Do not steal an active route. It retains real collision: a blocked
    -- owner waits for a real path or relinquishes its stalled reservation.
    local function choose(list)
        local best,best_path,path_tested,deferred
        local nominees={}
        for _,c in ipairs(list) do
            if best_path and c.distance>best_path then break end
            local target_face=s.faces[c.face]
            if target_face.count<COUNT and not target_face.slots[c.lane] and not c.skip
                and nominees[c.face]==nil then
                nominees[c.face]=replacement_owner(s,c.face,stamp) or false
            end
            local priority=nominees[c.face]
            -- Each face has four exclusive keys, including units still on
            -- their way around a corner. No fifth owner can use that face.
            local separated=true
            for _,other in pairs(s.claims) do
                if distance(c.point,other.point)<hull(unit)+hull(other.unit)+4 then
                    separated=false;break
                end
            end
            if (not priority or priority==unit) and separated and target_face.count<COUNT
                and not target_face.slots[c.lane] and not c.skip then
                -- A burst of arrivals or unreachable routes must not turn
                -- into a path search for every monster on the same frame.
                if s.paths_left<=0 then deferred=true;break end
                s.paths_left=s.paths_left-1
                path_tested=true
                local path=GridNav:FindPathLength(p,c.point)
                if path and path>=0 and path<=MAX_NATIVE_ROUTE and (not best_path or path<best_path) then
                    best,best_path=c,path;c.native_path_length=path
                end
            end
        end
        return best,path_tested,deferred
    end
    local best,path_tested,deferred=choose(candidates)
    -- Keep a valid in-flight claim stable, but allow new open-ground arrivals
    -- to go around the square to any genuinely reachable vacant face.
    if not best and not deferred and not retry and not preferred_face then
        local others=candidates_for(true)
        for other_side=1,4 do
            if other_side~=side then clean_face(s,other_side,origin,stamp) end
        end
        local tested
        best,tested,deferred=choose(others);path_tested=path_tested or tested
    end
    if not best then
        local source=nearest_claim(face,p) or (nearest and nearest.source)
        local wait_point=source and waiting_point(wall,unit,source,front_edge)
        if path_tested and not deferred then
            s.failed[id]={unit=unit,face=side,revision=s.revision,front_edge=front_edge,
                position=Vector(p.x,p.y,p.z),point=wait_point,
                until_time=stamp+POSITION_CACHE_SECONDS}
        end
        return waiting_plan(wall,unit,p,side,front_edge,wait_point)
    end
    grant_claim(s,unit,best.source,p,stamp)
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
