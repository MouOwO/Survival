-- Real repair AI/registry/order service, with an engine-like interval scheduler.
-- Run from addon root: lua tools/test_repair_idle_recovery.lua
package.path = 'scripts/vscripts/?.lua;' .. package.path
class = function(t) t.__index = t; return t end
IsServer = function() return true end
MODIFIER_ATTRIBUTE_PERMANENT, ACT_DOTA_ATTACK = 1, 2
FIND_UNITS_EVERYWHERE = -1
DOTA_UNIT_ORDER_STOP, DOTA_UNIT_ORDER_MOVE_TO_POSITION = 21, 1
DOTA_UNIT_ORDER_MOVE_TO_TARGET, DOTA_UNIT_ORDER_ATTACK_TARGET = 2, 4
Vector = function(x, y, z) return {x = x, y = y, z = z or 0} end
local now, entities, registered, modifiers = 0, {}, {}, {}
GameRules = {GetGameTime = function() return now end}
Time = function() return now end
local closest_calls, snapshots, orders, ticks, checks = 0, 0, {}, 0, 0
local function check(condition, description)
    checks = checks + 1
    assert(condition, description)
end
FindUnitsInRadius = function() error('repair must not scan engine units') end
Entities = {FindAllByClassname = function() error('repair must not scan entity classes') end}
EntIndexToHScript = function(index) return entities[index] end
local bus, events = require('core/event_bus'), require('core/events')
local candidates = require('systems/repair_building_candidates')
local wakeup = require('systems/repair_worker_wakeup')
local actual_closest = candidates.closest
candidates.closest = function(...)
    closest_calls = closest_calls + 1
    return actual_closest(...)
end
package.loaded['systems/builder_work_position_service'] = {
    find = function(_, _, position) return Vector(position.x - 30, position.y) end,
}
local definition = require('modifiers/modifier_repair_worker_ai')
local order_service = require('systems/repair_order_service')
local function unit(index, owner, x, building)
    local u = {index = index, survival_player_id = owner, team = 2, position = Vector(x, 0),
        survival_is_building = building, health = 1000, maximum = 1000, alive = true, idle = true}
    function u:IsNull() return self.removed == true end
    function u:IsAlive() return self.alive end
    function u:IsIdle() return self.idle end
    function u:entindex() return self.index end
    function u:GetTeamNumber() return self.team end
    function u:GetAbsOrigin() self.position_reads = (self.position_reads or 0) + 1; return self.position end
    function u:GetHullRadius() return 0 end
    function u:HasModifier() return self.constructing == true end
    function u:GetHealth() self.health_reads = (self.health_reads or 0) + 1; return self.health end
    function u:GetMaxHealth() return self.maximum end
    function u:SetHealth(value) self.health = value end
    function u:FaceTowards() end
    function u:StartGesture() self.gestures = (self.gestures or 0) + 1 end
    function u:IsChanneling() return self.channeling == true end
    function u:GetCurrentActiveAbility() return self.active_ability end
    function u:FindModifierByName(name) return name == 'modifier_repair_worker_ai' and self.repair end
    entities[index] = u
    return u
