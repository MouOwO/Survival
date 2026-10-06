local wall_navigation = require("systems/wall_navigation_service")
local event_bus = require("core/event_bus")
local events = require("core/events")
local config = require("config/grid_placement_config")
local region_service = require("systems/forbidden_region_service")

local M = {}
local occupied = {}
local occupied_entities = {}
local function set_occupant(column, y, index)
    local old = column[y]
    if old == index then return end
    if old then
        occupied_entities[old] = (occupied_entities[old] or 1) - 1
        if occupied_entities[old] <= 0 then occupied_entities[old] = nil end
    end
    column[y] = index
    if index then occupied_entities[index] = (occupied_entities[index] or 0) + 1 end
end
local marker_regions = {}
local static_terrain = {}
local reconcile_occupied

local function number(value, fallback)
    local result = tonumber(value)
    if result == nil then return fallback end
    return result
end

local geometry = require("core/building_grid_geometry")
local normalized_footprint = geometry.footprint

local function cell_center(grid_x, grid_y, z)
    local size = number(config.cell_size, 128)
    return Vector((grid_x + 0.5) * size, (grid_y + 0.5) * size, z or 0)
end

local function ground_height(position)
    local height = number(position.z, 0)
    -- GetGroundHeight already returns the terrain height. Only use the more
    -- expensive position query as a fallback, not a second query per sample.
    local ok, value = pcall(function() return GetGroundHeight(position, nil) end)
    if ok and type(value) == "number" then return value end
    pcall(function()
        local ground = GetGroundPosition(position, nil)
        if ground then height = number(ground.z, height) end
    end)
    return height
end

local function within_bounds(center)
    local bounds = config.build_bounds or {}
    local half = number(config.cell_size, 128) * 0.5
    return center.x - half >= number(bounds.min_x, -999999)
        and center.x + half <= number(bounds.max_x, 999999)
        and center.y - half >= number(bounds.min_y, -999999)
        and center.y + half <= number(bounds.max_y, 999999)
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function in_region(center, region)
    local half = number(config.cell_size, 128) * 0.5
    if region.shape == "circle" then
        local circle_x = number(region.x, 0)
        local circle_y = number(region.y, 0)
        local nearest_x = clamp(circle_x, center.x - half, center.x + half)
        local nearest_y = clamp(circle_y, center.y - half, center.y + half)
        local dx = nearest_x - circle_x
        local dy = nearest_y - circle_y
        local radius = number(region.radius, 0)
        return dx * dx + dy * dy <= radius * radius
    end
    return center.x + half >= number(region.min_x, 0)
        and center.x - half <= number(region.max_x, 0)
        and center.y + half >= number(region.min_y, 0)
        and center.y - half <= number(region.max_y, 0)
end

local function forbidden_marker(center)
    for _, region in ipairs(marker_regions) do
        if in_region(center, {
            shape = "circle",
            x = region.x,
            y = region.y,
            radius = region.radius,
        }) then
            return true, "forbidden_marker:" .. tostring(region.id)
        end
    end
    return false, nil
end

local function terrain_clear(center)
    local size = number(config.cell_size, 128)
    local inset = size * 0.38
    local samples = {
        center,
        center + Vector(inset, inset, 0),
        center + Vector(inset, -inset, 0),
        center + Vector(-inset, inset, 0),
        center + Vector(-inset, -inset, 0),
    }
    local lowest, highest = nil, nil
    for _, sample in ipairs(samples) do
        local traversable_ok, traversable = pcall(function()
            return GridNav:IsTraversable(sample)
        end)
        local blocked_ok, blocked = pcall(function()
            return GridNav:IsBlocked(sample)
        end)
        local original_traversable, original_blocked =
            wall_navigation.original_nav(sample)
        if original_traversable ~= nil then
            traversable_ok, traversable = true, original_traversable
            blocked_ok, blocked = true, original_blocked
        end
        if not traversable_ok or traversable ~= true
            or not blocked_ok or blocked ~= false then return false, "terrain_blocked" end
        local height = ground_height(sample)
        local build_height = number(config.build_ground_height, nil)
        if build_height and math.abs(height - build_height)
            > number(config.build_ground_height_tolerance, 0) then
            return false, "terrain_not_build_level"
        end
        lowest = lowest and math.min(lowest, height) or height
        highest = highest and math.max(highest, height) or height
    end
    if highest - lowest > number(config.max_height_delta, 48) then
        return false, "terrain_too_steep"
    end
    return true, nil
