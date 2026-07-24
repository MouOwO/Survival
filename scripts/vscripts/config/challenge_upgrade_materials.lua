-- Runtime-only challenge materials. These are represented by ground entities
-- and are never inserted into either the Dota inventory or content inventory.
local M = {}

M.pickup_radius = 300
M.rows = {}
M.by_challenge_and_stage = {}
M.by_id = {}

local function add(challenge_id, series_id, stage, auto_pickup, display_name)
    local material_id = string.format(
        "material_%s_upgrade_%02d",
        series_id,
        stage
    )
    local row = {
        material_id = material_id,
        challenge_id = challenge_id,
        series_id = series_id,
        required_stage = stage,
        auto_pickup = auto_pickup,
        display_name = display_name,
        enabled = true,
    }
    M.rows[#M.rows + 1] = row
    M.by_id[material_id] = row
    M.by_challenge_and_stage[challenge_id] =
        M.by_challenge_and_stage[challenge_id] or {}
    M.by_challenge_and_stage[challenge_id][stage] = row
end

for stage = 0, 6 do
    local suffix = stage == 0 and "" or "+" .. tostring(stage)
    add(
        "challenge_10",
        "epic_icefire",
        stage,
        false,
        "史诗：冰火裁决" .. suffix .. "合成材料"
    )
end

for stage = 0, 9 do
    local suffix = stage == 0 and "" or "+" .. tostring(stage)
    add(
        "challenge_11",
        "legend_abyss",
        stage,
        true,
        "传说：深渊审判" .. suffix .. "合成材料"
    )
end

function M.find(challenge_id, stage)
    local rows = M.by_challenge_and_stage[tostring(challenge_id or "")]
    return rows and rows[tonumber(stage)] or nil
end

return M