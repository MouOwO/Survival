-- Deterministic cosmetic selection shared by game and archive worker.
local catalog = require("config/generated/archive_titles")
local M = {}
function M.unlocked(archive, id)
    local row = catalog.by_id[id]
    return row ~= nil and row.enabled == true and (row.default_unlocked == true
        or type(archive.titles_owned) == "table" and archive.titles_owned[id] == true)
end
function M.selected(archive)
    archive = archive or {}
    local id = archive.equipped_title
    return type(id) == "string" and M.unlocked(archive, id) and id or ""
end
function M.apply(command, archive)
    local id = command.title_id
    if type(id) ~= "string" then return false, "称号请求无效" end
    if id ~= "" and not M.unlocked(archive, id) then return false, "称号未解锁或不存在" end
    archive.equipped_title = id
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
                unlocked=unlocked and 1 or 0, count=unlocked and 1 or 0, target=1,
                equipped=unlocked and selected==row.title_id and 1 or 0, quality="gold"}
        end
    end
    return rows
end
return M