end

local function has_tree(center)
    local found = false
    local radius = number(config.cell_size, 128)
        * number(config.tree_block_radius_scale, 0.42)
    pcall(function() found = GridNav:IsNearbyTree(center, radius, true) end)
    return found
end

local function unit_hull_radius(unit)
    local hull = number(unit and unit.survival_hull_radius, nil)
    if hull == nil and unit and unit.GetHullRadius then
        local ok, value = pcall(unit.GetHullRadius, unit)
        if ok then hull = number(value, 0) end
    end
    return math.max(0, hull or 0)
end

local function unit_overlaps_cell(unit, center, half)
    local origin = unit:GetAbsOrigin()
    local nearest_x = clamp(origin.x, center.x - half, center.x + half)
    local nearest_y = clamp(origin.y, center.y - half, center.y + half)
    local dx = origin.x - nearest_x
    local dy = origin.y - nearest_y
    local hull = unit_hull_radius(unit)
    return dx * dx + dy * dy <= hull * hull
end

local function construction_building_is_logical_only(unit, payload)
    -- Registered buildings already block their exact footprint. Counting the
    -- circular hull again incorrectly reserves neighboring cells after completion.
    if occupied_entities[unit:entindex()] then return true end
    if unit.survival_wall_collision_barrier == true then return true end
    if unit.survival_is_building ~= true or not unit.HasModifier then return false end
    local ok, constructing = pcall(
        unit.HasModifier,
        unit,
        "modifier_building_under_construction"
    )
    if not ok or not constructing then return false end
    return not unit.GetTeamNumber
        or unit:GetTeamNumber() == number(payload.team, DOTA_TEAM_GOODGUYS)
end

local function unit_is_dead(unit)
    if not unit or not unit.IsAlive then return false end
    local ok, alive = pcall(unit.IsAlive, unit)
    return ok and alive == false
end

local function has_unit(center, payload)
    local size = number(config.cell_size, 128)
    local half = size * 0.5
    local radius = half * math.sqrt(2)
        + number(config.max_unit_hull_radius, size * 4)
    local units = payload.nearby_units
    if not units then
        units = FindUnitsInRadius(
            number(payload.team, DOTA_TEAM_GOODGUYS),
            center,
            nil,
            radius,
            DOTA_UNIT_TARGET_TEAM_BOTH,
            DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC
                + DOTA_UNIT_TARGET_BUILDING,
            DOTA_UNIT_TARGET_FLAG_INVULNERABLE,
            FIND_ANY_ORDER,
            false
        ) or {}
    end
    local ignored = number(payload.ignore_entindex, -1)
    local ignored_set = payload.ignore_entindexes or {}
    for _, unit in ipairs(units) do
        if unit and not unit:IsNull()
            and not unit_is_dead(unit)
            and unit:entindex() ~= ignored
            and ignored_set[unit:entindex()] ~= true
            and not unit.survival_is_grid_preview
            and not construction_building_is_logical_only(unit, payload)
            and unit_overlaps_cell(unit, center, half) then
            return true
        end
    end
    return false
end

local function nearby_units_for_footprint(payload, footprint, world_position)
    if payload.nearby_units then return payload.nearby_units end
    local size = number(config.cell_size, 128)
    local half_width = footprint.x * size * 0.5
    local half_height = footprint.y * size * 0.5
    local radius = math.sqrt(half_width * half_width + half_height * half_height)
        + number(config.max_unit_hull_radius, size * 4)
    return FindUnitsInRadius(
        number(payload.team, DOTA_TEAM_GOODGUYS),
        world_position,
        nil,
        radius,
        DOTA_UNIT_TARGET_TEAM_BOTH,
        DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC
            + DOTA_UNIT_TARGET_BUILDING,
        DOTA_UNIT_TARGET_FLAG_INVULNERABLE,
        FIND_ANY_ORDER,
        false
    ) or {}
