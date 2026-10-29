-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: archive_challenge_actions.csv
local M = {}
M.rows = {
    { action_id = "endless", ability_name = "ability_archive_endless", building_id = 2, slot_order = 9, display_name = "无尽模式开启", min_difficulty = 3, unlock_text = "N3解锁", ability_icon = "nevermore_requiem", cooldown_seconds = 0, enabled = true, description = "需要：\n - N3解锁\n所有难度模式下难度一致，每波难度会逐层升高\n每通过10层获取无尽积分奖励增加100%\n\n无尽模式下每20波会掉落一件存档装备，波次越高品质概率越高" },
    { action_id = "endless_skip", ability_name = "ability_archive_endless_skip", building_id = 2, slot_order = 10, display_name = "无尽跳关", min_difficulty = 3, unlock_text = "N3解锁", ability_icon = "faceless_void_time_walk", cooldown_seconds = 0, enabled = true, description = "需要：\n - N3解锁\n每次点击无尽跳2/5/10/20层(每波)\n\n无法退回请谨慎" },
    { action_id = "tower_solo", ability_name = "ability_archive_tower_solo", building_id = 2, slot_order = 11, display_name = "通天塔(单人)开启", min_difficulty = 10, unlock_text = "极寒或天灾N10解锁", ability_icon = "skywrath_mage_mystic_flare", cooldown_seconds = 0, enabled = true, description = "需要：\n - 极寒或天灾N10解锁\n所有难度模式下难度一致，每波难度会逐层升高\n每通过10层获取无尽积分奖励增加100%（通天塔下积分获取更高）\n\n结束会立马计算存档，请在打之前把其他存档挑战都打完\n\n通天塔下每15波会掉落一件存档装备，波次越高品质概率越高" },
    { action_id = "return_1", ability_name = "ability_archive_return_1", building_id = 1, slot_order = 12, display_name = "返回", min_difficulty = 1, ability_icon = "kunkka_return", cooldown_seconds = 0, enabled = true, description = "返回选择自己的英雄；不结束存档挑战。" },
    { action_id = "return_2", ability_name = "ability_archive_return_2", building_id = 2, slot_order = 12, display_name = "返回", min_difficulty = 1, ability_icon = "kunkka_return", cooldown_seconds = 0, enabled = true, description = "返回选择自己的英雄；不结束存档挑战。" },
    { action_id = "return_3", ability_name = "ability_archive_return_3", building_id = 3, slot_order = 12, display_name = "返回", min_difficulty = 1, ability_icon = "kunkka_return", cooldown_seconds = 0, enabled = true, description = "返回选择自己的英雄；不结束存档挑战。" },
    { action_id = "return_4", ability_name = "ability_archive_return_4", building_id = 4, slot_order = 12, display_name = "返回", min_difficulty = 1, ability_icon = "kunkka_return", cooldown_seconds = 0, enabled = true, description = "返回选择自己的英雄；不结束存档挑战。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["action_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
