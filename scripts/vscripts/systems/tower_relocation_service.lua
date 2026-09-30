-- Relocation shares construction's authoritative grid, but never its costs or
-- building limits: an existing tower keeps its identity and occupied footprint.
local bus = require("core/event_bus")
local events = require("core/events")
local M = { ABILITY = "ability_building_blink", RANGE = 1000 }

local function valid(entity)
    return entity and not entity:IsNull()
end

function M.resolve(player_id, entindex, ability_entindex, ignore_cooldown)
    player_id, entindex = tonumber(player_id), tonumber(entindex)
    if not player_id or not entindex then return nil, "invalid_player_or_tower" end
    if require("systems/player_context_service").is_defeated(player_id) then
        return nil, "player_defeated"
    end
    local state = bus.request(events.BUILDING_QUERY_REQUEST, {entindex=entindex, read_only=true})
    local ultimate = false
    if not state then
        state = require("systems/tower_fusion_service").relocation_state(player_id, entindex)
        ultimate = true
    end
    if not state or state.player_id ~= player_id then return nil, "tower_not_owned" end
    if not ultimate and state.building_id ~= "arrow_tower" then return nil, "building_not_movable" end
    local unit = state.unit
    if not valid(unit) or not unit:IsAlive() then return nil, "tower_unavailable" end
    local ability = unit:FindAbilityByName(M.ABILITY)
    if not valid(ability) or ability:GetCaster() ~= unit or ability:IsHidden()
        or not ability:IsActivated() or ability:GetLevel() <= 0 then
        return nil, "move_ability_unavailable"
    end
    if ability_entindex and ability:entindex() ~= tonumber(ability_entindex) then
        return nil, "ability_profile_mismatch"
    end
    if not ignore_cooldown and ability.IsCooldownReady and not ability:IsCooldownReady() then
        return nil, "move_ability_cooldown"
    end
    return {unit=unit, ability=ability, ultimate=ultimate,
        footprint=state.footprint or (state.definition and state.definition.footprint)}
end

function M.validate(player_id, entindex, position, ability_entindex, ignore_cooldown)
    local resolved, reason = M.resolve(player_id, entindex, ability_entindex, ignore_cooldown)
    if not resolved then return {ok=false, error=reason, cells={}} end
    for _, axis in ipairs({"x", "y", "z"}) do
        local n = position and tonumber(position[axis])
        if not n or n ~= n or math.abs(n) > 32768 then
            return {ok=false, error="invalid_position", cells={}}
        end
    end
    local grid = bus.request(events.GRID_CAN_PLACE_REQUEST, {
        position=position, footprint=resolved.footprint,
        ignore_entindex=resolved.unit:entindex(), team=resolved.unit:GetTeamNumber(),
    }) or {ok=false, error="grid_validation_failed", cells={}}
    local destination = grid.world_position or position
    local origin = resolved.unit:GetAbsOrigin()
    -- Reject rather than clamp: preview and committed cells must be identical.
    if (destination.x-origin.x)^2 + (destination.y-origin.y)^2 > M.RANGE^2 then
        grid.ok, grid.error = false, "relocation_out_of_range"
    end
    return grid, resolved
end

function M.move(player_id, entindex, position, ability_entindex, native_cast)
    local grid, resolved = M.validate(player_id, entindex, position, ability_entindex, native_cast)
    if not grid.ok then return {ok=false, error=grid.error} end
    local result
    if resolved.ultimate then
        result = bus.request(events.TOWER_FUSION_MOVE_REQUEST, {
            player_id=tonumber(player_id), entindex=tonumber(entindex), position=grid.world_position,
        })
    else
        local ok, reason = require("systems/building_system").relocate_for_player(
            tonumber(player_id), tonumber(entindex), grid.world_position)
        result = {ok=ok, error=reason}
    end
    result = result or {ok=false, error="relocation_failed"}
    if result.ok and not native_cast then
        resolved.ability:StartCooldown(resolved.ability:GetCooldown(resolved.ability:GetLevel()))
    end
    return result
end

return M
