local M = {}

M.WAR3_TO_DOTA_RATIO = 1 / 3

function M.from_war3(war3_armor)
    local value = tonumber(war3_armor) or 0
    return value * M.WAR3_TO_DOTA_RATIO
end

function M.to_war3(dota_armor)
    local value = tonumber(dota_armor) or 0
    return value / M.WAR3_TO_DOTA_RATIO
end

return M