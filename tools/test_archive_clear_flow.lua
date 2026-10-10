-- Offline integration of the real wave victory closures, archive service,
-- HTTP adapter and shared reducer. Native monsters and the HTTP/DB boundary
-- are fixtures; this does not connect to production or award player rewards.
package.path = "scripts/vscripts/?.lua;" .. package.path
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}; for key, child in pairs(value) do result[key] = copy(child) end
    return result
end
local bus = require("core/event_bus")
local events = require("core/events")
local original_print, runtime_errors = print, {}
print = function(message)
    local text = tostring(message)
    if text:find("handler error", 1, true) or text:find("task failed", 1, true) then
        runtime_errors[#runtime_errors + 1] = text
    end
end
local schema = require("config/generated/player_gameplay_stats")
local reducer = require("systems/archive_settlement")
local tasks, profiles, packets, requests, receipts = {}, {}, {}, {}, {}
local clock, apply_count = 61, 0
local failure, failure_once, stall = nil, false, false
local roster = {0}
local scheduler = {
    after=function(_, callback, id) tasks[id or tostring(callback)] = callback end,
    every=function(_, callback, id) tasks[id] = callback end,
    cancel=function(id) tasks[id] = nil end,
}
package.loaded["core/scheduler"] = scheduler
package.loaded["systems/player_context_service"] = {
    active_player_ids=function() return copy(roster) end,
    is_defeated=function() return false end,
}
package.loaded["systems/title_presentation_service"] = {
    init=function() end, rows=function() return {} end, preview_mode=function() return false end,
}
GameRules = {GetGameTime=function() return clock end}
RandomInt = function(minimum) return minimum end
PlayerResource = {
    GetPlayer=function(_, id) return profiles[id] and id end,
    IsValidPlayerID=function(_, id) return profiles[id] ~= nil end,
    IsFakeClient=function(_, id) return id == 2 end,
}
CustomGameEventManager = {
    RegisterListener=function() end,
    Send_ServerToPlayer=function(_, id, name, data)
        packets[#packets + 1] = {player=id, name=name, data=copy(data)}
    end,
}
local provider = {
    archive_enabled=function() return true end,
    resolve_account_id=function(id) return "fixture-account-" .. id end,
}
function provider.archive_submit(body, success, rejected)
    requests[#requests + 1] = copy(body)
    if stall then return end
    if failure_once then
        failure_once = false
        rejected(failure or "unavailable", 503)
        return
    end
    local id = tonumber(body.account_id:match("(%d+)$"))
    local key = body.account_id .. ":" .. body.command.id
    local receipt = receipts[key]
    if not receipt then
        local result = reducer.settle(profiles[id], copy(body.command), false)
        assert(result.ok, result.error)
        local updated = copy(profiles[id])
        updated.revision = updated.revision + 1
        updated.save.archive, updated.save.gameplay_stats = result.archive, result.gameplay_stats
        receipt = {ok=true, profile=updated}
        receipts[key] = copy(receipt)
    end
    success(copy(receipt))
end
package.loaded["systems/player_profile_service"] = {
    get_account_profile=function(id) return copy(profiles[id]) end,
    get_profile=function() error("archive must use the account profile") end,
    get_provider=function() return provider end,
    apply_snapshot=function(id, snapshot, reason)
        assert(reason == "archive_clear", "unexpected profile application reason")
        assert(snapshot.account_id == "fixture-account-" .. id)
        if snapshot.revision < profiles[id].revision then
            return {ok=false, error="snapshot_revision_stale"}
        end
        profiles[id] = copy(snapshot)
        apply_count = apply_count + 1
        -- This is the production adapter ordering: profile change is emitted
        -- before archive complete clears the pending command and sends pages.
        bus.emit(events.PLAYER_PROFILE_CHANGED, {player_id=id, reason=reason})
        return {ok=true}
    end,
}
package.loaded["systems/archive_http_adapter"] = nil
local archive = require("systems/archive_service")
local no_op = function() end
local wave_deps = {
    ["core/event_bus"]=bus, ["core/events"]=events, ["core/scheduler"]=scheduler,
    ["config/difficulty_config"]={default_id="N1"},
    ["config/generated/archive_challenge_rules"]={by_id={default={building_unlock_difficulty=1}}},
    ["systems/player_context_service"]=package.loaded["systems/player_context_service"],
    ["systems/gameplay_phase_guard"]={set_post_clear_frozen=no_op},
    ["systems/wave_spawn_sequence"]={build=function() return {} end},
    ["systems/monster_hero_visual_service"]={on_death=no_op},
    ["systems/monster_visual_service"]={on_death=no_op},
}
local wave_env = setmetatable({require=function(name) return wave_deps[name] or {} end}, {__index=_G})
local function load_wave()
    local chunk = assert(loadfile("scripts/vscripts/systems/wave_system.lua"))
    setfenv(chunk, wave_env)
    return chunk()
end
local function find(module, wanted)
    local seen = {}
    local function visit(fn)
        if type(fn) ~= "function" or seen[fn] then return end
        seen[fn] = true
        for index=1, math.huge do
            local name, value = debug.getupvalue(fn, index)
            if not name then break end
            if name == wanted then return value end
            if type(value) == "function" then local found=visit(value); if found then return found end end
        end
    end
    for _, fn in pairs(module) do local found=visit(fn); if found then return found end end
    error("missing production closure " .. wanted)
end
local function set(fn, wanted, value)
    for index=1, math.huge do
        local name = debug.getupvalue(fn, index)
        if not name then break end
        if name == wanted then debug.setupvalue(fn, index, value); return end
    end
    error("missing production state " .. wanted)
end
local function fresh(ids)
    bus.reset(); tasks, profiles, packets, requests, receipts = {}, {}, {}, {}, {}
    apply_count, roster = 0, ids
    failure_once, stall = false, false
    for _, id in ipairs(ids) do
        local profile = {account_id="fixture-account-"..id, revision=1,
            save={gameplay_stats={}, content_inventory={}}, entitlements={}}
        for _, row in ipairs(schema.rows) do profile.save.gameplay_stats[row.field_id] = row.default_value end
        profiles[id] = profile
    end
    archive.init()
    archive.set_clock(function() return 1700000000 end)
    bus.handle_request("archive.challenge_begin", function() return {ok=true, keep_running=true} end)
    local wave = load_wave()
    local check = find(wave, "check_final_victory")
    local early = find(wave, "request_early_final")
    local normal = find(wave, "start_next_wave")
    local start = find(wave, "start_wave")
    local killed = find(wave, "on_killed")
    local state = {current_wave=30, total_waves=31, alive=2, pending=0,
        failed_spawn=0, killed=0, mode_selected=true, final_wave_generation_completed=false}
    set(check, "state", state)
    set(early, "game_started", true)
    set(find(wave, "early_final_remaining"), "game_started_at", 0)
    set(start, "waves", {[31]={batches={}}})
    set(find(wave, "active_wave_channels"), "wave_channels", {[0]={player_id=0}})
    set(find(wave, "refresh_selection_state"), "difficulty_selected", true)
    local first = {IsNull=function() return false end, entindex=function() return 101 end}
    local second = {IsNull=function() return false end, entindex=function() return 102 end}
    -- Native spawn/death bookkeeping fixture. Early-final removes prior wave
    -- entities, so install these two final-wave enemies after dispatch below.
    local enemy_state = {[101]={unit=first, player_id=0}, [102]={unit=second, player_id=0}}
    return {wave=wave, check=check, early=early, normal=normal, killed=killed,
        state=state, first=first, second=second, enemy_state=enemy_state}
end
local cases = 0
local function delivered_clear(id)
    local decoded, sequence
    for _, packet in ipairs(packets) do
        local data = packet.data
        if packet.player == id and packet.name == "survival_archive_snapshot"
            and data.category_id == "clear" then
            if data.delta == 1 then
                assert(decoded and data.base_sequence == sequence, "clear delta lost its base")
                for _, change in ipairs(data.rows) do
                    local cursor = decoded
                    for index=1, #change.path-1 do
                        local key = tonumber(change.path[index]) or change.path[index]
                        cursor = assert(cursor[key], "delta parent missing")
                    end
                    local leaf = tonumber(change.path[#change.path]) or change.path[#change.path]
                    if change.remove == 1 then cursor[leaf] = nil
                    else cursor[leaf] = copy(change.value) end
                end
            else
                if data.chunk == 1 then decoded=copy(data); decoded.rows={} end
                for _, row in ipairs(data.rows) do decoded.rows[#decoded.rows+1]=copy(row) end
            end
            if data.chunk == data.chunks then sequence=data.sequence end
        end
    end
    return assert(decoded, "clear HUD snapshot was not delivered")
end
local function run(mode, ids, retry_kind)
    local f = fresh(ids)
    if mode == "early" then
        local result = f.early(); assert(result.ok and result.final_wave == 31)
        assert(f.state.early_final_used == true)
    else f.normal() end
    assert(f.state.current_wave == 31 and not f.state.victory_settled)
    f.state.alive = 2
    set(f.killed, "enemies", f.enemy_state)
    f.check(); assert(#requests == 0, "cannot save before final generation completes")
    assert(tasks.wave_generation_complete)()
    assert(f.state.final_wave_generation_completed and #requests == 0,
        "cannot save while final enemies are alive")
    f.killed({victim=f.first, victim_entindex=101})
    assert(#requests == 0, "cannot save with one final enemy alive")
    if retry_kind == "503" then failure_once=true; failure="fixture_503" end
    if retry_kind == "timeout" then stall=true end
    f.killed({victim=f.second, victim_entindex=102})
    assert(f.state.victory_settled and f.state.post_clear_frozen)
    assert(#requests == #ids)
    for _, body in ipairs(requests) do
        assert(body.command.kind == "clear" and body.command.count == 1)
        assert(body.command.difficulty_id == "n1")
        assert(body.command.cooperative_win == (#ids >= 2 and body.account_id ~= "fixture-account-2" and 1 or 0))
    end
    f.check(); f.killed({victim=f.second, victim_entindex=102})
    assert(#requests == #ids, "duplicate native death/clear emitted another reward")
    if retry_kind then
        local first_id = requests[1].command.id
        assert(archive.has_pending(0), "transient failure must remain queued")
        if retry_kind == "timeout" then tasks["archive_remote_timeout:0"](); stall=false end
        assert(tasks.archive_retry)()
        assert(requests[#requests].command.id == first_id, "retry must retain the original idempotency key")
    end
    for _, id in ipairs(ids) do
        assert(not archive.has_pending(id))
        assert(profiles[id].save.archive.clear_counts.n1 == 1)
        assert(profiles[id].save.archive.completed.clear_n1_1 == true)
        local row = archive.snapshot(id, "clear").rows[1]
        assert(row.count == 1 and row.completed == 1, "authoritative clear was not reflected in the page")
        local delivered = delivered_clear(id)
        assert(delivered.pending == 0 and delivered.revision == profiles[id].revision,
            "confirmed revision/pending state not sent to the clear HUD")
        assert(delivered.rows[1].count == 1 and delivered.rows[1].completed == 1,
            "clear HUD did not receive confirmed row data")
    end
    assert(apply_count == #ids)
    -- A delayed receipt can have an older revision than a later checkpoint.
    -- Keep the newer authority rather than rolling back its inventory/stats.
    profiles[0].revision = profiles[0].revision + 1
    profiles[0].save.gameplay_stats.initial_gold = 12345
    archive.record_clear(0, "N1", #ids >= 2 and 1 or 0)
    assert(not archive.has_pending(0) and profiles[0].save.archive.clear_counts.n1 == 1)
    assert(profiles[0].save.gameplay_stats.initial_gold == 12345)
    assert(apply_count == #ids, "an older receipt replaced the newer authoritative snapshot")
    cases=cases+1
end
run("normal", {0})
run("early", {0})
run("normal", {0}, "503")
run("early", {0}, "timeout")
run("normal", {0,1})
run("early", {0,1})
local gates = fresh({0})
gates.state.current_wave = 31
gates.state.final_wave_generation_completed = true
gates.state.alive = 0
gates.state.failed_spawn = 1
gates.check(); assert(#requests == 0, "failed final spawn cannot award a clear")
gates.state.failed_spawn = 0; gates.state.pending = 1
gates.check(); assert(#requests == 0, "pending final spawn cannot award a clear")
gates.state.pending = 0; gates.state.defeat_settled = true
gates.check(); assert(#requests == 0, "defeated match cannot award a clear")
local developer = fresh({0})
developer.state.current_wave = 31
developer.state.final_wave_generation_completed = true
developer.state.alive = 0
set(find(developer.wave, "settle_victory_once"), "dev_mode", true)
developer.check()
assert(developer.state.victory_settled and #requests == 0,
    "developer monster commands deliberately do not award clear archives")
assert(#runtime_errors == 0, table.concat(runtime_errors, "\n"))
original_print("ARCHIVE_CLEAR_FLOW_PASS "..cases.." cases plus failure/dev guards: normal/early, final-wave guards, co-op flag, HTTP failure/timeout retries, duplicate death, stale receipt isolation, authoritative revision and HUD refresh")
