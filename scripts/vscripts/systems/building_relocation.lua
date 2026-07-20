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
    event_bus.request(events.GRID_RELEASE_REQUEST, {
        grid_x = state.grid_x, grid_y = state.grid_y,
        footprint = state.definition.footprint,
    })
    print(string.format("[BuildingBlink] SetAbsOrigin begin ent=%d target=(%.1f,%.1f,%.1f)", unit:entindex(), position.x, position.y, position.z))
    unit:SetAbsOrigin(position)
    state.grid_x = math.floor(position.x / 128)
    state.grid_y = math.floor(position.y / 128)
    event_bus.request(events.GRID_OCCUPY_REQUEST, {
        grid_x = state.grid_x, grid_y = state.grid_y,
        footprint = state.definition.footprint,
        entindex = unit:entindex(),
    })
    event_bus.emit(events.BUILDING_CHANGED, building_system.public_state(state))
    print(string.format("[BuildingBlink] SetAbsOrigin done ent=%d actual=(%.1f,%.1f,%.1f)", unit:entindex(), unit:GetAbsOrigin().x, unit:GetAbsOrigin().y, unit:GetAbsOrigin().z))
    return true
end
-- Compatibility name used by ability_building_blink.lua.
-- The relocation implementation is exposed as move(), but the ability calls
-- relocate_building(); keep both names pointing to the same function.
building_system.relocate_building = building_system.move
return building_system
