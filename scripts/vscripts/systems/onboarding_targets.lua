-- Resolve the player's real Hammer court, then offer only positions accepted
-- by the ordinary construction grid. This module never places buildings.
local bus = require("core/event_bus")
local events = require("core/events")
local geometry = require("core/building_grid_geometry")
local context = require("systems/player_context_service")
local M = {}

local footprints = { wall = {x=4,y=4}, main_city = {x=4,y=4}, tower = {x=2,y=2} }
local building_ids = {wall="wall", main_city="main_city", tower="arrow_tower"}

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function valid(unit)
    return unit and (not unit.IsNull or not unit:IsNull())
        and (not unit.IsAlive or unit:IsAlive())
end

local function marker(name)
    if not Entities or type(Entities.FindByName) ~= "function" then return nil end
    local ok, unit = pcall(Entities.FindByName, Entities, nil, name)
    if not ok or not valid(unit) or type(unit.GetAbsOrigin) ~= "function" then return nil end
    local read, point = pcall(unit.GetAbsOrigin, unit)
    return read and point and finite(point.x) and finite(point.y) and finite(point.z) and point or nil
end

local function point(x, y, z) return Vector(x, y, z or 0) end

local function target(position, kind, existing)
    return {x=position.x,y=position.y,z=position.z,width=64,height=64,
        footprint_x=footprints[kind].x,footprint_y=footprints[kind].y,
        existing_entindex=existing and existing.entindex or nil}
end

