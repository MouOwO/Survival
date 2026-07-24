-- Compatibility view for older consumers. The authoritative source for every
-- technology is data/csv/建筑与工人系统/technology_definitions.csv.
local definitions = require("config/generated/technology_definitions")
local M = { rows = {}, by_id = {} }

for _, row in ipairs(definitions.rows or {}) do
    if row.technology_track ~= "gold_mine" then
        M.rows[#M.rows + 1] = row
        M.by_id[row.technology_id] = row
    end
end

return M