-- Native units retain circular hulls. A square wall may close only the two
-- narrow bank seams of a centered doorway; real offset side routes stay open.
local M = {}
local HALF, MAX_SEAM = 128, 384
local MAX_OFFSET, MAX_OPENING = 128, 768

-- A displaced wall can contain one bank inside its footprint. Searching only
-- outside +/-128 loses that bank and centers the contacts on the wall instead
-- of on the real opening. Inspect the entire bounded cross-section once at
-- construction; no monster performs these terrain queries.
local function opening(origin, axis, normal, terrain, offset_limit)
    local limit = HALF + MAX_SEAM
    local function clear(lateral)
        return terrain(Vector(origin.x+(axis==1 and normal or lateral),
            origin.y+(axis==1 and lateral or normal),origin.z))
    end
    local previous, was_clear = -limit-1, clear(-limit-1)
    local low,high,start,invalid,selected
    local intervals={}
    local function interval(a,b)
        local segment={low=a or -math.huge,high=b or math.huge}
        intervals[#intervals+1]=segment
        -- A bank has finite thickness. Another floor beyond it is unrelated
        -- to the doorway, even if the bounded scan starts/ends on that floor.
        -- Only the continuous opening intersecting the wall footprint owns
        -- this cross-section; an actual unbounded side branch still rejects it.
        if math.max(a or -math.huge,-HALF)>=math.min(b or math.huge,HALF) then return end
        if low or not a or not b or b-a<192 or b-a>MAX_OPENING
            or math.abs((a+b)*.5)>(offset_limit or MAX_OFFSET) or a < -limit or b > limit then
            invalid=true;return
        end
        low,high,selected=a,b,segment
    end
    local lateral = previous
    while lateral < limit+1 do
        lateral = math.min(limit+1,lateral+16)
        local is_clear = clear(lateral)
        if is_clear ~= was_clear then
            local a,b = previous,lateral
            -- Native navigation uses cells, while a height bank may lie
            -- between them. Resolve both to sub-unit precision before using
            -- the same bank for obstruction reach and the contact center.
            for _=1,8 do
                local middle=(a+b)*.5
                if clear(middle)==was_clear then a=middle else b=middle end
            end
            local bank=math.floor((a+b)*.5+.5)
            if is_clear then start=bank else interval(start,bank);start=nil end
        end
        previous,was_clear=lateral,is_clear
    end
    if was_clear then interval(start,nil) end
    if invalid or not low or not high then return nil end
    -- Keep cached doorway recognition conservative when a thin bank separates
    -- another floor. This snapshot may describe an approach axis, but never
    -- grants permission to extend physical navigation over either floor.
    local low_extent=-HALF-math.ceil(math.max(0,-low-HALF)/128)*128
    local high_extent=HALF+math.ceil(math.max(0,high-HALF)/128)*128
    for _,segment in ipairs(intervals) do
        if segment~=selected and math.max(segment.low,low_extent)<math.min(segment.high,high_extent) then
            return nil
        end
    end
    return low,high
end

function M.seams(origin, terrain)
    local best
    for axis = 1, 2 do
        local low,high,enclosed
        enclosed=true
        for _,normal in ipairs({-96,-32,32,96}) do
            local a,b=opening(origin,axis,normal,terrain)
            -- Four real cross-sections must agree. A turn, a side branch or a
            -- staggered bank cannot become an invented solid doorway.
            if not a or (low and (math.abs(low-a)>1 or math.abs(high-b)>1)) then
                enclosed=false;break
            end
            low,high=a,b
        end
        if enclosed then
            local gaps={[-1]=math.max(0,-low-HALF),[1]=math.max(0,high-HALF)}
            local width=gaps[-1]+gaps[1]
            if not best or width < best.width then
                best={axis=axis,gaps=gaps,width=width,low=low,high=high}
            end
        end
    end
    if not best and type(GetGroundHeight)=="function" then
        -- Legal court placement sits just beyond the top stair cell: the
        -- wall's rear half is open lawn, while the bank already meets its
        -- front edge. A flat T junction provides no descending stair proof.
        -- Inspect only four bounded sections and keep the physical wall depth.
        for axis=1,2 do for _,sign in ipairs({-1,1}) do for _,lead in ipairs({0,64}) do
            local low,high,previous_height,near_height,proven
            proven=true
            for _,distance in ipairs({160,224,288,352}) do
                local normal=distance+lead
                local sample=Vector(origin.x+(axis==1 and sign*normal or 0),
                    origin.y+(axis==2 and sign*normal or 0),origin.z)
                local height=GetGroundHeight(sample,nil)
                if type(height)~="number" or height~=height
                    or (previous_height and previous_height-height<8) then proven=false;break end
                if not near_height then
                    near_height=height
                    if origin.z-height<16 or origin.z-height>128 then proven=false;break end
                end
                -- Lower stairs may be more than128 below the court. Compare
                -- their banks with the local stair height, not the wall top.
                local a,b=opening(Vector(origin.x,origin.y,height),axis,sign*normal,terrain,MAX_OFFSET+32)
                if not a or (low and (math.abs(a-low)>1 or math.abs(b-high)>1)) then
                    proven=false;break
                end
                low,high,previous_height=a,b,height
            end
            if proven then
                -- A one-cell normal displacement can leave a64 landing ahead
                -- of the wall. Verify the same banks there, without extending
                -- physical blockers forward. A second-cell gap is rejected.
                local normal=sign*(HALF+1+lead)
                local sample=Vector(origin.x+(axis==1 and normal or 0),
                    origin.y+(axis==2 and normal or 0),origin.z)
                local height=GetGroundHeight(sample,nil)
                local a,b=opening(Vector(origin.x,origin.y,height),axis,normal,terrain,MAX_OFFSET+32)
                if not a or math.abs(a-low)>1 or math.abs(b-high)>1 then proven=false end
            end
            if proven then
                local lateral_origin=axis==1 and origin.y or origin.x
                local center=math.floor((lateral_origin+(low+high)*.5)/64+.5)*64
                if math.abs(center-lateral_origin)<=MAX_OFFSET then
                    local gaps={[-1]=math.max(0,-low-HALF),[1]=math.max(0,high-HALF)}
                    local width=gaps[-1]+gaps[1]
                    if not best or width<best.width then
                        best={axis=axis,gaps=gaps,width=width,low=low,high=high,
                            stair=true,stair_sign=sign,stair_lead=lead,center=center}
                    end
                end
            end
        end end end
    end
    local offsets = {}
    local bounds = {min_x=-HALF, max_x=HALF, min_y=-HALF, max_y=HALF}
    -- The native384 stair has a64 seam on either side of the256 wall. Close
    -- only these bounded seams. A tangent shift makes one seam128 or wider;
    -- preserve that genuine side route rather than manufacturing a wide wall.
    local gate=best~=nil and best.gaps[-1]<=64 and best.gaps[1]<=64
    if gate then
        for _,side in ipairs({-1,1}) do
            if best.gaps[side]>0 then
                for _,normal in ipairs({-64,64}) do
                    offsets[#offsets+1]={x=best.axis==1 and normal or side*192,
                        y=best.axis==1 and side*192 or normal}
                end
                bounds[(side<0 and "min_" or "max_")..(best.axis==1 and "y" or "x")]=side*256
            end
        end
    end
    local base=best and (best.axis==1 and origin.y or origin.x)
    local layout=best and {gate=gate,axis=best.axis,bounds=bounds,
        center=best.center or base+(best.low+best.high)*.5,min=base+best.low,max=base+best.high,
        stair_mouth=best.stair or false,stair_sign=best.stair_sign,stair_lead=best.stair_lead,
        lateral_min=best.low,lateral_max=best.high} or nil
    return offsets,bounds,gate,best and best.axis or nil,layout
end

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

local function crossing(bounds, current, previous)
    local entry, side, exit = 0, nil, 1
    for _, axis in ipairs({"x", "y"}) do
        local start, delta = previous[axis], current[axis]-previous[axis]
        local low, high = bounds["min_"..axis], bounds["max_"..axis]
        if delta == 0 then
            if start <= low or start >= high then return nil end
        else
            local a, b = (low-start)/delta, (high-start)/delta
            local face = (delta > 0 and "min_" or "max_")..axis
            if a > b then a,b = b,a end
            if a >= entry then entry, side = a, face end
            exit = math.min(exit, b)
        end
    end
    return side and entry < exit and entry >= 0 and entry <= 1 and side or nil
end

local function swept_hull(bounds, current, previous, radius)
    if crossing(bounds,current,previous) then return true end
    -- Four straight face strips plus four round corners are the exact
    -- rectangle expanded by a circular unit hull, not a larger square.
    for _, axis in ipairs({"x", "y"}) do
        for _, sign in ipairs({-1, 1}) do
            local strip = {min_x=bounds.min_x,max_x=bounds.max_x,
                min_y=bounds.min_y,max_y=bounds.max_y}
            if sign < 0 then strip["max_"..axis]=strip["min_"..axis];strip["min_"..axis]=strip["min_"..axis]-radius
            else strip["min_"..axis]=strip["max_"..axis];strip["max_"..axis]=strip["max_"..axis]+radius end
            if crossing(strip,current,previous) then return true end
        end
    end
    local vx,vy=current.x-previous.x,current.y-previous.y
    local length=vx*vx+vy*vy
    if length == 0 then return false end
    for _, x in ipairs({bounds.min_x,bounds.max_x}) do
        for _, y in ipairs({bounds.min_y,bounds.max_y}) do
            local t=clamp(((x-previous.x)*vx+(y-previous.y)*vy)/length,0,1)
            local dx,dy=previous.x+t*vx-x,previous.y+t*vy-y
            if dx*dx+dy*dy < radius*radius then return true end
        end
    end
    return false
end

-- Return a side only on penetration or an observed crossing of the rectangle.
-- A legal move around a corner remains untouched; no distance square roots.
function M.outside(bounds, current, previous, radius, check_crossing)
    radius = math.max(1, tonumber(radius) or 1)
    if previous then
        -- Almost every AI observation is wholly outside the same face.
        if (current.x<=bounds.min_x-radius and previous.x<=bounds.min_x-radius)
            or (current.x>=bounds.max_x+radius and previous.x>=bounds.max_x+radius)
            or (current.y<=bounds.min_y-radius and previous.y<=bounds.min_y-radius)
            or (current.y>=bounds.max_y+radius and previous.y>=bounds.max_y+radius) then return nil end
    end
    local nearest_x = clamp(current.x, bounds.min_x, bounds.max_x)
    local nearest_y = clamp(current.y, bounds.min_y, bounds.max_y)
    local dx, dy = current.x-nearest_x, current.y-nearest_y
    local inside = dx*dx+dy*dy < radius*radius
    local entry_side = previous and check_crossing ~= false and crossing(bounds,current,previous)
    local crossed = previous and check_crossing ~= false and swept_hull(bounds,current,previous,radius)
    if not inside and not crossed then return nil end
    local side = entry_side
    if not side then
        -- Prefer the previous exterior side so unit pressure cannot eject a
        -- monster through the rear of the gate. Initial overlap uses nearest.
        local source = previous or current
        local distances = {
            {"min_x", source.x-bounds.min_x}, {"max_x", bounds.max_x-source.x},
            {"min_y", source.y-bounds.min_y}, {"max_y", bounds.max_y-source.y},
        }
        local minimum
        for _, candidate in ipairs(distances) do
            if not minimum or candidate[2] < minimum then
                side, minimum = candidate[1], candidate[2]
            end
        end
    end
    local result = {x=current.x, y=current.y, z=current.z}
    if side == "min_x" then result.x=bounds.min_x-radius-2
    elseif side == "max_x" then result.x=bounds.max_x+radius+2
    elseif side == "min_y" then result.y=bounds.min_y-radius-2
    else result.y=bounds.max_y+radius+2 end
    return result
end

return M
