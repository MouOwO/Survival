-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: worker_sound_definitions.csv
local M = {}
M.rows = {
    { cue_id = "worker_lumberjack_tree_impact", worker_id = "npc_survival_lumberjack", phase = "hit", sound_event = "Hero_Tiny_Tree.Impact", sound_resource = "soundevents/game_sounds_heroes/game_sounds_tiny.vsndevts", playback_mode = "oneshot", attach_scope = "unit", cooldown_group = "worker_lumberjack_tree_impact", cooldown_seconds = 0.12, max_plays_per_window = 4, window_seconds = 1, enabled = true, notes = "伐木工真实命中资源树；Tiny原生木质命中事件已用本机resourceinfo核实。", max_concurrent = 2, concurrency_seconds = 0.62 },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["cue_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
