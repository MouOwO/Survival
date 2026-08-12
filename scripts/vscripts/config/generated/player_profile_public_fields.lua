-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: player_profile_public_fields.csv
local M = {}
M.rows = {
    { field_id = "title_id", source_section = "public", source_key = "title_id", value_type = "string", enabled = true, notes = "公开称号ID。" },
    { field_id = "achievement_score", source_section = "public", source_key = "achievement_score", value_type = "number", default_value = "0", enabled = true, notes = "公开成就总分。" },
    { field_id = "vip_badge", source_section = "entitlements", source_key = "vip", value_type = "boolean", default_value = "0", enabled = true, notes = "只公开VIP展示标记，不公开订单或支付信息。" },
    { field_id = "highest_difficulty", source_section = "public", source_key = "highest_difficulty", value_type = "string", default_value = "N1", enabled = true, notes = "公开最高通关难度。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["field_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
