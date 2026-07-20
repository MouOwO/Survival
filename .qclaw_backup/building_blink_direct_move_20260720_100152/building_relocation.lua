local event_bus = require("core/event_bus")
local events = require("core/events")
local building_system = {}

function building_system.bind(get_state, public_state)
    building_system.get_state = get_state
    building_system.public_state = public_state
end

function building_system.move(unit, position)
    if not unit or unit:IsNull() or not position then return false, "invalid_unit_or_position" end
    local state = building_system.get_state(unit:entindex())
    if not state then return false, "building_state_not_found" end
    local grid = event_bus.request(events.GRID_CAN_PLACE_REQUEST, {
        position = position, footprint = state.definition.footprint,
    })
    if not grid or not grid.ok then return false, grid and grid.error or "grid_rejected" end
    event_bus.request(events.GRID_RELEASE_REQUEST, {
        grid_x = state.grid_x, grid_y = state.grid_y,
        footprint = state.definition.footprint,
    })
    unit:RemoveModifierByName("modifier_building_stationary")
    FindClearSpaceForUnit(unit, grid.world_position, true)
    unit:SetAbsOrigin(grid.world_position)
    unit:AddNewModifier(unit, nil, "modifier_building_stationary", {})
    state.grid_x, state.grid_y = grid.grid_x, grid.grid_y
    event_bus.request(events.GRID_OCCUPY_REQUEST, {
        grid_x = state.grid_x, grid_y = state.grid_y,
        footprint = state.definition.footprint, entindex = unit:entindex(),
    })
    event_bus.emit(events.BUILDING_CHANGED, building_system.public_state(state))
    print(string.format("[BuildingBlink] moved ent=%d to=(%.1f,%.1f,%.1f)", unit:entindex(), grid.world_position.x, grid.world_position.y, grid.world_position.z))
    return true
end
return building_system
