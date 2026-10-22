-- Rear goals are independent of the four attack contacts. Every move still
-- uses native terrain/unit collision; this module only reserves destinations.
local M = {}
local advance
local HALF, REAR_WIDTH, REAR_DEPTH = 128, 600, 900
local PATH_STEP, PATH_BUDGET, FAILURE_SECONDS = 0.5, 8, 2

local function alive(unit)
    return unit and (not unit.IsNull or not unit:IsNull())
        and (not unit.IsAlive or unit:IsAlive())
end
local function size(unit)
    local hull = math.max(1, tonumber(unit:GetHullRadius()) or 32)
    local padding = math.max(hull, tonumber(unit.GetPaddedCollisionRadius
        and unit:GetPaddedCollisionRadius()) or hull + 10)
    return hull, padding
end
local function normal(origin, point, side)
    local value = side <= 2 and point.x - origin.x or point.y - origin.y
    return (side == 1 or side == 3) and -value or value
end
local function lateral(origin, point, side)
    return side <= 2 and point.y - origin.y or point.x - origin.x
end
local function distance(a, b)
    return math.sqrt((a.x-b.x)^2 + (a.y-b.y)^2)
end
local function world(queue, side, depth, along)
    local origin = queue.origin
    local sign = (side == 1 or side == 3) and -1 or 1
    local point = side <= 2 and Vector(origin.x+sign*depth, origin.y+along, origin.z)
        or Vector(origin.x+along, origin.y+sign*depth, origin.z)
    point.z = GetGroundHeight and GetGroundHeight(point, nil) or origin.z
    return point
end
local function clear(point, hull)
    local radius = math.max(0, hull-1)
    for _, offset in ipairs({{0,0},{radius,0},{-radius,0},{0,radius},{0,-radius}}) do
        local sample = Vector(point.x+offset[1], point.y+offset[2], point.z)
        if not GridNav:IsTraversable(sample) or GridNav:IsBlocked(sample) then return false end
    end
    return true
end
local function unchanged(queue, wall, state)
    if not queue or queue.wall ~= wall or not alive(wall) then return false end
    local point = wall:GetAbsOrigin()
    return point.x == queue.origin.x and point.y == queue.origin.y and point.z == queue.origin.z
        and queue.wall_revision == (tonumber(wall.survival_wall_relocation_revision) or 0)
        and queue.geometry_revision == (tonumber(state.rear_queue_geometry_revision) or 0)
end
local function get_queue(state, wall)
    local queue = state.rear_queue
    if unchanged(queue, wall, state) then return queue end
    local origin = wall:GetAbsOrigin()
    queue = {wall=wall, state=state, origin=Vector(origin.x,origin.y,origin.z),
        wall_revision=tonumber(wall.survival_wall_relocation_revision) or 0,
        geometry_revision=tonumber(state.rear_queue_geometry_revision) or 0,
        records={}, pending={}, grids={}, faces={}, next_order=0,
        sweep_after=0, failures={}, paths_left=0, path_step=-1}
    state.rear_queue = queue
    return queue
end
local function face_for(queue, side)
    local face = queue.faces[side]
    if not face then face={gaps={}}; queue.faces[side]=face end
    return face
end
local function separated(queue, point, padding, except)
    for id, record in pairs(queue.records) do
        if id ~= except and alive(record.unit)
            and distance(point, record.point) < padding+record.padding+4-0.01 then return false end
    end
    for _, face in pairs(queue.faces) do
        local promotion = face.promotion
        if promotion and promotion.id ~= except
            and distance(point,promotion.point) < padding+promotion.padding+4-0.01 then return false end
    end
    return true
end
local function schedule(queue, side)
    local face = face_for(queue,side)
    if face.promotion then return end
    while #face.gaps > 0 do
        local gap = table.remove(face.gaps,1)
        local selected
        for id, record in pairs(queue.records) do
            if record.side == side and alive(record.unit) and record.padding <= gap.padding
                and normal(queue.origin,record.point,side) > normal(queue.origin,gap.point,side)+1
                and (not selected or record.order < selected.order)
                and separated(queue,gap.point,record.padding,id) then
                selected=record
            end
        end
        if selected then
            face.promotion={id=selected.id, point=gap.point, padding=selected.padding}
            return
        end
    end
