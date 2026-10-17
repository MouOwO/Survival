-- Standalone Lua 5.1 regression for purchase-triggered lottery refresh.
-- Execute from the repository root. No HTTP, accounts, archive writes or game APIs.
package.path = 'scripts/vscripts/?.lua;' .. package.path

local bus = require('core/event_bus')
local events = require('core/events')
local delta = require('core/ui_snapshot_delta')
local passed = 0
local function equal(actual, expected, message)
    assert(actual == expected, (message or 'unexpected value') ..
        ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual))
end
local function copy(value)
    if type(value) ~= 'table' then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = copy(item) end
    return out
end
local function fixture(tickets, owned, pool, extra)
    local snapshot = {
        selected_pool_id = pool or 'map',
        ticket_content_id = 'lottery_ticket',
        tickets = tickets,
        pools = {{id = pool or 'map', tickets = tickets}},
        items = {{id = 'purchase_reward', owned_count = owned or 0}},
    }
    for key, value in pairs(extra or {}) do snapshot[key] = value end
    return snapshot
end
local function harness()
    bus.reset()
    package.loaded['systems/lottery_http_service'] = nil
    local h = {
        accounts = {[0] = 'account_0', [1] = 'account_1'},
        match_session = 'match_a', mode = 'standard',
        reads = {}, commands = {}, scheduled = {}, packets = {},
    }
    local provider = {
        resolve_account_id = function(id) return h.accounts[id] end,
        lottery_snapshot = function(payload, done, failed)
            equal(payload.config_hash, 'regression_bundle', 'use configured authority hash')
            h.reads[#h.reads + 1] = {
                payload = copy(payload), done = done, failed = failed,
            }
        end,
    }
    package.loaded['systems/player_profile_service'] = {get_provider = function() return provider end}
    package.loaded['systems/match_setup_service'] = {
        get_session_id = function() return h.match_session end,
        get_mode = function() return h.mode end,
    }
    package.loaded['systems/archive_http_adapter'] = {
        submit = function(id, command, done)
            h.commands[#h.commands + 1] = {player_id = id, command = copy(command), done = done}
        end,
    }
    package.loaded['config/generated/archive_http_bundle'] = {hash = 'regression_bundle'}
    package.loaded['core/scheduler'] = {
        after = function(delay, fn, key)
            h.scheduled[#h.scheduled + 1] = {delay = delay, fn = fn, key = key}
        end,
    }
    bus.subscribe(events.LOTTERY_CHANGED, function(packet) h.packets[#h.packets + 1] = copy(packet) end)
    require('systems/lottery_http_service').init()
    function h.request(event, payload)
        local result, err = bus.request(event, payload)
        assert(not err, err)
        assert(result, 'request handler did not return a result')
        return result
    end
    function h.get(id, complete, prefetch, pool)
        return h.request(events.LOTTERY_SNAPSHOT_REQUEST, {
            player_id = id, pool_id = pool or 'map',
            prefetch = prefetch, complete = complete,
        })
    end
    function h.changed(id)
        bus.emit(events.PLAYER_PROFILE_CHANGED, {player_id = id})
    end
    function h.reply(index, snapshots)
        assert(h.reads[index], 'missing pending read ' .. index)
        h.reads[index].done({ok = true, snapshots = copy(snapshots)})
    end
    function h.fail(index, reason)
        assert(h.reads[index], 'missing pending read ' .. index)
        h.reads[index].failed(reason or 'temporary_http_failure')
    end
    function h.seed(id, tickets, owned, pool)
        local count = #h.reads
        assert(h.get(id, nil, 1, pool).pending)
        equal(#h.reads, count + 1, 'initial prefetch starts one read')
        h.reply(count + 1, {fixture(tickets, owned, pool)})
    end
    return h
end
local function test(name, run)
    local ok, err = pcall(run)
    assert(ok, name .. ': ' .. tostring(err))
    passed = passed + 1
    print('PASS ' .. name)
end

test('purchase events invalidate in-flight balances and coalesce into one trailing read', function()
    local h = harness()
    local results = {}
    assert(h.get(0, function(result) results[#results + 1] = result end).pending)
    h.changed(0); h.changed(0); h.changed(0)
    assert(h.get(0, function(result) results[#results + 1] = result end).pending)
    equal(#h.reads, 1, 'profile changes coalesce while HTTP is in flight')
    h.reply(1, {fixture(3, 0)})
    equal(#h.packets, 0, 'do not broadcast pre-purchase balance')
    equal(#results, 0, 'old read cannot satisfy post-purchase waiters')
    equal(#h.reads, 2, 'start exactly one trailing read')
    h.reply(2, {fixture(10, 4)})
    equal(#results, 2, 'all same-scope waiters complete after fresh response')
    equal(results[1].snapshot.tickets, 10)
    equal(results[2].snapshot.items[1].owned_count, 4)
    equal(#h.packets, 1)
    equal(h.packets[1].snapshot.snapshot_scope, 'cache')
    equal(h.get(0).snapshot.tickets, 10, 'clean cache is available immediately')
    equal(#h.reads, 2, 'clean tab read does not poll HTTP')
end)

test('stale failed requests cannot finish waiters before authoritative retry', function()
    local h = harness()
    local completed
    h.get(0, function(result) completed = result end)
    h.changed(0)
    h.fail(1)
    equal(completed, nil)
    equal(#h.reads, 2)
    h.reply(2, {fixture(8, 3)})
    assert(completed.ok)
    equal(completed.snapshot.tickets, 8)
end)

for _, kind in ipairs({'draw', 'exchange', 'read'}) do
    test('purchase during busy ' .. kind .. ' refreshes once after command completion', function()
        local h = harness()
        h.seed(0, 5, 0)
        local completed, waiting
        local event = kind == 'draw' and events.LOTTERY_DRAW_REQUEST
            or kind == 'exchange' and events.LOTTERY_EXCHANGE_REQUEST
            or events.LOTTERY_SNAPSHOT_REQUEST
        local payload = {player_id = 0, pool_id = 'map', count = 1,
            item_id = 'purchase_reward', request_id = 'test_' .. kind,
            complete = function(result) completed = result end}
        if kind == 'read' then payload.read_action = 'mark'; payload.revision = 1 end
        assert(h.request(event, payload).pending)
        equal(#h.commands, 1)
        equal(h.commands[1].command.kind, 'lottery_' .. kind)
        h.changed(0); h.changed(0)
        assert(h.get(0, function(result) waiting = result end).pending)
        equal(#h.reads, 1, 'defer authority fetch while command mutates inventory')
        h.commands[1].done({ok = true, response = {
            ok = true, results = {{id = 'reward'}}, snapshot = fixture(999, 999),
        }})
        equal(completed, nil, 'command callback must await authoritative read')
        equal(#h.reads, 2, 'one post-command refresh also satisfies purchase dirty state')
        h.reply(2, {fixture(11, 7)})
        assert(completed.ok and waiting.ok)
        equal(completed.snapshot.tickets, 11, 'ignore embedded command/pre-purchase balance')
        equal(waiting.snapshot.items[1].owned_count, 7)
        equal(#h.reads, 2)
    end)
end

test('in-flight read becoming stale while draw is busy waits until draw finishes', function()
    local h = harness()
    h.seed(0, 5, 0)
    h.changed(0)
    equal(#h.reads, 2)
    local completed, waiting
    h.request(events.LOTTERY_DRAW_REQUEST, {player_id = 0, pool_id = 'map', count = 1,
        request_id = 'draw_overlap', complete = function(result) completed = result end})
    h.changed(0)
    h.get(0, function(result) waiting = result end)
    h.reply(2, {fixture(6, 1)})
    equal(#h.reads, 2, 'do not race authoritative read with a pending command')
    equal(#h.packets, 1, 'discard stale overlapping HTTP result')
    equal(completed, nil); equal(waiting, nil)
    h.commands[1].done({ok = true, response = {ok = true}})
    equal(#h.reads, 3)
    h.reply(3, {fixture(10, 8)})
    equal(completed.snapshot.tickets, 10)
    equal(waiting.snapshot.items[1].owned_count, 8)
end)

test('old in-flight read after command completion cannot satisfy post-command refresh', function()
    local h = harness()
    h.seed(0, 5, 0)
    h.changed(0)
    local completed
    h.request(events.LOTTERY_DRAW_REQUEST, {player_id = 0, pool_id = 'map', count = 1,
        request_id = 'draw_then_old_read', complete = function(result) completed = result end})
    h.commands[1].done({ok = true, response = {ok = true}})
    equal(#h.reads, 2, 'reuse in-flight transport but invalidate its epoch')
    h.reply(2, {fixture(5, 0)})
    equal(completed, nil)
    equal(#h.packets, 1)
    equal(#h.reads, 3, 'fetch actual post-command inventory')
    h.reply(3, {fixture(4, 1)})
    equal(completed.snapshot.tickets, 4)
end)

test('two players retain separate caches, pending reads and waiters', function()
    local h = harness()
    local result0, result1
    h.get(0, function(result) result0 = result end)
    h.get(1, function(result) result1 = result end)
    equal(h.reads[1].payload.account_id, 'account_0')
    equal(h.reads[2].payload.account_id, 'account_1')
    h.changed(0)
    h.reply(2, {fixture(23, 3)})
    equal(result1.snapshot.tickets, 23)
    equal(result0, nil)
    equal(h.packets[1].player_id, 1)
    h.reply(1, {fixture(2, 0)})
    equal(#h.reads, 3)
    equal(h.reads[3].payload.account_id, 'account_0')
    h.reply(3, {fixture(7, 1)})
    equal(result0.snapshot.tickets, 7)
    equal(h.get(1).snapshot.tickets, 23)
    equal(h.packets[#h.packets].player_id, 0)
end)

local changes = {
    account = function(h) h.accounts[0] = 'replacement_account' end,
    session = function(h) h.match_session = 'replacement_match' end,
    mode = function(h) h.mode = 'pure' end,
}
for _, field in ipairs({'account', 'session', 'mode'}) do
    test(field .. ' change drops obsolete fetch and never touches new waiters', function()
        local h = harness()
        local obsolete, fresh
        h.get(0, function(result) obsolete = result end)
        changes[field](h)
        h.get(0, function(result) fresh = result end)
        equal(#h.reads, 2)
        h.reply(1, {fixture(999, 999)})
        equal(obsolete, nil, 'obsolete waiter is discarded')
        equal(fresh, nil, 'old callback cannot complete replacement waiter')
        equal(#h.packets, 0)
        h.reply(2, {fixture(4, 2)})
        equal(fresh.snapshot.tickets, 4)
        equal(h.get(0).snapshot.items[1].owned_count, 2)
        equal(#h.packets, 1)
        equal(h.packets[1].snapshot.snapshot_scope, 'cache', 'new identity starts with full snapshot')
    end)
    test(field .. ' change isolates old draw from replacement draw and refresh', function()
        local h = harness()
        h.seed(0, 5, 0)
        local obsolete, fresh
        h.request(events.LOTTERY_DRAW_REQUEST, {player_id = 0, pool_id = 'map', count = 1,
            request_id = 'old_draw', complete = function(result) obsolete = result end})
        changes[field](h)
        assert(h.request(events.LOTTERY_DRAW_REQUEST, {player_id = 0, pool_id = 'map', count = 1,
            request_id = 'new_draw', complete = function(result) fresh = result end}).pending)
        equal(#h.commands, 2, 'old busy job must not block new identity')
        h.commands[1].done({ok = true, response = {ok = true}})
        equal(#h.reads, 1, 'old command cannot trigger replacement inventory read')
        equal(obsolete, nil); equal(fresh, nil)
        h.commands[2].done({ok = true, response = {ok = true}})
        equal(#h.reads, 2)
        h.reply(2, {fixture(3, 1)})
        equal(fresh.snapshot.tickets, 3)
        equal(obsolete, nil)
    end)
end

test('identity invalidation discovered by old callback still permits a later request', function()
    local h = harness()
    local obsolete, fresh
    h.get(0, function(result) obsolete = result end)
    h.accounts[0] = nil
    h.reply(1, {fixture(999, 999)})
    equal(#h.packets, 0); equal(obsolete, nil)
    equal(h.get(0).error, 'http_profile_required')
    h.accounts[0] = 'new_account'
    h.get(0, function(result) fresh = result end)
    h.reply(2, {fixture(2, 0)})
    equal(fresh.snapshot.tickets, 2)
end)

test('failed purchase refresh preserves last cache but cannot present it as fresh', function()
    local h = harness()
    h.seed(0, 5, 2)
    local original = h.get(0).snapshot
    h.changed(0)
    local failed, retried
    h.get(0, function(result) failed = result end)
    h.fail(2, 'backend_temporarily_unavailable')
    assert(failed and not failed.ok)
    equal(failed.error, 'backend_temporarily_unavailable')
    equal(failed.snapshot, nil, 'failed refresh cannot claim a stale post-purchase balance')
    equal(#h.packets, 1, 'no invented increments and no cache removal on failure')
    equal(original.tickets, 5)
    equal(original.items[1].owned_count, 2)
    assert(h.get(0, function(result) retried = result end).pending,
        'dirty cache cannot satisfy new request after failure')
    equal(#h.reads, 3)
    h.reply(3, {fixture(9, 4)})
    equal(retried.snapshot.tickets, 9)
    equal(h.packets[2].snapshot.snapshot_scope, 'cache_patch', 'retained cache provides patch base')
    equal(h.packets[2].snapshot.base_sequence, h.packets[1].snapshot.cache_sequence)
end)

test('post-command refresh failure returns no stale snapshot and remains retryable', function()
    local h = harness()
    h.seed(0, 5, 2)
    local completed
    h.request(events.LOTTERY_DRAW_REQUEST, {player_id = 0, pool_id = 'map', count = 1,
        request_id = 'draw_refresh_failure', complete = function(result) completed = result end})
    h.commands[1].done({ok = true, response = {ok = true}})
    h.fail(2)
    assert(completed.ok, 'successful authoritative command remains successful')
    equal(completed.snapshot, nil, 'failed post-command fetch cannot attach old cache')
    equal(#h.packets, 1)
    assert(h.get(0).pending)
    h.reply(3, {fixture(4, 3)})
    equal(h.get(0).snapshot.tickets, 4)
end)

test('terminal command failure still refreshes purchase dirty state from authority', function()
    local h = harness()
    h.seed(0, 5, 0)
    local completed
    h.request(events.LOTTERY_DRAW_REQUEST, {player_id = 0, pool_id = 'map', count = 10,
        request_id = 'failed_draw', complete = function(result) completed = result end})
    h.changed(0)
    h.commands[1].done({ok = false, terminal = true, error = 'lottery_ticket_insufficient'})
    equal(completed, nil)
    h.reply(2, {fixture(9, 1)})
    equal(completed.ok, false)
    equal(completed.error, 'lottery_ticket_insufficient')
    equal(completed.snapshot.tickets, 9, 'inventory fetch reflects concurrent purchase despite draw failure')
end)

-- Small protocol client: apply the actual cache/cache_patch packets and reject
-- missing/incorrect version bases, including multi-chunk updates.
local function receiver()
    local r = {cache = {}, sequence = {}, pending = {}}
    function r.accept(snapshot)
        local pool = snapshot.selected_pool_id
        if snapshot.snapshot_scope == 'cache' then
            r.cache[pool] = copy(snapshot)
            r.cache[pool].snapshot_scope = nil
            r.cache[pool].cache_sequence = nil
            r.sequence[pool] = snapshot.cache_sequence
            r.pending[pool] = nil
            return
        end
        equal(snapshot.snapshot_scope, 'cache_patch')
        equal(snapshot.base_sequence, r.sequence[pool], 'patch must refer to last complete snapshot')
        local chunked = r.pending[pool]
        if not chunked then
            chunked = {value = copy(r.cache[pool]), next = 1,
                sequence = snapshot.cache_sequence, chunks = snapshot.chunks}
            r.pending[pool] = chunked
        end
        equal(snapshot.chunk, chunked.next, 'chunks must be ordered')
        equal(snapshot.cache_sequence, chunked.sequence, 'all chunks share one version')
        equal(snapshot.chunks, chunked.chunks)
        for _, change in ipairs(snapshot.changes) do
            local parent = chunked.value
            for index = 1, #change.path - 1 do
                local key = change.path[index]
                if parent[tonumber(key)] ~= nil then key = tonumber(key) end
                parent = assert(parent[key], 'patch path must exist')
            end
            local key = change.path[#change.path]
            if parent[tonumber(key)] ~= nil then key = tonumber(key) end
            if change.remove == 1 then parent[key] = nil else parent[key] = copy(change.value) end
        end
        chunked.next = chunked.next + 1
        if snapshot.chunk == snapshot.chunks then
            r.cache[pool], r.sequence[pool], r.pending[pool] = chunked.value, chunked.sequence, nil
        end
    end
    return r
end

test('multi-chunk purchase patches preserve version chain and prefetch reopens with full cache', function()
    local h = harness()
    local first = fixture(5, 1)
    for index = 1, 27 do first.items[index] = {id = 'item_' .. index, owned_count = 0} end
    h.get(0, nil, 1)
    h.reply(1, {first})
    local client = receiver()
    client.accept(h.packets[1].snapshot)
    h.changed(0)
    local second = copy(first); second.tickets = 18; second.pools[1].tickets = 18
    for index = 1, 27 do second.items[index].owned_count = index end
    h.reply(2, {second})
    equal(#h.packets, 4, '29 field changes produce three 12-change chunks')
    for index = 2, #h.packets do client.accept(h.packets[index].snapshot) end
    equal(client.cache.map.tickets, 18)
    equal(client.cache.map.items[27].owned_count, 27)
    equal(#delta.diff(client.cache.map, second), 0, 'packet reconstruction equals authoritative inventory')
    local last = client.sequence.map
    h.changed(0)
    local third = copy(second); third.tickets = 19; third.pools[1].tickets = 19
    h.reply(3, {third})
    equal(h.packets[5].snapshot.base_sequence, last, 'next patch chains from completed multi-chunk sequence')
    client.accept(h.packets[5].snapshot)
    equal(client.cache.map.tickets, 19)
    local complete
    assert(h.get(0, function(result) complete = result end, 1).pending)
    h.reply(4, {third})
    assert(complete.ok)
    equal(h.packets[6].snapshot.snapshot_scope, 'cache', 'unchanged reopen still sends full packet')
    equal(h.packets[6].snapshot.tickets, 19)
    local empty_reopened_client = receiver()
    empty_reopened_client.accept(h.packets[6].snapshot)
    equal(empty_reopened_client.cache.map.items[27].owned_count, 27)
end)

test('failed prefetch retains full-resync requirement until successful retry', function()
    local h = harness()
    h.seed(0, 3, 1)
    local failed
    h.get(0, function(result) failed = result end, 1)
    h.fail(2)
    assert(not failed.ok)
    equal(#h.packets, 1)
    assert(h.get(0).pending)
    h.reply(3, {fixture(4, 2)})
    equal(h.packets[2].snapshot.snapshot_scope, 'cache')
    equal(h.packets[2].snapshot.tickets, 4)
end)

test('refresh publishes every pool and owned count without guessing purchase rewards', function()
    local h = harness()
    h.get(0, nil, 1)
    h.reply(1, {fixture(2, 0, 'map'), fixture(3, 1, 'special')})
    equal(#h.packets, 2)
    h.changed(0)
    h.reply(2, {fixture(9, 4, 'map'), fixture(10, 5, 'special')})
    equal(h.get(0).snapshot.tickets, 9)
    equal(h.get(0, nil, nil, 'special').snapshot.tickets, 10)
    equal(h.get(0, nil, nil, 'special').snapshot.items[1].owned_count, 5)
    equal(#h.reads, 2)
    equal(#h.commands, 0, 'profile change is read-only and grants no local inventory')
end)

print('LOTTERY_PURCHASE_REFRESH_PASS: ' .. passed .. ' regression cases; real event bus/delta; deferred authority; no network')
