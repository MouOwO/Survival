package.path = "scripts/vscripts/?.lua;" .. package.path
local defeated = {}
package.loaded["systems/player_context_service"] = {is_defeated = function(p) return defeated[p] == true end}
local bus, events = require("core/event_bus"), require("core/events")
local scheduler, routes = require("core/scheduler"), require("config/tower_route_config")
local service = require("systems/tower_auto_upgrade_service")
local runtime = require("ui/ability_runtime_builder")
local clock, states, index, money, calls = 0, {}, 0, 0, 0
GameRules = {GetGameTime = function() return clock end}
EntIndexToHScript = function(id) return states[id] and states[id].unit end
local function publish(state)
    bus.emit(events.BUILDING_CHANGED, {unit = state.unit, entindex = state.unit:entindex()})
end
local function fixture(class, level)
    index = index + 1
    local id = index
    local ability = {IsNull = function() return false end, IsHidden = function() return false end}
    local unit = {alive = true}
    function unit:IsNull() return false end
    function unit:IsAlive() return self.alive end
    function unit:entindex() return id end
    function unit:HasModifier() return false end
    function unit:FindAbilityByName() return ability end
    local state = {unit = unit, level = level, tower_class = class, player_id = 0, building_id = "arrow_tower"}
    states[id] = state
    return state
end
local function toggle(state, player)
    return bus.request(events.TOWER_AUTO_UPGRADE_TOGGLE_REQUEST, {entindex = state.unit:entindex(), player_id = player or 0})
end
local function advance(seconds) clock = clock + seconds; scheduler.think() end
local function tick() advance(1.01) end
local checks = 0
local function finish(state)
    assert(state.unit.survival_upgrade_in_progress)
    state.level = state.level + 1
    state.unit.survival_upgrade_in_progress = nil
    publish(state)
end
bus.reset()
service.init({query = function(unit) return states[unit:entindex()] end, publish = publish,
    can_upgrade = function() checks = checks + 1; return money >= 1 end,
    upgrade = function(payload)
        calls = calls + 1
        assert(payload.upgrade_mode == "one" and payload.silent_notification)
        local state = states[payload.building:entindex()]
        assert(state.tower_class and routes.row_at_level(state,state.level+1), "never auto-select a route or exceed its final level")
        assert(not payload.building.survival_upgrade_in_progress, "never overlap upgrades")
        if money < 1 then return {ok = false, error = "wood_not_enough"} end
        money = money - 1
        bus.emit(events.RESOURCE_CHANGED, {player_id=state.player_id})
        payload.building.survival_upgrade_in_progress = true
        return {ok = true, pending = true}
    end})
local state = fixture("class_1", 6)
assert(not toggle(state, 1).ok, "reject another player's tower")
assert(toggle(state).enabled)
local auto_view = runtime.build("ability_upgrade_tower_lv01", state,
    {gold=1e12,wood=1e12,max_population=100})
local auto_hint
for _, field in ipairs(auto_view.fields or {}) do
    if field.label == "自动升级" then auto_hint = field.value end
end
assert(auto_view.auto_upgrade_enabled == 1 and auto_hint
    and auto_hint:find("右键", 1, true) and auto_hint:find("每秒", 1, true),
    "upgrade tooltip shows active automation and the right-click control")
advance(0.99)
assert(checks == 0 and calls == 0, "enabling waits for the first one-second check")
advance(0.02)
assert(state.level == 6 and state.unit.survival_tower_auto_upgrade, "wait for resources")
assert(calls == 0 and checks == 1, "insufficient resources never enter full upgrade")
for i=1,1000 do bus.emit(events.RESOURCE_CHANGED,{player_id=1}) end
advance(0.2); assert(checks == 1, "other player resources cannot wake this tower")
for i=1,1000 do bus.emit(events.RESOURCE_CHANGED,{player_id=0}) end
advance(0.2); assert(checks == 1 and calls == 0, "resource bursts cannot schedule early checks")
advance(0.59); assert(checks == 1, "never repeat a check before one second")
advance(0.02); assert(checks == 2 and calls == 0, "one lightweight preflight per second")
money = 1000
bus.emit(events.RESOURCE_CHANGED,{player_id=0})
advance(0.2); assert(calls == 0, "new income waits for the next periodic check")
tick()
local paid, started = money, calls
tick(); tick()
assert(money == paid and calls == started, "pending upgrade cannot spend twice")
assert(toggle(state).enabled == false)
finish(state); tick()
assert(not state.unit.survival_upgrade_in_progress and money == paid, "cancel prevents next upgrade")
-- Base LV1..5 never offer automation. Selected routes cross all stages.
for level=1,5 do
    local base=fixture(nil,level)
    assert(not toggle(base).ok)
    local view=runtime.build("ability_upgrade_tower_lv01",base,{gold=1e12,wood=1e12,max_population=100})
    assert(view.auto_upgrade_visible==0 and view.auto_upgrade_available==0)
