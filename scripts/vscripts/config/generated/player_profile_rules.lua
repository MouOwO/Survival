-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: player_profile_rules.csv
local M = {}
M.rows = {
    { profile_rule_id = "default_profile", provider_id = "local_fixture", schema_version = 1, max_processed_update_ids = 128, publish_public_profiles = true, load_on_hero_ready = true, enabled = true, notes = "首版使用本地JSON假数据；正式HTTP Provider必须保持同一快照与增量契约。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["profile_rule_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
