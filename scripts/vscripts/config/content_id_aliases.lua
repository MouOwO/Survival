-- Runtime aliases for source rows that describe the same logical content.
-- Keep recipe and inventory services on one canonical ID even when an older
-- challenge drop still carries its historical source ID.
local M = {}

local aliases = {
    challenge_synthesis_gem = "material_synthesis_gem",
    -- The first lottery prototype misread these two workbook names. Preserve
    -- existing local profiles while moving to the verified source names.
    lottery_flame_crystal = "lottery_nature_crystal",
    lottery_burst_crystal = "lottery_bombardment_crystal",
}

function M.canonical(content_id)
    local value = tostring(content_id or "")
    return aliases[value] or value
end

return M
