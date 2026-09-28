-- Shared score/floor milestones for game UI and authoritative settlement.
local definitions = require("config/generated/archive_endless_achievements")
local M = {}
function M.progress(archive, item)
    if item.required_wave then
        return tonumber(archive.endless_best_wave) or 0, item.required_wave, "wave"
    end
    return tonumber(archive.endless_score) or 0, item.required_score, "score"
end
function M.needs_reconcile(archive)
    archive = archive or {}
    for _, item in ipairs(definitions.rows) do
        local count, target = M.progress(archive, item)
        if item.enabled and target and count >= target
            and not (archive.completed or {})[item.achievement_id] then return true end
    end
    return false
end
function M.reconcile(archive, stats, apply_effects)
    archive.completed = archive.completed or {}
    for _, item in ipairs(definitions.rows) do
        local count, target = M.progress(archive, item)
        if item.enabled and target and count >= target and not archive.completed[item.achievement_id] then
            apply_effects(stats, item)
            archive.completed[item.achievement_id] = true
        end
    end
end
function M.rows(archive)
    local rows = {}
    for _, item in ipairs(definitions.rows) do
        if item.enabled then
            local count, target, kind = M.progress(archive, item)
            local floor = kind == "wave"
            rows[#rows + 1] = { id=item.achievement_id,
                name=floor and item.display_name or item.display_name .. "（" .. target .. "分）",
                short_name=floor and ("超过" .. (target - 1) .. "层") or nil,
                description=item.description, icon_style="seal", quality="gold", rune="∞",
                count=count, target=target, progress_kind=kind,
                unlock_condition=floor and ("历史最高通关层数大于" .. (target - 1) .. "，需完成第" .. target .. "层")
                    or ("累计无尽积分达到" .. target .. "分"),
                completed=(archive.completed or {})[item.achievement_id] and 1 or 0 }
        end
    end
    return rows
end
return M