end

local function occupied_by_other(grid_x, grid_y, ignored)
    local occupant = occupied[grid_x] and occupied[grid_x][grid_y] or nil
    return occupant ~= nil and occupant ~= ignored
end

local function cell_corners(grid_x, grid_y)
    local size = number(config.cell_size, 128)
    local points = {
        Vector(grid_x * size, grid_y * size, 0),
        Vector((grid_x + 1) * size, grid_y * size, 0),
        Vector((grid_x + 1) * size, (grid_y + 1) * size, 0),
        Vector(grid_x * size, (grid_y + 1) * size, 0),
    }
    local result = {}
    for _, point in ipairs(points) do
        table.insert(result, {
            x = point.x,
            y = point.y,
            z = ground_height(point),
        })
    end
    return result
end

local function validate_cell(grid_x, grid_y, payload)
    local center = cell_center(grid_x, grid_y, 0)
    center.z = ground_height(center)
    local result = {
        grid_x = grid_x,
        grid_y = grid_y,
        x = center.x,
        y = center.y,
        z = center.z,
        ok = true,
        reason = "",
    }
    if not payload.compact then result.corners = cell_corners(grid_x, grid_y) end
    if not within_bounds(center) then
        result.ok, result.reason = false, "build_out_of_bounds"
        return result
    end
    if payload.region_policy_error then
        result.ok, result.reason = false, payload.region_policy_error
        return result
    end
    local is_forbidden, forbidden_reason = forbidden_marker(center)
    if is_forbidden then
        result.ok, result.reason = false, forbidden_reason
        return result
    end
    local terrain_ok, terrain_error = terrain_clear(center)
    if not terrain_ok then
        result.ok, result.reason = false, terrain_error
        return result
    end
    if occupied_by_other(grid_x, grid_y, number(payload.ignore_entindex, -1)) then
        result.ok, result.reason = false, "build_cell_occupied"
        return result
    end
    if has_tree(center) then
        result.ok, result.reason = false, "tree_blocked"
        return result
    end
    if has_unit(center, payload) then
        result.ok, result.reason = false, "unit_blocked"
        return result
    end
    return result
end

local function can_place(payload)
    local position = payload and payload.position
    if not position then return { ok = false, error = "invalid_position", cells = {} } end
    reconcile_occupied()
    local footprint = normalized_footprint(payload.footprint)
    local anchor_x, world_x, grid_x = geometry.snap_axis(position.x, footprint.x)
    local anchor_y, world_y, grid_y = geometry.snap_axis(position.y, footprint.y)
    local world_position = Vector(world_x, world_y, 0)
    world_position.z = ground_height(world_position)
    local size = number(config.cell_size, 128)
    local policy_ok, policy_error = region_service.validate_building_footprint(
        grid_x * size,
        grid_y * size,
        (grid_x + footprint.x) * size,
        (grid_y + footprint.y) * size
    )
    if payload.policy_only == true then
        return {
            ok = policy_ok,
            error = policy_error,
            anchor_x = anchor_x,
            anchor_y = anchor_y,
            grid_x = grid_x,
            grid_y = grid_y,
            footprint = footprint,
            world_position = world_position,
            cells = {},
        }
    end
    local validation_payload = {}
    for key, value in pairs(payload) do validation_payload[key] = value end
    if not policy_ok then validation_payload.region_policy_error = policy_error end
    if policy_ok then
        validation_payload.nearby_units = nearby_units_for_footprint(
            payload,
            footprint,
            world_position
        )
    end
    local cells, all_valid, first_error = {}, true, nil
    for x = grid_x, grid_x + footprint.x - 1 do
        for y = grid_y, grid_y + footprint.y - 1 do
            local cell = validate_cell(x, y, validation_payload)
            table.insert(cells, cell)
            if not cell.ok then
                all_valid = false
                first_error = first_error or cell.reason
            end
        end
    end
    return {
        ok = all_valid,
        error = first_error,
        anchor_x = anchor_x,
        anchor_y = anchor_y,
        grid_x = grid_x,
        grid_y = grid_y,
        footprint = footprint,
        world_position = world_position,
        cells = cells,
    }
