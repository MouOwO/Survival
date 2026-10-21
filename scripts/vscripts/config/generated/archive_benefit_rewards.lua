-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: archive_benefit_rewards.csv
local M = {}
M.rows = {
    { reward_id = "daily_time_30", track = "daily_time", period = "day", metric = "minutes", required = 30, base_item_ids = {"lottery_ticket"}, base_counts = {"1"}, pass_item_ids = {"lottery_ticket"}, pass_counts = {"1"}, enabled = true },
    { reward_id = "daily_time_60", track = "daily_time", period = "day", metric = "minutes", required = 60, base_item_ids = {"lottery_ticket"}, base_counts = {"1"}, pass_item_ids = {"lottery_ticket"}, pass_counts = {"1"}, enabled = true },
    { reward_id = "daily_time_90", track = "daily_time", period = "day", metric = "minutes", required = 90, base_item_ids = {"lottery_ticket"}, base_counts = {"1"}, pass_item_ids = {"lottery_ticket"}, pass_counts = {"1"}, enabled = true },
    { reward_id = "daily_time_120", track = "daily_time", period = "day", metric = "minutes", required = 120, base_item_ids = {"lottery_ticket", "welfare_zongzi"}, base_counts = {"2", "1"}, pass_item_ids = {"lottery_ticket", "welfare_zongzi"}, pass_counts = {"2", "1"}, enabled = true },
    { reward_id = "daily_time_150", track = "daily_time", period = "day", metric = "minutes", required = 150, base_item_ids = {"lottery_ticket", "welfare_zongzi", "lottery_ember_of_legacy"}, base_counts = {"2", "2", "1"}, pass_item_ids = {"lottery_ticket", "welfare_zongzi", "special_lottery_ticket", "lottery_ember_of_legacy"}, pass_counts = {"2", "2", "2", "2"}, enabled = true },
    { reward_id = "daily_win_1", track = "daily_wins", period = "day", metric = "wins", required = 1, base_item_ids = {"lottery_ticket"}, base_counts = {"1"}, pass_item_ids = {"lottery_ticket"}, pass_counts = {"1"}, enabled = true },
    { reward_id = "daily_win_2", track = "daily_wins", period = "day", metric = "wins", required = 2, base_item_ids = {"lottery_ticket"}, base_counts = {"1"}, pass_item_ids = {"lottery_ticket"}, pass_counts = {"1"}, enabled = true },
    { reward_id = "daily_win_3", track = "daily_wins", period = "day", metric = "wins", required = 3, base_item_ids = {"lottery_ticket"}, base_counts = {"1"}, pass_item_ids = {"lottery_ticket"}, pass_counts = {"1"}, enabled = true },
    { reward_id = "daily_win_4", track = "daily_wins", period = "day", metric = "wins", required = 4, base_item_ids = {"lottery_ticket"}, base_counts = {"1"}, pass_item_ids = {"special_lottery_ticket"}, pass_counts = {"1"}, enabled = true },
    { reward_id = "daily_win_5", track = "daily_wins", period = "day", metric = "wins", required = 5, base_item_ids = {"lottery_ticket"}, base_counts = {"2"}, pass_item_ids = {"special_lottery_ticket"}, pass_counts = {"1"}, enabled = true },
    { reward_id = "weekly_time_120", track = "weekly_time", period = "week", metric = "minutes", required = 120, base_item_ids = {"lottery_ticket"}, base_counts = {"2"}, pass_item_ids = {"lottery_ticket", "special_lottery_ticket"}, pass_counts = {"2", "1"}, enabled = true },
    { reward_id = "weekly_time_240", track = "weekly_time", period = "week", metric = "minutes", required = 240, base_item_ids = {"lottery_ticket"}, base_counts = {"3"}, pass_item_ids = {"lottery_ticket", "special_lottery_ticket"}, pass_counts = {"3", "1"}, enabled = true },
    { reward_id = "weekly_time_360", track = "weekly_time", period = "week", metric = "minutes", required = 360, base_item_ids = {"lottery_ticket"}, base_counts = {"4"}, pass_item_ids = {"lottery_ticket", "special_lottery_ticket"}, pass_counts = {"4", "1"}, enabled = true },
    { reward_id = "weekly_time_480", track = "weekly_time", period = "week", metric = "minutes", required = 480, base_item_ids = {"lottery_ticket"}, base_counts = {"5"}, pass_item_ids = {"lottery_ticket", "special_lottery_ticket"}, pass_counts = {"5", "1"}, enabled = true },
    { reward_id = "weekly_time_600", track = "weekly_time", period = "week", metric = "minutes", required = 600, base_item_ids = {"lottery_ticket"}, base_counts = {"5"}, pass_item_ids = {"lottery_ticket", "special_lottery_ticket"}, pass_counts = {"5", "1"}, enabled = true },
    { reward_id = "weekly_time_720", track = "weekly_time", period = "week", metric = "minutes", required = 720, base_item_ids = {"lottery_ticket"}, base_counts = {"5"}, pass_item_ids = {"lottery_ticket", "special_lottery_ticket"}, pass_counts = {"5", "1"}, enabled = true },
    { reward_id = "weekly_time_840", track = "weekly_time", period = "week", metric = "minutes", required = 840, base_item_ids = {"lottery_ticket"}, base_counts = {"5"}, pass_item_ids = {"lottery_ticket", "special_lottery_ticket"}, pass_counts = {"5", "1"}, enabled = true },
    { reward_id = "weekly_time_960", track = "weekly_time", period = "week", metric = "minutes", required = 960, base_item_ids = {"lottery_ticket"}, base_counts = {"5"}, pass_item_ids = {"lottery_ticket", "special_lottery_ticket"}, pass_counts = {"5", "1"}, enabled = true },
    { reward_id = "weekly_time_1080", track = "weekly_time", period = "week", metric = "minutes", required = 1080, base_item_ids = {"lottery_ticket"}, base_counts = {"5"}, pass_item_ids = {"lottery_ticket", "special_lottery_ticket"}, pass_counts = {"5", "1"}, enabled = true },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["reward_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
