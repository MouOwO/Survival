-- Permission rules consume authenticated permanent progression only. Missing
-- independent maps mean the backend does not support the corresponding mode.
local M = {}
local parents = { rich = "standard", cold = "rich", scourge = "cold",
    ruins = "scourge", celestial = "ruins" }
local names = { standard = "常规模式", pure = "纯净模式", rich = "丰饶模式",
    cold = "极寒模式", scourge = "天灾模式", ruins = "归墟模式", celestial = "天域模式" }
local entry_difficulty = { rich=3, cold=5, scourge=9, ruins=9, celestial=11 }

local function positive_integer(value)
    return type(value) == "number" and value == value and value < math.huge
        and value >= 1 and value == math.floor(value)
end

function M.parent_mode(mode) return parents[mode] end
function M.clear_field(mode)
    return parents[mode] and (mode .. "_clear_counts")
        or mode == "standard" and "standard_clear_counts" or "clear_counts"
end

function M.counts(mode, progress)
    if type(progress) ~= "table" or progress.loaded ~= true then return nil end
    if mode == "pure" then
        local maps = type(progress.mode_clear_counts) == "table" and progress.mode_clear_counts or {}
        return type(maps.pure) == "table" and maps.pure or nil
    end
    local counts = progress[M.clear_field(mode)]
    -- Historical authoritative accounts have no provenance map. Once a map
    -- exists, even an empty one must never inherit pure or other-mode wins.
    if mode == "standard" and counts == nil then counts = progress.clear_counts end
    return type(counts) == "table" and counts or nil
end

function M.entry_unlocked(mode, progress)
    local required = entry_difficulty[mode]
    if not required then return mode == "standard" or mode == "pure" or mode == "fishing" end
    if not M.counts(mode, progress) then return false end
    -- The v3 source says 'clear N3/N5/N9/N11', without restricting the mode.
    -- Inspect only authenticated persisted maps, never a client highest-level hint.
    local key = "n" .. required
    for candidate in pairs(names) do
        local prior = M.counts(candidate, progress)
        if prior and positive_integer(prior[key]) then return true end
    end
    return false
end

function M.difficulty_unlocked(mode, difficulty, progress)
    if not names[mode] then return nil end
    local number = type(difficulty) == "string" and tonumber(difficulty:match("^N(%d+)$")) or nil
    local values = require("config/human_monster_rules").data.modes[mode]
    if not number or not values[number] or not M.entry_unlocked(mode, progress) then return false end
    if number <= 4 then return true end
    local own = M.counts(mode, progress)
    return own ~= nil and positive_integer(own["n" .. (number - 1)])
end

function M.entry_hint(mode)
    local required = entry_difficulty[mode]
    return required and ("通关任意战斗模式 N" .. required .. " 后解锁") or ""
end

function M.difficulty_hint(mode, difficulty)
    if not names[mode] then return nil end
    local number = type(difficulty) == "string" and tonumber(difficulty:match("^N(%d+)$")) or nil
    return number and number > 4 and (names[mode] .. " N" .. (number - 1) .. " 通关后解锁") or M.entry_hint(mode)
end

return M