end

local function occupy(payload)
    local footprint = normalized_footprint(payload.footprint)
    for x = payload.grid_x, payload.grid_x + footprint.x - 1 do
        occupied[x] = occupied[x] or {}
        for y = payload.grid_y, payload.grid_y + footprint.y - 1 do
            set_occupant(occupied[x], y, payload.entindex)
        end
    end
    return true
end

local function release(payload)
    local footprint = normalized_footprint(payload.footprint)
    local entindex = number(payload.entindex, nil)
    for x = payload.grid_x, payload.grid_x + footprint.x - 1 do
        if occupied[x] then
            for y = payload.grid_y, payload.grid_y + footprint.y - 1 do
                if entindex == nil or occupied[x][y] == entindex then
                    set_occupant(occupied[x], y, nil)
                end
            end
        end
    end
    return true
end

local function clear_occupied_entindex(entindex)
    for x, column in pairs(occupied) do
        for y, occupant in pairs(column) do
            if occupant == entindex then
                set_occupant(column, y, nil)
            end
        end
        if next(column) == nil then occupied[x] = nil end
    end
end

local function occupied_entity_is_valid(unit)
    if not unit or unit:IsNull() then return false end
    if unit_is_dead(unit) then return false end
    return unit.survival_is_building == true
        or unit.survival_building_id ~= nil
        or unit.survival_tree_owner_id ~= nil
end

reconcile_occupied = function()
    if type(EntIndexToHScript) ~= "function" then return end
    local checked = {}
    for _, column in pairs(occupied) do
        for _, entindex in pairs(column) do
            if entindex ~= nil and not checked[entindex] then
                checked[entindex] = true
                -- Tree locations reserve named cells before their entity is
                -- spawned. These markers are not stale entity handles.
                local entity_index = tonumber(entindex)
                if entity_index then
                    local ok, unit = pcall(EntIndexToHScript, entity_index)
                    if not ok or not occupied_entity_is_valid(unit) then
                        clear_occupied_entindex(entindex)
                    end
                end
            end
        end
    end
end

local function load_marker_regions()
    marker_regions = {}
    for _, row in ipairs(config.forbidden_markers or {}) do
        local marker = nil
        pcall(function() marker = Entities:FindByName(nil, row.marker_name) end)
        if marker and not marker:IsNull() then
            local origin = marker:GetAbsOrigin()
            table.insert(marker_regions, {
                id = row.id or row.marker_name,
                x = origin.x,
                y = origin.y,
                radius = number(row.radius, 128),
            })
        else
            print("[GridPlacement] optional marker missing: " .. tostring(row.marker_name))
        end
    end
end

-- Read-only point occupancy for builder work positions. This does not bypass
-- building placement policy and never changes an occupied cell.
function M.is_position_occupied(position)
    if not position then return true end
    local size = number(config.cell_size, 128)
    local x, y = math.floor(position.x / size), math.floor(position.y / size)
    return occupied_by_other(x, y, nil)
end

