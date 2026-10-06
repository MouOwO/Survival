local M = {}

-- This describes the end of a weapon's authored upgrade track, not the end
-- of its permanent attack/attribute growth or its use in a synthesis recipe.
function M.is_max_level(definition)
    if not definition or definition.equipment_slot ~= "main_hand" then return false end
    local maximum = tonumber(definition.max_stage) or 0
    if maximum <= 0 then return false end
    return (tonumber(definition.stage) or 0) >= maximum
        or tostring(definition.next_content_id or "") == ""
end

return M
