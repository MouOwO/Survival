-- Shared victory milestones. Solo history never implies cooperative progress.
local definitions = require("config/generated/archive_welfare_rewards")
local M = {}
local function nonnegative_integer(value)
    local number = tonumber(value)
    if number and number == number and number >= 0 and number < math.huge then return math.floor(number) end
    return 0
end
function M.wins(archive)
    local total = 0
    for _, count in pairs((archive or {}).clear_counts or {}) do total = total + nonnegative_integer(count) end
    return total
end
function M.cooperative_wins(archive)
    return nonnegative_integer((archive or {}).cooperative_clear_count)
end
function M.progress(archive, item)
    return item.progress_kind == "cooperative" and M.cooperative_wins(archive) or M.wins(archive)
end
function M.needs_reconcile(archive)
    archive = archive or {}
    for _, item in ipairs(definitions.rows) do
        if item.enabled and M.progress(archive, item) >= item.required_wins
            and not (archive.completed or {})[item.achievement_id] then return true end
    end
    return false
end
function M.reconcile(archive, stats, apply_effects)
    archive.completed = archive.completed or {}
    for _, item in ipairs(definitions.rows) do
        if item.enabled and M.progress(archive, item) >= item.required_wins and not archive.completed[item.achievement_id] then
            apply_effects(stats, item)
            archive.completed[item.achievement_id] = true
        end
    end
end
function M.rows(archive)
    archive = archive or {}
    local rows = {}
    for _, item in ipairs(definitions.rows) do
        if item.enabled then
            local cooperative = item.progress_kind == "cooperative"
            rows[#rows + 1] = {
                id=item.achievement_id, name=item.display_name,
                description=item.description, icon_style="seal", quality="gold",
                rune=tostring(item.required_wins), count=M.progress(archive, item), target=item.required_wins,
                progress_kind=item.progress_kind,
                unlock_condition=cooperative
                    and ("与至少1名真人队友共同胜利" .. item.required_wins .. "次（各难度合计，每局计1次）")
                    or ("累计胜利" .. item.required_wins .. "次（各难度合计）"),
                completed=(archive.completed or {})[item.achievement_id] and 1 or 0,
            }
        end
    end
    return rows
end
return M
