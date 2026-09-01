-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: building_challenge_definitions.csv
local M = {}
M.rows = {
    { challenge_id = "challenge_monster_01", display_name = "山岭巨人", ability_name = "ability_challenge_monster_01", unit_name = "npc_survival_wave_monster", model_path = "models/heroes/tiny/tiny_04/tiny_04.vmdl", model_scale = 1.3, rank = "boss", movement_type = "ground", attack_type = "melee", attack_range = 216, considered_boss = true, cooldown_seconds = 100, max_alive = 1, max_challenge_waves = 20, required_main_city_level = 0, reward_profile_id = "reward_building_challenge_mountain_giant", sort_order = 1, enabled = true, notes = "挑战进度独立于正式波次。" },
    { challenge_id = "challenge_monster_02", display_name = "树人", ability_name = "ability_challenge_monster_02", unit_name = "npc_survival_wave_monster", model_path = "models/heroes/treant_protector/treant_protector.vmdl", model_scale = 1.3, rank = "boss", movement_type = "ground", attack_type = "melee", attack_range = 216, considered_boss = true, cooldown_seconds = 110, max_alive = 1, max_challenge_waves = 20, required_main_city_level = 0, reward_profile_id = "reward_building_challenge_treant", sort_order = 2, enabled = true, notes = "挑战进度独立于正式波次。" },
    { challenge_id = "challenge_monster_03", display_name = "红龙", ability_name = "ability_challenge_monster_03", unit_name = "npc_survival_wave_monster", model_path = "models/heroes/visage/visage.vmdl", model_scale = 1.3, rank = "boss", movement_type = "flying", attack_type = "melee", attack_range = 216, considered_boss = true, cooldown_seconds = 120, max_alive = 1, max_challenge_waves = 20, required_main_city_level = 0, reward_profile_id = "reward_building_challenge_red_dragon", sort_order = 3, enabled = true, notes = "使用项目已验证的红龙飞行模型代理；挑战进度独立于正式波次。" },
    { challenge_id = "challenge_monster_04", display_name = "剑圣", ability_name = "ability_challenge_monster_04", unit_name = "npc_survival_wave_monster", model_path = "models/heroes/juggernaut/juggernaut.vmdl", model_scale = 1.2, rank = "boss", movement_type = "ground", attack_type = "melee", attack_range = 216, considered_boss = true, cooldown_seconds = 130, max_alive = 1, max_challenge_waves = 20, required_main_city_level = 5, reward_profile_id = "reward_building_challenge_blademaster", sort_order = 4, enabled = true, notes = "需要主城LV5；挑战进度独立于正式波次。", default_wearable_asset_id = "monster_default_juggernaut" },
    { challenge_id = "challenge_monster_05", display_name = "炼金", ability_name = "ability_challenge_monster_05", unit_name = "npc_survival_wave_monster", model_path = "models/heroes/alchemist/alchemist.vmdl", model_scale = 1.2, rank = "boss", movement_type = "ground", attack_type = "melee", attack_range = 216, considered_boss = true, cooldown_seconds = 140, max_alive = 1, max_challenge_waves = 20, required_main_city_level = 0, reward_profile_id = "reward_building_challenge_alchemist", sort_order = 5, enabled = true, notes = "挑战进度独立于正式波次。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["challenge_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
