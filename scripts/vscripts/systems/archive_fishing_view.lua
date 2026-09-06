local items = require("config/generated/archive_fishing_items")
local M = {}
function M.project(profile)
    local inventory = profile and profile.save and profile.save.fishing_inventory
    local ready = type(inventory) == "table" and inventory ~= require("core/json_decoder").null
    local rows, total, owned = {}, 0, 0
    for _, item in ipairs(items.rows) do
        if item.enabled then
            local value = ready and tonumber(inventory[item.reward_id]) or 0
            local count = value and value == value and value >= 0 and value < math.huge and math.floor(value) or 0
            total = total + count
            if count > 0 then owned = owned + 1 end
            rows[#rows + 1] = { id = item.reward_id, name = item.display_name,
                description = item.description, quality = item.quality, icon_style = "seal", rune = "鱼",
                count = count, target = item.max_owned, count_known = ready and 1 or 0 }
        end
    end
    return rows, { ready = ready and 1 or 0, total = total, owned = owned, types = #rows }
end
return M
