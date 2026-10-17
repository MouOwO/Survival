-- Real profile commits -> real content inventory -> real equipment projection.
-- Lua 5.1; run from repository root. Only transport/native APIs are fixtures.
package.path = 'scripts/vscripts/?.lua;' .. package.path
local bus, events = require('core/event_bus'), require('core/events')
package.loaded['core/logger'] = {info = function() end, warn = function() end}
package.loaded['systems/player_entitlement_service'] = {replace_all = function() end}
PlayerResource = {IsValidPlayerID = function(_, id) return id == 0 or id == 1 end,
    GetTeam = function(_, id) return 2 + id end}
CustomNetTables = nil
GameRules = nil
local profiles = require('systems/player_profile_service')
local inventory = require('systems/content_inventory_service')
local equipment = require('systems/equipment_instance_service')
local original_update_sections = profiles.update_save_sections
local original_update_section = profiles.update_save_section
local passed = 0
local function equal(actual, expected, context)
    assert(actual == expected, (context or 'unexpected value') ..
        ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual))
end
local function copy(value)
    if type(value) ~= 'table' then return value end
    local out = {}
    for key, child in pairs(value) do out[key] = copy(child) end
    return out
end
local function request(event, payload)
    local result, err = bus.request(event, payload)
    assert(not err, err); return assert(result)
