local event_bus = require("core/event_bus")
local events = require("core/events")
local grid_config = require("config/grid_placement_config")
local building_system = {}

function building_system.bind(get_state, public_state)
    building_system.get_state = get_state
    building_system.public_state = public_state
end

function building_system.validate(unit, position)
    if not unit or unit:IsNull() or not position then
        return nil, "invalid_unit_or_position"
    end
    local state = building_system.get_state(unit:entindex())
    if not state then return nil, "building_state_not_found" end
    local grid = event_bus.request(events.GRID_CAN_PLACE_REQUEST, {
        position = position,
        footprint = state.definition.footprint,
        ignore_entindex = unit:entindex(),
        team = state.team,
    })
    if not grid or grid.ok ~= true then
        return nil, grid and grid.error or "relocation_position_invalid"
    end
    return grid, nil
end

function building_system.move(unit, position)
    if not unit or unit:IsNull() or not position then return false, "invalid_unit_or_position" end
    local state = building_system.get_state(unit:entindex())
    if not state then return false, "building_state_not_found" end
    local grid, reason = building_system.validate(unit, position)
    if not grid then return false, reason end
    position = grid.world_position
    event_bus.request(events.GRID_RELEASE_REQUEST, {
        grid_x = state.grid_x, grid_y = state.grid_y,
        footprint = state.definition.footprint,
        entindex = unit:entindex(),
    })
    print(string.format("[BuildingBlink] SetAbsOrigin begin ent=%d target=(%.1f,%.1f,%.1f)", unit:entindex(), position.x, position.y, position.z))
    unit:Stop()
    if unit.SetForceAttackTarget then unit:SetForceAttackTarget(nil) end
    if unit.survival_projectile_model and unit.SetRangedProjectileName then
        unit:SetRangedProjectileName(unit.survival_projectile_model)
    end
    local auto_attack = unit:FindModifierByName("modifier_tower_auto_attack")
    if auto_attack and auto_attack.ResetTarget then auto_attack:ResetTarget() end
    local attack_effects = unit:FindModifierByName("modifier_tower_attack_effects")
    if attack_effects and attack_effects.ResetAfterRelocation then
        attack_effects:ResetAfterRelocation()
    end
    unit:RemoveModifierByName("modifier_building_stationary")
    unit.survival_fixed_position = Vector(position.x, position.y, position.z)
    unit:SetAbsOrigin(unit.survival_fixed_position)
    unit:AddNewModifier(unit, nil, "modifier_building_blink_move", {
        x = position.x, y = position.y, z = position.z,
    })
    local footprint = state.definition.footprint or { x = 2, y = 2 }
    local subdivision = math.max(
        1,
        tonumber(grid_config.footprint_subdivision) or 1
    )
    local footprint_x = math.max(2, tonumber(footprint.x) or 2)
        * subdivision
    local footprint_y = math.max(2, tonumber(footprint.y) or 2)
        * subdivision
    local cell_size = tonumber(grid_config.cell_size) or 64
    state.grid_x = math.floor(position.x / cell_size + 0.5)
        - math.floor(footprint_x / 2)
    state.grid_y = math.floor(position.y / cell_size + 0.5)
        - math.floor(footprint_y / 2)
    unit.survival_grid_x = state.grid_x
    unit.survival_grid_y = state.grid_y
    event_bus.request(events.GRID_OCCUPY_REQUEST, {
        grid_x = state.grid_x, grid_y = state.grid_y,
        footprint = state.definition.footprint,
        entindex = unit:entindex(),
    })
    event_bus.emit(events.BUILDING_CHANGED, building_system.public_state(state))
    GameRules:GetGameModeEntity():SetContextThink(
        "building_relocation_refresh_" .. tostring(unit:entindex()),
        function()
            if not unit or unit:IsNull() then return nil end
            unit:SetAbsOrigin(unit.survival_fixed_position)
            unit:Stop()
            if unit.SetForceAttackTarget then unit:SetForceAttackTarget(nil) end
            if unit.survival_projectile_model
                and unit.SetRangedProjectileName then
                unit:SetRangedProjectileName(unit.survival_projectile_model)
            end
            local effects = unit:FindModifierByName("modifier_tower_attack_effects")
            if effects and effects.ResetAfterRelocation then
                effects:ResetAfterRelocation()
            end
            print(string.format(
                "[BuildingBlink] network refresh ent=%d actual=(%.1f,%.1f,%.1f)",
                unit:entindex(), unit:GetAbsOrigin().x,
                unit:GetAbsOrigin().y, unit:GetAbsOrigin().z
            ))
            return nil
        end,
        0.06
    )
    print(string.format("[BuildingBlink] SetAbsOrigin done ent=%d actual=(%.1f,%.1f,%.1f)", unit:entindex(), unit:GetAbsOrigin().x, unit:GetAbsOrigin().y, unit:GetAbsOrigin().z))
    return true
end
-- Compatibility name used by ability_building_blink.lua.
-- The relocation implementation is exposed as move(), but the ability calls
-- relocate_building(); keep both names pointing to the same function.
building_system.relocate_building = building_system.move
return building_system
