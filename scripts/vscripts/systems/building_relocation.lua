local event_bus = require("core/event_bus")
local events = require("core/events")
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

local function move_wall(unit,state,grid)
    local navigation=require("systems/wall_navigation_service")
    local origin=unit:GetAbsOrigin()
    local old={position=Vector(origin.x,origin.y,origin.z),fixed=unit.survival_fixed_position,
        x=state.grid_x,y=state.grid_y,unit_x=unit.survival_grid_x,unit_y=unit.survival_grid_y}
    local position=grid.world_position
    local function cells(event,x,y)
        return event_bus.request(event,{grid_x=x,grid_y=y,
            footprint=state.definition.footprint,entindex=unit:entindex()})
    end
    local ok,reason=pcall(function()
        -- Release contacts at the OLD wall position, before restoring their
        -- normal hulls. create() alone would keep this handle's old blockers.
        navigation.clear(unit)
        assert(cells(events.GRID_RELEASE_REQUEST,old.x,old.y)==true,"old_grid_release_failed")
        unit:Stop()
        unit.survival_fixed_position=Vector(position.x,position.y,position.z)
        unit:SetAbsOrigin(unit.survival_fixed_position)
        state.grid_x,state.grid_y=grid.grid_x,grid.grid_y
        unit.survival_grid_x,unit.survival_grid_y=grid.grid_x,grid.grid_y
        assert(cells(events.GRID_OCCUPY_REQUEST,grid.grid_x,grid.grid_y)==true,"new_grid_occupy_failed")
        assert(#navigation.create(unit)>=4,"new_wall_navigation_missing")
    end)
    if not ok then
        -- Nothing is published and no delayed teleport is started until the
        -- new footprint and its navigation have both been installed.
        local restored,restore_error=pcall(function()
            navigation.clear(unit)
            assert(cells(events.GRID_RELEASE_REQUEST,grid.grid_x,grid.grid_y)==true,"new_grid_release_failed")
            unit.survival_fixed_position=old.fixed
            unit:SetAbsOrigin(old.position)
            state.grid_x,state.grid_y=old.x,old.y
            unit.survival_grid_x,unit.survival_grid_y=old.unit_x,old.unit_y
            assert(cells(events.GRID_OCCUPY_REQUEST,old.x,old.y)==true,"old_grid_restore_failed")
            assert(#navigation.create(unit)>=4,"old_wall_navigation_missing")
        end)
        print("[BuildingBlink] wall move failed: "..tostring(reason)
            ..(restored and " restored=1" or " restore_error="..tostring(restore_error)))
        return false,restored and "wall_relocation_failed" or "wall_relocation_rollback_failed"
    end
    unit.survival_wall_relocation_revision=(tonumber(unit.survival_wall_relocation_revision) or 0)+1
    unit:RemoveModifierByName("modifier_building_stationary")
    unit:AddNewModifier(unit,nil,"modifier_building_blink_move",{
        x=position.x,y=position.y,z=position.z,
    })
    event_bus.emit(events.BUILDING_CHANGED,building_system.public_state(state))
    GameRules:GetGameModeEntity():SetContextThink(
        "building_relocation_refresh_"..tostring(unit:entindex()),function()
            if not unit or unit:IsNull() or not unit:IsAlive() then return nil end
            unit:SetAbsOrigin(unit.survival_fixed_position)
            return nil
        end,0.06)
    return true
end

function building_system.move(unit, position)
    if not unit or unit:IsNull() or not position then return false, "invalid_unit_or_position" end
    local state = building_system.get_state(unit:entindex())
    if not state then return false, "building_state_not_found" end
    local grid, reason = building_system.validate(unit, position)
    if not grid then return false, reason end
    if state.building_id=="wall" then return move_wall(unit,state,grid) end
    position = grid.world_position
    event_bus.request(events.GRID_RELEASE_REQUEST, {
        grid_x = state.grid_x, grid_y = state.grid_y,
        footprint = state.definition.footprint,
        entindex = unit:entindex(),
    })
    print(string.format("[BuildingBlink] SetAbsOrigin begin ent=%d target=(%.1f,%.1f,%.1f)", unit:entindex(), position.x, position.y, position.z))
    unit:Stop()
    if unit.SetForceAttackTarget then unit:SetForceAttackTarget(nil) end
    if unit.survival_projectile_model ~= nil and unit.SetRangedProjectileName then
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
    state.grid_x, state.grid_y = grid.grid_x, grid.grid_y
    unit.survival_grid_x = state.grid_x
    unit.survival_grid_y = state.grid_y
    event_bus.request(events.GRID_OCCUPY_REQUEST, {
        grid_x = state.grid_x, grid_y = state.grid_y,
        footprint = state.definition.footprint,
        entindex = unit:entindex(),
    })
    event_bus.emit(events.BUILDING_CHANGED, building_system.public_state(state))
    if auto_attack and auto_attack.OnIntervalThink then auto_attack:OnIntervalThink() end
    GameRules:GetGameModeEntity():SetContextThink(
        "building_relocation_refresh_" .. tostring(unit:entindex()),
        function()
            if not unit or unit:IsNull() then return nil end
            unit:SetAbsOrigin(unit.survival_fixed_position)
            unit:Stop()
            if unit.SetForceAttackTarget then unit:SetForceAttackTarget(nil) end
            if unit.survival_projectile_model ~= nil
                and unit.SetRangedProjectileName then
                unit:SetRangedProjectileName(unit.survival_projectile_model)
            end
            local effects = unit:FindModifierByName("modifier_tower_attack_effects")
            if effects and effects.ResetAfterRelocation then
                effects:ResetAfterRelocation()
            end
            local auto = unit:FindModifierByName("modifier_tower_auto_attack")
            if auto and auto.ResetTarget then auto:ResetTarget() end
            if auto and auto.OnIntervalThink then auto:OnIntervalThink() end
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