-- Map terrain only. Run once at startup; never include units or occupancy.
-- This job is independent of mouse movement and preview cancellation.
function M.static_preview(payload)
    local b=config.build_bounds
    if not b then return "" end
    local size=number(config.cell_size,64)
    local x0,y0=math.floor(b.min_x/size),math.floor(b.min_y/size)
    local width,height=math.ceil(b.max_x/size)-x0,math.ceil(b.max_y/size)-y0
    if width<1 or height<1 or width*height>65536 then return "" end
    local states={}
    local clock=type(Time)=="function" and Time or os.clock
    local started,count=clock(),0
    for x=x0,x0+width-1 do for y=y0,y0+height-1 do
        local center=cell_center(x,y,0)
        local clear=within_bounds(center) and not forbidden_marker(center)
            and region_service.validate_building_footprint(x*size,y*size,(x+1)*size,(y+1)*size)
            and terrain_clear(center) and not has_tree(center)
        static_terrain[size..":"..x..":"..y]={clear=clear==true,static=true,time=0}
        states[#states+1]=clear and 2 or 1
        count=count+1
        if payload and payload.yield_after and (count>=payload.yield_after
            or (count>=8 and clock()-started>=number(payload.time_budget,0.002))) then
            coroutine.yield()
            started,count=clock(),0
        end
    end end
    local packed={}
    for i=1,#states,2 do packed[#packed+1]=string.format("%x",states[i]+4*(states[i+1] or 0)) end
    return table.concat({3,size,x0,y0,width,height,number(config.build_ground_height,0),table.concat(packed)},"|")
end

-- Read-only local terrain overlay. One unit query per refresh; reuse exactly
-- the same cell rules as placement. The footprint is still validated separately.
function M.preview_area(payload)
    local position = payload.position
    local size = number(config.cell_size, 64)
    local visual = config.preview_visual or {}
    local radius = math.min(1536, math.max(size, number(visual.radius, 1280)))
    local stride = math.max(1, math.floor(number(visual.area_stride, 1)))
    local display_size = size * stride
    -- A single construction plane avoids overlapping projected tiles on cliffs.
    -- Terrain validation below still uses each underlying cell's actual height.
    local display_height = math.floor(number(config.build_ground_height, ground_height(position)))
    reconcile_occupied()
    local clock = type(Time) == "function" and Time or os.clock
    local now = GameRules and GameRules:GetGameTime() or 0
    -- Cache only advisory terrain results. Occupancy and units are refreshed
    -- every scan; GRID_CAN_PLACE / actual construction never use this cache.
    local cache = payload.terrain_cache or {}
    local ttl = number(visual.area_terrain_cache_seconds, 2)
    local cache_count = 0
    for key, entry in pairs(cache) do
        -- Keep recently expired samples visible while refreshing them. Dropping
        -- all expired cells at once made the whole overlay blink every TTL.
        if now - entry.time >= ttl+2 or now < entry.time then cache[key] = nil
        else cache_count = cache_count + 1 end
    end
    if cache_count > 8192 then for key in pairs(cache) do cache[key] = nil end end
    local units = nearby_units_for_footprint(payload,
        { x = radius * 2 / size + 2, y = radius * 2 / size + 2 }, position)
    local unit_cells = {}
    local ignored = number(payload.ignore_entindex, -1)
    -- Rasterize each unit once instead of testing every unit against every
    -- tile (and repeatedly calling GetAbsOrigin/GetHullRadius across Lua/C++).
    for _, unit in ipairs(units) do
        if unit and not unit:IsNull() and not unit_is_dead(unit)
            and unit:entindex() ~= ignored
            and not (payload.ignore_entindexes or {})[unit:entindex()]
            and not unit.survival_is_grid_preview
            and not construction_building_is_logical_only(unit, payload) then
            local origin, hull = unit:GetAbsOrigin(), unit_hull_radius(unit)
            for x = math.max(math.floor((origin.x-hull)/size)-1,math.floor((position.x-radius)/size)),
                math.min(math.floor((origin.x+hull)/size),math.floor((position.x+radius)/size)) do
                for y = math.max(math.floor((origin.y-hull)/size)-1,math.floor((position.y-radius)/size)),
                    math.min(math.floor((origin.y+hull)/size),math.floor((position.y+radius)/size)) do
                    local dx = origin.x-clamp(origin.x,x*size,(x+1)*size)
                    local dy = origin.y-clamp(origin.y,y*size,(y+1)*size)
                    if dx*dx+dy*dy <= hull*hull then unit_cells[x..":"..y] = true end
                end
            end
        end
    end
    local min_x = math.floor((position.x - radius) / display_size)
    local max_x = math.floor((position.x + radius) / display_size)
    local min_y = math.floor((position.y - radius) / display_size)
    local max_y = math.floor((position.y + radius) / display_size)
    local height = max_y-min_y+1
    local states, work = {}, {}
    local function dynamic_clear(x, y)
        for sx = 0, stride-1 do
            for sy = 0, stride-1 do
                local gx, gy = x*stride+sx, y*stride+sy
                if occupied_by_other(gx,gy,ignored) or unit_cells[gx..":"..gy] then return false end
            end
        end
        return true
    end
    local function encode()
        local rows = {}
        for i = 1, #states, 2 do rows[#rows+1] = string.format("%x",states[i]+4*(states[i+1] or 0)) end
        return table.concat({3,display_size,min_x,min_y,max_x-min_x+1,height,
            display_height,table.concat(rows)},"|")
    end
    for x = min_x, max_x do
        for y = min_y, max_y do
            local index = #states+1
            states[index] = 0 -- unknown is absent, never assumed buildable
            local distance = ((x+0.5)*display_size-position.x)^2+((y+0.5)*display_size-position.y)^2
            if distance <= radius^2 then
                local key = display_size..":"..x..":"..y
                local entry = static_terrain[key] or cache[key]
                -- Outside the legal construction rectangle is permanently red;
                -- no terrain scan or TTL refresh is needed, including ocean.
                if not within_bounds(cell_center(x*stride,y*stride,0)) then
                    entry = {clear=false,static=true,time=0}
                end
                if entry then states[index] = entry.clear and dynamic_clear(x,y) and 2 or 1 end
                if not entry or (not entry.static and now-entry.time >= ttl) then
                    work[#work+1] = {x=x,y=y,index=index,key=key,distance=distance}
                end
            end
        end
    end
    table.sort(work,function(a,b) return a.distance < b.distance end)
    local batch_start, batch_count = clock(), 0
    for wi, tile in ipairs(work) do
        local x,y = tile.x,tile.y
        local clear = region_service.validate_building_footprint(
            x*display_size,y*display_size,(x+1)*display_size,(y+1)*display_size)
        for sx = 0,stride-1 do
            if not clear then break end
            for sy = 0,stride-1 do
                local center = cell_center(x*stride+sx,y*stride+sy,0)
                if not within_bounds(center) or forbidden_marker(center)
                    or not terrain_clear(center) or has_tree(center) then clear = false; break end
            end
        end
        cache[tile.key] = {time=now,clear=clear}
        states[tile.index] = clear and dynamic_clear(x,y) and 2 or 1
        batch_count = batch_count+1
        if payload.yield_after and wi < #work and (batch_count >= payload.yield_after
            or (batch_count >= 8 and clock()-batch_start >= number(payload.time_budget,0.002))) then
            -- Publish useful near-cursor cells immediately, before the distant
            -- edge finishes. Completed work survives a cursor-driven restart.
            coroutine.yield(encode())
            batch_start,batch_count = clock(),0
        end
    end
    return encode()
end

function M.init()
    occupied = {}
    occupied_entities = {}
    static_terrain = {}
    load_marker_regions()
    event_bus.handle_request(events.GRID_CAN_PLACE_REQUEST, can_place)
    event_bus.handle_request(events.GRID_OCCUPY_REQUEST, occupy)
    event_bus.handle_request(events.GRID_RELEASE_REQUEST, release)
    print("[GridPlacement] server grid validation initialized")
end

M._unit_overlaps_cell_for_test = unit_overlaps_cell
M._has_unit_for_test = has_unit
M._unit_is_dead_for_test = unit_is_dead
M._nearby_units_for_footprint_for_test = nearby_units_for_footprint
M._occupied_for_test = function() return occupied end
M._can_place_for_test = can_place
M._reconcile_occupied_for_test = reconcile_occupied

return M