end
local stage_count=0
for route_index=1,7 do
    state=fixture("class_"..route_index,6)
    assert(toggle(state).enabled)
    while routes.row_at_level(state,state.level+1) do
        local previous=routes.current(state)
        tick();finish(state)
        if previous.stage_id~=routes.current(state).stage_id then stage_count=stage_count+1 end
        if routes.row_at_level(state,state.level+1) then
            assert(state.unit.survival_tower_auto_upgrade,"keep automation across stage transitions")
        end
    end
    assert(not state.unit.survival_tower_auto_upgrade,"stop at final route level")
    local paid_at_end=money;tick();tick()
    assert(money==paid_at_end and not toggle(state).ok)
    local view=runtime.build("ability_upgrade_tower_lv01",state,{gold=1e12,wood=1e12,max_population=100})
    assert(view.auto_upgrade_visible==1 and view.auto_upgrade_enabled==0 and view.auto_upgrade_available==0 and view.available==0)
    for _,field in ipairs(view.fields or {}) do assert(field.label~="自动升级" and field.label~="升级规则","no auto text in upgrade tooltip") end
end
state = fixture("class_1", 6); assert(toggle(state).enabled)
state.unit.alive = false
bus.emit(events.BUILDING_DESTROYED, {entindex = state.unit:entindex(), unit = state.unit})
local before = calls; tick(); assert(calls == before)
state = fixture("class_1", 6); assert(toggle(state).enabled)
defeated[0] = true; tick(); assert(not state.unit.survival_tower_auto_upgrade)
defeated[0] = nil
state = fixture("class_1", 6); assert(toggle(state).enabled)
bus.emit(events.PLAYER_DISCONNECTED, {player_id = 0, defeat_cleanup = true})
assert(not state.unit.survival_tower_auto_upgrade)
assert(scheduler.task_count() == 0, "no stale auto-upgrade timers")
print("TOWER_AUTO_UPGRADE_PASS stages=" .. stage_count .. ": resources, pending, cancellation, automatic stage transitions, max-level runtime, ownership, destruction and defeat")

-- Many towers share one owner queue. Spending emits synchronous notifications;
-- these cannot reenter or overspend, and each slice checks at most eight units.
local batch = {}
money = 3
for i=1,24 do batch[i]=fixture("class_1",6);assert(toggle(batch[i]).enabled) end
local check_start, call_start = checks, calls
tick()
assert(checks-check_start==8 and calls-call_start==3 and money==0,"bounded slice, live wallet prevents overspend")
tick();tick();tick()
assert(calls-call_start==3,"spend notifications do not recursively upgrade")
for _, tower in ipairs(batch) do assert(toggle(tower).enabled==false) end
assert(scheduler.task_count()==0,"last cancellation clears continuation and fallback")

state=fixture("class_1",6);money=0;assert(toggle(state).enabled);tick()
check_start=checks
for i=1,1000 do
 bus.emit(events.BUILDING_CHANGED,{entindex=state.unit:entindex(),level=6,tower_class="class_1",reason="tower_personal_attack_changed"})
end
advance(0.2);assert(checks==check_start,"attack growth never schedules an early auto-upgrade check")
-- Normal one-second polling also notices grants without a resource event.
money=1;tick()
assert(state.unit.survival_upgrade_in_progress and money==0,"periodic check recovers missed event")
assert(toggle(state).enabled==false)
finish(state)
assert(scheduler.task_count()==0)
print("TOWER_AUTO_QUEUE_PASS: one-second cadence, 24 towers, eight per slice, 3 upgrades/3 resources, ignored income/growth bursts, missed-event recovery")

-- Exercise the real ability sync: the final route row removes upgrade buttons,
-- while fusion and the utility buttons keep their existing visibility.
package.loaded["systems/tower_skill_runtime"] = {get = function() return {} end}
local ability_sync = require("systems/tower_ability_sync")
local definition = require("config/buildings_config").arrow_tower
bus.handle_request(events.TOWER_FUSION_ELIGIBILITY_REQUEST, function() return {eligible = true} end)
local abilities = {}
local u = {survival_tower_auto_upgrade = nil}
function u:IsNull() return false end
function u:entindex() return 900 end
function u:GetAbilityCount() return #abilities end
function u:GetAbilityByIndex(i) return abilities[i + 1] end
function u:FindAbilityByName(name)
    for _, a in ipairs(abilities) do if a.name == name then return a end end
end
function u:RemoveAbility(name)
    for i = #abilities, 1, -1 do if abilities[i].name == name then table.remove(abilities, i) end end
end
function u:AddAbility(name)
    local a = {name = name, hidden = false, active = true}
    function a:IsNull() return false end
    function a:GetAbilityName() return self.name end
    function a:IsHidden() return self.hidden end
    function a:SetHidden(v) self.hidden = v end
    function a:SetActivated(v) self.active = v end
    function a:SetLevel(v) self.level = v end
    abilities[#abilities + 1] = a
    return a
end
state = {unit = u, player_id = 0, building_id = "arrow_tower", tower_class = "class_5", level = 25, definition = definition}
ability_sync.sync(state, routes.current(state), true)
tick()
assert(not u:FindAbilityByName("ability_upgrade_tower_lv01"), "final route removes upgrade icon")
assert(not u:FindAbilityByName("ability_upgrade_tower_max"), "final route removes upgrade-max icon")
assert(u:FindAbilityByName("ability_tower_fusion").active)
assert(not u:FindAbilityByName("ability_building_blink").hidden)
assert(not u:FindAbilityByName("ability_destroy_arrow_tower").hidden)
state.level = 10
ability_sync.sync(state, routes.current(state), true)
tick()
assert(u:FindAbilityByName("ability_upgrade_tower_lv01").active, "manual cross-stage upgrade remains enabled")
print("TOWER_MAX_ICON_PASS: no final upgrade icons, fusion and utility controls, manual promotion")
