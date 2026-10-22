-- Fixed-roster advanced-mode permissions use independent authenticated maps.
package.path = "scripts/vscripts/?.lua;" .. package.path
require("config/mode_release_config").all_difficulties_unlocked = false
local function profile()
    return {loaded=true, clear_counts={n4=99,n9=99,n10=99}, standard_clear_counts={n3=1},
        mode_clear_counts={pure={}}, rich_clear_counts={}, cold_clear_counts={}, scourge_clear_counts={},
        ruins_clear_counts={}, celestial_clear_counts={}}
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
assert(result.ready and result.max_difficulty_id == "N4" and #result.options == 30)
assert(result.options[4].unlocked == 1 and result.options[5].unlocked == 0)
assert(result.options[5].unlock_hint:find("丰饶模式 N4",1,true))
progression[0].rich_clear_counts.n4 = 1
result = snapshot("rich")
assert(result.max_difficulty_id == "N4" and #result.limit_player_ids == 1 and result.limit_player_ids[1] == 1,
    "the host's advance cannot bypass a teammate's independent N4")
progression[1].rich_clear_counts.n4 = 1
result = snapshot("rich")
assert(result.max_difficulty_id == "N5" and result.options[6].unlocked == 0,
    "one clear advances only one tier")
for id=0,1 do
    for number=5,29 do progression[id].rich_clear_counts["n"..number]=1 end
end
result = snapshot("rich")
assert(result.max_difficulty_id == "N30")
for _, row in ipairs(result.options) do assert(row.unlocked == 1) end
progression[1].standard_clear_counts.n3 = 0
result = snapshot("rich")
assert(result.ready and result.max_difficulty_id == "" and result.options[1].unlocked == 0)
assert(result.options[1].unlock_hint:find("任意战斗模式 N3",1,true),
    "each frozen-roster player must meet the entry prerequisite")
progression[1].mode_clear_counts.pure.n3 = 1
assert(snapshot("rich").options[1].unlocked == 1, "pure clear is valid authenticated entry evidence")
progression[0] = nil
result = snapshot("rich")
assert(not result.ready and result.max_difficulty_id == "" and #result.limit_player_ids == 0,
    "a disconnected teammate remains required even when active-player enumeration drops them")
assert(result.options[1].unlock_hint == "等待队伍玩家进度加载")
progression[0] = profile()
local required={cold=5,scourge=9,ruins=9,celestial=11}
local limits={cold=50,scourge=50,ruins=50,celestial=35}
for mode,threshold in pairs(required) do
    progression[0], progression[1] = profile(), profile()
    local first_donor=threshold<=10 and progression[0].mode_clear_counts.pure or progression[0].rich_clear_counts
    first_donor["n"..threshold] = 1
    result = snapshot(mode)
    assert(result.ready and result.max_difficulty_id == "" and #result.options==limits[mode])
    assert(result.options[1].unlocked == 0 and result.limit_player_ids[1] == 1)
    local second_donor=threshold<=10 and progression[1].mode_clear_counts.pure or progression[1].rich_clear_counts
    second_donor["n"..threshold] = 1
    result = snapshot(mode)
    assert(result.ready and result.options[1].unlocked == 1 and result.max_difficulty_id == "N4")
    progression[1][mode .. "_clear_counts"] = nil
    result = snapshot(mode)
    assert(not result.ready and result.max_difficulty_id == "", "missing backend mode capability fails closed for the whole team")
    progression[1][mode .. "_clear_counts"] = {}
end
print("TEAM_MODE_DIFFICULTY_PASS: fixed roster, all-member exact entry, independent sequential tiers, disconnect and capability guards")