end
local function remove(queue, id)
    local record = queue.records[id]
    queue.records[id],queue.pending[id],queue.failures[id]=nil,nil,nil
    if not record then return end
    local face=face_for(queue,record.side)
    if face.promotion and face.promotion.id==id then face.promotion=nil end
    face.gaps[#face.gaps+1]={point=record.point,padding=record.padding}
    schedule(queue,record.side)
end
function M.release(state, id)
    if state and state.rear_queue then remove(state.rear_queue,tonumber(id) or id) end
end
function M.reset(state)
    if state then state.rear_queue=nil end
end
function M.peek(state, unit)
    local queue=state and state.rear_queue
    if not queue then return nil end
    if not unchanged(queue,queue.wall,state) then M.reset(state);return nil end
    local record=unit and queue.records[unit:entindex()]
    if record and record.unit==unit then
        if alive(unit) then
            -- Distant rear actors may only be observed through peek. The one
            -- nominated waiter must still advance toward a released near gap.
            local stamp=GameRules and GameRules:GetGameTime() or queue.last_stamp or 0
            advance(queue,record,stamp)
            return record.point,record.side
        end
        remove(queue,record.id)
    end
end
local function sweep(queue, stamp)
    if stamp < queue.sweep_after then return end
    queue.sweep_after=stamp+2
    local dead={}
    for id, record in pairs(queue.records) do if not alive(record.unit) then dead[#dead+1]=id end end
    for _, id in ipairs(dead) do remove(queue,id) end
    for id, pending in pairs(queue.pending) do
        if not alive(pending.unit) or stamp-pending.updated > 4 then
            queue.pending[id],queue.failures[id]=nil,nil
        end
    end
end
local function path(queue, unit, point, stamp)
    local step=math.floor(stamp/PATH_STEP)
    if step ~= queue.path_step then queue.path_step,queue.paths_left=step,PATH_BUDGET end
    local state=queue.state
    if state.path_step~=step then
        state.path_step,state.paths_left=step,state.path_limit or 16
    end
    if queue.paths_left <= 0 or state.paths_left<=0 then return nil end
    local id, origin=unit:entindex(),unit:GetAbsOrigin()
    local failures=queue.failures[id]
    if not failures then failures={};queue.failures[id]=failures end
    local key=string.format("%.3f:%.3f:%.3f",point.x,point.y,point.z)
    local failed=failures[key]
    if failed and stamp<failed.until_time and distance(origin,failed.origin)<32 then return false end
    queue.paths_left=queue.paths_left-1
    state.paths_left=state.paths_left-1
    local length=GridNav:FindPathLength(origin,point)
    -- Native navigation proves stairs/detours. Reject a long route around the
    -- wall or a disconnected floor even when its destination is walkable.
    if type(length)=="number" and length>=0 and length<=math.max(1024,distance(origin,point)*3+256) then
        failures[key]=nil
        return true
    end
    failures[key]={origin=Vector(origin.x,origin.y,origin.z),until_time=stamp+FAILURE_SECONDS}
    return false
end
local function grid(queue, side, hull, padding, edge)
    local key=string.format("%d:%.4f:%.4f:%.4f",side,hull,padding,edge)
    if queue.grids[key] then return queue.grids[key] end
    local result, pitch={},2*padding+4
    local first=edge+padding+8
    for row=0,math.floor(REAR_DEPTH/pitch) do
        local depth=first+row*pitch
        -- Offer both grid phases. Four native 88-spaced columns at
        -- +/-132,+/-44 fit a 384 corridor; forcing its rear onto +/-88,0
        -- would stagger solid bodies and obstruct the next front replacement.
        -- Candidate density never relaxes the actual padded separation check.
        local lateral_pitch=pitch*0.5
        for column=-math.floor(REAR_WIDTH/lateral_pitch),math.floor(REAR_WIDTH/lateral_pitch) do
            local point=world(queue,side,depth,column*lateral_pitch)
            if depth>=HALF+hull+8 and clear(point,hull) then
                result[#result+1]={point=point,depth=depth,column=column}
            end
        end
    end
    queue.grids[key]=result
    return result
end

local function minimum_goal(queue, unit, side, edge, padding)
    local minimum=edge+padding+8
    -- A native retreat MOVE can finish 32 short, on the front side of its
    -- destination. Only an actor already inside the safe rear envelope needs
    -- that extra margin. Once assigned, its record keeps the same goal.
    if normal(queue.origin,unit:GetAbsOrigin(),side)<minimum then minimum=minimum+32 end
    return minimum
end

advance=function(queue, record, stamp)
    local face=face_for(queue,record.side)
    local promotion=face.promotion
    if not promotion or promotion.id~=record.id then return end
    local edge=math.ceil(math.max(face.front_edge or 0,184+record.padding)/16)*16
    if normal(queue.origin,promotion.point,record.side)
            <minimum_goal(queue,record.unit,record.side,edge,record.padding)-0.01
        or not separated(queue,promotion.point,record.padding,record.id) then
        face.promotion=nil;schedule(queue,record.side)
        return
    end
    local reachable=path(queue,record.unit,promotion.point,stamp)
    if reachable then
        local previous=record.point
        record.point=promotion.point;face.promotion=nil
        queue.failures[record.id]=nil
        face.gaps[#face.gaps+1]={point=previous,padding=record.padding}
        schedule(queue,record.side)
    end
end

function M.reserve(state, wall, unit, side, front_edge, stamp)
    side=tonumber(side)
    if not state or not alive(wall) or not alive(unit)
        or not side or side~=math.floor(side) or side<1 or side>4 then return nil end
    stamp=tonumber(stamp) or (GameRules and GameRules:GetGameTime()) or 0
    local queue=get_queue(state,wall)
    queue.last_stamp=stamp
    sweep(queue,stamp)
    local id=unit:entindex()
    local hull,padding=size(unit)
    -- Native acceptance can shift a settled front by fractions. Round only
    -- outward so its safe envelope shares a bounded set of rear-grid caches.
    -- The supplied front edge already includes its actual largest body.
    -- A historical rear boss must not leave a permanent empty band after it
    -- dies or advances. Mixed rear bodies are separated by their own radii.
    local edge=math.ceil(math.max(tonumber(front_edge) or 0,184+padding)/16)*16
    face_for(queue,side).front_edge=tonumber(front_edge) or 0
    local minimum=minimum_goal(queue,unit,side,edge,padding)
    local record=queue.records[id]
    if record and (record.unit~=unit or record.side~=side or record.hull~=hull
        or record.padding~=padding or normal(queue.origin,record.point,side)<minimum-0.01) then
        remove(queue,id);record=nil
    end
    if record then
        advance(queue,record,stamp)
        return record.point
    end
    local pending=queue.pending[id]
    local geometry=string.format("%d:%.4f:%.4f:%.4f",side,hull,padding,edge)
    if not pending or pending.unit~=unit or pending.geometry~=geometry then
        queue.failures[id]=nil
        queue.next_order=queue.next_order+1
        local candidates={}
        for _, candidate in ipairs(grid(queue,side,hull,padding,edge)) do candidates[#candidates+1]=candidate end
        local along=lateral(queue.origin,unit:GetAbsOrigin(),side)
        table.sort(candidates,function(a,b)
            if a.depth~=b.depth then return a.depth<b.depth end
            local da,db=math.abs(lateral(queue.origin,a.point,side)-along),math.abs(lateral(queue.origin,b.point,side)-along)
            return da==db and a.column<b.column or da<db
        end)
        pending={unit=unit,geometry=geometry,order=queue.next_order,candidates=candidates,index=1}
        queue.pending[id]=pending
    end
    pending.updated=stamp
    local checked=0
    while checked<#pending.candidates do
        local candidate=pending.candidates[pending.index]
        if not candidate then return nil end
        if candidate.depth>=minimum-0.01 and separated(queue,candidate.point,padding,id) then
            local reachable=path(queue,unit,candidate.point,stamp)
            if reachable==nil then return nil end
            if reachable then
                record={id=id,unit=unit,side=side,hull=hull,padding=padding,
                    point=candidate.point,order=pending.order}
                queue.records[id],queue.pending[id]=record,nil
                queue.failures[id]=nil
                return record.point
            end
        end
        pending.index=pending.index % #pending.candidates+1
        checked=checked+1
    end
end
return M
