local buildings = require("config/buildings_config")
local rogue_effect_state = require("systems/rogue_effect_state_service")

local M = {}

function M.altar_built(altar)
    return altar ~= nil and not altar:IsNull()
        and (not altar.IsAlive or altar:IsAlive())
end

-- Summoning follows the altar's unlock, not its placement/cost or a separate
-- city-level rule. A completed early altar remains eligible after construction
-- consumes its free-build charge.
function M.check(player_id, city_level, altar)
    if M.altar_built(altar) then return true, nil, "hero_altar" end
    if rogue_effect_state.numeric(player_id, "builder_free_hero_altar") > 0 then
        return true, nil, "rogue"
    end
    local required = tonumber(buildings.hero_altar.unlock_city_level) or 3
    if (tonumber(city_level) or 0) >= required then
        return true, nil, "city_level"
    end
    return false, "主城达到Lv." .. tostring(required) .. "或获得英雄祭坛解锁后可召唤英雄"
end

return M
