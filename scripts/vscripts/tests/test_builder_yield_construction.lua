package.path = "scripts/vscripts/?.lua;" .. package.path
local bus, events = require("core/event_bus"), require("core/events")
local noop = function() end
for _, name in ipairs({"tower_skill_runtime", "building_population_service", "asset_preload_service",
    "building_sound_service", "tower_utility_ability_sync", "wall_destruction_visual", "tower_ability_sync",
    "war3_armor_target", "wall_collision_barrier_service", "online_time_service"}) do
    package.loaded["systems/" .. name] = {reset = noop, apply = noop, sync = noop,
        clear = noop, play = noop, queue_particle = noop, grant_level = noop,
        construction_started = noop, construction_completed = noop}
end
package.loaded["systems/building_construction_visual_service"] = {reset = noop, start = function() return {} end,
    cancel = noop, complete = noop}
package.loaded["systems/building_visual_service"] = {init = noop, clear = noop, apply = noop}
package.loaded["systems/building_relocation"] = {bind = noop}
package.loaded["debug/dev_wall_stats"] = {apply = noop, reset = noop}
package.loaded["core/team_alignment"] = {enforce = noop}
package.loaded["core/logger"] = {info = noop, warn = noop}
local rogue_effects = require("systems/rogue_effect_state_service")
package.loaded["systems/forbidden_region_service"] = {validate_building_footprint = function() return true end}
local defeated = false
package.loaded["systems/player_context_service"] = {is_defeated = function() return defeated end}
package.loaded["systems/multiplayer_player_service"] = {is_disconnected = function() return false end}
DOTA_TEAM_GOODGUYS = 2
DOTA_UNIT_TARGET_TEAM_BOTH, DOTA_UNIT_TARGET_HERO, DOTA_UNIT_TARGET_BASIC = 3,1,2
DOTA_UNIT_TARGET_BUILDING, DOTA_UNIT_TARGET_FLAG_INVULNERABLE, FIND_ANY_ORDER = 4,16,0
DOTA_UNIT_ORDER_MOVE_TO_POSITION, ACT_DOTA_ATTACK, ACT_DOTA_TAUNT, ACT_DOTA_CAST_ABILITY_3 = 1,1,2,3
PATTACH_ABSORIGIN_FOLLOW = 1
local particle_id, charge, destroyed_charge, released_charge = 0,{}, {}, {}
ParticleManager = {
    CreateParticle = function(_,path,_,owner)
        particle_id=particle_id+1
        if path=="particles/econ/items/wisp/wisp_overcharge_ti7.vpcf" then charge[particle_id]=owner end
        return particle_id
    end,
    DestroyParticle = function(_,id) if charge[id] then destroyed_charge[id]=true end end,
    ReleaseParticleIndex = function(_,id) if charge[id] then released_charge[id]=true end end,
    SetParticleControl = noop, SetParticleControlEnt = noop,
}
local mt = {}; mt.__index = {Length2D = function(v) return math.sqrt(v.x*v.x+v.y*v.y) end}
Vector = function(x,y,z) return setmetatable({x=x,y=y,z=z or 0},mt) end
mt.__add=function(a,b)return Vector(a.x+b.x,a.y+b.y,a.z+b.z)end
mt.__sub=function(a,b)return Vector(a.x-b.x,a.y-b.y,a.z-b.z)end
local clock, units, by_id, caster, move, paid, refunded, created, failed_create, reachable, foreign, account, cooldowns
local counts_events, completed_events, destroyed_events, failed_move, authorized_builders
GameRules = {GetGameTime = function() return clock end}
GetGroundHeight = function() return 128 end
GridNav = {IsTraversable = function() return true end, IsBlocked = function() return false end,
    IsNearbyTree = function() return false end, CanFindPath = function() return reachable end}
