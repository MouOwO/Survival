package.path = "scripts/vscripts/?.lua;" .. package.path
local profile = require("tests/development_release_profile")
-- Keep this test independent of the owner's local four-account admission list.
package.loaded["config/test_access"] = { enabled = false }
local bus, events = require("core/event_bus"), require("core/events")
local chat, chat_registrations, scale_registrations = nil, 0, 0
ListenToGameEvent = function(name, callback)
    assert(name == "player_chat")
    chat_registrations = chat_registrations + 1
    chat = callback
end
CustomGameEventManager = { RegisterListener = function(_, name)
    assert(name == "survival_scale_selection_changed")
    scale_registrations = scale_registrations + 1
end }
PlayerResource = {
    IsValidPlayerID = function(_, id) return id == 0 end,
    GetTeam = function() return 2 end,
}
local grants = {}
bus.handle_request(events.RESOURCE_ADD_REQUEST, function(request)
    grants[#grants + 1] = request
    return { ok = true }
end)
local cheats = require("debug/cheat_command_service")
cheats.init()
cheats.init()
assert(chat_registrations == 1 and scale_registrations == 1,
    "enabling local cheats again must not register duplicate callbacks")
chat({ playerid = 0, text = "-addgold 500" })
assert(#grants == 1 and grants[1].gold == 500 and grants[1].wood == 0)
assert(grants[1].reason == "cheat_addgold")
profile.channel = "production"
chat({ playerid = 0, text = "-addgold 500" })
assert(#grants == 1, "registered callbacks must still respect a revoked profile")
profile.channel = "development"
cheats.init()
assert(chat_registrations == 1 and scale_registrations == 1)
chat({ playerid = 0, text = "-addwood 250" })
assert(#grants == 2 and grants[2].wood == 250 and grants[2].gold == 0)
IsInToolsMode = function() return false end
chat({ playerid = 0, text = "-addgold 500" })
assert(#grants == 2, "development still cannot grant resources outside Tools")
print("CHEAT_INIT_IDEMPOTENT_PASS")
