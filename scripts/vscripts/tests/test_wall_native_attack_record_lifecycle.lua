-- Offline contract for the test-only native attack-record drain gate. A Stop
-- call is not an OnAttackRecordDestroy event and must never authorize cleanup.
package.path = 'scripts/vscripts/?.lua;' .. package.path

local function forbidden(name)
    return function() error('drain ledger must not call production/native business: ' .. name, 2) end
end
for _, name in ipairs({ 'CreateUnitByName', 'CreateUnitByNameAsync', 'FindUnitsInRadius',
    'FindUnitsInLine', 'ApplyDamage', 'CreateHTTPRequestScriptVM', 'CreateHTTPRequest',
    'SendToServerConsole', 'ExecuteOrderFromTable', 'UTIL_Remove' }) do
    _G[name] = forbidden(name)
end
HTTP = setmetatable({}, { __index = function(_, key) return forbidden('HTTP.' .. tostring(key)) end })
PlayerResource = setmetatable({}, {
    __index = function(_, key) return forbidden('PlayerResource.' .. tostring(key)) end,
})
GameRules = setmetatable({}, {
    __index = function(_, key) return forbidden('GameRules.' .. tostring(key)) end,
})

local original_require = require
require = function(name)
    assert(name == 'tests/wall_native_attack_record_lifecycle',
        'attack-record ledger must not import production modules: ' .. tostring(name))
    return original_require(name)
end
local lifecycle = require('tests/wall_native_attack_record_lifecycle')
assert(type(lifecycle.new) == 'function', 'test-only record lifecycle constructor is required')

