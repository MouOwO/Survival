local M = {}

function M.level_rows(passive, maximum)
    if type(passive) ~= "table" then return {} end
    maximum = math.max(0, math.floor(tonumber(maximum) or 0))
    local rows = {}
    for level = 1, maximum do
        rows[#rows + 1] = {
            level = level,
            trigger_chance = passive.trigger_chance[level] or 0,
            damage_multiplier = passive.damage_multiplier[level] or 0,
            effect = passive.level_text[level] or "",
        }
    end
    return rows
end

return M