local function own_buildings(player_id)
    local result = bus.request(events.BUILDING_LIST_REQUEST, {player_id=player_id,handles_only=true})
    local existing = {towers={},walls={}}
    for _, row in ipairs(result and result.buildings or {}) do
        if row.player_id == player_id and valid(row.unit) and row.unit.GetAbsOrigin then
            for kind, id in pairs(building_ids) do
                if row.building_id == id and (kind == "tower" or kind == "wall" or not existing[kind]) then
                    local position = row.unit:GetAbsOrigin()
                    if finite(position.x) and finite(position.y) and finite(position.z) then
                        local item = {position=position,entindex=row.entindex or row.unit:entindex()}
                        if kind == "tower" then existing.towers[#existing.towers+1] = item
                        elseif kind == "wall" then existing.walls[#existing.walls+1] = item
                        else existing[kind] = item end
                    end
                end
            end
        end
    end
    return existing
end

local function snap(position, footprint)
    local _, x = geometry.snap_axis(position.x, footprint.x)
    local _, y = geometry.snap_axis(position.y, footprint.y)
    return point(x, y, position.z)
end

local function legal(position, kind, player_id, builder)
    local result = bus.request(events.GRID_CAN_PLACE_REQUEST, {
        position=snap(position,footprints[kind]), footprint=footprints[kind],
        player_id=player_id, team=DOTA_TEAM_GOODGUYS,
        ignore_entindex=valid(builder) and builder.entindex and builder:entindex() or nil,
    })
    local accepted = result and result.ok and result.world_position
    if accepted and finite(accepted.x) and finite(accepted.y) and finite(accepted.z) then
        return accepted
    end
    return nil, result and result.error or "onboarding_grid_unavailable"
end

-- A cached completed own building is already legal occupancy. Re-validating
-- its occupied footprint would wrongly hide the guide after reconnection.
-- Other players' buildings never satisfy this recovery path.
function M.get(player_id, mode_id)
    if mode_id ~= "standard" and mode_id ~= "pure" then return nil,"onboarding_mode_unsupported" end
    if type(GetMapName) ~= "function" or GetMapName() ~= "template_map" then
        return nil,"onboarding_map_unsupported"
    end
    player_id = tonumber(player_id)
    if not finite(player_id) or player_id < 0 or player_id ~= math.floor(player_id) then
        return nil,"onboarding_invalid_player"
    end
    -- Follow the same slot-to-marker contract as builder spawning. Steam IDs
    -- and sparse engine PlayerIDs are not indices into the four court array.
    local slot = context.slot(player_id)
    local index = slot and tostring(slot.builder_spawn_marker or ""):match("^player_(%d+)_builder_spawn$")
    index = tonumber(index)
    if not index or index < 0 or index > 3 then return nil,"onboarding_player_slot_missing" end
    local prefix = "c6_player_" .. tostring(index)
    local turret, corner = marker(prefix .. "_turret_2"), marker(prefix .. "_corner_2")
    if not turret or not corner then return nil,"onboarding_court_marker_missing" end
    local dx,dy = corner.x-turret.x,corner.y-turret.y
    if math.abs(math.sqrt(dx*dx+dy*dy)-math.sqrt(1024*1024+288*288)) > 64 then
        return nil,"onboarding_court_geometry_mismatch"
    end
    local ax,ay = dx*1024+dy*288,dy*1024-dx*288
    local length = math.sqrt(ax*ax+ay*ay)
    ax,ay = ax/length,ay/length
    local bx,by = -ay,ax
    local function local_point(x,y)
        return point(turret.x+ax*(x-1408)+bx*(y-624),
            turret.y+ay*(x-1408)+by*(y-624),turret.z)
    end
    local existing = own_buildings(player_id)
    local wall_center = snap(local_point(2304,912),footprints.wall)
    for _, built in ipairs(existing.walls) do
        local occupied_center = snap(built.position,footprints.wall)
        -- Account admission can finish after a player has already built.
        -- Recover only the wall at this court's one real stair-mouth center;
        -- a wall elsewhere must never relocate the guide or complete its step.
        if occupied_center.x == wall_center.x and occupied_center.y == wall_center.y then
            existing.wall = {position=point(wall_center.x,wall_center.y,built.position.z),entindex=built.entindex}
            break
        end
    end
    -- A misplaced completed wall already consumes the player's unique wall
    -- slot. Do not demand a second wall, relocate it, or count it as success.
    if not existing.wall and #existing.walls > 0 then return nil,"misplaced_wall" end
    local builder_result = bus.request(events.BUILDER_GET_REQUEST, {player_id=player_id})
    local builder = builder_result and builder_result.ok and builder_result.builder or nil
    local result = {court_index=index,slot_id=slot.slot_id,existing={},
        center={x=turret.x+bx*492,y=turret.y+by*492,z=turret.z}}
    local function choose(kind,candidates)
        if existing[kind] then
            result[kind] = target(existing[kind].position,kind,existing[kind])
            result.existing[kind] = existing[kind].entindex
            return true
        end
        local seen,last_error = {},nil
        for _, candidate in ipairs(candidates) do
            local snapped = snap(candidate,footprints[kind])
            local key = tostring(snapped.x)..":"..tostring(snapped.y)
            if not seen[key] then
                seen[key] = true
                local accepted,reason = legal(snapped,kind,player_id,builder)
                if accepted then result[kind]=target(accepted,kind); return true end
                last_error = reason
            end
        end
        return false,"onboarding_"..kind.."_position_unavailable:"..tostring(last_error)
    end
    -- A single snapped center seals this particular stair mouth. Never move
    -- the recommended wall out onto a slope or onto a different player's court.
    local ok,reason = choose("wall",{wall_center})
    if not ok then return nil,reason end
    local city_candidates = {local_point(1408,1488)}
    -- Prefer the quiet rear of the court; bounded alternatives handle scenery,
    -- another live unit, or an existing building at the initial recommendation.
    for radius=128,384,128 do
        for _,offset in ipairs({{0,-1},{-1,0},{1,0},{-1,-1},{1,-1},{0,1},{-1,1},{1,1}}) do
            local x,y = 1408+radius*offset[1],1488+radius*offset[2]
            if x>=848 and x<=1992 and y>=544 and y<=1688 then
                city_candidates[#city_candidates+1]=local_point(x,y)
            end
        end
    end
    ok,reason = choose("main_city",city_candidates)
    if not ok then return nil,reason end
    local tower_candidates = {local_point(1408,624)}
    for _,number in ipairs({1,3}) do
        local alternative = marker(prefix.."_turret_"..number)
        if alternative then tower_candidates[#tower_candidates+1]=alternative end
    end
    for radius=128,256,128 do
        for _,offset in ipairs({{-1,0},{1,0},{0,1},{-1,1},{1,1}}) do
            tower_candidates[#tower_candidates+1]=local_point(1408+radius*offset[1],624+radius*offset[2])
        end
    end
    -- Several completed towers can predate the admission response. Accept
    -- only one at a recommended snapped anchor, not whichever list row is
    -- returned first. Keep the guide centered on that exact candidate.
    for _, built in ipairs(existing.towers) do
        local occupied_center = snap(built.position,footprints.tower)
        for _, candidate in ipairs(tower_candidates) do
            local candidate_center = snap(candidate,footprints.tower)
            if occupied_center.x == candidate_center.x and occupied_center.y == candidate_center.y then
                existing.tower = {position=point(candidate_center.x,candidate_center.y,built.position.z),
                    entindex=built.entindex}
                break
            end
        end
        if existing.tower then break end
    end
    ok,reason = choose("tower",tower_candidates)
    if not ok then return nil,reason end
    return result
end

return M
