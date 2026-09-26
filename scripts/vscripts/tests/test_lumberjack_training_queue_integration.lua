package.path = "scripts/vscripts/?.lua;" .. package.path
local definitions = require("config/generated/training_definitions")
package.loaded["systems/technology_stat_manager"] = {get = function() return {final = {lumberjack = {}}} end}
package.loaded["systems/player_profile_service"] = {get_profile = function() return nil end}
package.loaded["systems/rogue_effect_state_service"] = {numeric = function() return 0 end}
package.loaded["core/modifier_registry"] = {ensure = function() return true end}
local defeated = {}
package.loaded["systems/player_context_service"] = {is_defeated = function(id) return defeated[id] == true end}
DOTA_UNIT_TARGET_TEAM_BOTH, DOTA_UNIT_TARGET_ALL = 3, 55
DOTA_UNIT_TARGET_FLAG_NONE, FIND_ANY_ORDER = 0, 0
DOTA_UNIT_CAP_NO_ATTACK, DOTA_UNIT_CAP_RANGED_ATTACK = 0, 2
local vector = {}; vector.__add = function(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
Vector = function(x,y,z) return setmetatable({x=x,y=y,z=z or 0},vector) end
local now = 0
GameRules = {GetGameTime = function() return now end}
local bus, events = require("core/event_bus"), require("core/events")
local scheduler, workers = require("core/scheduler"), require("systems/worker_system")
local cities, states, accounts, spawned, units, create_ok, land_ok, ability
local function reset()
    now, defeated, cities, states, accounts, spawned, units = 0, {}, {}, {}, {}, {}, {}
    create_ok, land_ok = true, true
    scheduler.clear(); bus.reset(); workers.init()
    ability = {SetHidden = function(self, value) self.hidden = value end}
    for player = 0, 1 do
        local id = 10 + player
        local city = {alive = true}
        function city:IsNull() return false end
        function city:IsAlive() return self.alive end
        function city:entindex() return id end
        function city:GetAbsOrigin() return Vector(player * 3000, 0, 128) end
        function city:GetHullRadius() return 128 end
        function city:GetTeamNumber() return 2 end
        function city:GetPlayerOwnerID() return player end
        function city:FindAbilityByName() return ability end
        cities[player] = city
        states[id] = {building_id = "main_city", team = 2, player_id = player,
            level = 4, entindex = id, unit = city}
        accounts[player] = {wood = 1000000, gold = 1000000, population = 0, max_population = 100}
    end
    bus.handle_request(events.BUILDING_QUERY_REQUEST, function(payload) return states[payload.entindex] end)
    bus.handle_request(events.BUILDING_LIST_REQUEST, function() return {buildings = {}} end)
    local function account_snapshot(player_id)
        local copy = {}
        for key, value in pairs(accounts[player_id]) do copy[key] = value end
        return copy
    end
    bus.handle_request(events.RESOURCE_GET_REQUEST, function(payload) return account_snapshot(payload.player_id) end)
    local function affordability(payload)
        local account = accounts[payload.player_id]
        if account.debug_mode then return {ok = true} end
        if account.wood < (payload.wood or 0) then return {ok = false, error = "wood_not_enough"} end
        if account.gold < (payload.gold or 0) then return {ok = false, error = "gold_not_enough"} end
        if account.population + (payload.population or 0) > account.max_population then
            return {ok = false, error = "population_not_enough"}
        end
        return {ok = true}
    end
    bus.handle_request(events.RESOURCE_CAN_SPEND_REQUEST, affordability)
    bus.handle_request(events.RESOURCE_TRY_SPEND_REQUEST, function(payload)
        local result = affordability(payload); if not result.ok then return result end
        local account = accounts[payload.player_id]
        if account.debug_mode then return {ok = true, snapshot = account_snapshot(payload.player_id)} end
        account.wood = account.wood - (payload.wood or 0)
        account.gold = account.gold - (payload.gold or 0)
        account.population = account.population + (payload.population or 0)
        return {ok = true, snapshot = account_snapshot(payload.player_id)}
    end)
    bus.handle_request(events.RESOURCE_ADD_REQUEST, function(payload)
        local account = accounts[payload.player_id]
        account.wood = account.wood + (payload.wood or 0)
        account.gold = account.gold + (payload.gold or 0)
        return {ok = true}
    end)
    bus.handle_request(events.RESOURCE_RELEASE_POP_REQUEST, function(payload)
        accounts[payload.player_id].population = accounts[payload.player_id].population - (payload.population or 0)
        return {ok = true}
    end)
    GridNav = {IsTraversable = function() return land_ok end, IsBlocked = function() return false end}
    GetGroundHeight = function() return 128 end
    FindUnitsInRadius = function() return {} end
    RandomFloat = function() return 0 end
    FindClearSpaceForUnit = function() end
    CreateUnitByName = function(name, position)
        if not create_ok then return nil end
        local id, unit = 100 + #spawned, {name = name, position = position}
        function unit:IsNull() return false end
        function unit:IsAlive() return not self.killed end
        function unit:entindex() return id end
        function unit:GetAbsOrigin() return self.position end
        function unit:HasModifier() return false end
        function unit:FindModifierByName() return nil end
        function unit:FindAbilityByName() return nil end
        function unit:AddAbility() return {GetLevel = function() return 1 end} end
        function unit:ForceKill() self.killed = true end
        setmetatable(unit, {__index = function(_, key)
            if key:match("^Set") or key == "Script_SetAttackRange" or key == "AddNewModifier" then
                return function() end
            end
        end})
        spawned[#spawned + 1], units[id] = unit, unit
        return unit
    end
    EntIndexToHScript = function(id) return units[id] or states[id] and states[id].unit end
end
local function train(player, level)
    local result, err = bus.request(events.WORKER_TRAIN_REQUEST, {city = cities[player],
        player_id = player, training_id = string.format("train_lumberjack_%02d", level)})
    assert(not err, err); return result
end
local function snapshot(player)
    local result, err = bus.request(events.WORKER_TRAINING_GET_REQUEST,
        {player_id = player, source_entindex = cities[player]:entindex(), team = 2})
    assert(not err, err); return result
end
local function tick(time) now = time; scheduler.think() end

reset()
assert(#snapshot(0).options == 8 and snapshot(0).options[1].available == 1)
assert(snapshot(0).options[5].available == 0, "future tiers cannot bypass the four available entrances")
local result = train(0, 3)
assert(result.ok and result.queued and #spawned == 0, "explicit LV3 does not silently train LV1")
assert(accounts[0].wood == 999500 and accounts[0].population == 1)
assert(snapshot(0).active_job.level == 3 and snapshot(0).active_job.finish_at == 1)
assert(snapshot(0).options[3].count == 0 and snapshot(0).options[3].queued_count == 1)
assert(train(0, 2).ok and train(1, 1).ok)
tick(0.99); assert(#spawned == 0)
tick(1)
assert(#spawned == 2 and snapshot(0).active_job.level == 2)
assert(snapshot(0).options[3].count == 1 and snapshot(1).options[3].count == 0)
assert(snapshot(0).options[1].count == 0 and snapshot(1).options[1].count == 1,
    "same-team training counters are owned by player")
tick(2); assert(#spawned == 3 and snapshot(0).queue_count == 0)
assert(accounts[0].wood == 999400 and accounts[0].population == 2, "completion does not charge twice")

reset()
for _ = 1, 5 do assert(train(0, 1).ok) end
assert(not train(0, 1).ok, "LV1 quota stays five even though queue capacity is seven")
assert(train(0, 2).ok, "sixth job can use a different training tier")
assert(train(0, 3).ok, "seventh job can use another unlocked training tier")
assert(not train(0, 4).ok and accounts[0].wood == 999350, "eighth job rejected without charge")
assert(snapshot(0).queue_count == 7 and snapshot(0).queue_capacity == 7)
assert(#snapshot(0).queued == 6 and snapshot(0).queued[5].level == 2
    and snapshot(0).queued[6].level == 3, "six waiting jobs retain their tier order")
assert(snapshot(0).options[1].queued_count == 5 and snapshot(0).options[1].count == 0)
for index = 1, 5 do tick(index) end
assert(#spawned == 5 and snapshot(0).options[1].completed == 1)
assert(snapshot(0).options[5].available == 1 and train(0, 5).ok,
    "finishing LV1 exposes LV5 without needing to finish LV2 through LV4")
assert(snapshot(1).options[1].count == 0 and train(1, 1).ok)

reset(); states[10].level = 1
assert(not train(0, 4).ok and accounts[0].wood == 1000000, "city prerequisite rejects before payment")
assert(not train(0, 5).ok)
result = bus.request(events.WORKER_TRAIN_REQUEST, {city = cities[1], player_id = 0, training_id = "train_lumberjack_01"})
assert(not result.ok and accounts[1].wood == 1000000)
result = bus.request(events.WORKER_TRAINING_GET_REQUEST, {source_entindex = 11, player_id = 0})
assert(result.ok == false and #result.options == 0, "foreign city snapshot rejected")
accounts[0].max_population = 0
assert(not train(0, 1).ok and snapshot(0).options[1].available == 0)

reset(); assert(train(0, 2).ok and train(0, 3).ok and train(1, 1).ok)
states[10] = nil; cities[0].alive = false
bus.emit(events.BUILDING_DESTROYED, {entindex = 10, player_id = 0})
assert(accounts[0].wood == 1000000 and accounts[0].population == 0)
tick(5); assert(#spawned == 1 and spawned[1].survival_player_id == 1)

reset(); assert(train(0, 2).ok and train(0, 3).ok)
bus.emit(events.PLAYER_DISCONNECTED, {player_id = 0})
assert(accounts[0].wood == 1000000 and accounts[0].population == 0)
assert(not train(0, 1).ok); tick(10); assert(#spawned == 0)

reset(); assert(train(0, 2).ok)
defeated[0] = true; bus.emit(events.PLAYER_DEFEATED, {player_id = 0})
assert(accounts[0].wood == 1000000 and accounts[0].population == 0)
tick(10); assert(#spawned == 0 and not train(0, 1).ok)

reset(); assert(train(0, 2).ok); create_ok = false; tick(1)
assert(accounts[0].wood == 1000000 and accounts[0].population == 0)
assert(snapshot(0).options[2].count == 0 and snapshot(0).queue_count == 0)
reset(); assert(train(0, 2).ok); land_ok = false; tick(1)
assert(accounts[0].wood == 1000000 and accounts[0].population == 0 and #spawned == 0)
reset(); assert(train(0, 4).ok); states[10].level = 1; tick(1)
assert(accounts[0].wood == 1000000 and accounts[0].population == 0 and #spawned == 0)

reset(); accounts[0].debug_mode = true
assert(train(0, 1).ok and accounts[0].population == 0)
bus.emit(events.BUILDING_DESTROYED, {entindex = 10, player_id = 0})
assert(accounts[0].wood == 1000000 and accounts[0].population == 0,
    "debug training cancellation must not refund resources that were never charged")

reset()
result = bus.request(events.WORKER_TRAIN_REQUEST, {city = cities[0], source = "rogue_reward",
    training_id = "train_repairer_01", count = 2, wood_cost_override = 0, gold_cost_override = 0})
assert(result.ok and #spawned == 2 and snapshot(0).queue_count == 0 and accounts[0].wood == 1000000,
    "reward recruits are immediate and keep their free grant semantics")
bus.emit(events.BUILDING_CREATED, states[10]); assert(ability.hidden == true)
for _, row in ipairs(definitions.rows) do
    if row.training_id:match("^train_lumberjack_") then assert(row.training_duration_seconds == 1) end
end
print("PASS lumberjack training integration: real completion, independent tiers/players, four entrances, capacity, resource/population reservations, cancel/refund, lifecycle and instant reward recruits")

-- Harvest growth exercises the real stat manager with the real worker subscriber.
local stub_manager = package.loaded["systems/technology_stat_manager"]
package.loaded["systems/technology_stat_manager"] = nil
local real_manager = require("systems/technology_stat_manager")
stub_manager.get = real_manager.get
reset(); real_manager.init()
assert(train(0,1).ok and train(0,2).ok and train(1,1).ok)
tick(1); tick(2)
local own = bus.request(events.WORKER_LIST_REQUEST,{player_id=0})
local foreign = bus.request(events.WORKER_LIST_REQUEST,{player_id=1})[1]
assert(#own==2 and foreign)
local errors, stat_events, range_writes, attack_writes, modifier_lookups = {},0,0,0,0
local prior_print = print
print=function(message,...)
    if tostring(message):find("[EventBus] handler error",1,true) then errors[#errors+1]=message
    else prior_print(message,...) end
end
bus.subscribe(events.UNIT_COMBAT_STATS_CHANGED,function() stat_events=stat_events+1 end)
for _,state in ipairs(own) do
    state.unit.SetBaseDamageMin=function(self,v) self.base_min=v;attack_writes=attack_writes+1 end
    state.unit.SetBaseDamageMax=function(self,v) self.base_max=v end
    state.unit.SetBaseAttackTime=function() range_writes=range_writes+1 end
    state.unit.Script_SetAttackRange=function() range_writes=range_writes+1 end
    state.unit.SetAcquisitionRange=function() range_writes=range_writes+1 end
    state.unit.FindModifierByName=function() modifier_lookups=modifier_lookups+1 end
end
own[2].technology_multiplier=3
own[2].personality_attack_growth=7
own[2].personality_attack_pct=25
local foreign_before=foreign.unit.survival_attack_min
bus.handle_request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST,function()
    return {totals={lumberjack_attack_growth=0.25}}
end)
for i=1,200 do
    bus.emit(events.TREE_HIT,{player_id=0,source="lumberjack",attacker=own[1].unit})
    assert(real_manager.get(0).final.lumberjack.attack_flat==i*0.25)
    for _,state in ipairs(own) do
        assert(state.unit.base_min==(state.base_damage_min+i*0.25*(state.technology_multiplier or 1)+(state.personality_attack_growth or 0))
            *(1+(state.personality_attack_pct or 0)/100),"each hit applies attack immediately")
    end
end
assert(attack_writes==400 and stat_events==400)
assert(range_writes==0 and modifier_lookups==0,"growth must not reset attack timers/ranges or all modifiers")
assert(foreign.unit.survival_attack_min==foreign_before,"growth stays player-private")
-- Unscoped research still changes speed/range/modifiers.
bus.emit(events.TECHNOLOGY_STATS_CHANGED,{player_id=0,reason="research_completed"})
assert(range_writes>0 and modifier_lookups>0)
bus.emit(events.TREE_CHANGED,{player_id=0,entindex=900,lumber_efficiency_buff=99})
modifier_lookups=0
for i=1,200 do bus.emit(events.TREE_CHANGED,{player_id=0,entindex=900,lumber_efficiency_buff=99,reason="tree_max_level_reset"}) end
assert(modifier_lookups==0,"same capped tree must not walk all worker modifiers again")
bus.emit(events.TREE_CHANGED,{player_id=0,entindex=901,lumber_efficiency_buff=99})
assert(modifier_lookups>0,"replacement tree still updates targets")
assert(#errors==0,table.concat(errors,"\n")); print=prior_print
print("LUMBERJACK_GROWTH_FAST_PATH_PASS: 200 immediate shared growth hits; 400 attack writes; zero range/timer/modifier resets; player isolation; capped-tree skip")
