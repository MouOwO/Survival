package.path = "scripts/vscripts/?.lua;" .. package.path
require("config/mode_release_config").all_difficulties_unlocked = false
local players = {
    [0] = { id = 0, team = 2, connected = 2 },
    [1] = { id = 1, team = 2, connected = 2 },
    [2] = { id = 2, team = 1, connected = 2 },
}
DOTA_MAX_TEAM_PLAYERS = 4
PlayerResource = {
    IsValidPlayerID = function(_, id) return players[id] ~= nil end,
    IsFakeClient = function(_, id) return players[id].fake end,
    GetPlayer = function(_, id) return players[id] end,
    GetTeam = function(_, id) return players[id].team end,
    GetConnectionState = function(_, id) return players[id].connected end,
}
local host, tools = 1, false
GameRules = { PlayerHasCustomGameHostPrivileges = function(_, player) return player.id == host end }
IsInToolsMode = function() return tools end
local setup = require("systems/match_setup_service")
setup.init("match-one")
assert(setup.get_mode() == nil and not setup.is_mode_selected())
assert(setup.get_profile_mode() == nil and not setup.is_fishing_mode())
assert(setup.selector_player_id() == 1, "host is not necessarily player zero")
assert(setup.select_mode(0, "pure", "match-one").error == "selection_not_host")
assert(setup.select_mode(1, "pure", "old-match").error == "match_session_mismatch")
assert(setup.select_mode(1, "cheat", "match-one").error == "mode_not_found")
assert(setup.select_mode(1, "pure", "match-one").ok)
assert(setup.get_profile_mode() == "pure" and not setup.is_fishing_mode())
assert(setup.select_mode(1, "pure", "match-one").ok, "same choice is idempotent")
assert(setup.select_mode(1, "standard", "match-one").error == "mode_locked")
assert(setup.select_mode(2, "pure", "match-one").error == "selection_not_host")
local snapshot = setup.snapshot()
snapshot.mode_options[1].display_name = "tampered"
assert(setup.snapshot().mode_options[1].display_name == "常规模式")
assert(#setup.snapshot().mode_options == 4 and not setup.snapshot().read_only_acceptance)
local order = {"standard", "rich", "cold", "pure"}
for index, expected in ipairs(order) do assert(setup.snapshot().mode_options[index].mode_id == expected) end
local function option(mode)
    for _, row in ipairs(setup.snapshot().mode_options) do if row.mode_id == mode then return row end end
    error("missing mode " .. mode)
end
setup.init("fishing-match")
assert(setup.select_mode(0, "fishing", "fishing-match").error == "selection_not_host")
assert(setup.select_mode(1, "fishing", "old-match").error == "match_session_mismatch")
for _, closed in ipairs({"fishing", "scourge", "ruins", "celestial"}) do
    assert(setup.select_mode(1, closed, "fishing-match").error == "mode_not_released",
        "configured future modes remain unavailable to direct requests")
end
assert(not setup.is_mode_selected() and not setup.is_fishing_mode() and setup.get_profile_mode() == nil)
setup.init("standard-match")
assert(setup.select_mode(1, "standard", "standard-match").ok)
assert(setup.get_profile_mode() == "standard" and not setup.is_fishing_mode())
local progress
package.loaded["systems/player_profile_service"] = {
    get_authenticated_progression = function(id) assert(id == 1); return progress end,
}
setup.init("rich-match")
assert(option("rich").pending == 1)
assert(setup.select_mode(1, "rich", "rich-match").error == "mode_profile_pending")
progress = {loaded=true,clear_counts={n10=99}}
assert(option("rich").pending == 1)
assert(option("rich").unlock_hint:find("服务尚未就绪",1,true))
assert(setup.select_mode(1,"rich","rich-match").error=="mode_profile_pending",
    "old backend capability cannot be inferred from a standard N10 alone")
progress = {loaded=true,clear_counts={n10=99},standard_clear_counts={},rich_clear_counts={}}
assert(option("rich").unlocked == 0)
assert(setup.select_mode(1, "rich", "rich-match").error == "mode_not_unlocked",
    "an explicit empty provenance map prevents historical mixed-counter fallback")
for _, invalid in ipairs({true,"1",-1,0,0.5,math.huge}) do
    progress.standard_clear_counts.n3 = invalid
    assert(setup.select_mode(1, "rich", "rich-match").error == "mode_not_unlocked")
end
progress = {loaded=true,clear_counts={n3=1},rich_clear_counts={}}
assert(option("rich").unlocked == 1,
    "existing authoritative pre-mode history remains eligible")
assert(setup.select_mode(1, "rich", "rich-match").ok)
assert(setup.is_rich_mode() and setup.get_mode() == "rich" and setup.get_profile_mode() == "standard")
assert(setup.select_mode(1, "rich", "rich-match").ok)
assert(setup.select_mode(1, "standard", "rich-match").error == "mode_locked")
local rules = require("config/mode_progression")
local difficulty = require("config/difficulty_config")
assert(difficulty.is_unlocked("N4", progress, "rich") and not difficulty.is_unlocked("N5", progress, "rich"),
    "normal released modes retain their independent sequential difficulty gate")
progress.rich_clear_counts.n4 = 1
assert(difficulty.is_unlocked("N5", progress, "rich") and not difficulty.is_unlocked("N6", progress, "rich"))
for _, advanced in ipairs({"cold"}) do
    local session = advanced .. "-match"
    setup.init(session)
    local field, parent = rules.clear_field(advanced), rules.clear_field(rules.parent_mode(advanced))
    progress = {loaded=true, clear_counts={n10=99}, standard_clear_counts={n10=99},
        rich_clear_counts={}, cold_clear_counts={}, scourge_clear_counts={}}
    progress[field].n10 = 99
    assert(option(advanced).unlocked == 0 and option(advanced).pending == 0,
        "neither ordinary nor same-mode N10 can replace the exact N5 entry clear")
    local denial = setup.select_mode(1, advanced, session)
    assert(denial.error == "mode_not_unlocked" and denial.unlock_hint == rules.entry_hint(advanced))
    progress[field] = nil
    progress[parent].n5 = 1
    assert(option(advanced).pending == 1 and setup.select_mode(1, advanced, session).error == "mode_profile_pending",
        "an exact entry victory cannot imply missing backend mode support")
    progress[field] = {}
    assert(option(advanced).unlocked == 1 and option(advanced).pending == 0)
    assert(setup.select_mode(1, advanced, session).ok)
    assert(setup.get_mode() == advanced and setup.get_profile_mode() == "standard")
    assert(setup.select_mode(1, advanced, session).ok, "same advanced selection remains idempotent")
    assert(setup.select_mode(1, "standard", session).error == "mode_locked")
end
setup.init("daily-quota-match")
local daily = {day_key=tostring(require("systems/archive_calendar").day()),
    by_key={clear={key="clear",limit=3,earned=3,remaining=0,capped=1}}}
package.loaded["systems/player_profile_service"].get_authenticated_daily_limits = function(id)
    assert(id == 1); return daily
end
assert(option("standard").daily_capped == 1)
assert(setup.select_mode(1, "standard", "daily-quota-match").error == "mode_daily_limit_reached")
daily.by_key.clear = {key="clear",limit=3,earned=2,remaining=1,capped=0}
assert(setup.select_mode(1, "standard", "daily-quota-match").ok,
    "normal mode admission uses the current authoritative daily quota")
package.loaded["systems/player_profile_service"] = nil
setup.init("match-two")
assert(not setup.is_mode_selected() and setup.get_session_id() == "match-two")
assert(setup.get_profile_mode() == nil and not setup.is_fishing_mode(), "new sessions clear both gameplay and profile modes")
host = 2 -- Spectators cannot choose, even if an engine host flag is present.
assert(setup.selector_player_id() == -1)
GameRules.PlayerHasCustomGameHostPrivileges = nil
assert(setup.selector_player_id() == -1, "normal lobby fails closed when host is unknown")
tools = true
assert(setup.selector_player_id() == 0, "Workshop launch can use its first real player")
players[0].fake = true
assert(setup.selector_player_id() == 1)
players[1].connected = 3
assert(setup.selector_player_id() == -1)
print("MATCH_SETUP_SERVICE_PASS: host authority, immutable mode, session reset, spectator/bot and Tools handling")
