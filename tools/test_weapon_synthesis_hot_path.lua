-- Exercise the real synthesis service, event bus and all authored recipes.
package.path = "scripts/vscripts/?.lua;" .. package.path
local bus = require("core/event_bus")
local events = require("core/events")
local actual_recipes = require("config/recipe_definitions")
assert(#actual_recipes.rows >= 10)
local original_print = print
local growth_reasons = {"attack_landed", "damage_dealt", "debug_attack_growth", "forging_hammer_changed"}
local function copy(value)
    local result = {}
    for key, entry in pairs(value or {}) do result[key] = entry end
    return result
end
local function harness(diagnostics, synchronous)
    bus.reset()
    package.loaded["systems/weapon_synthesis_service"] = nil
    package.loaded["config/generated/global_rules"] = {by_id = {
        runtime_detailed_diagnostics = {enabled = true, value = diagnostics and 1 or 0},
    }}
    local h = {tasks = {}, running = {}, registrations = 0, reads = 0,
        counts = {[0] = {}, [1] = {}}, transactions = {}, commits = {}, notifications = {}, logs = {}}
    print = function(message) h.logs[#h.logs + 1] = tostring(message) end
    local mode = {}
    function mode:SetContextThink(name, callback, delay)
        assert(delay == 0.10)
        assert(not h.running[name], "a reentrant synthesis event must reuse its active ContextThink")
        h.registrations = h.registrations + 1
        h.tasks[name] = callback
    end
    if synchronous then GameRules = nil
    else GameRules = {GetGameModeEntity = function() return mode end} end
    function h.run_one()
        local name, callback = next(h.tasks)
        if not name then return false end
        h.running[name] = true
        local delay = callback()
        h.running[name], h.tasks[name] = nil, nil
        if delay ~= nil then assert(delay == 0.10); h.tasks[name] = callback end
        return true
    end
    function h.drain()
        local runs = 0
        while h.run_one() do runs = runs + 1; assert(runs <= 200, "synthesis callback cannot spin forever") end
        return runs
    end
    function h.emit(event, payload) bus.emit(event, payload) end
    function h.grow(count, player_id)
        for index = 1, count do
            bus.emit(events.WEAPON_GROWTH_CHANGED, {
                player_id = player_id or 0,
                reason = growth_reasons[(index - 1) % #growth_reasons + 1],
                snapshot = {content_id = "weapon_growth_sword_01", stage = 1,
                    stage_attack_count = index, growth_attack = index, growth_strength = index},
            })
        end
    end
    bus.handle_request(events.CONTENT_INVENTORY_GET_REQUEST, function(payload)
        h.reads = h.reads + 1
        local snapshot = {counts = copy(h.counts[payload.player_id])}
        if h.on_read then h.on_read(payload.player_id) end
        if h.fail_read then return {ok = false, error = "injected_inventory_failure"} end
        return {ok = true, snapshot = snapshot}
    end)
    bus.handle_request(events.INVENTORY_TRANSACTION_EXECUTE_REQUEST, function(payload)
        h.transactions[#h.transactions + 1] = payload
        if h.fail_transaction then return {ok = false, error = "injected_transaction_failure"} end
        local counts = h.counts[payload.player_id]
        for id, amount in pairs(payload.consume) do
            if (counts[id] or 0) < amount then return {ok = false, error = "materials_changed"} end
        end
        for id, amount in pairs(payload.consume) do counts[id] = counts[id] - amount end
        for id, amount in pairs(payload.grant) do counts[id] = (counts[id] or 0) + amount end
        h.commits[#h.commits + 1] = payload
        bus.emit(events.CONTENT_INVENTORY_CHANGED, {player_id = payload.player_id, reason = payload.reason})
        return {ok = true}
    end)
    bus.subscribe(events.UI_NOTIFICATION, function(payload) h.notifications[#h.notifications + 1] = payload end)
    h.service = require("systems/weapon_synthesis_service")
    h.service.init()
    h.logs = {}
    return h
end
local function ingredients(h, player_id)
    h.counts[player_id] = {weapon_growth_sword_max = 1, item_death_mask = 1}
end
local function assert_no_detailed_logs(h)
    for _, message in ipairs(h.logs) do
        for _, name in ipairs({"SCHEDULE]", "SCAN_BEGIN]", "MATERIAL_CHECK]", "MATERIAL_MISSING]",
            "INFERNAL_PENDING]", "RUN_RELEASE]", "CHECK]"}) do
            assert(not message:find("WEAPON_SYNTH_" .. name, 1, true), "hot-path diagnostic must be opt-in: " .. message)
        end
    end
end

-- Attack progress never allocates delayed work, reads logical inventory,
-- formats recipe diagnostics or dirties an already scheduled empty check.
do
    local h = harness(false)
    h.grow(1000)
    assert(h.registrations == 0 and h.reads == 0 and #h.logs == 0 and next(h.tasks) == nil)
    h.emit(events.WEAPON_SYNTHESIS_CHECK_REQUESTED, {player_id = 0, reason = "explicit_check"})
    h.on_read = function() h.grow(1000) end
    assert(h.drain() == 1 and h.registrations == 1 and h.reads == 1,
        "growth during a scan cannot force a second scan; disabled infernal diagnostics do not fetch inventory")
    assert(#h.transactions == 0 and #h.logs == 0)
end

-- True inventory, equipment, explicit and unknown structural growth events
-- coalesce while waiting. The final inventory snapshot is read exactly once.
do
    local h = harness(false)
    for _ = 1, 100 do
        h.emit(events.CONTENT_INVENTORY_CHANGED, {player_id = "0", reason = "pickup"})
        h.emit(events.WEAPON_EQUIPPED_CHANGED, {player_id = 0})
        h.emit(events.WEAPON_GROWTH_CHANGED, {player_id = 0, reason = "stage_changed"})
        h.emit(events.WEAPON_SYNTHESIS_CHECK_REQUESTED, {player_id = 0})
    end
    assert(h.registrations == 1 and h.reads == 0)
    assert(h.drain() == 1 and h.reads == 1 and #h.logs == 0)
end

-- The per-attack growth notification precedes actual upgrades. Its inventory
-- commit still triggers the ordinary auto recipe, including string player ids.
for _, trigger in ipairs({events.CONTENT_INVENTORY_CHANGED, events.WEAPON_EQUIPPED_CHANGED,
        events.WEAPON_SYNTHESIS_CHECK_REQUESTED, events.WEAPON_GROWTH_CHANGED}) do
    local h = harness(false)
    h.grow(1000)
    ingredients(h, 0)
    h.emit(trigger, {player_id = "0", reason = "weapon_attack_upgrade"})
    h.drain()
    assert(h.counts[0].weapon_frost_blade_01 == 1 and h.counts[0].weapon_growth_sword_max == 0
        and h.counts[0].item_death_mask == 0 and #h.commits == 1 and #h.notifications == 1,
        "real stage upgrades and inventory/equipment events must still synthesize once")
    assert(h.registrations == 1 and next(h.tasks) == nil)
    assert_no_detailed_logs(h)
end

-- Inventory can change after a scan already captured its snapshot. This dirty
-- event must survive into the same native callback's next scheduled execution.
do
    local h = harness(false)
    h.on_read = function(player_id)
        h.on_read = nil
        ingredients(h, player_id)
        h.emit(events.CONTENT_INVENTORY_CHANGED, {player_id = player_id, reason = "reentrant_pickup"})
        h.grow(1000)
    end
    h.emit(events.CONTENT_INVENTORY_CHANGED, {player_id = 0})
    assert(h.run_one() and #h.commits == 0 and next(h.tasks) ~= nil)
    h.drain()
    assert(#h.commits == 1 and h.counts[0].weapon_frost_blade_01 == 1 and h.registrations == 1)
end

-- Consecutive recipes and independent players keep their transactional ordering
-- while reentrant inventory emissions are coalesced rather than overwritten.
do
    local h = harness(false)
    h.counts[0].material_molten_core_01 = 9
    ingredients(h, 1)
    h.emit(events.CONTENT_INVENTORY_CHANGED, {player_id = 0})
    h.emit(events.CONTENT_INVENTORY_CHANGED, {player_id = 1})
    h.drain()
    assert(h.counts[0].material_molten_core_03 == 1 and h.counts[0].material_molten_core_02 == 0
        and h.counts[0].material_molten_core_01 == 0)
    assert(h.counts[1].weapon_frost_blade_01 == 1 and #h.commits == 5 and h.registrations == 2)
    local ids = {}
    for _, tx in ipairs(h.commits) do
        local key = tx.player_id .. ":" .. tx.request_id
        assert(not ids[key], "new transactions need distinct per-player request ids")
        ids[key] = true
    end
end

-- Read errors, atomic-transaction failure and an actual scan exception all
-- release their pending slot; a later inventory/check event can retry safely.
for _, failure in ipairs({"inventory", "transaction", "scan"}) do
    local h = harness(false)
    ingredients(h, 0)
    if failure == "inventory" then h.fail_read = true
    elseif failure == "transaction" then h.fail_transaction = true
    else
        h.on_read = function()
            h.on_read = nil
            local recipe = actual_recipes.rows[1]
            h.old_ingredients = recipe.ingredients
            recipe.ingredients = 1 -- maps() errors inside the guarded scan.
        end
    end
    h.emit(events.CONTENT_INVENTORY_CHANGED, {player_id = 0})
    h.drain()
    assert(#h.commits == 0 and next(h.tasks) == nil)
    h.fail_read, h.fail_transaction = false, false
    if h.old_ingredients then actual_recipes.rows[1].ingredients = h.old_ingredients end
    h.emit(events.WEAPON_SYNTHESIS_CHECK_REQUESTED, {player_id = 0, reason = "retry"})
    h.drain()
    assert(#h.commits == 1 and h.registrations == 2 and h.counts[0].weapon_frost_blade_01 == 1)
    if failure == "transaction" then
        assert(h.transactions[1].request_id ~= h.transactions[2].request_id,
            "retry cannot replay an idempotently cached failed transaction")
    end
end

-- A reentrant dirty event is retained even when that read fails. Manual request
-- idempotency and the early-bootstrap synchronous path remain unchanged.
do
    local h = harness(false)
    h.on_read = function(player_id)
        h.on_read = nil
        ingredients(h, player_id)
        h.emit(events.CONTENT_INVENTORY_CHANGED, {player_id = player_id})
        error("injected inventory read error after dirty event")
    end
    h.emit(events.CONTENT_INVENTORY_CHANGED, {player_id = 0})
    h.drain()
    assert(#h.commits == 1 and h.registrations == 1 and next(h.tasks) == nil)
end
do
    local h = harness(false)
    ingredients(h, 0)
    local request = {player_id = 0, request_id = "manual_once", recipe_id = actual_recipes.rows[1].recipe_id}
    local first = bus.request(events.WEAPON_SYNTHESIS_REQUEST, request)
    local second = bus.request(events.WEAPON_SYNTHESIS_REQUEST, request)
    assert(first.ok and first == second and #h.transactions == 1)
    h.drain(); assert(#h.commits == 1)
end
do
    local h = harness(false, true)
    h.grow(1000); ingredients(h, 0)
    h.emit(events.CONTENT_INVENTORY_CHANGED, {player_id = 0})
    assert(h.counts[0].weapon_frost_blade_01 == 1 and #h.commits == 1 and h.registrations == 0)
end

-- Operators can still opt into detailed recipe diagnostics; enabling them
-- does not reintroduce scans for pure attack progress.
do
    local h = harness(true)
    h.grow(1000); assert(#h.logs == 0 and h.reads == 0 and h.registrations == 0)
    h.emit(events.CONTENT_INVENTORY_CHANGED, {player_id = 0})
    h.drain()
    local text = table.concat(h.logs, "\n")
    assert(text:find("WEAPON_SYNTH_SCAN_BEGIN", 1, true)
        and text:find("WEAPON_SYNTH_MATERIAL_CHECK", 1, true)
        and text:find("WEAPON_SYNTH_INFERNAL_PENDING", 1, true))
end
print = original_print
print("WEAPON_SYNTHESIS_HOT_PATH_PASS: 1000-hit bursts schedule/read/log zero; real ten-recipe upgrades, coalescing, reentrant dirty work, chains, player isolation, failures/retries and diagnostics preserved")
