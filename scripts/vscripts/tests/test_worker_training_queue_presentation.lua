-- Exercise the real worker request/snapshot boundary. Completed recruits and
-- every admitted reservation share a tier's quota; only the queue head pays.
package.path = "scripts/vscripts/?.lua;" .. package.path
package.loaded["systems/technology_stat_manager"] = {get = function() return {final = {lumberjack = {}}} end}
package.loaded["systems/player_profile_service"] = {get_profile = function() return nil end}
package.loaded["systems/rogue_effect_state_service"] = {numeric = function() return 0 end}
package.loaded["systems/player_context_service"] = {is_defeated = function() return false end}
package.loaded["core/modifier_registry"] = {ensure = function() return true end}
if arg and arg[1] then
    package.preload["systems/worker_system"] = function() return dofile(arg[1]) end
end

DOTA_UNIT_TARGET_TEAM_BOTH, DOTA_UNIT_TARGET_ALL = 3, 55
DOTA_UNIT_TARGET_FLAG_NONE, FIND_ANY_ORDER = 0, 0
DOTA_UNIT_CAP_NO_ATTACK, DOTA_UNIT_CAP_MELEE_ATTACK = 0, 1
local vector = {}; vector.__add = function(a, b) return Vector(a.x+b.x, a.y+b.y, a.z+b.z) end
Vector = function(x, y, z) return setmetatable({x=x, y=y, z=z or 0}, vector) end
local now = 0
GameRules = {GetGameTime = function() return now end}
local bus, events = require("core/event_bus"), require("core/events")
local scheduler, workers = require("core/scheduler"), require("systems/worker_system")
local cities, states, accounts, spawned, create_ok, spend_count, refund_count, fund_checks
local function same(actual, expected, message)
    assert(actual == expected, (message or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function reset()
    now, cities, states, accounts, spawned = 0, {}, {}, {}, {}
    create_ok, spend_count, refund_count, fund_checks = true, 0, 0, 0
    scheduler.clear(); bus.reset(); workers.init()
    for _, id in ipairs({10, 11, 12}) do
        local owner = id == 11 and 1 or 0
        local city = {alive = true}
        function city:IsNull() return false end
        function city:IsAlive() return self.alive end
        function city:entindex() return id end
        function city:GetAbsOrigin() return Vector(id * 1000, 0, 128) end
        function city:GetHullRadius() return 128 end
        function city:GetTeamNumber() return 2 end
        function city:GetPlayerOwnerID() return owner end
        cities[id] = city
        states[id] = {building_id="main_city", team=2, player_id=owner, level=4, unit=city}
        accounts[owner] = {wood=1000000, gold=1000000, population=0, max_population=100}
    end
    local function wallet(id)
        local result = {}; for key, value in pairs(accounts[id]) do result[key] = value end
        return result
    end
    local function affordable(payload)
        local account = accounts[payload.player_id]
        if account.wood < (payload.wood or 0) then return {ok=false, error="wood_not_enough"} end
        if account.gold < (payload.gold or 0) then return {ok=false, error="gold_not_enough"} end
        if account.population + (payload.population or 0) > account.max_population then
            return {ok=false, error="population_not_enough"}
        end
        return {ok=true}
    end
    bus.handle_request(events.BUILDING_QUERY_REQUEST, function(p) return states[p.entindex] end)
    bus.handle_request(events.RESOURCE_GET_REQUEST, function(p) return wallet(p.player_id) end)
    bus.handle_request(events.RESOURCE_CAN_SPEND_REQUEST, function(p)
        fund_checks = fund_checks + 1; return affordable(p)
    end)
    bus.handle_request(events.RESOURCE_TRY_SPEND_REQUEST, function(p)
        spend_count = spend_count + 1
        local result = affordable(p); if not result.ok then return result end
        local account = accounts[p.player_id]
        account.wood, account.gold, account.population = account.wood-(p.wood or 0),
            account.gold-(p.gold or 0), account.population+(p.population or 0)
        return {ok=true, snapshot=wallet(p.player_id)}
    end)
    bus.handle_request(events.RESOURCE_ADD_REQUEST, function(p)
        refund_count = refund_count + 1
        accounts[p.player_id].wood = accounts[p.player_id].wood+(p.wood or 0)
        accounts[p.player_id].gold = accounts[p.player_id].gold+(p.gold or 0)
        return {ok=true}
    end)
    bus.handle_request(events.RESOURCE_RELEASE_POP_REQUEST, function(p)
        accounts[p.player_id].population = accounts[p.player_id].population-(p.population or 0)
        return {ok=true}
    end)
    GridNav = {IsTraversable=function() return true end, IsBlocked=function() return false end}
    GetGroundHeight = function() return 128 end
    FindUnitsInRadius = function() return {} end
    RandomFloat = function() return 0 end
    FindClearSpaceForUnit = function() end
    CreateUnitByName = function(name, position)
        if not create_ok then return nil end
        local id, unit = 100+#spawned, {name=name, position=position, abilities={}}
        function unit:IsNull() return false end
        function unit:IsAlive() return not self.killed end
        function unit:entindex() return id end
        function unit:GetAbsOrigin() return self.position end
        function unit:HasModifier() return false end
        function unit:FindModifierByName() return nil end
        function unit:FindAbilityByName(name) return self.abilities[name] end
        function unit:AddAbility(name)
            local ability = {level=0}
            function ability:GetLevel() return self.level end
            function ability:SetLevel(value) self.level=value end
            self.abilities[name]=ability; return ability
        end
        function unit:GetTeamNumber() return 2 end
        function unit:ForceKill() self.killed = true end
        setmetatable(unit, {__index=function(_, key)
            if key:match("^Set") or key == "Script_SetAttackRange" or key == "AddNewModifier" then return function() end end
        end})
        spawned[#spawned+1] = unit; return unit
    end
end
local function train(level, city)
    city = city or 10
    local result, err = bus.request(events.WORKER_TRAIN_REQUEST, {city=cities[city],
        player_id=states[city].player_id,
        training_id=level == "auto" and "train_lumberjack_auto" or string.format("train_lumberjack_%02d", level)})
    assert(not err, err); return result
end
local function view(city)
    city = city or 10
    local result, err = bus.request(events.WORKER_TRAINING_GET_REQUEST,
        {player_id=states[city].player_id, source_entindex=city, team=2})
    assert(not err, err); return result
end
local function tick(at) now=at; scheduler.think() end
local function fill(level, count, city)
    local jobs = {}; for index=1,count do jobs[index]=train(level, city); assert(jobs[index].ok) end
    return jobs
end

reset()
same(view().queue_revision, 0, "empty untouched city starts at revision zero")
same(view().options[5].prerequisite_met, 0, "initial four entrances stop at LV4")
local jobs = fill(1, 5)
local state = view()
same(state.queue_revision, 5, "each accepted FIFO change publishes a new revision")
same(view().queue_revision, state.queue_revision, "read-only snapshots do not advance revision")
same(state.options[1].count, 0); same(state.options[1].queued_count, 5)
same(state.options[1].available, 0, "fifth accepted click immediately fills LV1")
same(state.options[5].prerequisite_met, 1, "reserved-full LV1 exposes LV5 before completion")
same(state.options[5].available, 1, "revealed tier is genuinely trainable")
same(state.active_job.job_id, jobs[1].job_id, "first job is active")
same(#state.queued, 4, "active is excluded from the waiting list")
same(state.queued[1].job_id, jobs[2].job_id, "second admitted job is the first waiter")
same(train(1).error, "training_max_count_reached", "server fences stale sixth click")
same(view().queue_revision, 5, "rejected admission leaves authoritative queue revision unchanged")
assert(train(5).ok, "revealed LV5 must be admitted, not only displayed")
assert(train("auto").ok)
same(view().queued[6].level, 2, "automatic training skips the reserved-full tier")
same(view().queue_count, 7); same(view().queue_capacity, 7); same(#view().queued, 6)
same(train(3).error, "training_queue_full", "active plus six waiters retain original capacity")
same(accounts[0].wood, 999990, "only active LV1 paid its configured 10 wood")
same(accounts[0].population, 1); same(spend_count, 1)
same(view(11).options[1].queued_count, 0, "same-team players own independent quotas")
local checks = fund_checks; view(); view(); same(fund_checks, checks, "snapshots do not poll affordability")
for index=1,5 do
    tick(index); state=view()
    same(state.options[1].count+state.options[1].queued_count, 5, "completion preserves claimed quota")
    same(state.options[1].available, 0)
end
same(#spawned, 5); same(view().active_job.level, 5)
same(accounts[0].wood, 994950, "five LV1 completions and the next LV5 use unchanged costs")
tick(6); tick(7)
same(view().queue_count, 0)
local drained_revision = view().queue_revision
assert(drained_revision > 7, "drained queue retains its final published revision")
assert(train(3).ok)
assert(view().queue_revision > drained_revision, "new work on a drained city cannot reuse an old revision")

reset(); fill(2, 3)
same(view().options[1].available, 1, "filling LV2 must not hide LV1")
same(view().options[2].available, 0)
same(view().options[5].prerequisite_met, 1, "reserved-full tiers are removed independently")
assert(train(5).ok and train("auto").ok)
same(view().queued[4].level, 1)

reset(); fill(1, 5)
local before_cancel_revision = view().queue_revision
bus.emit(events.BUILDING_DESTROYED, {entindex=10})
assert(view().queue_revision > before_cancel_revision, "cancelled empty snapshot retains cancellation revision")
same(view().queue_count, 0); same(view().options[1].queued_count, 0)
same(view().options[1].available, 1, "cancelled reservations restore LV1")
same(view().options[5].prerequisite_met, 0, "cancelled reservations restore the original tier window")
same(refund_count, 1, "only charged active job refunds")
same(accounts[0].wood, 1000000); same(accounts[0].population, 0)

reset(); jobs=fill(1, 5); accounts[0].wood=0; tick(1); state=view()
same(state.options[1].count, 1); same(state.options[1].queued_count, 4)
same(state.options[1].available, 0, "blocked unpaid head keeps its reservation")
same(state.active_job.job_id, nil); same(state.blocked_head.job_id, jobs[2].job_id)
same(state.blocked_head.started_at, 0); same(state.blocked_head.finish_at, 0)
same(state.queued[1].job_id, jobs[3].job_id); same(#state.queued, 3)
same(state.options[5].prerequisite_met, 1, "resource wait does not move the tier window backwards")
local blocked_revision = state.queue_revision
tick(2)
same(view().queue_revision, blocked_revision, "unchanged one-second resource retry has no new presentation revision")
bus.emit(events.BUILDING_DESTROYED, {entindex=10})
same(refund_count, 0, "unpaid jobs cannot mint a cancellation refund")
same(accounts[0].wood, 0); same(accounts[0].population, 1)
same(view().options[1].available, 1, "cancelling unpaid reservations reopens its tier")

reset(); fill(1, 5); create_ok=false; tick(1)
same(view().options[1].count, 0); same(view().options[1].queued_count, 4)
same(view().options[1].available, 1, "failed completion releases its quota")
same(view().options[5].prerequisite_met, 0, "failed completion restores the earlier tier")
same(refund_count, 1); same(accounts[0].wood, 999990)

reset(); fill(1, 2, 10); fill(1, 3, 12)
same(view(10).options[1].queued_count, 5); same(view(12).options[1].queued_count, 5)
same(view(12).options[5].prerequisite_met, 1, "another city sees the same owner's claimed tiers")
same(train(1, 12).error, "training_max_count_reached")
same(view(10).queue_count, 2); same(view(12).queue_count, 3)
same(accounts[0].wood, 999980, "each city charges only its own active job")

print("PASS training presentation contract: completed+active+waiting quota, immediate next entrance, explicit/auto admission, unchanged 1+6 FIFO/costs, blocked head, cancellation, failed spawn and player/city isolation")