end
ExecuteOrderFromTable = function(order)
    local u = assert(entities[order.UnitIndex])
    orders[#orders + 1] = {order = order, time = now}
    check(order_service.process({issuer_player_id_const = -1,
        order_type = order.OrderType, units = {['0'] = u.index}}) == false,
        'deferred/internal engine movement cannot cancel its own repair')
    u.idle = order.OrderType == DOTA_UNIT_ORDER_STOP
end
local function register(u)
    u.survival_building_id = 'wall'
    local payload = {unit = u, entindex = u.index, player_id = u.survival_player_id,
        building_id = 'wall', team = u.team}
    registered[u] = payload
    bus.emit(events.BUILDING_CREATED, payload)
end
local function fixture()
    for _, m in ipairs(modifiers) do if m.OnDestroy then m:OnDestroy() end end
    now, entities, registered, modifiers = 0, {}, {}, {}
    closest_calls, snapshots, orders, ticks = 0, 0, {}, 0
    candidates.reset()
    bus.reset()
    bus.handle_request(events.BUILDING_LIST_REQUEST, function(payload)
        check(payload.handles_only == true, 'registry seed uses handle-only formal buildings')
        snapshots = snapshots + 1
        local result = {}
        for _, record in pairs(registered) do result[#result + 1] = record end
        return {ok = true, buildings = result}
    end)
end
local function worker(index, owner, x)
    local u = unit(index, owner, x, false)
    u.survival_worker_type = 'repairer'
    local m = setmetatable({}, definition)
    u.repair = m
    function m:GetParent() return u end
    function m:StartIntervalThink(interval)
        self.interval = interval
        self.next_due = interval >= 0 and now + interval or math.huge
        self.interval_changes = (self.interval_changes or 0) + 1
    end
    m:OnCreated({repair_max_health_pct_per_second = 2, repair_range = 200, detection_range = 1000})
    modifiers[#modifiers + 1] = m
    return u, m
end
local function advance(seconds)
    local deadline = now + seconds
    local safety = 0
    while true do
        local due = math.huge
        for _, m in ipairs(modifiers) do due = math.min(due, m.next_due or math.huge) end
        if due > deadline + 1e-8 then break end
        now = due
        for _, m in ipairs(modifiers) do
            if (m.next_due or math.huge) <= now + 1e-8 then
                m.next_due = now + m.interval
                ticks = ticks + 1
                m:OnIntervalThink()
            end
        end
        safety = safety + 1
        assert(safety < 100000, 'repair scheduler must not reschedule itself at zero delay')
    end
    now = deadline
end

-- A damaged wall need not receive another attack to wake an idle repairer.
fixture()
local wall = unit(1, 0, 0, true); register(wall)
local u, m = worker(101, 0, 100)
wall.health = 989
check(m.interval == 1, 'new idle repair worker checks once per second')
advance(0.99)
check(wall.health == 989 and closest_calls == 0, 'idle interval does not perform hidden 100 ms candidate scans')
advance(0.01)
check(wall.health > 989 and m.repair_target_handle == wall, '98.9% wall is repaired without any damage event')
check(m.interval == 0.1, 'actual repair retains its smooth healing interval')
advance(0.5)
check(wall.health == 1000 and not m.repairing, 'repair continues through 99% until completely full')
check(m.interval == 1 and not m.repair_target_handle, 'completed automatic work releases target and returns to idle cadence')
local scanned = closest_calls
advance(5)
check(closest_calls - scanned <= 5, 'full-health idle candidate scans are bounded to once each second')
check(snapshots == 1, 'the idle heartbeat reuses one lifecycle-maintained registry seed')

-- The exact boundary is admission-only; the worker still fills an admitted wall.
fixture()
wall = unit(1, 0, 0, true); register(wall)
u, m = worker(101, 0, 100)
wall.health = 990
advance(3)
check(wall.health == 990 and not m.repair_target_handle and not u.gestures,
    'a wall at exactly 99% does not begin new automatic repair')
wall.health = 989
advance(1)
check(m.repairing and wall.health > 990, 'a wall below 99% starts and crosses its admission threshold')
advance(1)
check(wall.health == 1000, '99% is not a stopping condition once work began')

-- Explicit wall assignment stays at the wall without movement/scan churn.
fixture()
wall = unit(1, 0, 0, true); register(wall)
u, m = worker(101, 0, 100)
check(m:SetManualRepairTarget(wall), 'full wall can be explicitly assigned as standby target')
advance(1)
local before_orders, before_scans = #orders, closest_calls
advance(5)
check(#orders == before_orders and closest_calls == before_scans,
    'manual full-health standby issues no recurring orders and never searches other walls')
check(m.interval == 1 and m.manual_repair_target_handle == wall,
    'manual standby keeps its identity with only the slow health check')
wall.health = 989
advance(1)
check(wall.health > 989 and m.repair_target_handle == wall,
    'assigned standby repairs damage even when no damage event was emitted')
advance(1)
check(wall.health == 1000 and m.manual_repair_target_handle == wall and m.interval == 1,
    'a completed manual assignment returns to standby at the same full wall')

-- Actual player movement takes priority over both healing and the idle heartbeat.
fixture()
wall = unit(1, 0, 0, true); wall.health = 500; register(wall)
u, m = worker(101, 0, 100)
advance(1)
check(m.repairing, 'precondition: automatic repair is in progress')
check(not order_service.process({issuer_player_id_const = 0,
    order_type = DOTA_UNIT_ORDER_MOVE_TO_POSITION, position_x = 900, position_y = 0,
    units = {['0'] = u.index}}), 'a real player move remains an engine movement order')
u.idle = false
local health_before, order_count = wall.health, #orders
advance(3)
check(wall.health == health_before and #orders == order_count and not m.repair_target_handle,
    'once-per-second discovery never steals control while a real movement order is running')
check(m.interval == 1, 'a busy worker also uses the slow cadence')
u.idle = true
advance(1)
check(wall.health > health_before, 'after player movement finishes idle repair resumes within one second')

-- Busy construction/channeling/abilities are never interrupted by automatic healing.
for _, busy_field in ipairs({'survival_build_task', 'channeling', 'active_ability'}) do
    fixture()
    wall = unit(1, 0, 0, true); wall.health = 500; register(wall)
    u, m = worker(101, 0, 100)
    u[busy_field] = busy_field == 'survival_build_task' and {constructing = true} or true
    advance(5)
    check(wall.health == 500 and #orders == 0 and closest_calls == 0,
        busy_field .. ' cannot be interrupted by the idle repair heartbeat')
    u[busy_field] = nil
    advance(1)
    check(wall.health > 500, 'repair resumes after ' .. busy_field .. ' ends without another attack')
end

-- Four owners share one seed and never inspect or repair a foreign region.
fixture()
local regional_walls, regional_workers = {}, {}
for owner = 0, 3 do
    regional_walls[owner] = unit(owner + 1, owner, owner * 5000, true)
    register(regional_walls[owner])
    regional_workers[owner] = {}
    for i = 1, 8 do
        regional_workers[owner][i] = worker(100 + owner * 10 + i, owner, owner * 5000 + 100)
    end
end
advance(10)
check(ticks <= 320 and closest_calls <= 320 and snapshots == 1,
    '32 idle workers over ten seconds perform at most 320 decisions and share one registry seed')
for owner = 0, 3 do regional_walls[owner].health = 500 end
local candidate_before = closest_calls
advance(1)
for owner = 0, 3 do
    check(regional_walls[owner].health == 516,
        'eight local workers each contribute exactly one first repair tick in region ' .. owner)
    for _, regional_worker in ipairs(regional_workers[owner]) do
        check(regional_worker.repair.repair_target_handle == regional_walls[owner],
            'a worker retains its own owner-specific wall')
    end
end
check(closest_calls - candidate_before == 32,
    'one idle heartbeat obtains each worker target once rather than repeatedly per healing tick')
candidate_before = closest_calls
advance(1)
check(closest_calls == candidate_before and #orders == 0,
    'active nearby repair neither searches candidates again nor emits movement orders')

-- The old wall damage listener wakes an owner bucket once, regardless of the
-- number of simultaneous monster hits. It never creates one global listener
-- per repair worker or restarts a pending timer after each hit.
fixture()
local sounds = 0
package.loaded['systems/building_sound_service'] = {wall_damaged = function() sounds = sounds + 1 end}
MODIFIER_EVENT_ON_TAKEDAMAGE, MODIFIER_EVENT_ON_ATTACK_LANDED = 100, 101
local wall_listener = require('modifiers/modifier_building_damage_sound')
regional_walls = {}
regional_workers = {}
for owner = 0, 3 do
    regional_walls[owner] = unit(owner + 1, owner, owner * 5000, true)
    register(regional_walls[owner])
    regional_workers[owner] = {}
    for i = 1, 4 do
        local w, mod = worker(100 + owner * 10 + i, owner, owner * 5000 + (i == 4 and 1000 or 100))
        regional_workers[owner][i] = w
        local actual_wake = mod.WakeForDamagedBuilding
        function mod:WakeForDamagedBuilding(building)
            self.wake_calls = (self.wake_calls or 0) + 1
            return actual_wake(self, building)
        end
    end
end
wall = regional_walls[0]
wall.health = 500
local listener = setmetatable({}, wall_listener)
function listener:GetParent() return wall end
for hit = 1, 20 do listener:OnTakeDamage({unit = wall, damage = 1}) end
check(sounds == 20, 'existing wall damage callback remains functional')
for owner = 0, 3 do
    for _, w in ipairs(regional_workers[owner]) do
        check((w.repair.wake_calls or 0) == (owner == 0 and 1 or 0),
            'one burst visits only the owner bucket once')
        check(w.repair.interval_changes == (owner == 0 and 2 or 1),
            'only eligible owner workers switch from idle to active once')
    end
end
check(#orders == 0 and closest_calls == 0, 'damage callback itself emits no movement order or building scan')
advance(0.1)
check(wall.health == 506 and #orders == 1,
    'three nearby workers repair promptly and one distant worker receives exactly one approach order')
for hit = 1, 20 do listener:OnTakeDamage({unit = wall, damage = 1}) end
advance(0.2)
check(closest_calls == 4 and #orders == 1,
    'repeated hits do not duplicate acquisition or movement while repair/approach is active')
for _, w in ipairs(regional_workers[0]) do
    check(w.repair.interval_changes == 2, 'active timers are not restarted by repeated damage')
end

-- Wakes have the same player-control and explicit-target priority as discovery.
fixture()
wall = unit(1, 0, 0, true); wall.health = 500; register(wall)
local other_wall = unit(2, 0, 100, true); register(other_wall)
local controlled = {}
for i = 1, 4 do controlled[i] = worker(100 + i, 0, 100) end
controlled[1].idle = false
controlled[2].channeling = true
controlled[3].survival_build_task = {constructing = true}
check(controlled[4].repair:SetManualRepairTarget(other_wall), 'manual priority precondition')
advance(0.1)
check(controlled[4].repair.interval == 1, 'full explicit target is on slow standby')
wakeup.wall_damaged(wall)
for _, w in ipairs(controlled) do
    check(w.repair.interval == 1, 'damage wake cannot override moving/busy workers or a different manual wall')
end
advance(1)
check(wall.health == 500 and controlled[4].repair.manual_repair_target_handle == other_wall,
    'unrelated damaged wall neither steals a manual assignment nor overrides a player action')

-- Another healer can finish a cached target while our worker is already busy.
-- Automatic assignments must not pin a full wall and hide the next repair job.
fixture()
wall = unit(1, 0, 0, true); wall.health = 500; register(wall)
other_wall = unit(2, 0, 50, true); other_wall.health = 500; register(other_wall)
u, m = worker(101, 0, 100)
advance(1)
check(m.repair_target_handle == other_wall, 'nearest damaged wall is chosen first')
other_wall.health = 1000
advance(0.1)
check(m.repair_target_handle == wall and wall.health == 502,
    'external completion releases automatic target and obtains other damaged work immediately')

for _, completed_health in ipairs({990, 1000}) do
    fixture()
    wall = unit(1, 0, 0, true); wall.health = 500; register(wall)
    u, m = worker(101, 0, 1000)
    advance(1)
    check(m.repair_target_handle == wall and #orders == 1 and not m.repairing,
        'a distant damaged wall starts one automatic approach')
    wall.health = completed_health
    advance(0.1)
    check(not m.repair_target_handle and m.interval == 1,
        'external healing before arrival releases an automatic wall at ' .. completed_health .. '/1000')
    local moves = 0
    for _, issued in ipairs(orders) do
        if issued.order.OrderType == DOTA_UNIT_ORDER_MOVE_TO_POSITION then moves = moves + 1 end
    end
    check(wall.health == completed_health and moves == 1,
        'abandoned healthy wall receives no healing or repeated approach order')
    check(u.idle and orders[#orders].order.OrderType == DOTA_UNIT_ORDER_STOP,
        'the worker cancels its own obsolete approach instead of walking into a healthy wall')
end

for _, completed_health in ipairs({990, 1000}) do
    fixture()
    wall = unit(1, 0, 0, true); wall.health = 500; register(wall)
    u, m = worker(101, 0, 1000)
    advance(1)
    other_wall = unit(2, 0, 500, true); other_wall.health = 500; register(other_wall)
    wall.health = completed_health
    advance(0.1)
    check(m.repair_target_handle == other_wall and #orders == 3,
        'an obsolete approach stops and immediately obtains the next damaged wall')
    check(orders[2].order.OrderType == DOTA_UNIT_ORDER_STOP
        and orders[3].order.OrderType == DOTA_UNIT_ORDER_MOVE_TO_POSITION
        and orders[3].order.Position.x == 470,
        'obsolete automatic path is stopped before moving to the new work position')
    u.position = orders[3].order.Position
    advance(0.1)
    check(#orders == 4 and orders[4].order.OrderType == DOTA_UNIT_ORDER_STOP
        and u.idle and other_wall.health == 502,
        'arrival at the new repair position stops its automatic movement once and begins healing')
    advance(0.2)
    check(#orders == 4 and other_wall.health == 506,
        'continuing repair does not repeat arrival STOP orders')
end

fixture()
wall = unit(1, 0, 0, true); wall.health = 500; register(wall)
u, m = worker(101, 0, 1000)
advance(1)
local prior_orders = #orders
order_service.process({issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_MOVE_TO_POSITION,
    position_x = 1500, position_y = 0, units = {['0'] = u.index}})
u.idle = false
advance(2)
check(#orders == prior_orders and not m.repair_target_handle and not m.approaching_repair_target,
    'a player move cancels automatic approach bookkeeping without inserting a STOP into the new order')

fixture()
wall = unit(1, 0, 0, true); wall.health = 500; register(wall)
u, m = worker(101, 0, 100)
check(m:SetManualRepairTarget(wall), 'entity-reuse precondition: explicit wall is assigned')
local replacement = unit(1, 0, 0, true); replacement.health = 500
advance(0.1)
check(not m.manual_repair_target_handle and not m.repair_target_handle and replacement.health == 500,
    'a recycled entity index cannot inherit an old explicit repair assignment')

-- Life-cycle churn must not leave modifier/parent handles in the wake registry.
fixture()
local function upvalue(fn, name)
    for index = 1, 30 do
        local key, value = debug.getupvalue(fn, index)
        if key == name then return value end
        if not key then break end
    end
    error('expected wake registry upvalue ' .. name)
end
for cycle = 1, 1000 do
    local transient, mod = worker(1000 + cycle, cycle % 4, cycle)
    mod:OnDestroy()
    transient.removed = true
end
check(next(upvalue(wakeup.unregister, 'records')) == nil,
    'one thousand modifier destructions leave no retained worker records')
check(next(upvalue(wakeup.unregister, 'teams')) == nil,
    'empty owner and team wake buckets are removed as their last worker leaves')

print('REPAIR_IDLE_RECOVERY_PASS: checks=' .. checks ..
    ' no-hit <99% recovery, strict boundary/full completion, dynamic cadence, manual standby,' ..
    ' player/busy priority, 32 workers/four owners, shared registry, coalesced damage wake,' ..
    ' external healing, 1000 lifecycle cycles and no engine scans')