end
local function harness()
    bus.reset()
    profiles.update_save_sections = original_update_sections
    profiles.update_save_section = original_update_section
    local h = {events = {}, equipment_events = {}, writes = 0, revisions = {}, fail_write = false}
    profiles.init({provider = {
        init = function() end,
        resolve_account_id = function(id) return 'test_account_' .. tostring(id) end,
        fetch_snapshot = function() error('test must never perform HTTP') end,
        persist_save = function()
            h.writes = h.writes + 1
            if h.fail_write then return false, 'test_write_rejected' end
            return true
        end,
    }})
    inventory.init()
    equipment.init()
    bus.subscribe(events.CONTENT_INVENTORY_CHANGED, function(payload)
        h.events[#h.events + 1] = copy(payload)
    end)
    bus.subscribe(events.EQUIPMENT_INSTANCE_CHANGED, function(payload)
        h.equipment_events[#h.equipment_events + 1] = copy(payload)
    end)
    function h.commit(id, counts, reason)
        local profile = profiles.get_profile(id)
        local revision = profile and profile.revision or 0
        local result = profiles.apply_snapshot(id, {
            schema_version = 1, account_id = 'test_account_' .. tostring(id),
            revision = revision + 1, entitlements = {}, achievements = {}, public = {},
            save = {content_inventory = copy(counts), gameplay_stats = {}},
        }, reason or 'authoritative_purchase_refresh')
        assert(result.ok, result.error)
    end
    function h.counts(id)
        return request(events.CONTENT_INVENTORY_GET_REQUEST, {player_id = id or 0}).snapshot.counts
    end
    function h.instances(id)
        return request(events.EQUIPMENT_INSTANCE_GET_REQUEST, {player_id = id or 0}).instances
    end
    function h.grant(id, content, count)
        return request(events.CONTENT_INVENTORY_GRANT_REQUEST,
            {player_id = id, content_id = content, count = count, reason = 'fixture_local_grant'})
    end
    function h.transaction(id, consume, grant)
        return request(events.CONTENT_INVENTORY_TRANSACTION_REQUEST,
            {player_id = id, consume = consume, grant = grant, reason = 'fixture_transaction'})
    end
    return h
end
local function test(name, run)
    local ok, err = pcall(run)
    assert(ok, name .. ': ' .. tostring(err))
    passed = passed + 1
    print('PASS ' .. name)
end

test('nil profiles and empty initial commits do not fabricate inventory', function()
    local h = harness()
    equal(next(h.counts()), nil)
    bus.emit(events.PLAYER_PROFILE_CHANGED, {player_id = 0})
    bus.emit(events.PLAYER_PROFILE_CHANGED, {})
    bus.emit(events.PLAYER_PROFILE_CHANGED, {player_id = 99})
    equal(#h.events, 0)
    h.commit(0, {})
    equal(#h.events, 0)
    equal(next(h.instances()), nil)
    equal(h.writes, 0, 'read-only profile projection never persists')
end)

test('invalid player input retains ordinary rejection without indexing mutation state', function()
    local h = harness()
    for _, id in ipairs({-1, 99, 0/0, math.huge, 'unknown'}) do
        local result, err = bus.request(events.CONTENT_INVENTORY_GRANT_REQUEST,
            {player_id = id, content_id = 'lottery_ticket', count = 1})
        assert(not err, err)
        assert(result and not result.ok)
    end
    equal(#h.events, 0)
    equal(h.writes, 0)
end)

test('initial authoritative content refresh reaches existing equipment consumer', function()
    local h = harness()
    h.commit(0, {lottery_ticket = 3, special_lottery_ticket = 2})
    equal(#h.events, 1)
    equal(h.events[1].changes.lottery_ticket, 3)
    equal(h.instances().lottery_ticket.quantity, 3)
    equal(h.instances().special_lottery_ticket.quantity, 2)
    equal(#h.equipment_events, 1)
    equal(h.writes, 0)
end)

test('purchased tickets and other permanent items refresh consumers without a write', function()
    local h = harness()
    h.commit(0, {lottery_ticket = 3, special_lottery_ticket = 2, lottery_nature_crystal = 1})
    h.commit(0, {lottery_ticket = 10, special_lottery_ticket = 7, lottery_nature_crystal = 4},
        'any_authoritative_reason')
    equal(#h.events, 2)
    local event = h.events[2]
    equal(event.changes.lottery_ticket, 7)
    equal(event.changes.special_lottery_ticket, 5)
    equal(event.changes.lottery_nature_crystal, 3)
    equal(event.snapshot.counts.lottery_ticket, 10)
    equal(h.instances().lottery_ticket.quantity, 10)
    equal(h.instances().lottery_nature_crystal.quantity, 4)
    equal(h.writes, 0, 'external purchase is not persisted or granted a second time')
end)

test('decreases and zero/removal update actual equipment instances', function()
    local h = harness()
    h.commit(0, {lottery_ticket = 10, special_lottery_ticket = 5, lottery_nature_crystal = 4})
    h.commit(0, {lottery_ticket = 2, special_lottery_ticket = 0})
    equal(#h.events, 2)
    equal(h.events[2].changes.lottery_ticket, -8)
    equal(h.events[2].changes.special_lottery_ticket, -5)
    equal(h.events[2].changes.lottery_nature_crystal, -4)
    equal(h.instances().lottery_ticket.quantity, 2)
    equal(h.instances().special_lottery_ticket, nil)
    equal(h.instances().lottery_nature_crystal, nil)
    equal(h.writes, 0)
end)

test('equivalent normalized aliases do not refresh unchanged quantities', function()
    local h = harness()
    h.commit(0, {lottery_flame_crystal = 2, lottery_nature_crystal = 3})
    equal(h.instances().lottery_nature_crystal.quantity, 5)
    equal(h.instances().lottery_flame_crystal, nil)
    h.commit(0, {lottery_nature_crystal = '5'})
    equal(#h.events, 1, 'canonical representation change is not an inventory change')
    h.commit(0, {lottery_flame_crystal = 7.8})
    equal(#h.events, 2)
    equal(h.events[2].changes.lottery_nature_crystal, 2)
    equal(h.instances().lottery_nature_crystal.quantity, 7)
    equal(h.writes, 0)
end)

test('unchanged profile, unrelated fields and source ordering do not republish', function()
    local h = harness()
    h.commit(0, {lottery_ticket = 5, special_lottery_ticket = 2})
    h.commit(0, {special_lottery_ticket = 2, lottery_ticket = 5})
    bus.emit(events.PLAYER_PROFILE_CHANGED, {player_id = 0, reason = 'ui_or_entitlement_refresh'})
    equal(#h.events, 1)
    equal(#h.equipment_events, 1)
    equal(h.writes, 0)
end)

test('profile refresh preserves match weapons and ignores persisted match copies', function()
    local h = harness()
    h.commit(0, {lottery_ticket = 5})
    assert(h.grant(0, 'weapon_growth_sword_01', 1).ok)
    equal(h.writes, 0)
    h.commit(0, {lottery_ticket = 8, weapon_growth_sword_01 = 99, item_death_mask = 88})
    equal(h.counts().weapon_growth_sword_01, 1)
    equal(h.counts().item_death_mask, nil)
    equal(h.instances().weapon_growth_sword_01.quantity, 1)
    equal(h.instances().item_death_mask, nil)
    equal(h.events[#h.events].changes.weapon_growth_sword_01, nil)
    equal(h.events[#h.events].changes.item_death_mask, nil)
    equal(h.events[#h.events].changes.lottery_ticket, 3)
    equal(h.writes, 0)
end)

test('all profile projections finish before dependent inventory notification', function()
    local h = harness()
    local projected = {}
    local checked = 0
    bus.subscribe(events.PLAYER_PROFILE_CHANGED, function(payload)
        projected[payload.player_id] = profiles.get_profile(payload.player_id).revision
    end)
    bus.subscribe(events.CONTENT_INVENTORY_CHANGED, function(payload)
        equal(projected[payload.player_id], profiles.get_profile(payload.player_id).revision,
            'profile subscribers must finish before inventory consumer')
        checked = checked + 1
    end)
    h.commit(0, {lottery_ticket = 3})
    h.commit(0, {lottery_ticket = 8})
    equal(checked, 2)
end)

test('nested profile changes coalesce against final committed inventory', function()
    local h = harness()
    h.commit(0, {lottery_ticket = 3})
    local finished, checked = false, false
    bus.subscribe(events.CONTENT_INVENTORY_CHANGED, function(payload)
        if payload.snapshot.counts.lottery_ticket == 9 then
            assert(finished, 'outer event projections must finish first')
            checked = true
        end
    end)
    bus.subscribe('test.profile_batch', function()
        h.commit(0, {lottery_ticket = 6})
        h.commit(0, {lottery_ticket = 9})
        equal(#h.events, 1, 'batch must not emit intermediate inventory')
        finished = true
    end)
    bus.emit('test.profile_batch', {})
    equal(#h.events, 2)
    equal(h.events[2].changes.lottery_ticket, 6)
    equal(h.instances().lottery_ticket.quantity, 9)
    assert(checked)
end)

test('different players have independent profile, match inventory and consumers', function()
    local h = harness()
    h.commit(0, {lottery_ticket = 3})
    h.commit(1, {lottery_ticket = 20})
    h.grant(0, 'weapon_growth_sword_01', 1)
    local start = #h.events
    bus.subscribe('test.multiplayer_profile_batch', function()
        h.commit(0, {lottery_ticket = 8})
        h.commit(1, {lottery_ticket = 31})
    end)
    bus.emit('test.multiplayer_profile_batch', {})
    equal(#h.events, start + 2)
    equal(h.instances(0).lottery_ticket.quantity, 8)
    equal(h.instances(1).lottery_ticket.quantity, 31)
    equal(h.instances(0).weapon_growth_sword_01.quantity, 1)
    equal(h.instances(1).weapon_growth_sword_01, nil)
    equal(h.counts(0).weapon_growth_sword_01, 1)
    equal(h.counts(1).weapon_growth_sword_01, nil)
    equal(h.writes, 0)
end)

test('local permanent grant sends one existing notification despite profile commit', function()
    local h = harness()
    h.commit(0, {lottery_ticket = 3})
    local start = #h.events
    local result = h.grant(0, 'lottery_ticket', 4)
    assert(result.ok)
    equal(#h.events, start + 1, 'do not duplicate synchronous local grant profile event')
    equal(h.events[#h.events].reason, 'fixture_local_grant')
    equal(h.events[#h.events].changes.lottery_ticket, 4)
    equal(h.instances().lottery_ticket.quantity, 7)
    equal(h.writes, 1)
    bus.emit(events.PLAYER_PROFILE_CHANGED, {player_id = 0})
    equal(#h.events, start + 1)
end)

test('local permanent transaction sends one existing notification and keeps changes', function()
    local h = harness()
    h.commit(0, {lottery_ticket = 3})
    local start = #h.events
    local result = h.transaction(0, {lottery_ticket = 2}, {special_lottery_ticket = 1})
    assert(result.ok)
    equal(#h.events, start + 1)
    equal(h.events[#h.events].reason, 'fixture_transaction')
    equal(h.events[#h.events].changes.lottery_ticket, -2)
    equal(h.events[#h.events].changes.special_lottery_ticket, 1)
    equal(h.instances().lottery_ticket.quantity, 1)
    equal(h.instances().special_lottery_ticket.quantity, 1)
    equal(h.writes, 1)
end)

test('rejected local write preserves counts and cannot suppress next purchase', function()
    local h = harness()
    h.commit(0, {lottery_ticket = 3})
    h.fail_write = true
    local result = h.grant(0, 'lottery_ticket', 4)
    assert(not result.ok)
    equal(#h.events, 1)
    equal(h.counts().lottery_ticket, 3)
    h.commit(0, {lottery_ticket = 8})
    equal(#h.events, 2)
    equal(h.instances().lottery_ticket.quantity, 8)
    equal(h.writes, 1, 'authoritative refresh does not retry rejected local writes')
end)

test('throwing local writer releases mutation guard for subsequent purchase', function()
    local h = harness()
    h.commit(0, {lottery_ticket = 3})
    profiles.update_save_sections = function() error('expected_writer_failure') end
    local result, err = bus.request(events.CONTENT_INVENTORY_GRANT_REQUEST,
        {player_id = 0, content_id = 'lottery_ticket', count = 4})
    equal(result, nil)
    assert(err and tostring(err):find('expected_writer_failure'))
    equal(#h.events, 1)
    h.commit(0, {lottery_ticket = 8})
    equal(#h.events, 2)
    equal(h.instances().lottery_ticket.quantity, 8)
    equal(h.writes, 0)
end)

test('throw after a real committed profile still publishes that authoritative change', function()
    local h = harness()
    h.commit(0, {lottery_ticket = 3})
    profiles.update_save_sections = function(...)
        local result = original_update_sections(...)
        assert(result.ok)
        error('expected_failure_after_commit')
    end
    local result, err = bus.request(events.CONTENT_INVENTORY_GRANT_REQUEST,
        {player_id = 0, content_id = 'lottery_ticket', count = 4})
    equal(result, nil)
    assert(err and tostring(err):find('expected_failure_after_commit'))
    equal(#h.events, 2, 'committed ownership must reach consumers even if caller throws')
    equal(h.instances().lottery_ticket.quantity, 7)
    h.commit(0, {lottery_ticket = 9})
    equal(#h.events, 3)
    equal(h.instances().lottery_ticket.quantity, 9)
    equal(h.writes, 1)
end)

print('PURCHASE_INVENTORY_REFRESH_PASS: ' .. passed ..
    ' cases; real profile/inventory/equipment/event bus; no network or real account writes')
