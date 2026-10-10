-- Presentation only: the 25 existing upgrade rows remain the gameplay authority.
local M = {}

-- Allocation-free rarity lookup for high-frequency beam presentation.
function M.rarity(building_id, level)
    if building_id=="ultimate_tower" then return "UR" end
    level=math.floor(tonumber(level) or 0)
    if building_id~="arrow_tower" or level<1 or level>25 then return nil end
    if level<=5 then return "N" end
    if level<=10 then return "R" end
    if level<=15 then return "SR" end
    return "SSR"
end

function M.project(state)
    if type(state) ~= "table" then return nil end
    local level = math.floor(tonumber(state.absolute_level or state.level) or 0)
    if state.building_id == "ultimate_tower" then
        return { rarity = "UR", stars = math.max(1, math.min(5, level)), red_stars = 0 }
    end
    if state.building_id ~= "arrow_tower" or level < 1 or level > 25 then return nil end
    if level <= 5 then return { rarity = "N", stars = level, red_stars = 0 } end
    if level <= 10 then return { rarity = "R", stars = level - 5, red_stars = 0 } end
    if level <= 15 then return { rarity = "SR", stars = level - 10, red_stars = 0 } end
    -- Existing final form has ten upgrades. Its last five progressively turn
    -- the five gold stars red; it never shows six stars or resets progression.
    return {
        rarity = "SSR",
        stars = math.min(5, level - 15),
        red_stars = math.max(0, level - 20),
    }
end

function M.display_name(state, name)
    local rank = M.project(state)
    if not rank then return nil end
    -- Names may already carry a cached old rarity from a Tools reload.
    name = tostring(name or ""):gsub("^【.-】", "")
        :gsub("（进阶 %d+/5）$", "")
    if rank.red_stars > 0 then
        name = name .. "（进阶 " .. tostring(rank.red_stars) .. "/5）"
    end
    return "【" .. rank.rarity .. "】" .. name
end

return M
