local M = {}

function M.should_trigger(defeat_triggered, state)
    return defeat_triggered ~= true
        and state ~= nil
        and state.building_id == "wall"
        and state.constructing ~= true
end

return M