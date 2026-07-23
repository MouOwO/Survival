-- 挑战入口与掉落声明；实际掉落仍须由服务端挑战逻辑验证。
local M = {}
M.rows = {
    { content_id = "challenge_01", challenge_type = "resource", reward = { wood = 100 }, review_status = "mapped" },
    { content_id = "challenge_02", challenge_type = "resource", reward = { gold = 100 }, review_status = "mapped" },
    { content_id = "challenge_03", challenge_type = "resource", reward = { all_attributes = 10 }, review_status = "mapped" },
    { content_id = "challenge_04", challenge_type = "resource", reward = { all_attributes = 100, gold = 1000 }, review_status = "mapped" },
    { content_id = "challenge_05", challenge_type = "boss_drop", reward_content_id = "challenge_synthesis_gem", review_status = "mapped" },
    { content_id = "challenge_06", challenge_type = "virtual_kill_counter", counter = { enemy_tag = "ice_wraith", required = 200, event = "valid_enemy_death", attribution = "owner_player" }, requires_content_id = "item_small_polar_crystal", completion = { replace_content_id = "item_large_polar_crystal" }, enabled = true, review_status = "explicit_requirement" },
    { content_id = "challenge_07", challenge_type = "upgrade_material", reward_content_id = "item_molten_upgrade_gem_01_03", review_status = "mapped" },
    { content_id = "challenge_08", challenge_type = "upgrade_material", reward_content_id = "item_molten_upgrade_gem_04", review_status = "mapped" },
    { content_id = "challenge_09", challenge_type = "boss_drop", reward_content_id = "material_ice_soul_ember", review_status = "mapped" },
    { content_id = "challenge_10", challenge_type = "staged_boss", stage_count = 7, stages = {}, completion = { upgrade_series = "epic_icefire", upgrade_steps = 1 }, enabled = true, review_status = "test_balance_enabled" },
    { content_id = "challenge_11", challenge_type = "simultaneous_boss", stage_count = 10, stages = {}, completion = { upgrade_series = "legend_abyss", upgrade_steps = 1 }, enabled = true, review_status = "test_balance_enabled" },
}
for _, challenge in ipairs(M.rows) do
    if challenge.stages then
        for stage = 1, challenge.stage_count do
            challenge.stages[stage] = { stage = stage, boss_values_enabled = true, balance_status = "n1_curve_test_pending_balance" }
        end
    end
end
M.by_id = {}
for _, row in ipairs(M.rows) do M.by_id[row.content_id] = row end
return M
