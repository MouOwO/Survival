package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path
local helper_path = assert(arg[1])
local nonce = string.rep("a", 24)
local output, callbacks, registrations, authenticated, loaded = {}, {}, 0, 0, 0
local tools, server, map, scale, token = true, true, "template_map", 1, "present"
local mode = { IsNull = function() return false end }
IsServer = function() return server end
IsInToolsMode = function() return tools end
GetMapName = function() return map end
LoadKeyValues = function() error("inspection must never load KV") end
GameRules = { GetGameModeEntity = function() return mode end }
DOTA_MAX_TEAM_PLAYERS = 6
DOTA_TEAM_SPECTATOR = 1
Convars = {
    SetStr = function() error("inspection must never change convars") end,
    GetStr = function(_, name) assert(name == "survival_fishing_api_token"); return token end,
    GetFloat = function(_, name) assert(name == "host_timescale"); return scale end,
    RegisterCommand = function(_, name, callback)
        registrations = registrations + 1
        callbacks[name] = callback
    end,
}
local players = {
    [0] = { account = 123, team = 2 },
    [1] = { account = 456, team = 2, fake = true },
    [2] = { account = 789, team = 1 },
    [3] = { account = 234, team = 2, absent = true },
    [4] = { account = 0, team = 2 },
    [5] = { account = 345, team = 2 },
}
PlayerResource = {
    IsValidPlayerID = function(_, id) return players[id] ~= nil end,
    IsFakeClient = function(_, id) return players[id].fake == true end,
    GetTeam = function(_, id) return players[id].team end,
    GetPlayer = function(_, id) return not players[id].absent and players[id] or nil end,
    GetSteamAccountID = function(_, id) return players[id].account end,
}
package.loaded["systems/player_profile_service"] = {
    is_authenticated_for_account = function(id, account)
        assert(account == tostring(players[id].account)); authenticated = authenticated + 1; return id == 0
    end,
    is_loaded_for_account = function(id, account)
        assert(account == tostring(players[id].account)); loaded = loaded + 1; return id == 5
    end,
    get_profile = function() error("inspection must never copy profiles") end,
}
package.loaded["systems/match_setup_service"] = { get_session_id = function() return "current-match-session" end }
local party = false
package.loaded["systems/startup_loading_service"] = { is_party_waiting = function() return party end }
local encoder = require("core/json_encoder")
print = function(line) output[#output + 1] = line end
local M = dofile(helper_path)
assert(registrations == 0 and #output == 0, "loading installs no timer/command")
assert(M.prepare() == true and registrations == 1)
local native = callbacks[M.command]
native("", nonce)
local state = M.read_state()
assert(state.status == "configured" and state.players == 2 and state.authenticated == 1 and state.loaded == 1)
assert(output[#output] == "GOUFAYU_HAMMER_STATE:" .. nonce .. ":" .. encoder.encode(state))
assert(authenticated == 4 and loaded == 4, "only two real current owners receive scalar checks")
assert(M.prepare() == true and registrations == 1, "healthy repeats do not re-register")
local before = #output
for _, bad in ipairs({ "", string.rep("a", 23), string.rep("A", 24), nonce .. ";quit" }) do
    native("", bad)
end
native("", nonce, "extra")
assert(#output == before, "nonce command accepts no source or extra arguments")
party = true
assert(M.read_state().status == "waiting_for_party")
party = false; token = ""
assert(M.read_state().status == "authentication_required")
token = nil
assert(M.read_state().status == "waiting_for_map")
token = "present"
local expected = { { "tools", false }, { "server", false }, { "map", "other_map" }, { "scale", 0.5 } }
for _, pair in ipairs(expected) do
    if pair[1] == "tools" then tools = pair[2] end
    if pair[1] == "server" then server = pair[2] end
    if pair[1] == "map" then map = pair[2] end
    if pair[1] == "scale" then scale = pair[2] end
    assert(M.read_state().status == "waiting_for_map", "original capability gate is retained")
    tools, server, map, scale = true, true, "template_map", 1
end
mode = { IsNull = function() return false end }
local previous = loaded
native("", nonce)
assert(loaded == previous and output[#output]:find("inspection_not_installed", 1, true),
    "an old world callback cannot read a new world's profile until explicitly rebound")
assert(M.prepare() == true and registrations == 1)
native("", nonce)
assert(loaded == previous + 2)
local next_M = dofile(helper_path)
M.read_state = function() error("old module must not run") end
assert(next_M.prepare() == true and registrations == 1)
native("", nonce)
assert(not output[#output]:find("inspection_failed", 1, true), "native callback resolves the latest module API")
callbacks[next_M.command] = nil
assert(next_M.prepare(true) == true and registrations == 2 and callbacks[next_M.command])
local register = Convars.RegisterCommand
Convars.RegisterCommand = function() return false end
assert(next_M.prepare(true) == false, "failed native registration cannot claim installed")
Convars.RegisterCommand = register
mode = nil
assert(next_M.prepare() == false)
tools = false
assert(next_M.prepare() == false and next_M.dispatch(nonce) == false)
io.write("PASS Tools bridge static inspection: guards, scoped nonce, account bools, map/reload/rebuild lifecycle\n")
