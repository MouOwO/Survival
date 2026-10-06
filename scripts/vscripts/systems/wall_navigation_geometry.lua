-- Native units retain circular hulls. Navigation seals the square wall and,
-- only in a narrow terrain corridor, the short seams up to the static banks.
local M = {}
local HALF, CELL = 128, 64

function M.seams(origin, terrain)
    local best
    for axis = 1, 2 do
        local gaps, enclosed = {}, true
        for _, side in ipairs({-1, 1}) do
            local boundary
            for _, normal in ipairs({-96, -32, 32, 96}) do
                local closed
                -- Front/middle/rear must see the same terrain bank. Do not
                -- close a T junction, a staggered opening or a wide meadow.
                for step = 0, 4 do
                    local lateral = side * (HALF + CELL * (step + .5))
                    local x = axis == 1 and normal or lateral
                    local y = axis == 1 and lateral or normal
                    if not terrain(Vector(origin.x+x, origin.y+y, origin.z)) then
                        closed = step; break
                    end
                end
                if closed == nil or (boundary ~= nil and closed ~= boundary) then
                    enclosed = false; break
                end
                boundary = closed
            end
            if not enclosed then break end
            -- Height cliffs can begin between navigation-cell centers. Verify
            -- the actual tile edge joins the bank, including zero-width samples.
            local reach=HALF+math.ceil(boundary/2)*128
            while true do
                local joined=true
                for _, normal in ipairs({-96, -32, 32, 96}) do
                    local lateral=side*(reach+1)
                    local x=axis == 1 and normal or lateral
                    local y=axis == 1 and lateral or normal
                    if terrain(Vector(origin.x+x,origin.y+y,origin.z)) then joined=false;break end
                end
                if joined then break end
                if reach>=384 then enclosed=false;break end
                reach=reach+128
            end
            if not enclosed then break end
            boundary=(reach-HALF)/CELL
            gaps[side] = boundary
        end
        if enclosed then
            local width = gaps[-1]+gaps[1]
            if not best or width < best.width then
                best = {axis=axis, gaps=gaps, width=width}
            end
        end
    end
    local offsets = {}
    local bounds = {min_x=-HALF, max_x=HALF, min_y=-HALF, max_y=HALF}
    if best then
        for _, side in ipairs({-1, 1}) do
            if best.gaps[side] > 0 then
                local reach = HALF
                for tile = 1, math.ceil(best.gaps[side]/2) do
                    local lateral = side*(HALF+(tile-.5)*128)
                    for _, normal in ipairs({-64, 64}) do
                        offsets[#offsets+1] = {
                            x=best.axis == 1 and normal or lateral,
                            y=best.axis == 1 and lateral or normal,
                        }
                    end
                    reach = HALF+tile*128
                end
                local name = (side < 0 and "min_" or "max_")
                    .. (best.axis == 1 and "y" or "x")
                bounds[name] = side*reach
            end
        end
    end
    return offsets, bounds, best ~= nil
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