FindUnitsInRadius = function() return units end
Entities = {FindAllByClassname = function() return units end}
EntIndexToHScript = function(id) return by_id[id] end
local scheduler = require("core/scheduler")
local grid = require("systems/grid_placement_system")
local building = require("systems/building_system")
local presentation = require("systems/builder_presentation_service")
local config = require("config/buildings_config")
-- The starting city is free in gameplay; use a charged fixture to exercise
-- the shared construction spend/refund boundary without changing live data.
config.main_city.build_cost = {wood = 100, gold = 50}
local function entity(id, name, position)
    local unit = {index=id,name=name,position=position,alive=true,modifiers={},abilities={},health=5000}
    function unit:IsNull() return self.null == true end
    function unit:IsAlive() return self.alive end
    function unit:entindex() return self.index end
    function unit:GetUnitName() return self.name end
    function unit:GetAbsOrigin() return self.position end
    function unit:SetAbsOrigin(value) self.position=value end
    function unit:GetTeamNumber() return 2 end
    function unit:GetPlayerOwnerID() return 0 end
    function unit:GetHullRadius() return self.hull or 0 end
    function unit:SetHullRadius(value) self.hull=value end
    function unit:GetMaxHealth() return 5000 end
    function unit:GetHealth() return self.health end
    function unit:SetHealth(value) self.health=value end
    function unit:GetPhysicalArmorBaseValue() return 0 end
    function unit:HasModifier(name) return self.modifiers[name] ~= nil end
    function unit:AddNewModifier(_,_,name) self.modifiers[name]={};return self.modifiers[name] end
    function unit:RemoveModifierByName(name) self.modifiers[name]=nil end
    function unit:FindAbilityByName(name) return self.abilities[name] end
    function unit:AddAbility(name)
        local ability={}
        function ability:SetLevel() end
        function ability:SetHidden(hidden) self.hidden=hidden end
        function ability:SetActivated(active) self.active=active end
        function ability:GetAbilityIndex() return 0 end
        self.abilities[name]=ability;return ability
    end
    function unit:StartGesture(activity) self.last_gesture=activity;self.gesture_count=(self.gesture_count or 0)+1 end
    function unit:FadeGesture(activity) self.last_fade=activity;self.fade_count=(self.fade_count or 0)+1 end
    setmetatable(unit,{__index=function(_,key)if key:match("^Set") then return noop end end})
    units[#units+1],by_id[id]=unit,unit
    return unit
end
local function reset()
    rogue_effects.reset()
    bus.reset();scheduler.clear();clock=0;units={};by_id={};defeated=false
    move=nil;paid=0;refunded=0;created=0;failed_create=false;reachable=true;foreign=false;cooldowns=0
    counts_events={};completed_events=0;destroyed_events=0;failed_move=false
    account={gold=10000,wood=10000}
    caster=entity(1,"npc_survival_builder_proxy",Vector(0,0,128))
    presentation.init();presentation.apply(caster)
    authorized_builders={[caster]=0}
    bus.handle_request(events.BUILDER_GET_REQUEST,function(payload)
        local owner=authorized_builders[payload.caster]
        return {ok=not foreign and owner~=nil,player_id=owner,
            builder=not foreign and owner~=nil and payload.caster or nil,error="builder_not_owned"}
    end)
    bus.handle_request(events.RESOURCE_CAN_SPEND_REQUEST,function(p)
        return {ok=account.wood >= p.wood and account.gold >= p.gold,error="poor"}
    end)
    bus.handle_request(events.RESOURCE_TRY_SPEND_REQUEST,function(p)
        paid=paid+1
        if account.wood < p.wood or account.gold < p.gold then return {ok=false,error="poor"} end
        account.wood=account.wood-p.wood;account.gold=account.gold-p.gold
        return {ok=true}
    end)
    bus.handle_request(events.RESOURCE_ADD_REQUEST,function(p)
        refunded=refunded+1;account.wood=account.wood+(p.wood or 0);account.gold=account.gold+(p.gold or 0)
        return {ok=true}
    end)
    bus.handle_request(events.RESOURCE_RELEASE_POP_REQUEST,function()return {ok=true}end)
    ExecuteOrderFromTable=function(order)
        assert(order.UnitIndex==1 and order.OrderType==DOTA_UNIT_ORDER_MOVE_TO_POSITION)
        assert(caster.survival_build_internal_order==true,"automated move must not cancel its own task")
        if failed_move then error("injected builder movement failure") end
        move=order.Position
    end
    CreateUnitByName=function(name,position)
        created=created+1
        if failed_create then return nil end
        assert(math.abs(caster.position.x-position.x)>64 or math.abs(caster.position.y-position.y)>64,
            "the builder must physically clear the footprint before creation")
        return entity(10+created,name,position)
    end
    bus.subscribe(events.BUILDING_COUNTS_CHANGED,function(payload)
        counts_events[#counts_events+1]=payload
    end)
    bus.subscribe(events.BUILDING_CREATED,function()completed_events=completed_events+1 end)
    bus.subscribe(events.BUILDING_DESTROYED,function()destroyed_events=destroyed_events+1 end)
    grid.init();building.init()
end
local ability={IsNull=function()return false end,EndCooldown=function()cooldowns=cooldowns+1 end}
local function build(position)
    local result,error_code=bus.request(events.BUILD_REQUEST,{caster=caster,player_id=0,
        building_id="main_city",position=position or Vector(0,0,128),source_ability=ability})
    assert(not error_code,error_code);return result
end
local errors = {}
local original_print = print
print = function(message, ...)
    if tostring(message):find("handler error", 1, true) or tostring(message):find("task failed", 1, true) then
        errors[#errors + 1] = tostring(message)
    else original_print(message, ...) end
end
local function tick(time)
    clock=time;scheduler.think();assert(#errors == 0,table.concat(errors,"\n"))
end
local function arrived() caster.position=Vector(move.x,move.y,move.z) end
local function occupied(player_id)
    local result,error_code=bus.request(events.BUILDING_COUNTS_REQUEST,{player_id=player_id or 0})
    assert(not error_code and result and result.ok,error_code)
    assert(result.counts.main_city~=nil and result.counts.building_farm~=nil,
        "authoritative snapshots must include zero counts for known building types")
    return result.counts.main_city
end
local function actual_count()
    return building._building_limit_for_test.count_for(0,"main_city")
end

reset()
assert(occupied()==0 and actual_count()==0)
assert(build().ok and move and paid==0 and created==0)
assert(occupied()==1 and actual_count()==0 and completed_events==0,
    "accepting a unique order reserves its allowance immediately without counting a completed building")
assert(occupied(1)==0,"unique reservations must be scoped to the authenticated player")
local accepted_task=caster.survival_build_task
assert(not build(Vector(640,640,128)).ok and caster.survival_build_task==accepted_task,
    "a second unique order must not replace the accepted travel task")
assert(caster.position.x==0 and caster.position.y==0,"request issues movement without teleporting")
tick(0.1);assert(paid==0 and created==0,"remaining inside footprint cannot spend or construct")
assert(caster.gesture_count==nil,"travel must not trigger Io construction feedback")
assert(occupied()==1 and actual_count()==0)
arrived();tick(0.2)
assert(paid==1 and created==1 and refunded==0)
assert(caster.last_gesture==ACT_DOTA_ATTACK and caster.gesture_count==1,
    "actual construction must play the native Io attack activity once")
assert(next(charge)==nil,"actual construction must not create red charging particles")
assert(occupied()==1 and actual_count()==1 and completed_events==0,
    "arrival transfers the reserved allowance into construction without advancing completed-building state")
assert(#counts_events==2 and counts_events[1].counts.main_city==1 and counts_events[2].counts.main_city==1,
    "travel-to-construction synchronization must never publish a reopened or double-counted unique allowance")
assert(by_id[11].survival_hull_radius>0 and by_id[11]:HasModifier("modifier_building_under_construction"),
    "invisible construction must reserve a physical hull before completion")
assert(account.wood==10000-config.main_city.build_cost.wood)
assert(not build().ok and paid==1,"duplicate request cannot construct a second city")
tick(20);assert(paid==1 and created==1)
assert(next(charge)==nil and caster.last_fade==ACT_DOTA_ATTACK,
    "actual completion must end its gesture without charging particles")
assert(occupied()==1 and actual_count()==1 and completed_events==1)
local city=by_id[11]
assert(not city:HasModifier("modifier_building_under_construction") and city.survival_hull_radius>0,
    "completed city retains its ordinary collision")
assert(city.abilities.ability_train_lumberjack.hidden==true,"preserve the production-panel skill hiding fix")

reset();assert(build().ok);accepted_task=caster.survival_build_task
assert(not build().ok and caster.survival_build_task==accepted_task and paid==0)
arrived();tick(0.1);assert(paid==1 and created==1,"duplicate unique orders still produce exactly one paid construction")

reset();assert(build().ok)
local other_builder=entity(2,"npc_survival_builder_proxy",Vector(1000,1000,128))
authorized_builders[other_builder]=0
local second=bus.request(events.BUILD_REQUEST,{caster=other_builder,player_id=0,
    building_id="main_city",position=Vector(640,640,128),source_ability=ability})
assert(second and not second.ok and other_builder.survival_build_task==nil and occupied()==1,
    "another authenticated builder must not bypass the player's queued unique reservation")

reset();assert(build().ok);accepted_task=caster.survival_build_task
caster.survival_build_task=nil;tick(0.1)
assert(paid==0 and created==0 and cooldowns==1,"external cancellation before arrival is free")
assert(occupied()==0 and actual_count()==0 and counts_events[#counts_events].counts.main_city==0)
tick(1);assert(cooldowns==1 and occupied()==0 and #counts_events==2)
assert(build().ok,"cancellation must restore the unique construction allowance")
local replacement_task=caster.survival_build_task
building._clear_build_task_for_test(caster,accepted_task)
assert(caster.survival_build_task==replacement_task and occupied()==1,
    "stale task cleanup must not release a newer accepted order")
reset();assert(build().ok);caster.alive=false;tick(0.1)
assert(paid==0 and created==0 and caster.survival_build_task==nil and occupied()==0)
reset();assert(build().ok);caster.null=true;tick(0.1)
assert(paid==0 and created==0 and occupied()==0 and cooldowns==1,
    "an invalid builder handle must still release its task's unique reservation")
reset();assert(build().ok);defeated=true;arrived();tick(0.1)
assert(paid==0 and created==0 and occupied()==0,"defeated players cannot begin delayed construction")
reset();assert(build().ok);foreign=true;arrived();tick(0.1)
assert(paid==0 and created==0 and occupied()==0,"ownership is rechecked after movement")
reset();reachable=false
assert(not build().ok and move==nil and paid==0 and occupied()==0,"no safe reachable position rejects before movement or payment")
reset();failed_move=true
assert(not build().ok and caster.survival_build_task==nil and occupied()==0 and #counts_events==0,
    "a rejected engine move order must not reserve a unique building allowance")
reset();assert(build().ok);tick(100)
assert(paid==0 and created==0 and caster.survival_build_task==nil and occupied()==0,"stalled movement expires without charging")
reset();assert(build().ok);arrived();account.wood=0;tick(0.1)
assert(paid==0 and created==0 and cooldowns==1 and occupied()==0,"resources are rejected before final spend after arrival")
reset();assert(build().ok);arrived();failed_create=true;tick(0.1)
assert(paid==1 and created==1 and refunded==1 and account.wood==10000 and account.gold==10000)
assert(occupied()==0 and actual_count()==0 and completed_events==0)
tick(10);assert(refunded==1,"failed creation refunds once")
reset();assert(build().ok);arrived()
entity(7,"enemy",Vector(0,0,128));tick(0.1)
assert(paid==0 and created==0 and occupied()==0,"other units entering the requested footprint invalidate construction")

reset();assert(build().ok);arrived();tick(0.1)
local failed_building=by_id[11]
failed_building.alive=false;tick(0.2)
assert(occupied()==0 and actual_count()==0 and refunded==1 and completed_events==0 and destroyed_events==0,
    "construction watchdog failure must release the allowance without a completed-building event")
tick(0.3);assert(refunded==1 and occupied()==0)

reset();assert(build().ok);arrived();tick(0.1)
local killed_building=by_id[11]
killed_building.alive=false
bus.emit(events.ENGINE_ENTITY_KILLED,{victim=killed_building})
assert(occupied()==0 and actual_count()==0 and refunded==1 and destroyed_events==0,
    "construction death must release its actual count even without BUILDING_DESTROYED")
bus.emit(events.ENGINE_ENTITY_KILLED,{victim=killed_building});tick(0.2)
assert(occupied()==0 and refunded==1,"late death and watchdog callbacks must not release twice")

reset();assert(build().ok)
bus.emit(events.PLAYER_DISCONNECTED,{player_id=0})
assert(occupied()==0 and caster.survival_build_task==nil)
tick(0.1);assert(paid==0 and created==0 and cooldowns==1,
    "disconnect cleanup must cancel the pending allowance without later starting construction")
print("BUILDER_YIELD_CONSTRUCTION_PASS: accepted unique reservation, atomic construction transfer, duplicate/multi-builder rejection; cancel/death/invalid/timeout/failure/disconnect release; actual move and one spend/refund")

-- The client talent projection and real construction must agree before the
-- first city exists; only successful completion consumes the free charge.
reset()
local runtime_builder = require("ui/ability_runtime_builder")
local view = {player_id = 0, city_level = 0, building_counts = {}, hero_summoned = 0}
local resources = {wood = 0, gold = 0, population = 0, max_population = 0}
local function build_altar()
    return bus.request(events.BUILD_REQUEST, {caster = caster, player_id = 0,
        building_id = "hero_altar", position = Vector(0,0,128), source_ability = ability})
end
assert(not build_altar().ok, "ordinary altar still requires a completed city level3")
rogue_effects.add_numeric(0, "builder_free_hero_altar", 1)
account.wood, account.gold = 0, 0
local free_runtime = runtime_builder.build("ability_build_hero_altar", view, resources)
assert(free_runtime.available == 1 and free_runtime.can_afford == 1)
assert(build_altar().ok, "talent admits real altar construction at city0 with no resources")
arrived();tick(0.1)
assert(created == 1 and account.wood == 0 and account.gold == 0)
assert(rogue_effects.numeric(0, "builder_free_hero_altar") == 1, "charge is retained during construction")
tick(100)
assert(completed_events == 1 and rogue_effects.numeric(0, "builder_free_hero_altar") == 0)
assert(not build_altar().ok, "completion cannot reopen a duplicate free altar")
print("FREE_ALTAR_CONSTRUCTION_PASS: real city0 placement/construction, zero cost, completion-only charge consumption, unique limit")
-- Unfunded requests cannot create a preview/travel task, reserve a unique
-- building, issue movement, spend resources or create an entity.
reset();account.wood,account.gold=0,0
assert(not build().ok)
assert(caster.survival_build_task==nil and occupied()==0 and move==nil and paid==0 and created==0)
print("BUILD_RESOURCE_PREFLIGHT_PASS: no task, movement, reservation, spend or entity when materials are insufficient")

-- Mixed promoted/base towers and accepted travel orders share one per-owner
-- cap. In-progress construction transfers that reservation without opening it.
reset()
local original_unlock = config.arrow_tower.unlock_city_level
config.arrow_tower.unlock_city_level = 0
building._building_limit_for_test.change_count(0, "class_1", 3)
building._building_limit_for_test.change_count(0, "class_2", 3)
local function tower_count(player_id)
    return bus.request(events.BUILDING_COUNTS_REQUEST, {player_id = player_id or 0}).counts.arrow_tower
end
local function tower_request(owner, builder_unit, position, task, event)
    return bus.request(event or events.BUILD_REQUEST, {player_id = owner, caster = builder_unit,
        building_id = "arrow_tower", position = position or Vector(0,0,128),
        source_ability = ability, build_task = task})
end
assert(tower_count() == 6 and tower_request(0,caster).ok and tower_count() == 7)
local seventh_task = caster.survival_build_task
local competitor = entity(30,"npc_survival_builder_proxy",Vector(2000,2000,128))
authorized_builders[competitor] = 0
local blocked = tower_request(0,competitor,Vector(2400,2400,128))
assert(not blocked.ok and competitor.survival_build_task == nil and paid == 0,
    "the seventh travel order preoccupies the slot against another builder")
assert(not tower_request(0,competitor,Vector(2400,2400,128),seventh_task,events.BUILD_CAN_PLACE_REQUEST).ok,
    "another builder cannot bypass the cap with the first builder's task handle")
assert(tower_request(0,caster,nil,seventh_task,events.BUILD_CAN_PLACE_REQUEST).ok,
    "the authenticated pending order does not count itself twice on final preflight")
local teammate = entity(31,"npc_survival_builder_proxy",Vector(800,800,128))
authorized_builders[teammate] = 1
local teammate_check = tower_request(1,teammate,Vector(512,512,128),nil,events.BUILD_CAN_PLACE_REQUEST)
assert(tower_count(1) == 0 and teammate_check.ok,
    "a full player on the same team does not consume another player's cap: " .. tostring(teammate_check.error))
arrived();tick(0.1)
assert(created == 1 and paid == 1 and tower_count() == 7
    and building._building_limit_for_test.count_for(0,"arrow_tower") == 7,
    "arrival atomically transfers the accepted order to the construction entity")
assert(not tower_request(0,competitor,Vector(2400,2400,128)).ok)
local seventh = by_id[11]
seventh.alive = false
bus.emit(events.ENGINE_ENTITY_KILLED,{victim=seventh})
assert(tower_count() == 6 and refunded == 1)
bus.emit(events.ENGINE_ENTITY_KILLED,{victim=seventh});tick(0.2)
assert(tower_count() == 6 and refunded == 1,
    "construction death and its delayed watchdog release exactly one live slot")
assert(tower_request(0,caster).ok and tower_count() == 7,
    "a dead construction can be immediately replaced without a historical build limit")
local replacement = caster.survival_build_task
caster.survival_build_task = nil;tick(0.31)
assert(tower_count() == 6 and replacement ~= seventh_task,
    "canceling the replacement travel order returns its reservation")
config.arrow_tower.unlock_city_level = original_unlock
print("PLAYER_TOWER_PENDING_CAP_PASS: promoted totals, seventh-order reservation, authenticated recheck, same-team owner isolation, atomic construction, death/refund and cancellation")
