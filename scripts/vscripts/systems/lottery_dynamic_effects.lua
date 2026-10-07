-- Recomputed from the authoritative mode-projected inventory on profile refresh.
-- Never persist these totals: ownership order, reconnect and repeated refreshes
-- must produce the same bonus without stacking it into saved static stats.
local definitions = require("config/generated/lottery_item_definitions")
local aliases = require("config/content_id_aliases")
local M = {}
local function positive_count(value)
    local n = tonumber(value)
    return n and n == n and n < math.huge and n >= 1
end
function M.project(save)
    save = save or {}
    local owned, ur_count = {}, 0
    for id, count in pairs(save.content_inventory or {}) do
        local canonical = aliases.canonical(id)
        local item = definitions.by_id[canonical]
        if positive_count(count) and item and item.enabled ~= false
            and not owned[canonical] then
            owned[canonical] = true
            if item.quality == "ur" then ur_count = ur_count + 1 end
        end
    end
    local bonus = {}
    if owned.lottery_kings_treasure then
        local level = tonumber((save.gameplay_stats or {}).map_level) or 0
        if level ~= level or level == math.huge or level == -math.huge then level = 0 end
        bonus.hero_attribute_bonus_pct = math.max(0, math.floor(level)) * 2.5
    end
    if owned.lottery_muramasa then
        bonus.hero_final_damage_bonus_pct = ur_count * 4
    end
    return bonus
end
return M
