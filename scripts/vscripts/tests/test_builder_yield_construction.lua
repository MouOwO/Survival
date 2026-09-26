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
package.loaded["systems/rogue_effect_state_service"] = {numeric = function() return 0 end}
package.loaded["systems/forbidden_region_service"] = {validate_building_footprint = function() return true end}
local defeated = false
package.loaded["systems/player_context_service"] = {is_defeated = function() return defeated end}
DOTA_TEAM_GOODGUYS = 2
DOTA_UNIT_TARGET_TEAM_BOTH, DOTA_UNIT_TARGET_HERO, DOTA_UNIT_TARGET_BASIC = 3,1,2
DOTA_UNIT_TARGET_BUILDING, DOTA_UNIT_TARGET_FLAG_INVULNERABLE, FIND_ANY_ORDER = 4,16,0
DOTA_UNIT_ORDER_MOVE_TO_POSITION, ACT_DOTA_ATTACK = 1,1
local mt = {}; mt.__index = {Length2D = function(v) return math.sqrt(v.x*v.x+v.y*v.y) end}
Vector = function(x,y,z) return setmetatable({x=x,y=y,z=z or 0},mt) end
mt.__add=function(a,b)return Vector(a.x+b.x,a.y+b.y,a.z+b.z)end
mt.__sub=function(a,b)return Vector(a.x-b.x,a.y-b.y,a.z-b.z)end
local clock, units, by_id, caster, move, paid, refunded, created, failed_create, reachable, foreign, account, cooldowns
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
local config = require("config/buildings_config")
-- The starting city is free in gameplay; use a charged fixture to exercise
-- the shared construction spend/refund boundary without changing live data.
config.main_city.build_cost = {wood = 100, gold = 50}
local function entity(id, name, position)
    local unit = {index=id,name=name,position=position,alive=true,modifiers={},abilities={},health=5000}
    function unit:IsNull() return false end
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
    function unit:StartGesture() end
    setmetatable(unit,{__index=function(_,key)if key:match("^Set") then return noop end end})
    units[#units+1],by_id[id]=unit,unit
    return unit
end
local function reset()
    bus.reset();scheduler.clear();clock=0;units={};by_id={};defeated=false
    move=nil;paid=0;refunded=0;created=0;failed_create=false;reachable=true;foreign=false;cooldowns=0
    account={gold=10000,wood=10000}
    caster=entity(1,"npc_survival_builder_proxy",Vector(0,0,128))
    bus.handle_request(events.BUILDER_GET_REQUEST,function(payload)
        return {ok=not foreign,player_id=0,builder=not foreign and caster or nil,error="builder_not_owned"}
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
        move=order.Position
    end
    CreateUnitByName=function(name,position)
        created=created+1
        if failed_create then return nil end
        assert(math.abs(caster.position.x-position.x)>64 or math.abs(caster.position.y-position.y)>64,
            "the builder must physically clear the footprint before creation")
        return entity(10+created,name,position)
    end
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

reset()
assert(build().ok and move and paid==0 and created==0)
assert(caster.position.x==0 and caster.position.y==0,"request issues movement without teleporting")
tick(0.1);assert(paid==0 and created==0,"remaining inside footprint cannot spend or construct")
arrived();tick(0.2)
assert(paid==1 and created==1 and refunded==0)
assert(account.wood==10000-config.main_city.build_cost.wood)
assert(not build().ok and paid==1,"duplicate request cannot construct a second city")
tick(20);assert(paid==1 and created==1)
local city=by_id[11]
assert(city.abilities.ability_train_lumberjack.hidden==true,"preserve the production-panel skill hiding fix")

reset();assert(build().ok);assert(build().ok);assert(paid==0)
arrived();tick(0.1);assert(paid==1 and created==1,"replacement orders produce exactly one paid construction")

reset();assert(build().ok);caster.survival_build_task=nil;tick(0.1)
assert(paid==0 and created==0 and cooldowns==1,"external cancellation before arrival is free")
tick(1);assert(cooldowns==1)
reset();assert(build().ok);caster.alive=false;tick(0.1)
assert(paid==0 and created==0 and caster.survival_build_task==nil)
reset();assert(build().ok);defeated=true;arrived();tick(0.1)
assert(paid==0 and created==0,"defeated players cannot begin delayed construction")
reset();assert(build().ok);foreign=true;arrived();tick(0.1)
assert(paid==0 and created==0,"ownership is rechecked after movement")
reset();reachable=false
assert(not build().ok and move==nil and paid==0,"no safe reachable position rejects before movement or payment")
reset();assert(build().ok);tick(100)
assert(paid==0 and created==0 and caster.survival_build_task==nil,"stalled movement expires without charging")
reset();assert(build().ok);arrived();account.wood=0;tick(0.1)
assert(paid==1 and created==0 and cooldowns==1,"resources are rechecked after arrival")
reset();assert(build().ok);arrived();failed_create=true;tick(0.1)
assert(paid==1 and created==1 and refunded==1 and account.wood==10000 and account.gold==10000)
tick(10);assert(refunded==1,"failed creation refunds once")
reset();assert(build().ok);arrived()
entity(7,"enemy",Vector(0,0,128));tick(0.1)
assert(paid==0 and created==0,"other units entering the requested footprint invalidate construction")
print("BUILDER_YIELD_CONSTRUCTION_PASS: actual move before spend, one construction, full arrival validation, cancellation/death/defeat/ownership/timeout, resource failure and refund")