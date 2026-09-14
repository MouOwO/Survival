-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: player_profile_rules.csv
local M = {}
M.rows = {
    { profile_rule_id = "default_profile", provider_id = "http_fishing", schema_version = 1, max_processed_update_ids = 128, publish_public_profiles = true, load_on_hero_ready = true, enabled = true, notes = "HTTP权威档案联调；禁止自动回退到本地模拟档案。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["profile_rule_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
