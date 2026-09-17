package.path = "scripts/vscripts/?.lua;" .. package.path
local function copy(v)
    if type(v) ~= "table" then return v end
    local r = {}; for k, x in pairs(v) do r[k] = copy(x) end; return r
end
local stats = require("config/generated/player_gameplay_stats")
local achievements = require("config/generated/archive_achievements")
local shadow = require("config/generated/archive_shadow_items")
assert(#achievements.rows == 44, "44 regular milestones")
assert(#shadow.rows == 23, "23 shadow items")
for _, list in ipairs({ achievements.rows, shadow.rows }) do
    for _, row in ipairs(list) do
        assert(#row.effect_ids == #row.effect_values and #row.effect_ids > 0)
        for i, field in ipairs(row.effect_ids) do
            assert(stats.by_id[field], field)
            assert(tonumber(row.effect_values[i]) > 0)
        end
    end
end
local profiles, writes, fail, persistable = {}, 0, false, true
local bus = require("core/event_bus")
local events = require("core/events")
local tasks, listeners, packets = {}, {}, {}
package.loaded["core/scheduler"] = {
    every = function(_, cb, key) tasks[key] = cb end,
    after = function(_, cb, key) tasks[key] = cb end,
    cancel = function(key) tasks[key] = nil end,
}
local function new_profile()
    local p = { revision = 1, save = { gameplay_stats = {}, content_inventory = {} }, entitlements = {} }
    for _, row in ipairs(stats.rows) do p.save.gameplay_stats[row.field_id] = row.default_value end
    return p
end
profiles[0], profiles[1] = new_profile(), new_profile()
local provider = { persist_save = function() end }
package.loaded["systems/player_profile_service"] = {
    get_profile = function(id) return copy(profiles[id]) end,
    get_provider = function() return persistable and provider or {} end,
    update_save_sections = function(id, replacements)
        if fail then return { ok = false, error = "disk_failed" } end
        for k, v in pairs(replacements) do profiles[id].save[k] = copy(v) end
        profiles[id].revision = profiles[id].revision + 1; writes = writes + 1
        bus.emit(events.PLAYER_PROFILE_CHANGED, { player_id = id })
        return { ok = true }
    end,
}
local tools_mode, time, rolls = true, 0, 0
GameRules = { GetGameTime = function() return time end, IsCheatMode = function() return false end }
IsInToolsMode = function() return tools_mode end
DoUniqueString = function() return "test_match" end
RandomInt = function(a, b) rolls = rolls + 1; return a end
PlayerResource = { GetPlayer = function(_, id) return id end,
    IsValidPlayerID = function(_, id) return id == 0 or id == 1 end }
CustomGameEventManager = {
    RegisterListener = function(_, name, fn) listeners[name] = fn end,
    Send_ServerToPlayer = function(_, id, name, data) packets[#packets + 1] = { id = id, data = copy(data) } end,
}
local archive = require("systems/archive_service")
archive.init()
assert(#archive.snapshot(0, "shadow").rows == 0, "new profile starts with no shadow items")
bus.emit(events.PLAYER_PROFILE_CHANGED, { player_id = 0 })
assert(#archive.snapshot(0, "shadow").rows == 0, "profile load grants no items")
local function cheat(id, difficulty, count)
    return archive.cheat({ player_id = id, args = { difficulty, tostring(count) } })
end
assert(cheat(0, "n1", 20))
assert(profiles[0].save.archive.clear_counts.n1 == 20)
assert(profiles[0].save.gameplay_stats.initial_wood == 10 + 50 + 80 + 100)
assert(profiles[1].save.gameplay_stats.initial_wood == 10, "player isolation")
assert(cheat(0, "clear_n1_1", 20))
assert(profiles[0].save.archive.clear_counts.n1 == 40)
assert(profiles[0].save.gameplay_stats.initial_wood == 240, "milestones granted only once")
tools_mode = false
assert(not cheat(0, "n1", 1), "production cheat denied")
tools_mode = true
for _, invalid in ipairs({ "0", "-1", "1.5", "100001", "nan", "inf" }) do
    assert(not cheat(0, "n1", invalid), invalid)
end
assert(not cheat(0, "no_such_id", 20))
assert(archive.record_clear(1, "N1").ok)
local old_writes = writes
assert(archive.record_clear(1, "N1").ok)
assert(writes == old_writes and profiles[1].save.archive.clear_counts.n1 == 1, "match clear dedup")
local snapshot = archive.snapshot(0, "clear")
assert(snapshot.rows[1].completed == 1 and snapshot.rows[4].completed == 0)
assert(snapshot.gameplay_stats == nil and snapshot.entitlements == nil)
assert(#archive.snapshot(0, "points").rows == 0)
local fishing_pending=archive.snapshot(0,"fishing")
assert(#fishing_pending.rows==26 and fishing_pending.fishing.ready==0,"missing inventory is unknown, not an empty bag")
profiles[0].save.fishing_inventory={star_blessing_001=3,star_blessing_002=301,star_blessing_automation_9001=999}
local fishing_before_writes=writes
local fishing=archive.snapshot(0,"fishing")
assert(fishing.fishing.ready==1 and fishing.fishing.total==304 and fishing.fishing.owned==2)
assert(fishing.rows[1].count==3 and fishing.rows[1].target==90)
assert(fishing.rows[2].count==301 and fishing.rows[2].target==300,"display must not silently clip existing server counts")
assert(fishing.rows[3].count==0 and fishing.rows[3].count_known==1)
assert(writes==fishing_before_writes,"viewing fishing cannot grant or apply effects")
assert(archive.snapshot(1,"fishing").fishing.ready==0,"player isolation")
profiles[1].save.fishing_inventory={}
assert(archive.snapshot(1,"fishing").fishing.ready==1 and archive.snapshot(1,"fishing").fishing.total==0)
profiles[0].save.fishing_inventory.star_blessing_001=4
assert(archive.snapshot(0,"fishing").rows[1].count==4,"authoritative profile refresh updates counts")
profiles[0].save.content_inventory.lottery_attribute_crystal = 1
assert(#archive.snapshot(0, "points").rows == 1)
assert(#archive.snapshot(0, "shadow").rows == 0, "clear cheat grants no shadow items")
bus.emit("archive.final_boss_killed", { player_id = 0, difficulty_id = "N1" })
bus.emit("archive.final_wave_cleared", { player_id = 0, difficulty_id = "N1" })
assert(#archive.snapshot(0, "shadow").rows == 0, "final boss and clear grant no shadow items")
assert(archive.record_challenge(0, "shadow_1", 100, "N3").ok)
assert(profiles[0].save.archive.shadow_counts.shadow_01 == 2)
local wood = profiles[0].save.gameplay_stats.initial_wood
archive.record_challenge(0, "shadow_1", 100, "N3")
assert(profiles[0].save.gameplay_stats.initial_wood == wood, "boss dedup")
profiles[1].entitlements.archive_pass = { active = true, expires_at = os.time() + 600 }
fail = true
local before = copy(profiles[1])
assert(not archive.record_challenge(1, "shadow_1", 100, "N3").ok)
assert(profiles[1].save.gameplay_stats.initial_wood == before.save.gameplay_stats.initial_wood)
local prior_rolls = rolls
fail = false; tasks.archive_retry()
assert(rolls == prior_rolls, "write retry reuses draws")
assert(profiles[1].save.archive.shadow_counts.shadow_01 == 2, "shadow 1 always gives two items even with pass")
assert(#archive.snapshot(1, "shadow").rows == 1)
profiles[1].entitlements.archive_pass.expires_at = os.time() - 1
assert(archive.snapshot(1, "shadow").has_pass == 0, "expired pass")
profiles[1].entitlements.archive_pass = { active = false }
assert(archive.snapshot(1, "shadow").has_pass == 0)
-- No fake local success when HTTP provider has no archive mutation adapter.
persistable = false
assert(not cheat(1, "n2", 3))
assert(profiles[1].save.archive.clear_counts.n2 == nil)
persistable = true; tasks.archive_retry()
assert(profiles[1].save.archive.clear_counts.n2 == 3)
-- Missing profiles keep server-authored outcomes queued until load.
profiles[2] = nil
assert(not archive.record_clear(2, "N3").ok)
profiles[2] = new_profile(); tasks.archive_retry()
assert(profiles[2].save.archive.clear_counts.n3 == 1)
-- Snapshot identity is injected PlayerID; forged player_id is ignored.
packets = {}; time = 5
listeners.survival_archive_request(nil, { PlayerID = 1, player_id = 0, category_id = "clear" })
assert(#packets == 4, "44 rows paginated into private chunks")
for _, packet in ipairs(packets) do assert(packet.id == 1 and #packet.data.rows <= 12) end
local n = #packets
listeners.survival_archive_request(nil, { PlayerID = 1, category_id = "shadow" })
assert(#packets == n, "request throttling")
listeners.survival_archive_request(nil, { PlayerID = -1, category_id = "clear" })
assert(#packets == n)
-- Upper ownership cap suppresses both extra copies and duplicate effects.
profiles[3] = new_profile()
profiles[3].save.archive = { shadow_counts = { shadow_01 = 429 } }
assert(archive.record_challenge(3, "shadow_1", 100, "N3").ok)
assert(profiles[3].save.archive.shadow_counts.shadow_01 == 430)
assert(profiles[3].save.gameplay_stats.initial_wood == 20)
local rules = require("config/generated/archive_drop_rules")
local total = 0; for _, row in ipairs(rules.rows) do total = total + row.weight end
assert(total == 120 and rules.rows[1].weight == 33)
-- Server adapters can expire passes even when the VScript OS clock is absent.
archive.set_clock(function() return 1000 end)
profiles[0].entitlements.archive_pass = { active = true, expires_at = 1001 }
assert(archive.snapshot(0, "shadow").has_pass == 1)
archive.set_clock(function() return 1001 end)
assert(archive.snapshot(0, "shadow").has_pass == 0)
archive.set_clock(nil)
-- Challenge grants and promotion use the same atomic save/retry boundary.
profiles[4] = new_profile()
profiles[4].save.archive = { fragment_counts = {fragment_01 = 19}, fragment_totals = {fragment_01 = 19} }
fail = true
assert(not archive.record_challenge(4, "hunt_01", 100).ok)
assert(profiles[4].save.archive.fragment_counts.fragment_01 == 19)
assert(archive.has_pending(4))
fail = false; tasks.archive_retry()
assert(profiles[4].save.archive.fragment_counts.fragment_01 == 20)
assert(profiles[4].save.archive.fragment_levels.fragment_01 == 1)
local stats_after = copy(profiles[4].save.gameplay_stats)
archive.record_challenge(4, "hunt_01", 100)
assert(profiles[4].save.archive.fragment_counts.fragment_01 == 20)
for key, value in pairs(stats_after) do assert(profiles[4].save.gameplay_stats[key] == value) end
profiles[4].save.archive.fragment_counts.fragment_01 = 201
profiles[4].save.archive.fragment_totals.fragment_01 = 201
fail = true
assert(not archive.promote(4, "fragment_01", "test_promotion").ok)
assert(profiles[4].save.archive.fragment_counts.fragment_01 == 201)
fail = false; tasks.archive_retry()
assert(profiles[4].save.archive.fragment_counts.fragment_01 == 191)
assert(profiles[4].save.archive.fragment_counts.fragment_05 == 1)
archive.promote(4, "fragment_01", "test_promotion")
assert(profiles[4].save.archive.fragment_counts.fragment_05 == 1, "promotion dedup")
assert(not archive.has_pending(4))
-- Remote failure/timeout retries preserve the exact command id.
local remote_commands, remote_done = {}, nil
archive.set_provider({ submit = function(id, command, done)
    remote_commands[#remote_commands + 1] = command
    remote_done = done
end })
assert(cheat(0, "n2", 1))
assert(#remote_commands == 1)
tasks["archive_remote_timeout:0"]()
tasks.archive_retry()
assert(#remote_commands == 2 and remote_commands[1].id == remote_commands[2].id)
remote_done({ ok = true }); tasks.archive_retry()
assert(#remote_commands == 2)
archive.set_provider(nil)
-- Endless wave score and milestones are committed atomically and deduplicated.
profiles[5] = new_profile()
fail = true
assert(not archive.record_endless_wave(5, 1, 10).ok)
assert(not profiles[5].save.archive, "failed score write leaves profile untouched")
fail = false; tasks.archive_retry()
assert(profiles[5].save.archive.endless_score == 1)
assert(archive.record_endless_wave(5, 1, 10).ok)
assert(profiles[5].save.archive.endless_score == 1, "wave score dedup")
for wave = 2, 60 do assert(archive.record_endless_wave(5, wave, 10).ok) end
assert(profiles[5].save.archive.endless_score == 1110)
assert(profiles[5].save.archive.completed.endless_1)
assert(profiles[5].save.gameplay_stats.lumberjack_efficiency == stats.by_id.lumberjack_efficiency.default_value + 1)
assert(not archive.record_endless_wave(5, 1001, 10).ok)
local endless_rows = archive.snapshot(5, "endless").rows
assert(#endless_rows == 50 and endless_rows[1].completed == 1 and endless_rows[2].completed == 0)
assert(endless_rows[1].count == 1110)
for _, row in ipairs(require("config/generated/archive_endless_achievements").rows) do
    for _, field in ipairs(row.effect_ids) do assert(stats.by_id[field], field) end
end
-- A real fixture provider must roll back its cached snapshot after disk failure.
local fixture = require("systems/player_profile_providers/local_fixture_provider")
fixture.init()
local initial
fixture.fetch_snapshot("mock_account_10001", function(p) initial = copy(p) end, error)
local open = io.open
local attempted_write = false
io.open = function(path, mode)
    if mode == "wb" then attempted_write = true; return nil, "test_write_denied" end
    return open(path, mode)
end
local changed = copy(initial.save)
changed.archive = { clear_counts = { n1 = 999 } }
local persisted = fixture.persist_save("mock_account_10001", changed, initial.revision + 1)
io.open = open
assert(not persisted and attempted_write)
fixture.fetch_snapshot("mock_account_10001", function(p)
    assert(p.revision == initial.revision)
    assert((p.save.archive or {}).clear_counts == nil or p.save.archive.clear_counts.n1 ~= 999)
end, error)
profiles[6] = new_profile()
assert(archive.yitie({player_id=6,args={"1000"}}))
assert(archive.snapshot(6,"friend").social.tickets == 1000)
assert(#archive.snapshot(6,"friend").rows == 40 and #archive.snapshot(6,"ex").rows == 40)
fail = true
assert(not archive.social_draw(6,"friend","first").ok)
assert(archive.snapshot(6,"friend").social.tickets == 1000, "failed save never consumes tickets")
fail = false
archive._test.flush(6)
assert(archive.snapshot(6,"friend").social.tickets == 999)
assert(archive.social_draw(6,"friend","first").ok)
assert(archive.snapshot(6,"friend").social.tickets == 999, "duplicate draw does not charge")
for i=2,100 do assert(archive.social_draw(6,"friend","draw_"..i).ok) end
assert(archive.snapshot(6,"friend").social.unlocked == 1)
assert(archive.snapshot(6,"friend").social.total == 100)
local remaining = archive.snapshot(6,"friend").social.remaining
for i=1,remaining do assert(archive.social_draw(6,"friend","fill_"..i).ok) end
local balance = archive.snapshot(6,"friend").social.tickets
assert(not archive.social_draw(6,"friend","full").ok)
assert(archive.snapshot(6,"friend").social.tickets == balance)
for _, row in ipairs(archive.snapshot(6,"friend").rows) do assert(row.count == row.target) end
assert(not archive.social_draw(6,"ex","no_invitation").ok)
assert(archive.yitie({player_id=6,args={"2","ex"}}))
assert(archive.social_draw(6,"ex","ex_first").ok)
assert(archive.snapshot(6,"ex").social.tickets == 1)
assert(archive.snapshot(6,"friend").social.tickets == balance)
assert(archive.yitie({player_id=6,args={"3","beast"}}))
assert(#archive.snapshot(6,"beast").rows == 40)
assert(archive.social_draw(6,"beast","beast_first").ok)
assert(archive.snapshot(6,"beast").social.tickets == 2)
assert(archive.snapshot(6,"beast").social.total == 1)
profiles[7] = new_profile()
for i=1,12 do assert(archive.record_challenge(7,"social_friend",1000+i,"N5").ok) end
assert(archive.snapshot(7,"friend").social.tickets == 10, "daily challenge limit")
assert(archive.record_challenge(7,"social_friend",1001,"N5").ok)
assert(archive.snapshot(7,"friend").social.tickets == 10, "kill dedup")
assert(archive.record_challenge(7,"social_ex",2001,"N5").ok)
assert(archive.snapshot(7,"ex").social.tickets == 1, "independent daily quota and currency")
assert(archive.snapshot(7,"friend").social.tickets == 10)
assert(archive.record_challenge(7,"social_beast",2002,"N5").ok)
assert(archive.snapshot(7,"beast").social.tickets == 1)
for _, item in ipairs(require("config/generated/archive_social_items").rows) do
    assert(stats.by_id[item.effect_ids[1]] and item.max_owned > 0)
end
print("ARCHIVE_SERVICE_PASS: atomic grants, retries, social draws, caps, 100 unlock, daily limits")
profiles[8]=new_profile()
local day=25000
local timestamp=day*86400
archive.set_clock(function()return timestamp end)
for i=1,5 do assert(archive.record_boss(8,"boss_"..i).ok) end
assert(archive.record_boss(8,"boss_1").ok)
local b=archive.snapshot(8,"boss").rows[1]
assert(b.count==5 and b.target==10 and b.completed==0)
profiles[8].entitlements.archive_pass={active=true,expires_at=timestamp+3600}
b=archive.snapshot(8,"boss").rows[1];assert(b.target==5 and b.completed==1)
timestamp=timestamp+3601
b=archive.snapshot(8,"boss").rows[1];assert(b.target==10 and b.completed==0)
timestamp=day*86400
profiles[8].entitlements.archive_pass={active=true,expires_at=timestamp+40*86400}
fail=true
assert(not archive.daily_claim(8,day).ok)
assert(not profiles[8].save.archive.daily_rewards)
fail=false;archive._test.flush(8)
assert(archive.daily_snapshot(8).claimed==1 and archive.daily_snapshot(8).count==1)
assert(archive.daily_claim(8,day).ok)
assert(archive.daily_snapshot(8).count==1)
assert(not archive.daily_claim(8,day+1).ok)
timestamp=(day+2)*86400
assert(archive.daily_claim(8,day+2).ok)
profiles[8].entitlements.archive_pass.active=false
assert(not archive.daily_claim(8,day+1).ok)
profiles[8].entitlements.archive_pass.active=true
assert(archive.daily_claim(8,day+1).ok)
for i=3,20 do timestamp=(day+i)*86400;assert(archive.daily_claim(8,day+i).ok) end
local daily=profiles[8].save.archive.daily_rewards
assert(daily.count==21)
assert(daily.item_counts.daily_wealth_talisman==1 and daily.item_counts.daily_ancient_tree==1 and daily.item_counts.daily_forest_origin==1)
assert(daily.item_counts.daily_growth_gem==9 and daily.item_counts.daily_gold_gem==9)
assert(profiles[8].save.gameplay_stats.hero_attack_per_second==9)
local count=0;for _,row in ipairs(archive.snapshot(8,"points").rows) do if row.id:match('^daily_') then count=count+1 end end
assert(count==12)
for _,row in ipairs(require("config/lottery_config").items) do assert(not row.id:match('^daily_'),"daily exclusives cannot be rolled") end
assert(#archive.snapshot(8,"boss").rows==34)
print("ARCHIVE_BOSS_DAILY_PASS: pass expiry, dedup, day boundaries, makeup, 21-day rewards, point inventory")
local calendar=require("systems/archive_calendar")
timestamp=25000*86400+16*3600-1
assert(calendar.day()==25000)
timestamp=timestamp+1
assert(calendar.day()==25001,"UTC+8 midnight")
