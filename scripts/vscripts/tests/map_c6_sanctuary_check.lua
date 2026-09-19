-- Folded entrance terrain: script_reload_code tests/map_c6_sanctuary_check
-- Read-only Workshop checks; does not place buildings, move units or reset services.
local map_name = GetMapName()
if not IsInToolsMode() or (map_name ~= "survival_c6" and map_name ~= "template_map") then return end

local event_bus = require("core/event_bus")
local events = require("core/events")
local checked, failed = 0, 0
local cx, cy = -1024, map_name == "template_map" and 0 or 5376
local function test(name, ok, detail)
    checked = checked + 1
    if not ok then failed = failed + 1 end
    print("[C6_SANCTUARY] " .. (ok and "PASS " or "FAIL ")
        .. name .. " " .. (detail or ""))
end

-- The east entrance opens north into NE. Rotate clockwise for S, W and N.
local function rotate(x, y, turns)
    for _ = 1, turns do x, y = y, -x end
    return x, y
end

local function point(x, y, turns)
    x, y = rotate(x, y, turns or 0)
    local p = Vector(cx + x, cy + y, 0)
    p.z = GetGroundHeight(p, nil)
    return p
end

local function clear(p)
    return GridNav:IsTraversable(p) and not GridNav:IsBlocked(p)
end

local function marker(name, expected)
    local entity = Entities:FindByName(nil, name)
    if not entity then
        test(name, false, "missing")
        return nil
    end
    local p = entity:GetAbsOrigin()
    local dx, dy = p.x - expected.x, p.y - expected.y
    test(name, math.sqrt(dx * dx + dy * dy) <= 2
        and math.abs(p.z - GetGroundHeight(p, nil)) < 64
        and clear(p), string.format("x=%.0f y=%.0f z=%.0f", p.x, p.y, p.z))
    return p
end

local function route_segment(name, a, b, turns)
    local dx, dy = b[1] - a[1], b[2] - a[2]
    local steps = math.max(1, math.ceil(math.sqrt(dx * dx + dy * dy) / 64))
    local first_failure, samples = nil, 0
    for step = 0, steps do
        local x, y = a[1] + dx * step / steps, a[2] + dy * step / steps
        local p = point(x, y, turns)
        samples = samples + 1
        if not clear(p) and not first_failure then
            first_failure = string.format("blocked local=(%.0f,%.0f) world=(%.0f,%.0f)",
                x, y, p.x, p.y)
        end
    end
    test(name, first_failure == nil, first_failure or ("samples=" .. samples))
end

