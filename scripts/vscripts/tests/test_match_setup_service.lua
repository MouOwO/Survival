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
assert(setup.selector_player_id() == 1, "host is not necessarily player zero")
assert(setup.select_mode(0, "pure", "match-one").error == "selection_not_host")
assert(setup.select_mode(1, "pure", "old-match").error == "match_session_mismatch")
assert(setup.select_mode(1, "cheat", "match-one").error == "mode_not_found")
assert(setup.select_mode(1, "pure", "match-one").ok)
assert(setup.select_mode(1, "pure", "match-one").ok, "same choice is idempotent")
assert(setup.select_mode(1, "standard", "match-one").error == "mode_locked")
assert(setup.select_mode(2, "pure", "match-one").error == "selection_not_host")
local snapshot = setup.snapshot()
snapshot.mode_options[1].display_name = "tampered"
assert(setup.snapshot().mode_options[1].display_name == "纯净模式")
setup.init("match-two")
assert(not setup.is_mode_selected() and setup.get_session_id() == "match-two")
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
