-- Deterministic cosmetic selection shared by game and archive worker.
local catalog = require("config/generated/archive_titles")
local M = {}
function M.best_wave(archive)
    local value = tonumber(archive and archive.endless_best_wave) or 0
    if value ~= value or value == math.huge or value < 0 then return 0 end
    return math.floor(value)
end
function M.unlocked(archive, id)
    archive = archive or {}
    local row = catalog.by_id[id]
    if not row or row.enabled ~= true then return false end
    if tonumber(row.required_wave) then
        return M.best_wave(archive) >= row.required_wave
    end
    return row.default_unlocked == true
        or type(archive.titles_owned) == "table" and archive.titles_owned[id] == true
end
function M.highest(archive)
    local selected, highest = "", -1
    for index, row in ipairs(catalog.rows) do
        local level = tonumber(row.title_level) or index
        if level > highest and M.unlocked(archive, row.title_id) then
            selected, highest = row.title_id, level
        end
    end
    return selected
end
function M.selected(archive)
    archive = archive or {}
    local id = archive.equipped_title
    if archive.title_selection_manual == true and type(id) == "string" and M.unlocked(archive, id) then
        return id
    end
    return M.highest(archive)
end
function M.needs_reconcile(archive)
    archive = archive or {}
    return (archive.equipped_title or "") ~= M.selected(archive)
end
function M.sync(archive)
    archive.equipped_title = M.selected(archive)
end
function M.apply(command, archive)
    local id = command.title_id
    if type(id) ~= "string" then return false, "称号请求无效" end
    if id ~= "" and not M.unlocked(archive, id) then return false, "称号未解锁或不存在" end
    archive.title_selection_manual = id ~= ""
    archive.equipped_title = id
    M.sync(archive)
    return true
end
function M.rows(archive, override)
    archive = archive or {}
    local selected = override ~= nil and override or M.selected(archive)
    local rows = {}
    for _, row in ipairs(catalog.rows) do
        if row.enabled then
            local unlocked = M.unlocked(archive, row.title_id)
            rows[#rows + 1] = {id=row.title_id, name=row.display_name, icon=row.icon,
                description=row.description, unlock_condition=row.unlock_condition,
                level=row.title_level, required_wave=row.required_wave,
                unlocked=unlocked and 1 or 0,
                count=row.required_wave and M.best_wave(archive) or (unlocked and 1 or 0),
                target=row.required_wave or 1,
                automatic=archive.title_selection_manual ~= true and 1 or 0,
                equipped=unlocked and selected==row.title_id and 1 or 0, quality="gold"}
        end
    end
    return rows
end
return M
