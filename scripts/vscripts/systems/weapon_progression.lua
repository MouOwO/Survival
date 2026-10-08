local M = {}

-- These synthesized weapons use enhancement badges, not attack counters.
-- The unenhanced _00 template is displayed as +1; authored levels stay intact.
function M.icon_level(definition)
    if not definition or definition.equipment_slot ~= "main_hand"
        or (definition.series_id ~= "epic_icefire" and definition.series_id ~= "legend_abyss") then return nil end
    return math.max(1, math.min(tonumber(definition.max_stage) or 10,
        math.floor(tonumber(definition.stage) or 0)))
end

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
