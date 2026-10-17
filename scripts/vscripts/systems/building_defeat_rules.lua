local M = {}

function M.should_trigger(defeat_triggered, state)
    return defeat_triggered ~= true
        and state ~= nil
        and state.building_id == "wall"
        and state.constructing ~= true
end

-- Only the registered participant owns this personal loss. Do not infer an
-- owner from native creature getters, teams or a missing/default slot zero.
function M.player_for_completed_wall(state, participating_player_ids)
    if not M.should_trigger(false, state) or type(participating_player_ids) ~= "table" then return nil end
    local player_id = state.player_id
    if type(player_id) ~= "number" or player_id ~= player_id or player_id < 0
        or player_id >= math.huge or player_id ~= math.floor(player_id) then return nil end
    for _, participant in ipairs(participating_player_ids) do
        if participant == player_id then return player_id end
    end
    return nil
end

return M
