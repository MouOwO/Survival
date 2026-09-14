package.path = "scripts/vscripts/?.lua;" .. package.path
local config = require("config/buildings_config")
local rules = require("systems/wall_upgrade_rules")
local quote = assert(rules.quote(config.wall, 1, true))
assert(quote.target_level == 25 and quote.data.display_name == "城墙_9_1")
assert(quote.cost.wood == 946600 and quote.cost.gold == 143860)
assert(not rules.quote(config.wall, 2, true))
assert(not rules.quote(config.wall, 30, false))

local bus = require("core/event_bus")
local events = require("core/events")
local noop = function() end
for _, name in ipairs({"tower_skill_runtime", "tower_ability_sync", "building_population_service", "building_visual_service", "asset_preload_service", "building_sound_service", "tower_utility_ability_sync", "war3_armor_target"}) do
    package.loaded["systems/" .. name] = {reset=noop, apply=noop, upgrade_completed=noop}
end
package.loaded["debug/dev_wall_stats"] = {apply=noop}
package.loaded["systems/technology_stat_manager"] = {get=function() return {final={}} end}
package.loaded["systems/player_profile_service"] = {get_profile=function() return nil end}
local free_consumed = 0
package.loaded["systems/rogue_effect_state_service"] = {
    wall_health_flat=function() return 0 end, numeric=function() return 1 end,
    consume_numeric=function() free_consumed=free_consumed+1 end,
}
package.loaded["systems/building_health_projection"] = {
    maximum_with_flat_bonus=function(base,pct,flat) return base*(1+pct/100)+flat end,
    apply_maximum_health_increase=function(unit,fn) fn() end,
}
local pending, start_fail
package.loaded["systems/building_upgrade_process"] = {
    reset=noop, is_active=function(unit) return pending and pending.unit==unit or false end,
    begin=function(unit,options)
        if start_fail then return {ok=false} end
        pending={unit=unit,options=options}; options.on_start(); return {ok=true,pending=true}
    end,
}
local service = require("systems/building_upgrade_system")
service.init()
local wood,gold=2000000,400000
bus.handle_request(events.RESOURCE_TRY_SPEND_REQUEST,function(p)
    if p.wood>wood or p.gold>gold then return {ok=false,error="余额不足"} end
    wood,gold=wood-p.wood,gold-p.gold;return {ok=true}
end)
bus.handle_request(events.RESOURCE_ADD_REQUEST,function(p) wood,gold=wood+p.wood,gold+p.gold;return {ok=true} end)
local serial=0
local function create(id,level)
    serial=serial+1
    local unit={index=serial, abilities={}, max_health=2000, health=2000,survival_player_id=0,survival_building_id=id}
    function unit:IsNull() return false end
    function unit:IsAlive() return true end
    function unit:entindex() return self.index end
    function unit:GetHealth() return self.health end
    function unit:GetMaxHealth() return self.max_health end
    function unit:SetHealth(n) self.health=n end
    function unit:SetMaxHealth(n) self.max_health=n end
    unit.SetBaseMaxHealth=noop;unit.SetPhysicalArmorBaseValue=noop
    function unit:FindAbilityByName(name) return self.abilities[name] end
    function unit:AddAbility(name)
        local a={SetLevel=noop,SetHidden=function(self,v) self.hidden=v end,SetActivated=function(self,v) self.active=v end}
        function a:IsNull() return false end
        function a:GetCaster() return unit end
        function a:GetAbilityName() return name end
        function a:IsPassive() return false end
        function a:IsHidden() return self.hidden end
        function a:IsActivated() return self.active end
        function a:IsFullyCastable() return true end
        function a:GetLevel() return 1 end
        function a:GetCooldown() return 1 end
        function a:StartCooldown() self.cooldown_started=true end
        self.abilities[name]=a;return a
    end
    bus.emit(events.BUILDING_CREATED,{unit=unit,entindex=unit.index,definition=config[id],building_id=id,level=level,team=2,player_id=0})
    return unit
end
create("main_city",1)
local wall=create("wall",1)
assert(wall.abilities.ability_upgrade_wall_9_1.active)
local function request(unit,mode)
    return assert(bus.request(events.BUILDING_UPGRADE_REQUEST,{building=unit,upgrade_mode=mode,silent_notification=true}))
end
local w0,g0=wood,gold
assert(request(wall,"wall_9_1").ok)
assert(wood==w0-946600 and gold==g0-143860 and free_consumed==0,"quick upgrade must pay full cost even with a free one-level reward")
assert(not wall.abilities.ability_upgrade_wall_9_1.active)
assert(not request(wall,"wall_9_1").ok,"busy requests must not spend twice")
local action=pending;pending=nil;action.options.on_complete()
assert(wall.survival_level==25 and wall.max_health==450000)
assert(wall.abilities.ability_upgrade_wall_9_1.hidden and wall.abilities.ability_upgrade_wall.active)
assert(not request(wall,"wall_9_1").ok)

local normal=create("wall",1)
assert(request(normal,"one").ok)
action=pending;pending=nil;action.options.on_complete()
assert(normal.survival_level==2 and normal.abilities.ability_upgrade_wall_9_1.hidden)
local last=create("wall",29)
assert(request(last,"one").ok)
action=pending;pending=nil;action.options.on_complete()
assert(last.survival_level==30 and last.abilities.ability_upgrade_wall.hidden and not last.abilities.ability_upgrade_wall.active)
local restored=create("wall",30)
assert(restored.abilities.ability_upgrade_wall==nil,"already-max wall must not acquire an upgrade button")

local cancelled=create("wall",1)
w0,g0=wood,gold
assert(request(cancelled,"wall_9_1").ok)
action=pending;pending=nil;action.options.on_cancel("test_cancel")
assert(wood==w0 and gold==g0 and cancelled.abilities.ability_upgrade_wall_9_1.active)
start_fail=true;assert(not request(cancelled,"wall_9_1").ok);assert(wood==w0 and gold==g0);start_fail=false
wood=0;assert(not request(cancelled,"wall_9_1").ok);assert(pending==nil and not cancelled.abilities.ability_upgrade_wall_9_1.hidden)
assert(not bus.request(events.BUILDING_UPGRADE_FREE_REQUEST,{building=cancelled,upgrade_mode="wall_9_1"}).ok)
wood,gold=2000000,400000
local ui_wall=create("wall",1)
local batch=require("systems/building_batch_upgrade_service")
assert(batch.execute({player_id=0,primary=ui_wall,primary_ability=ui_wall.abilities.ability_upgrade_wall_9_1,ability_name="ability_upgrade_wall_9_1"}).ok)
assert(pending.options.target_level==25 and wood==2000000-946600 and gold==400000-143860)
assert(ui_wall.abilities.ability_upgrade_wall_9_1.cooldown_started)
print("WALL_QUICK_UPGRADE_PASS: cumulative cost, paid quick upgrade, completion stats, hide after one level/max, busy rejection, cancellation/start refunds, insufficient resources")
