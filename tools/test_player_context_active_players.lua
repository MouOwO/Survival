package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

DOTA_TEAM_GOODGUYS = 2
PlayerResource = {
    IsValidPlayerID = function(_, player_id) return player_id ~= 3 end,
    GetPlayer = function(_, player_id) return player_id ~= 2 and {} or nil end,
    GetTeam = function(_, player_id) return player_id == 1 and 3 or DOTA_TEAM_GOODGUYS end,
}

local context = require("systems/player_context_service")
context._reset_for_test()
local active = context.active_player_ids()
assert(#active == 1 and active[1] == 0,
    "active players must require configured range, valid ID, player entity, and good-guys team")
print("PLAYER_CONTEXT_ACTIVE_PLAYERS_LUA51_PASS")