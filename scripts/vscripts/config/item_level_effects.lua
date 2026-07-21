-- 可执行的数据驱动效果。每个 content_id 指向完整快照，不做隐式继承。
local M = {}
local levels = require("config/equipment_level_definitions")
local dictionary = require("config/effect_dictionary")

M.by_content_id = {}
M.invalid = {}

for content_id, level in pairs(levels.by_id) do
    local snapshot = { content_id = content_id, effects = {}, snapshot_complete = true, enabled = level.enabled ~= false, review_status = level.review_status }
    for _, effect in ipairs(level.effects or {}) do
        if dictionary.is_supported(effect.effect_type) then
            snapshot.effects[#snapshot.effects + 1] = effect
        else
            M.invalid[#M.invalid + 1] = {
                content_id = content_id,
                effect_type = effect.effect_type,
                enabled = false,
                error = "unknown_effect_type",
            }
        end
    end
    M.by_content_id[content_id] = snapshot
end

function M.resolve(content_id)
    local snapshot = M.by_content_id[content_id]
    if not snapshot then return nil, "effect_snapshot_missing" end
    if not snapshot.enabled then return nil, "effect_snapshot_disabled" end
    for _, effect in ipairs(snapshot.effects) do
        if not dictionary.is_supported(effect.effect_type) then
            return nil, "unknown_effect_type"
        end
    end
    return snapshot
end

return M
