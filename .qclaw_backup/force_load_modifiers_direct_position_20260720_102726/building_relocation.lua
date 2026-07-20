local event_bus = require("core/event_bus")
local events = require("core/events")
local building_system = {}

function building_system.bind(get_state, public_state)
    building_system.get_state = get_state
    building_system.public_state = public_state
end

function building_system.move(unit, position)
    if not unit or unit:IsNull() or not position then
        return false, "invalid_unit_or_position"
    end
    local state = building_system.get_state(unit:entindex())
    if not state then return false, "building_state_not_found" end

    local old_x, old_y = state.grid_x, state.grid_y
    event_bus.request(events.GRID_RELEASE_REQUEST, {
        grid_x = old_x, grid_y = old_y,
        footprint = state.definition.footprint,
    })

    state.grid_x = math.floor(position.x / 128)
    state.grid_y = math.floor(position.y / 128)
    state.blink_position = position
    unit:RemoveModifierByName("modifier_building_stationary")
    unit:AddNewModifier(unit, nil, "modifier_building_blink_move", {
        x = position.x, y = position.y, z = position.z,
    })

    event_bus.request(events.GRID_OCCUPY_REQUEST, {
        grid_x = state.grid_x, grid_y = state.grid_y,
        footprint = state.definition.footprint,
        entindex = unit:entindex(),
    })
    event_bus.emit(events.BUILDING_CHANGED, building_system.public_state(state))
    print(string.format("[BuildingBlink] direct move ent=%d target=(%.1f,%.1f,%.1f)",
        unit:entindex(), position.x, position.y, position.z))
    return true
end
return building_system
