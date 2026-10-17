-- Real roster, dispatcher, archive queue and reducer; in-memory account/HTTP
-- fixtures only. No production requests, rewards or player saves are written.
package.path = "scripts/vscripts/?.lua;" .. package.path
local bus, events = require("core/event_bus"), require("core/events")
local scheduler = require("core/scheduler")
local context = require("systems/player_context_service")
local multiplayer = require("systems/multiplayer_player_service")
local schema = require("config/generated/player_gameplay_stats")
local calendar = require("systems/archive_calendar")
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}; for key, child in pairs(value) do result[key] = copy(child) end; return result
end
local clock, profiles, requests, receipts, fake, teams, blocked = 0, {}, {}, {}, {}, {}, {}
local checks, delivered, errors = 0, 0, {}
local report = print
print = function(message)
    message = tostring(message)
    if message:find("handler error", 1, true) or message:find("task failed", 1, true) then
        errors[#errors + 1] = message
    end
end
DOTA_TEAM_GOODGUYS = 2
GameRules = {GetGameTime = function() return clock end}
RandomInt = function(a) return a end
PlayerResource = {
    GetPlayer = function(_, id) return id >= 0 and id <= 3 and id or nil end,
    IsValidPlayerID = function(_, id) return id >= 0 and id <= 3 end,
    IsFakeClient = function(_, id) return fake[id] == true end,
    GetTeam = function(_, id) return teams[id] or 2 end,
}
CustomGameEventManager = {RegisterListener = function() end, Send_ServerToPlayer = function() end}
local provider = {archive_enabled = function() return false end}
package.loaded["systems/player_profile_service"] = {
    get_account_profile = function(id) return copy(profiles[id]) end,
    get_provider = function() return provider end,
}
package.loaded["systems/title_presentation_service"] = {
    init = function() end, rows = function() return {} end, preview_mode = function() return false end,
}
package.loaded["systems/online_time_service"] = {disconnect = function() end}
local archive = require("systems/archive_service")
local cooperative = require("systems/archive_cooperative_reward_service")
local reducer = require("systems/archive_settlement")
local function profile()
    local value = {revision = 1, save = {gameplay_stats = {}, content_inventory = {}}, entitlements = {}}
    for _, row in ipairs(schema.rows) do value.save.gameplay_stats[row.field_id] = row.default_value end
    return value
end
function provider.submit(id, command, complete)
    requests[#requests + 1] = {player_id = id, command = copy(command), reference = command}
    assert(command.drops == nil and command.has_pass == nil and command.vip == nil,
        "team dispatcher cannot send another account's drops or paid identity")
    if blocked[id] or not profiles[id] then complete({ok = false, error = "profile_not_loaded"}); return end
    local key = id .. ":" .. command.id
    local result = receipts[key]
    if not result then
        result = reducer.settle(profiles[id], command, calendar.has_pass(profiles[id]))
        assert(result.ok, result.error)
        profiles[id].save.archive, profiles[id].save.gameplay_stats = result.archive, result.gameplay_stats
        profiles[id].revision = profiles[id].revision + 1
        delivered = delivered + 1
        receipts[key] = copy(result)
    end
    complete({ok = true})
end
local function check(value, message) checks = checks + 1; assert(value, message) end
local function tick(delta)
    clock = clock + (delta or 1)
    scheduler.think()
end
local function fresh(ids)
    bus.reset(); scheduler.clear(); multiplayer._reset_for_test(); context._reset_for_test()
    clock, profiles, requests, receipts, fake, teams, blocked = 0, {}, {}, {}, {}, {}, {}
    delivered, errors = 0, {}
    for id = 0, 3 do multiplayer.mark_connected(id); profiles[id] = profile() end
    archive.init(); archive.set_clock(function() return 1700000000 end); archive.set_provider(provider)
    cooperative.init()
    if ids then check(cooperative.begin(ids, "N10"), "valid frozen roster") end
end
local function flush_all()
    cooperative.flush_endless_rewards()
    for _ = 1, 40 do
        local pending = cooperative.has_pending()
        for id = 0, 3 do pending = pending or archive.has_pending(id) end
        if not pending then return end
        tick(1)
    end
    error("fixture rewards failed to drain")
end

fresh()
check(not cooperative.begin({0}, "N0") and not cooperative.begin({0}, "N21"),
    "invalid match difficulty cannot freeze an unusable roster")
check(not cooperative.record_challenge(0, "social_ex", 1, "N10").ok,
    "empty/uninitialized roster cannot fall back to every active player")
fake[3], teams[2] = true, 3
check(cooperative.begin({0, 1, 1, 2, 3, 4, -1}, "N10"), "trusted roster filters invalid entries")
check(not cooperative.record_challenge(3, "social_ex", 1, "N10").ok, "fake client cannot source rewards")
check(not cooperative.record_challenge(2, "social_ex", 1, "N10").ok, "enemy team cannot source rewards")
check(not cooperative.record_challenge(4, "social_ex", 1, "N10").ok, "outside roster cannot source rewards")
check(not cooperative.record_challenge(0, "social_ex", 1, "N9").ok, "difficulty cannot be substituted")
check(not cooperative.record_challenge(0, "missing", 1, "N10").ok, "unknown challenge cannot claim a team event")
check(not cooperative.record_challenge(0, "social_ex", 100001, "N10").ok,
    "invalid kill sequence rejected before it can poison the shared event identity")
check(not cooperative.record_endless_wave(0, 1001, 10).ok, "out-of-config layer cannot claim a team event")
check(not cooperative.record_endless_wave(0, "1", 10).ok, "invalid wave type rejected before claiming event")
check(cooperative.record_challenge(0, "social_ex", 1, "N10").recipients == 2,
    "two legitimate winners each own a complete reward")
check(#requests == 2 and delivered == 2, "deduplicated roster and no rewards to excluded clients")
check(requests[1].command.id == requests[2].command.id
    and requests[1].command.kill_sequence == requests[2].command.kill_sequence
    and requests[1].command.day_key == requests[2].command.day_key,
    "shared event identity and date are equal across accounts")
check(requests[1].reference ~= requests[2].reference, "account commands have separate mutable objects")
check(cooperative.record_challenge(1, "social_ex", 99, "N10").duplicate
    and #requests == 2, "another summoner cannot reroll or multiply the same challenge")

fresh()
multiplayer.defeat(2, "fixture_defeated")
fake[3] = true
check(cooperative.begin({0, 1, 2, 3}, "N10"), "roster excludes defeated participants")
check(not cooperative.record_challenge(2, "social_ex", 1, "N10").ok,
    "defeated participant cannot generate a team reward")
check(cooperative.record_challenge(0, "social_ex", 1, "N10").recipients == 2,
    "defeated and fake teammates do not obtain new rewards")
multiplayer.mark_disconnected(0)
check(not cooperative.record_endless_wave(0, 1, 10).ok,
    "a disconnected source cannot claim a layer on behalf of the team")
multiplayer.mark_connected(0)

fresh({0, 1, 2, 3})
profiles[0].entitlements.archive_pass = {active = true, expires_at = 1700000600}
profiles[1].entitlements.vip = {active = true, level = 12}
profiles[2].entitlements.archive_pass = {active = true, expires_at = 1699999999}
profiles[3] = nil
check(cooperative.record_challenge(0, "cage_1", 8, "N10").recipients == 4,
    "profile-not-ready is still a participant and receives a queued intent")
check(archive.has_reward_pending(3, "challenge", "cage_1") and not cooperative.has_pending(),
    "archive queue owns delayed profile retries; dispatcher need not keep polling the account")
local function cage_count(id)
    local total = 0; for _, count in pairs(profiles[id].save.archive.cage_counts or {}) do total = total + count end
    return total
end
check(cage_count(0) == 2 and cage_count(1) == 1 and cage_count(2) == 1,
    "only each account's active monthly pass adds an item; VIP-only/expired pass cannot borrow it")
multiplayer.mark_disconnected(3)
profiles[3] = profile(); archive._test.flush(3)
check(cage_count(3) == 1 and not archive.has_pending(3),
    "disconnect never discards an already-earned intent, even when profile loads later")
check(cooperative.record_challenge(0, "social_friend", 9, "N10").recipients == 3,
    "disconnected teammate earns no new event")
check((profiles[3].save.archive.social_tickets or {}).yitie == nil, "offline player did not gain new ticket")
multiplayer.mark_connected(3)
check(cooperative.record_challenge(3, "social_friend", 10, "N10").duplicate,
    "reconnect does not replay old events to add another team share")
blocked[1] = true
cooperative.record_challenge(0, "social_beast", 11, "N10")
check(archive.has_reward_pending(1, "challenge", "social_beast"), "transient failure remains queued")
check(cooperative.record_challenge(2, "social_beast", 12, "N10").duplicate,
    "save retry and second summoner do not create another reward")
blocked[1] = nil; archive._test.flush(1)
for id = 0, 3 do
    check(profiles[id].save.archive.social_tickets.blessing_ticket == 1, "full independent base share " .. id)
end

fresh({0, 1, 2, 3})
for wave = 1, 100 do
    check(cooperative.record_endless_wave(0, wave, 10).recipients == 4, "new team layer awards four complete shares")
    if wave <= 60 then
        check(cooperative.record_endless_wave(1, wave, 10).duplicate,
            "second independent run's same layer never multiplies the team score")
    end
end
check(#requests == 0, "endless team fanout retains the five-second batching delay")
flush_all()
for id = 0, 3 do
    check(profiles[id].save.archive.endless_score == 3250
        and profiles[id].save.archive.endless_best_wave == 100,
        "team highest 100 gives each account 3250, rather than summing the two runs")
    check(not archive.has_pending(id), "terminal flush includes every recipient")
end
check(delivered == 400, "each account owns exactly one receipt per successful layer")

fresh({0, 1, 2, 3})
local original_record = archive.record_challenge
blocked[1] = true
archive.record_challenge(1, "social_friend", 19, "N10")
archive.record_challenge = function(id, ...)
    if id == 1 then return nil end
    return original_record(id, ...)
end
cooperative.record_challenge(0, "social_ex", 20, "N10")
check(cooperative.has_pending() and not archive.has_reward_pending(1, "challenge", "social_ex"),
    "nil without exact queue evidence remains in the outbox despite an unrelated pending command")
check(profiles[0].save.archive.social_tickets.invitation == 1
    and profiles[2].save.archive.social_tickets.invitation == 1,
    "one account's exception cannot stop the other complete shares")
archive.record_challenge = original_record
blocked[1] = nil
tick(1)
check(not cooperative.has_pending() and profiles[1].save.archive.social_tickets.invitation == 1,
    "retry successfully hands off the missing account with the same event")
check(delivered == 5, "each shared receipt plus the unrelated ticket occurs once during retry")
-- A wife challenge is a new team event and owns an independent daily currency.
fresh({0, 1, 2, 3})
local wife_rule=assert(require("config/generated/archive_social_rules").by_id.wife,
    "wife challenge needs its own configured social pool")
check(wife_rule.daily_limit==10 and wife_rule.currency_id~="invitation"
    and wife_rule.currency_id~="yitie" and wife_rule.currency_id~="blessing_ticket",
    "wife tickets have an independent ten-per-day limit")
profiles[0].entitlements.archive_pass={active=true,expires_at=1700000600}
profiles[1].entitlements.vip={active=true,level=12}
for index,id in ipairs({"social_ex","social_friend","social_beast","social_wife"}) do
    check(cooperative.record_challenge(0,id,index,"N10").recipients==4,
        "all four participants receive the complete independent "..id.." reward")
end
for id=0,3 do
    local tickets=profiles[id].save.archive.social_tickets
    check(tickets[wife_rule.currency_id]==1 and tickets.invitation==1 and tickets.yitie==1
        and tickets.blessing_ticket==1,"wife reward preserves all other currencies for account "..id)
end
check(cooperative.record_challenge(2,"social_wife",99,"N10").duplicate and delivered==16,
    "a second summoner cannot multiply the shared wife reward; VIP/pass do not lend bonus identity")
local saved=profile()
saved.save.archive={social_tickets={invitation=7,yitie=8,blessing_ticket=9}}
for index=1,wife_rule.daily_limit+2 do
    local command={id="wife_daily:"..index,kind="challenge",challenge_id="social_wife",
        difficulty_id="N10",kill_sequence=index,day_key="20410"}
    local result=reducer.settle(saved,command,false)
    check(result.ok,"wife daily settlement accepts a trusted challenge event")
    saved.save.archive,saved.save.gameplay_stats=result.archive,result.gameplay_stats
    local replay=reducer.settle(saved,command,false)
    check(replay.ok and replay.duplicate
        and replay.archive.social_tickets[wife_rule.currency_id]==result.archive.social_tickets[wife_rule.currency_id],
        "wife settlement replay cannot add another ticket")
end
check(saved.save.archive.social_tickets[wife_rule.currency_id]==10
    and saved.save.archive.daily["20410"].social_wife==10,"wife daily limit clamps repeated matches at ten")
check(saved.save.archive.social_tickets.invitation==7 and saved.save.archive.social_tickets.yitie==8
    and saved.save.archive.social_tickets.blessing_ticket==9,"wife daily quota never consumes another pool's currency")
local tomorrow=reducer.settle(saved,{id="wife_daily:tomorrow",kind="challenge",challenge_id="social_wife",
    difficulty_id="N10",kill_sequence=1,day_key="20411"},false)
check(tomorrow.ok and tomorrow.archive.social_tickets[wife_rule.currency_id]==11
    and tomorrow.archive.daily["20411"].social_wife==1,"wife quota resets for the next trusted day bucket")
check(#errors == 0, table.concat(errors, "\n"))
report("ARCHIVE_COOPERATIVE_REWARDS_PASS " .. checks .. " checks: roster, source authority, account isolation, monthly perks, delayed profile, disconnect, failure retries, highest team floor, bounded transport, terminal flush and independent wife daily rewards")
