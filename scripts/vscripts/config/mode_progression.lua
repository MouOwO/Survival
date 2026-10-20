-- Permission rules consume authenticated permanent progression only. Missing
-- independent maps mean the backend does not support the corresponding mode.
local M = {}
local parents = { rich = "standard", cold = "rich", scourge = "cold" }
local names = { standard = "常规模式", rich = "丰饶模式", cold = "极寒模式", scourge = "天灾模式" }

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
    local counts = progress[M.clear_field(mode)]
    -- Historical authoritative accounts have no provenance map. Once a map
    -- exists, even an empty one must never inherit pure or other-mode wins.
    if mode == "standard" and counts == nil then counts = progress.clear_counts end
    return type(counts) == "table" and counts or nil
end

function M.entry_unlocked(mode, progress)
    local parent = parents[mode]
    if not parent then return mode == "standard" or mode == "pure" or mode == "fishing" end
    if not M.counts(mode, progress) then return false end
    local prior = M.counts(parent, progress)
    return prior ~= nil and positive_integer(prior.n10)
end

function M.difficulty_unlocked(mode, difficulty, progress)
    if not parents[mode] then return nil end -- Preserve ordinary progression.
    local number = type(difficulty) == "string" and tonumber(difficulty:match("^N(%d+)$")) or nil
    if not number or number < 1 or number > 10 or not M.entry_unlocked(mode, progress) then return false end
    return number <= 5 or positive_integer(M.counts(mode, progress).n5)
end

function M.entry_hint(mode)
    local parent = parents[mode]
    return parent and (names[parent] .. " N10 通关后解锁") or ""
end

function M.difficulty_hint(mode, difficulty)
    if not parents[mode] then return nil end
    local number = type(difficulty) == "string" and tonumber(difficulty:match("^N(%d+)$")) or nil
    return number and number > 5 and (names[mode] .. " N5 通关后解锁 N6–N10") or M.entry_hint(mode)
end

return M
