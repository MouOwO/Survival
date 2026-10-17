package.path = "scripts/vscripts/?.lua;" .. package.path
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
assert(setup.snapshot().mode_options[1].display_name == "纯净模式")
assert(#setup.snapshot().mode_options == 4)
assert(setup.snapshot().mode_options[3].mode_id == "fishing"
    and setup.snapshot().mode_options[3].display_name == "摸鱼模式")
setup.init("fishing-match")
assert(setup.select_mode(0, "fishing", "fishing-match").error == "selection_not_host")
assert(setup.select_mode(1, "fishing", "old-match").error == "match_session_mismatch")
assert(setup.select_mode(1, "fishing", "fishing-match").ok)
assert(setup.get_mode() == "fishing" and setup.is_fishing_mode())
assert(setup.get_profile_mode() == "standard", "idle gameplay uses the existing regular HTTP profile contract")
assert(setup.snapshot().mode_id == "fishing", "the HUD still sees the actual selected gameplay mode")
assert(setup.select_mode(1, "fishing", "fishing-match").ok, "idle selection is idempotent")
assert(setup.select_mode(1, "pure", "fishing-match").error == "mode_locked")
assert(setup.select_mode(1, "standard", "fishing-match").error == "mode_locked")
setup.init("standard-match")
assert(setup.select_mode(1, "standard", "standard-match").ok)
assert(setup.get_profile_mode() == "standard" and not setup.is_fishing_mode())
local progress
package.loaded["systems/player_profile_service"] = {
    get_authenticated_progression = function(id) assert(id == 1); return progress end,
}
setup.init("rich-match")
assert(setup.snapshot().mode_options[4].mode_id == "rich")
assert(setup.snapshot().mode_options[4].pending == 1)
assert(setup.select_mode(1, "rich", "rich-match").error == "rich_progression_pending")
progress = {loaded=true,clear_counts={n10=99}}
assert(setup.snapshot().mode_options[4].pending == 1)
assert(setup.snapshot().mode_options[4].unlock_hint:find("服务尚未就绪",1,true))
assert(setup.select_mode(1,"rich","rich-match").error=="rich_progression_pending",
    "old backend capability cannot be inferred from a standard N10 alone")
progress = {loaded=true,clear_counts={n10=99},standard_clear_counts={},rich_clear_counts={}}
assert(setup.snapshot().mode_options[4].unlocked == 0)
assert(setup.select_mode(1, "rich", "rich-match").error == "rich_mode_locked",
    "an explicit empty provenance map prevents historical mixed-counter fallback")
for _, invalid in ipairs({true,"1",-1,0,0.5,math.huge}) do
    progress.standard_clear_counts.n10 = invalid
    assert(setup.select_mode(1, "rich", "rich-match").error == "rich_mode_locked")
end
progress = {loaded=true,clear_counts={n10=1},rich_clear_counts={}}
assert(setup.snapshot().mode_options[4].unlocked == 1,
    "existing authoritative pre-mode history remains eligible")
assert(setup.select_mode(1, "rich", "rich-match").ok)
assert(setup.is_rich_mode() and setup.get_mode() == "rich" and setup.get_profile_mode() == "standard")
assert(setup.select_mode(1, "rich", "rich-match").ok)
assert(setup.select_mode(1, "standard", "rich-match").error == "mode_locked")
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