local pool = point(0, 0)
for id = 0, 3 do
    local suffix = "_player_" .. id
    local a = marker("monsterborn_player" .. (id + 1), point(600, 0, id))
    local b = marker("c6_player_" .. id .. "_entrance", point(2100, 0, id))
    if a and b then
        local dx, dy = b.x - a.x, b.y - a.y
        local length = math.sqrt(dx * dx + dy * dy)
        test("spawn_to_entrance_1500" .. suffix, math.abs(length - 1500) <= 2,
            string.format("distance=%.1f", length))
    end

    local builder = Entities:FindByName(nil, "player_" .. id .. "_builder_spawn")
    local builder_pos = builder and builder:GetAbsOrigin() or nil
    local local_x, local_y = 0, 0
    if builder_pos then
        local_x, local_y = rotate(builder_pos.x - cx, builder_pos.y - cy, (4 - id) % 4)
    end
    test("builder_in_own_court" .. suffix, builder_pos
        and local_x >= 720 and local_x <= 2120
        and local_y >= 416 and local_y <= 1816
        and math.abs(GetGroundHeight(builder_pos, nil) - 384) < 20
        and clear(builder_pos))
    test("builder_to_pool" .. suffix, builder_pos
        and GridNav:CanFindPath(builder_pos, pool))

    route_segment("full_approach" .. suffix, {600, 0}, {2100, 0}, id)
    for _, distance in ipairs({1200, 1408, 1600, 2032}) do
        local p = point(distance, 0, id)
        local expected = 24
        test("lane_height_" .. distance .. suffix, math.abs(p.z - expected) < 20,
            string.format("ground=%.1f", p.z))
    end
    local route = {{2100, 0}, {2432, 0}, {2432, 800}, {2000, 1000}, {1420, 1116}}
    for segment = 1, #route - 1 do
        route_segment("fold_segment_" .. segment .. suffix,
            route[segment], route[segment + 1], id)
    end
    test("entrance_to_own_court" .. suffix, b
        and GridNav:CanFindPath(b, point(1420, 1116, id)))

    -- Corner samples sit 96 units inside the specified 1400 x 1400 lawn.
    for index, xy in ipairs({{816, 512}, {2024, 512}, {2024, 1720}, {816, 1720}, {1420, 1116}}) do
        local p = point(xy[1], xy[2], id)
        test("court_floor_" .. index .. suffix, clear(p) and math.abs(p.z - 384) < 20,
            string.format("ground=%.1f", p.z))
    end

    for index, x in ipairs({1024, 1408, 1792}) do
        local p = point(x, 624, id)
        test("turret_ground_" .. index .. suffix,
            clear(p) and math.abs(p.z - 384) < 20,
            string.format("ground=%.1f", p.z))
        -- Exercise the live placement handler, including 64-unit snapping,
        -- 128 x 128 footprint, terrain slope, nearby trees and occupied cells.
        local result, request_error = event_bus.request(events.GRID_CAN_PLACE_REQUEST, {
            position = p,
            footprint = { x = 2, y = 2 },
            team = DOTA_TEAM_GOODGUYS,
            player_id = id,
            compact = true,
        })
        local detail = result and result.error or request_error or ""
        if result and result.world_position then
            detail = detail .. string.format(" snapped=(%.0f,%.0f)",
                result.world_position.x, result.world_position.y)
        end
        test("turret_buildable_" .. index .. suffix, result and result.ok == true, detail)
    end

    -- Flat lower and upper landings remain buildable; the staircase is outside
    -- the original lawn and is tested separately for walking and rising height.
    for index, xy in ipairs({{2100,-80},{2280,-80},{2432,-80},{2480,-80},{2100,864},{2280,864},{2432,912},{2480,960}}) do
        local p = point(xy[1],xy[2],id)
        local expected = xy[2]<64 and 24 or 384
        test("corner_level_" .. index .. suffix, clear(p) and math.abs(p.z-expected)<20,
            string.format("ground=%.1f",p.z))
        for _, size in ipairs({2,4}) do
            local result, request_error = event_bus.request(events.GRID_CAN_PLACE_REQUEST, {
                position=p,footprint={x=size,y=size},team=DOTA_TEAM_GOODGUYS,player_id=id,compact=true,
            })
            test("corner_buildable_" .. index .. "_" .. size*64 .. suffix,
                result and result.ok==true,result and result.error or request_error or "")
        end
    end
    for index, y in ipairs({64,224,384,544,704}) do
        local p=point(2432,y,id)
        local expected=24+360*(y-64)/640
        test("bend_stair_height_"..index..suffix,clear(p) and math.abs(p.z-expected)<24,
            string.format("ground=%.1f expected=%.1f",p.z,expected))
    end
    for _, y in ipairs({160,320,480,608}) do
        test("stair_side_blocks_"..y..suffix,not clear(point(2176,y,id)))
    end
    -- All previously decorated lawn locations must now be clear for buildings.
    for index, xy in ipairs({{1784,1008},{1176,1320},{1952,1544},{864,1056},{896,1552},{1120,1696},{1488,1680},{1968,1592}}) do
        local result, request_error = event_bus.request(events.GRID_CAN_PLACE_REQUEST, {
            position=point(xy[1],xy[2],id),footprint={x=2,y=2},team=DOTA_TEAM_GOODGUYS,player_id=id,compact=true,
        })
        test("clean_court_buildable_" .. index .. suffix,
            result and result.ok==true,result and result.error or request_error or "")
    end

    -- The open firing strip must not create a shortcut through the low retaining edge.
    for _, x in ipairs({1024, 1216, 1408, 1600, 1792}) do
        local p = point(x, 320, id)
        test("lane_court_barrier_" .. x .. suffix, not clear(p))
    end
end

for index, xy in ipairs({{470, 470}, {-470, 470}, {-470, -470}, {470, -470}}) do
    local p = point(xy[1], xy[2])
    test("square_pool_corner_" .. index, math.abs(p.z - 4) < 8 and clear(p),
        string.format("ground=%.1f", p.z))
end
print(string.format("[C6_SANCTUARY] RESULT checked=%d failed=%d", checked, failed))
