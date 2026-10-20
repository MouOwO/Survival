-- Fixed-roster advanced-mode permissions use independent authenticated maps.
package.path = "scripts/vscripts/?.lua;" .. package.path
local function profile()
    return {loaded=true, clear_counts={n5=99,n9=99,n10=99}, standard_clear_counts={n10=1},
        rich_clear_counts={}, cold_clear_counts={}, scourge_clear_counts={}}
end
local progression = {[0]=profile(), [1]=profile()}
local expected_mode
package.loaded["systems/player_profile_service"] = {get_progression=function(id, mode)
    assert(mode == expected_mode, "the server mode is passed to every authenticated profile read")
    return progression[id]
end}
local frozen_ids = {0,1}
package.loaded["systems/startup_loading_service"] = {selection_player_ids=function() return frozen_ids end}
package.loaded["systems/player_context_service"] = {active_player_ids=function() return {1} end}
local permission = require("systems/team_difficulty_service")
local function snapshot(mode)
    expected_mode = mode
    return permission.current(mode)
end
local result = snapshot("rich")
assert(result.ready and result.max_difficulty_id == "N5" and #result.options == 10)
assert(result.options[5].unlocked == 1 and result.options[6].unlocked == 0)
assert(result.options[6].unlock_hint:find("丰饶模式 N5",1,true))
progression[0].rich_clear_counts.n5 = 1
result = snapshot("rich")
assert(result.max_difficulty_id == "N5" and #result.limit_player_ids == 1 and result.limit_player_ids[1] == 1,
    "the host's advance cannot bypass a teammate's independent N5")
progression[1].rich_clear_counts.n5 = 1
result = snapshot("rich")
assert(result.max_difficulty_id == "N10")
for _, row in ipairs(result.options) do assert(row.unlocked == 1) end
progression[1].standard_clear_counts.n10 = 0
result = snapshot("rich")
assert(result.ready and result.max_difficulty_id == "" and result.options[1].unlocked == 0)
assert(result.options[1].unlock_hint:find("常规模式 N10",1,true),
    "each frozen-roster player must meet the entry prerequisite")
progression[1].standard_clear_counts.n10 = 1
progression[0] = nil
result = snapshot("rich")
assert(not result.ready and result.max_difficulty_id == "" and #result.limit_player_ids == 0,
    "a disconnected teammate remains required even when active-player enumeration drops them")
assert(result.options[1].unlock_hint == "等待队伍玩家进度加载")
progression[0] = profile()
for _, mode in ipairs({"cold", "scourge"}) do
    local parent_field = mode == "cold" and "rich_clear_counts" or "cold_clear_counts"
    progression[0][parent_field].n10 = 1
    progression[1][parent_field].n10 = 0
    result = snapshot(mode)
    assert(result.ready and result.max_difficulty_id == "")
    assert(result.options[1].unlocked == 0 and result.limit_player_ids[1] == 1)
    progression[1][parent_field].n10 = 1
    result = snapshot(mode)
    assert(result.ready and result.options[1].unlocked == 1 and result.max_difficulty_id ~= "")
    progression[1][mode .. "_clear_counts"] = nil
    result = snapshot(mode)
    assert(not result.ready and result.max_difficulty_id == "", "missing backend mode capability fails closed for the whole team")
    progression[1][mode .. "_clear_counts"] = {}
end
print("TEAM_MODE_DIFFICULTY_PASS: fixed roster, all-member parent N10, independent N5 bracket, disconnect and capability guards")
