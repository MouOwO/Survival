package.path = "scripts/vscripts/?.lua;" .. package.path
local sent, requests, callbacks, clock, accounts = {}, {}, {}, 10, { [0] = "42", [1] = "43" }
local provider = { resolve_account_id = function(id) return accounts[id] end }
provider.endless_leaderboard = function(payload, success, failure)
    requests[#requests + 1] = payload
    callbacks[#callbacks + 1] = { success = success, failure = failure }
end
package.loaded["systems/player_profile_service"] = { get_provider = function() return provider end }
Time = function() return clock end
GameRules = { GetGameTime = function() return 0 end }
PlayerResource = {
    IsValidPlayerID = function(_, id) return accounts[id] ~= nil end,
    GetPlayer = function(_, id) return accounts[id] and { id = id } or nil end,
}
CustomGameEventManager = {
    RegisterListener = function(_, name, fn) assert(name == "survival_leaderboard_request") end,
    Send_ServerToPlayer = function(_, player, name, data)
        assert(name == "survival_leaderboard_result")
        sent[#sent + 1] = { player_id = player.id, data = data }
    end,
    Send_ServerToAllClients = function() error("leaderboard_must_never_broadcast") end,
}
local service = require("systems/endless_leaderboard_service")
local revision = string.rep("a", 64)
local function reset()
    service.init();sent, requests, callbacks = {}, {}, {};clock = clock + 1
end
local function request(id, known)
    service.request({ PlayerID = id or 0, request_id = "leaderboard_request_001", known_revision = known,
        account_id = "999999", player_id = 1 })
end
local function result(count, own)
    local value = { ok = true, revision = revision, total = count, self_steam_id = own or "76561197960265770", entries = {} }
    for index = 1, count do
        value.entries[index] = { rank = index, entry_id = string.format("00000000-0000-4000-8000-%012d", index),
            steam_id = "", display_name = "untrusted fallback", best_floor = 1001 - index, endless_score = 1000 + index,
            private_profile = "must never be sent" }
    end
    if count > 1 then value.entries[2].steam_id = value.self_steam_id end
    return value
end
local checks = 0
local function check(name, run)
    reset();run();checks = checks + 1;print("PASS " .. name)
end
check("100 authoritative entries, source identity only, no broadcast or private fields", function()
    request();assert(#requests == 1 and requests[1].account_id == "42" and requests[1].revision == "")
    callbacks[1].success(result(100));assert(#sent == 102)
    assert(sent[1].data.phase == "begin" and sent[102].data.phase == "end" and sent[102].data.listed == 1)
    for _, packet in ipairs(sent) do
        assert(packet.player_id == 0 and packet.data.self_steam_id == "76561197960265770")
        local row = packet.data.row
        if row then assert(row.private_profile == nil);if row.steam_id == "" then assert(row.display_name == "玩家资料待同步") end end
    end
end)
check("unchanged revision sends one packet without rows", function()
    request(0, revision)
    callbacks[1].success({ ok = true, unchanged = true, revision = revision, total = 100,
        self_steam_id = "76561197960265770", self = { listed = false } })
    assert(#sent == 1 and sent[1].data.phase == "unchanged" and sent[1].data.listed == 0)
end)
check("zero valid progress is an empty successful board", function()
    request();callbacks[1].success(result(0));assert(#sent == 2 and sent[2].data.total == 0 and sent[2].data.listed == 0)
end)
check("invalid account or missing player cannot impersonate requester", function()
    request(8);assert(#requests == 0 and #sent == 0)
    service.request({ PlayerID = 0, request_id = "bad<>" });assert(#requests == 0)
end)
check("malformed or unsorted backend data never sends a partial board", function()
    local cases = {
        function(v) v.self_steam_id = "76561197960265771" end,
        function(v) v.entries[2].entry_id = v.entries[1].entry_id end,
        function(v) v.entries[2].best_floor = 9007199254740992 end,
        function(v) v.entries[2].endless_score = 0/0 end,
        function(v) v.entries[2].rank = 4 end,
        function(v) v.entries[2].best_floor = v.entries[1].best_floor;v.entries[2].endless_score = v.entries[1].endless_score + 1 end,
    }
    for _, mutate in ipairs(cases) do
        reset();request();local value = result(3);mutate(value);callbacks[1].success(value)
        assert(#sent == 1 and sent[1].data.phase == "error")
    end
end)
check("paused game time does not block real-time throttling", function()
    request();callbacks[1].success(result(1));clock = clock + 1;request();assert(#requests == 2)
end)
check("inflight spam is bounded and recoverable", function()
    request();request();assert(#requests == 1 and #sent == 1 and sent[1].data.phase == "error")
    callbacks[1].failure("private error");clock = clock + 1;request();assert(#requests == 2)
end)
check("reconnected identity ignores stale responses and can request again", function()
    request();accounts[0] = "44";request();assert(#requests == 2)
    callbacks[1].success(result(1));assert(#sent == 0)
    callbacks[2].success(result(1, "76561197960265772"));assert(#sent == 3)
    accounts[0] = "42"
end)
check("module reinitialization invalidates old callbacks", function()
    request();local old = callbacks[1];service.init();old.success(result(1));assert(#sent == 0)
end)
check("Steam64 conversion is precise at the largest account32", function()
    accounts[0] = "4294967295";request();callbacks[1].success(result(1, "76561202255233023"))
    assert(#sent == 3 and sent[3].data.self_steam_id == "76561202255233023");accounts[0] = "42"
end)
check("large counters cross the native event boundary as exact decimal text", function()
    request();local value = result(1)
    value.entries[1].best_floor, value.entries[1].endless_score = 9007199254740991, 9007199254740991
    callbacks[1].success(value)
    assert(#sent == 3 and sent[2].data.row.best_floor == "9007199254740991"
        and sent[2].data.row.endless_score == "9007199254740991")
end)
print("ENDLESS_LEADERBOARD_TRANSPORT_PASS " .. checks .. " groups")
