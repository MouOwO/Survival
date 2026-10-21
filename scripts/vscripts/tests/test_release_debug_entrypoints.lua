package.path = "scripts/vscripts/?.lua;" .. package.path
local profile = require("config/release_profile")
assert(profile.channel == "production")
IsServer, IsInToolsMode = function() return true end, function() return true end
GameRules = {IsCheatMode=function() return true end}
local bus, events = require("core/event_bus"), require("core/events")
local calls, chat, listeners = 0, nil, {}
local function poison() calls = calls + 1; error("production reached a mutating dependency") end
local payload = setmetatable({}, {__index=poison})
ListenToGameEvent = function(name, callback)
    calls = calls + 1
    if name == "player_chat" then chat = callback end
end
CustomGameEventManager = {RegisterListener=function(_, name, callback)
    calls = calls + 1; listeners[name] = callback
end}
Convars = {RegisterCommand=function(_, name)
    -- This command only records scheduler timing; it is not a gameplay grant.
    if name ~= "survival_perf_capture" then poison() end
end}
local cheats = require("debug/cheat_command_service")
cheats.init()
require("debug/payment_test_commands").init()
require("combat/combat_debug_command").init(nil, {debug_enabled=true})
assert(calls == 0 and chat == nil and next(listeners) == nil,
    "production never registers chat, scale selection or combat test commands")

local checked = 0
local function denied_result(callback, ...)
    local result = callback(...)
    assert(type(result) == "table" and result.ok == false
        and result.error == "release_debug_disabled")
    checked = checked + 1
end
local function denied_pair(callback, ...)
    local ok, reason = callback(...)
    assert(ok == false and reason == "release_debug_disabled", tostring(reason))
    checked = checked + 1
end
local function upvalue(callback, wanted)
    for index = 1, 100 do
        local name, value = debug.getupvalue(callback, index)
        if name == wanted then return value end
        if name == nil then break end
    end
    error("missing production callback upvalue " .. wanted)
end
for _, row in ipairs({
    {"systems/resource_system", "handle_debug_set"},
    {"systems/shop_system", "set_debug_unlock"},
    {"systems/hero_combat_stat_service", "debug_set_attack"},
    {"systems/weapon_growth_service", "debug_add"},
    {"systems/hero_summon_system", "delete_hero"},
}) do
    denied_result(upvalue(require(row[1]).init, row[2]), payload)
end
require("debug/technology_cheat_handler").register({}, poison)
denied_result(function() return bus.request(events.TECHNOLOGY_CHEAT_SET_REQUEST, payload) end)
denied_result(require("systems/rogue_reward_service").debug_offer, nil, payload)
denied_result(upvalue(require("systems/hero_summon_system").init, "summon"),
    {debug_bypass=true, player_id=0, hero_id="hero_doom"})
local wave = require("systems/wave_system")
denied_pair(wave.debug_spawn_wave, nil, payload)
denied_pair(wave.set_dev_mode, true)
if wave.debug_clear_wave_for_comparison then denied_result(wave.debug_clear_wave_for_comparison) end
denied_pair(require("debug/dev_wall_stats").enable, payload)
assert(require("debug/dev_wall_stats").apply(payload) == false)
denied_pair(require("debug/health_cheat").apply, payload, "100000")
denied_pair(require("debug/attack_speed_cheat").set_rate, 0, 100)
denied_pair(require("debug/attack_speed_cheat").execute, payload)
denied_pair(require("debug/dev_asset_preload").start, payload)
denied_pair(require("debug/armor_engine_diagnostic").run, payload)
denied_pair(require("debug/research_technology_test").run)
for _, method in pairs(require("debug/weapon_cheat_handlers")) do
    if type(method) == "function" then denied_pair(method, payload) end
end
for _, method in pairs(cheats._test) do denied_pair(method, payload) end
local stats = require("systems/player_gameplay_stats_order_service")
denied_result(stats.order, nil, nil, nil)
denied_result(stats.test_order, nil, nil, nil)
denied_result(stats.reset_defaults, nil)
denied_result(stats.apply_packet, payload)
local archive = require("systems/archive_service")
for _, name in ipairs({"cheat", "xinyang", "yitie", "zaixian"}) do
    denied_pair(archive[name], payload)
end
local reset_ok, reset_error = require("systems/payment_service").reset_player(payload, "refreshdata")
assert(reset_ok == false and reset_error == "test_reset_disabled")
assert(calls == 0, "denials must precede grants, registrations, state reads and HTTP")

-- A captured callback cannot retain permission after a development world is
-- revoked. Client debug fields, host privileges and sv_cheats stay irrelevant.
profile.channel = "development"
cheats.init()
local development_chat, scale = chat, listeners.survival_scale_selection_changed
assert(type(development_chat) == "function" and type(scale) == "function")
require("debug/payment_test_commands").init()
local payment_chat = chat
assert(type(payment_chat) == "function" and payment_chat ~= development_chat)
local commands = upvalue(development_chat, "COMMANDS")
local count = calls
profile.channel = "production"
for command in pairs(commands) do
    development_chat({playerid=0, text=command .. " 999999999", debug=true,
        debug_bypass=true, test_only=true, admin=true})
    checked = checked + 1
end
for _, command in ipairs({"monster15", "pass100", "0"}) do
    development_chat({playerid=0, text=command})
end
scale(nil, payload)
payment_chat({playerid=0, text="refreshdata"})
payment_chat({playerid=0, text="refreshmoney"})
assert(calls == count, "captured callbacks recheck the trusted build policy")
-- The normal client route remains usable in production and discards attacker
-- supplied debug/price/identity fields instead of forwarding a whole payload.
bus.reset()
local routed
PlayerResource = {IsValidPlayerID=function(_, id) return id == 0 end,
    GetPlayer=function() return {} end}
CustomGameEventManager.Send_ServerToPlayer = function() end
bus.handle_request(events.HERO_SUMMON_REQUEST, function(request)
    routed = request
    return {ok=false, error="ordinary locked hero"}
end)
require("ui/hero_summon_ui_service").init()
listeners.ui_hero_summon_request(nil, {PlayerID=0, player_id=9,
    hero_id="hero_doom", debug_bypass=true, debug=true, test_only=true,
    admin=true, amount=999999})
assert(routed and routed.player_id == 0 and routed.hero_id == "hero_doom")
local fields = 0
for key in pairs(routed) do
    fields = fields + 1
    assert(key == "player_id" or key == "hero_id", "client extra field leaked: " .. key)
end
assert(fields == 2, "production normal summon keeps its existing field allowlist")
profile.channel = "production"
print("RELEASE_DEBUG_ENTRYPOINTS_PASS checked=" .. checked
    .. " production plus Tools/sv_cheats, dedicated handlers and revoked callbacks")