local tests, failures = 0, {}
local function test(name, callback)
    tests = tests + 1
    local ok, message = pcall(callback)
    if not ok then failures[#failures + 1] = name .. ': ' .. tostring(message) end
end

local function unit(id)
    local result = {
        id = id, alive = true, removed = false, modifiers = {}, modifier_adds = 0,
        force_clears = 0, stops = 0, interrupts = 0, acquisition_writes = 0,
        modifier_refreshes = 0, modifier_destroys = 0, modifier_removes = 0,
        modifier_stack_writes = 0,
    }
    function result:entindex() return self.id end
    function result:IsNull() return self.removed end
    function result:IsAlive() return self.alive end
    function result:AddNewModifier(caster, _, name)
        assert(not self.removed, 'cannot attach an observer to a removed entity')
        assert(caster == self, 'native record observer must be owned by its actual unit')
        assert(type(name) == 'string' and not name:lower():find('phas', 1, true),
            'record draining must not phase units or change their collision policy')
        self.modifier_adds = self.modifier_adds + 1
        local owner = self
        local modifier = { removed = false, name = name }
        function modifier:IsNull() return self.removed end
        function modifier:GetParent() return owner end
        function modifier:SetStackCount(value)
            assert(value == 1, 'record audit drain state must use its disarm flag')
            assert(owner.survival_native_attack_record_lifecycle.draining,
                'draining must be visible before native observer disarm')
            owner.modifier_stack_writes = owner.modifier_stack_writes + 1
        end
        function modifier:ForceRefresh()
            assert(not self.removed, 'cannot refresh a destroyed observer')
            assert(owner.survival_native_attack_record_lifecycle.draining,
                'draining must be visible before native observer state refresh')
            owner.modifier_refreshes = owner.modifier_refreshes + 1
        end
        function modifier:Destroy()
            assert(not self.removed, 'observer destruction must not be repeated')
            self.removed = true
            owner.modifier_destroys = owner.modifier_destroys + 1
            owner.modifiers[name] = nil
        end
        self.modifiers[name] = modifier
        return modifier
    end
    function result:FindModifierByName(name) return self.modifiers[name] end
    function result:RemoveModifierByName(name)
        local modifier = assert(self.modifiers[name], 'cannot remove an unknown record observer')
        self.modifier_removes = self.modifier_removes + 1
        modifier:Destroy()
    end
    function result:SetForceAttackTarget(target)
        assert(target == nil, 'drain must clear the force target')
        self.force_clears = self.force_clears + 1
    end
    function result:Stop() self.stops = self.stops + 1 end
    function result:Interrupt() self.interrupts = self.interrupts + 1 end
    function result:SetAcquisitionRange(value)
        assert(value == 0, 'drain must disable further native target acquisition')
        self.acquisition_writes = self.acquisition_writes + 1
    end
    return result
end

local function fixture(options)
    local clock = { time = 0 }
    local parameters = {
        timeout = 5, quiet_seconds = .1, min_drain_seconds = .15,
        now = function() return clock.time end,
    }
    for key, value in pairs(options or {}) do parameters[key] = value end
    return lifecycle.new(parameters), clock
end

local function summary(ledger, expected)
    local value = ledger:summary()
    for _, key in ipairs({ 'pending', 'created', 'destroyed', 'drain_created', 'unknown_destroy' }) do
        assert(type(value[key]) == 'number' and value[key] >= 0,
            'summary requires nonnegative numeric ' .. key)
    end
    for _, key in ipairs({ 'draining', 'ready', 'timed_out', 'passed' }) do
        assert(type(value[key]) == 'boolean', 'summary requires boolean ' .. key)
    end
    assert(type(value.errors) == 'table', 'summary must expose lifecycle errors')
    for key, expected_value in pairs(expected or {}) do
        assert(value[key] == expected_value,
            'summary.' .. key .. ' expected ' .. tostring(expected_value)
                .. ', got ' .. tostring(value[key]))
    end
    return value
end

local function attach(ledger, actor)
    local ok, message = ledger:attach(actor)
    assert(ok == true, 'observer attachment failed: ' .. tostring(message))
    local state = assert(actor.survival_native_attack_record_lifecycle)
    assert(state.owner == ledger and state.unit == actor and type(state.pending) == 'table',
        'unit must own a ledger-scoped pending-record table')
    assert(state.draining == false and state.modifier,
        'attached observer state must start outside drain and retain its native modifier')
    return state
end

local function record(ledger, actor, id)
    ledger:on_record(actor, { attacker = actor, record = id })
end

local function destroy(ledger, actor, id)
    ledger:on_record_destroy(actor, { attacker = actor, record = id })
end

local function assert_one_stop(actor)
    assert(actor.force_clears == 1 and actor.stops == 1 and actor.interrupts == 1
        and actor.acquisition_writes == 1 and actor.modifier_refreshes == 1
        and actor.modifier_stack_writes == 1,
        'each live unit must be stopped and refreshed exactly once per drain')
end

test('event lifecycle and minimum drain duration', function()
    local ledger, clock = fixture()
    local actor = unit(1)
    local state = attach(ledger, actor)
    summary(ledger, { pending = 0, created = 0, destroyed = 0, draining = false,
        ready = false, timed_out = false, passed = false })
    record(ledger, actor, 101)
    assert(state.pending[101] ~= nil, 'record creation must be retained by its unit')
    summary(ledger, { pending = 1, created = 1, destroyed = 0, drain_created = 0 })
    clock.time = .02
    ledger:begin_drain()
    assert(state.draining == true, 'begin_drain must switch the record observer to drain mode')
    assert_one_stop(actor)
    assert(ledger:poll() == 'pending', 'Stop/Interrupt cannot stand in for destroy callbacks')
    summary(ledger, { pending = 1, passed = false, ready = false })
    clock.time = .03
    destroy(ledger, actor, 101)
    assert(state.pending[101] == nil, 'destroy callback must release its exact record')
    summary(ledger, { pending = 0, created = 1, destroyed = 1 })
    clock.time = .16
    assert(ledger:poll() == 'pending', 'quiet records do not bypass the minimum drain duration')
    clock.time = .18
    assert(ledger:poll() == 'ready', 'fully destroyed and quiet records must permit cleanup')
    local result = summary(ledger, { pending = 0, ready = true, timed_out = false, passed = true })
    assert(#result.errors == 0, 'normal native record destruction must be clean')
end)

test('same native record ID belongs to each unit independently', function()
    local ledger, clock = fixture()
    local first, second = unit(2), unit(3)
    local a, b = attach(ledger, first), attach(ledger, second)
    record(ledger, first, 77)
    record(ledger, second, 77)
    ledger:begin_drain()
    assert_one_stop(first)
    assert_one_stop(second)
    summary(ledger, { pending = 2, created = 2 })
    destroy(ledger, first, 77)
    assert(a.pending[77] == nil and b.pending[77] ~= nil,
        'one unit record destruction must not clear another unit using the same ID')
    clock.time = .3
    assert(ledger:poll() == 'pending', 'another unit still owns a native attack record')
    destroy(ledger, second, 77)
    clock.time = .35
    assert(ledger:poll() == 'pending', 'final record must receive its full quiet period')
    clock.time = .41
    assert(ledger:poll() == 'ready', 'all units have independently drained')
    summary(ledger, { pending = 0, created = 2, destroyed = 2, passed = true })
end)

test('late drain record restarts the quiet period', function()
    local ledger, clock = fixture()
    local actor = unit(4)
    attach(ledger, actor)
    ledger:begin_drain()
    clock.time = .14
    record(ledger, actor, 8)
    summary(ledger, { pending = 1, created = 1, drain_created = 1, passed = false })
    clock.time = .3
    assert(ledger:poll() == 'pending', 'a drain-time record cannot be silently ignored')
    destroy(ledger, actor, 8)
    clock.time = .399
    assert(ledger:poll() == 'pending', 'late record destruction restarts the full quiet window')
    clock.time = .401
    assert(ledger:poll() == 'ready', 'late records can drain through their real destroy event')
    summary(ledger, { pending = 0, created = 1, destroyed = 1, drain_created = 1, passed = true })
end)

test('repeated attachment and drain cannot erase or restart a phase', function()
    local ledger, clock = fixture()
    local actor = unit(5)
    local state = attach(ledger, actor)
    record(ledger, actor, 19)
    ledger:attach(actor)
    assert(actor.survival_native_attack_record_lifecycle == state and actor.modifier_adds == 1
        and state.pending[19] ~= nil, 'duplicate attachment must preserve the original observer and pending records')
    ledger:begin_drain()
    clock.time = .09
    destroy(ledger, actor, 19)
    clock.time = .18
    ledger:begin_drain()
    assert_one_stop(actor)
    clock.time = .2
    assert(ledger:poll() == 'ready', 'repeated begin_drain must not reset the original drain timestamp')
    ledger:begin_drain()
    assert_one_stop(actor)
    assert(ledger:poll() == 'ready', 'a completed drain cannot be reopened by another begin_drain')
    summary(ledger, { created = 1, destroyed = 1, pending = 0, passed = true })
end)

test('pending detach is refused and clean detach removes only the observer', function()
    local ledger, clock = fixture()
    local actor = unit(6)
    local state = attach(ledger, actor)
    record(ledger, actor, 21)
    local ok, message = ledger:detach(actor)
    assert(ok == false and message ~= nil, 'pending native records must refuse observer detachment with a reason')
    assert(actor.survival_native_attack_record_lifecycle == state
        and actor.modifier_destroys == 0, 'refused detach must preserve the live record observer')
    ledger:begin_drain()
    destroy(ledger, actor, 21)
    clock.time = .2
    assert(ledger:poll() == 'ready', 'a refused detach must not poison an otherwise valid drain')
    local detached, error_message = ledger:detach(actor)
    assert(detached == true, 'clean observer detach failed: ' .. tostring(error_message))
    assert(actor.survival_native_attack_record_lifecycle == nil and actor.modifier_destroys == 1,
        'clean detach must destroy the native observer and release the unit state')
    assert(not actor.removed, 'test cleanup must not remove a production entity')
    summary(ledger, { pending = 0, passed = true })
    ledger:detach(actor)
    assert(actor.modifier_destroys == 1, 'repeated detach must not destroy the native observer twice')
end)

test('duplicate record creation is diagnostic failure, never false green', function()
    local ledger, clock = fixture()
    local actor = unit(7)
    attach(ledger, actor)
    record(ledger, actor, 44)
    record(ledger, actor, 44)
    local result = summary(ledger, { pending = 1, passed = false })
    assert(#result.errors > 0, 'duplicate create must be recorded instead of silently overwriting')
    ledger:begin_drain()
    destroy(ledger, actor, 44)
    clock.time = .3
    assert(ledger:poll() == 'failed', 'balanced counts cannot erase a duplicate-record invariant failure')
    summary(ledger, { pending = 0, ready = false, passed = false })
end)

test('unknown and duplicate destroy do not decrement another pending record', function()
    local ledger, clock = fixture()
    local actor = unit(8)
    local state = attach(ledger, actor)
    record(ledger, actor, 51)
    destroy(ledger, actor, 999)
    assert(state.pending[51] ~= nil, 'unknown destroy must not clear another outstanding record')
    local result = summary(ledger, { pending = 1, unknown_destroy = 1, passed = false })
    assert(#result.errors > 0, 'unknown destroy must retain a diagnostic invariant failure')
    ledger:begin_drain()
    destroy(ledger, actor, 51)
    destroy(ledger, actor, 51)
    summary(ledger, { pending = 0, unknown_destroy = 2, passed = false })
    clock.time = .3
    assert(ledger:poll() == 'failed', 'unknown or double destroy must never make a case pass')
end)

test('timeout preserves pending evidence and remains failed after late destruction', function()
    local ledger, clock = fixture()
    local actor = unit(9)
    local state = attach(ledger, actor)
    record(ledger, actor, 62)
    ledger:begin_drain()
    clock.time = 4.99
    assert(ledger:poll() == 'pending', 'deadline must allow the configured native drain duration')
    clock.time = 5.01
    assert(ledger:poll() == 'timeout', 'outstanding native records must time out instead of appearing ready')
    assert(state.pending[62] ~= nil, 'timeout must not discard the original outstanding record')
    summary(ledger, { pending = 1, timed_out = true, ready = false, passed = false })
    clock.time = 5.1
    destroy(ledger, actor, 62)
    clock.time = 5.3
    assert(ledger:poll() ~= 'ready', 'a late destroy must not turn an already timed-out case green')
    summary(ledger, { pending = 0, timed_out = true, ready = false, passed = false })
    assert(ledger:detach(actor) == true, 'late destruction may allow safe observer disposal without passing the case')
end)

test('destroy after deadline before first poll remains timed out', function()
    local ledger, clock = fixture()
    local actor = unit(11)
    attach(ledger, actor)
    record(ledger, actor, 88)
    ledger:begin_drain()
    clock.time = 5.01
    destroy(ledger, actor, 88)
    clock.time = 5.2
    assert(ledger:poll() == 'timeout', 'late final destroy cannot erase a deadline before the next poll')
    summary(ledger, { pending = 0, created = 1, destroyed = 1, timed_out = true, passed = false })
end)

test('externally removed entity with pending records is a hard failure', function()
    local ledger, clock = fixture()
    local actor = unit(10)
    local state = attach(ledger, actor)
    record(ledger, actor, 73)
    ledger:begin_drain()
    actor.removed = true
    clock.time = .3
    assert(ledger:poll() == 'failed', 'entity deletion cannot substitute for native record destruction')
    assert(state.pending[73] ~= nil, 'externally removed unit must retain the missing-record evidence')
    local result = summary(ledger, { pending = 1, ready = false, passed = false })
    assert(#result.errors > 0, 'external entity removal must explain why native cleanup is unsafe')
    local errors = #result.errors
    assert(ledger:poll() == 'failed', 'a terminal failure must not disappear on repeated polls')
    assert(#summary(ledger).errors == errors, 'repeated polls must not append the same removed-entity error forever')
end)

test('empty ledger still observes drain timing without gameplay work', function()
    local ledger, clock = fixture()
    assert(ledger:poll() == 'pending', 'a case must explicitly enter drain before becoming ready')
    ledger:begin_drain()
    clock.time = .149
    assert(ledger:poll() == 'pending', 'an empty ledger still needs the native minimum drain window')
    clock.time = .151
    assert(ledger:poll() == 'ready', 'an empty clean drain must finish after minimum and quiet windows')
    local result = summary(ledger, { pending = 0, created = 0, destroyed = 0,
        drain_created = 0, unknown_destroy = 0, ready = true, passed = true })
    assert(#result.errors == 0, 'empty drain must not invent record failures')
end)

assert(#failures == 0, 'native record lifecycle failures:\n' .. table.concat(failures, '\n'))
print('WALL_NATIVE_ATTACK_RECORD_LIFECYCLE_PASS cases=' .. tests
    .. ' native_destroy=required unit_ids=independent quiet=required timeout=fail'
    .. ' duplicate_events=fail external_removal=fail drain=idempotent phase=forbidden business=forbidden')
