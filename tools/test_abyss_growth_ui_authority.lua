-- Production stat service, adapter, health guard, scheduler, bus and math.
-- Only unrelated bootstrap/config and the native entity/modifier boundary are mocked.
package.path = "scripts/vscripts/?.lua;" .. package.path
package.loaded["core/test_access_policy"]={enabled=function()return false end,allowed=function()return true end}
for _, name in ipairs({ "systems/effect_handler_registry", "systems/equipment_effect_service",
    "systems/equipment_stat_aggregation_service", "systems/triggered_proc_service" }) do
    package.loaded[name] = { init = function() end }
end
local rules = { hero_strength_health_per_point = 0, hero_intellect_attack_per_point = 0,
    number = function(_, fallback) return fallback end }
package.loaded["config/global_rules"] = rules
local definition = { hero_id = "growth_test", unit_name = "npc_growth_test", attack_speed = 2,
    base_damage_min = 112, base_damage_max = 120, base_health = 1000,
    base_strength = 10, base_agility = 20, base_intellect = 30, attack_range = 800 }
package.loaded["config/generated/hero_definitions"] = { by_id = { growth_test = definition } }
package.loaded["config/generated/weapon_definitions"] = { by_id = {
    growing = { base_attack_min = 50, base_attack_max = 60,
        base_strength = 1, base_agility = 2, base_intellect = 3 },
    replacement = { base_attack_min = 80, base_attack_max = 100,
        base_strength = 4, base_agility = 5, base_intellect = 6 },
} }
package.loaded["config/generated/hero_attack_projectiles"] = { by_id = {
    growth_test = { attack_capability = "ranged", projectile_speed = 900,
        projectile_model = "particles/test_projectile.vpcf" },
} }
local technology, equipment, growth = {}, {}, {}
package.loaded["systems/technology_stat_manager"] = {
    get = function(id) return { final = { hero = technology[id] or {} } } end,
}
local logs = {}
package.loaded["core/logger"] = { info = function(category)
    logs[category] = (logs[category] or 0) + 1
end, warn = function() end }
DOTA_UNIT_CAP_RANGED_ATTACK, DOTA_UNIT_CAP_MELEE_ATTACK = 2, 1
local now = 0
GameRules = { GetGameTime = function() return now end }
local bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local health_guard = require("core/hero_health_guard")
local counts, publications, growth_reads, recalculations = {}, {}, {}, {}
local function count(unit, key)
    local c = counts[unit]
    c[key] = (c[key] or 0) + 1
end
local function near(actual, expected, label)
    assert(type(actual) == "number" and math.abs(actual - expected) < 1e-7,
        (label or "number") .. ": " .. tostring(actual) .. " != " .. tostring(expected))
end
local function snapshot(id)
    local result, err = bus.request(events.HERO_COMBAT_STATS_GET_REQUEST, { player_id = id })
    assert(result and result.ok, tostring(err or result and result.error))
    return result.snapshot
end
local function unit(id, player_id)
    local u = { id = id, player_id = player_id, modifiers = {}, health = 230,
        maximum = 300, native_health = 300, bat = 0.5, damage_min = 112, damage_max = 120,
        projectile_speed = 300, refill_on_calculate = true }
    counts[u] = {}
    function u:IsNull() return self.null == true end
    function u:IsAlive() return not self.null and not self.dead end
    function u:entindex() return self.id end
    function u:GetLevel() return 1 end
    function u:GetUnitName() return "npc_growth_test" end
    function u:GetHealth() return self.health end
    function u:GetMaxHealth() return self.maximum end
    function u:SetHealth(value) count(self, "health"); self.health = value end
    function u:GetBaseAttackTime() return self.bat end
    function u:SetBaseAttackTime(value)
        count(self, "bat")
        if self.fail_next_bat then self.fail_next_bat = nil; return false end
        self.bat = value
    end
    function u:GetBaseDamageMin() return self.damage_min end
    function u:GetBaseDamageMax() return self.damage_max end
    function u:SetBaseDamageMin(value) count(self, "damage_min"); self.damage_min = value end
    function u:SetBaseDamageMax(value) count(self, "damage_max"); self.damage_max = value end
    function u:SetBaseStrength() count(self, "strength_zero") end
    function u:SetBaseAgility() count(self, "agility_zero") end
    function u:SetBaseIntellect() count(self, "intellect_zero") end
    function u:Script_SetAttackRange(value) count(self, "range"); self.range = value end
    function u:SetAcquisitionRange(value) count(self, "acquisition"); self.acquisition = value end
    function u:GetAttackRange() return self.range or 150 end
    function u:GetAttackSpeed() return 100 end
    function u:GetPhysicalArmorValue() return 0 end
    function u:GetMoveCapability() return 1 end
    function u:GetAttackCapability() return self.capability end
    function u:SetAttackCapability(value) count(self, "capability"); self.capability = value end
    function u:SetRangedProjectileName(value) count(self, "projectile_name"); self.projectile = value end
    function u:GetProjectileSpeed()
        local modifier = self.modifiers.modifier_survival_hero_projectile_speed
        return self.projectile_speed + (modifier and modifier.stack or 0)
    end
    function u:SetProjectileSpeed(value) count(self, "projectile_speed"); self.projectile_speed = value end
    function u:FindModifierByName(name) return self.modifiers[name] end
    function u:HasModifier(name) return self.modifiers[name] ~= nil end
    function u:RemoveModifierByName(name) self.modifiers[name] = nil end
    function u:CalculateStatBonus()
        count(self, "calculate")
        local bonus = self.modifiers.modifier_survival_hero_base_health
        self.maximum = self.native_health + (bonus and bonus.stack or 0)
        -- Simulate the reported native stat-recalculation refill. The real
        -- adapter and health guard must preserve missing HP despite this.
        if self.refill_on_calculate then self.health = self.maximum end
    end
    function u:AddNewModifier(_, _, name, params)
        count(self, "modifier_add:" .. name)
        local m = { stack = 0 }
        function m:GetStackCount() return self.stack end
        function m:SetHealthBonus(value) count(u, "health_bonus"); self.stack = value end
        function m:SetStackCount(value) count(u, "stack:" .. name); self.stack = value end
        function m:SetProjectileSpeedBonus(value) count(u, "projectile_bonus"); self.stack = value end
        function m:SetAttackRange(value) count(u, "range_modifier"); self.range = value end
        function m:SetTechnologyValues(...) count(u, "technology"); self.values = { ... } end
        function m:ForceRefresh()
            if name == "modifier_weapon_stat_projection" then
                count(u, "weapon_refresh")
                self.snapshot = snapshot(u.player_id) -- Real modifier's recursive request contract.
            elseif name == "modifier_equipment_effects" then
                count(u, "equipment_refresh")
            end
        end
        self.modifiers[name] = m
        if params and params.health_bonus then m:SetHealthBonus(params.health_bonus) end
        if params and params.projectile_speed_bonus then m:SetProjectileSpeedBonus(params.projectile_speed_bonus) end
        return m
    end
    -- The primary hero adapter normally installs this before HERO_SUMMONED.
    u:AddNewModifier(u, nil, "modifier_survival_hero_attack_range", {})
    return u
end
package.loaded["core/modifier_registry"] = { ensure = function(u, name, params)
    return u:FindModifierByName(name) or u:AddNewModifier(u, nil, name, params)
end }
local print_original = print
print = function(message)
    if tostring(message):find("%[EventBus%] handler error")
        or tostring(message):find("%[Scheduler%] task failed") then error(message) end
end
package.loaded["core/test_access_policy"]={enabled=function()return false end,allowed=function()return true end}
package.loaded["systems/player_profile_service"]={get_profile=function()return nil end}
package.loaded["systems/technology_stat_manager"].training_room_multiplier=function()return 1 end
local real_weapons=dofile("scripts/vscripts/config/generated/weapon_definitions.lua")
local abyss=real_weapons.by_id.weapon_legend_abyss_10
package.loaded["config/generated/weapon_definitions"].by_id[abyss.content_id]=abyss
local service = require("systems/hero_combat_stat_service")
service.init()
bus.handle_request(events.WEAPON_EQUIPMENT_GET_REQUEST, function(payload)
    return { ok = true, snapshot = equipment[payload.player_id] or {} }
end)

bus.handle_request(events.EQUIPMENT_STATS_GET_REQUEST, function(payload)
    local id = payload.player_id
    recalculations[id] = (recalculations[id] or 0) + 1
    return { ok = true, snapshot = { values = {} } }
end)
bus.subscribe(events.HERO_COMBAT_STATS_CHANGED, function(payload)
    local id = payload.player_id
    publications[id] = (publications[id] or 0) + 1
end)
local function summon(id, player_id)
    equipment[player_id] = equipment[player_id] or { main_hand_content_id = "growing", main_hand_name = "Growing" }
    growth[player_id] = growth[player_id] or {}
    local hero = unit(id, player_id)
    bus.emit(events.HERO_SUMMONED, { player_id = player_id, hero_id = "growth_test", unit = hero })
    near(hero.maximum, 1000, "real health adapter at birth")
    return hero
end
local function copy_counts(hero)
    local copy = {}
    for key, value in pairs(counts[hero]) do copy[key] = value end
    return copy
end
local function delta(hero, before, key) return (counts[hero][key] or 0) - (before[key] or 0) end
local stable_native = { "equipment_refresh", "projectile_name", "projectile_speed", "projectile_bonus",
    "capability", "bat", "range", "acquisition", "range_modifier",
    "strength_zero", "agility_zero", "intellect_zero", "damage_min", "damage_max", "technology",
    "health_bonus", "calculate", "health" }

local producer=require("systems/weapon_growth_service");producer.init()
local native_tables,table_first,table_last={},nil,nil
CustomNetTables={GetTableValue=function()return nil end,SetTableValue=function(_,name,key,value)
 native_tables[name]=(native_tables[name]or 0)+1
 if name=="survival_combat_stats"then table_first=table_first or value;table_last=value end
end}
local indexed={}
EntIndexToHScript=function(id)return indexed[id]end
if arg[2]and arg[2]~='baseline'then package.preload['ui/combat_stats_ui_service']=function()return assert(loadfile(arg[2]))()end end
-- Explicit legacy consumer isolates batching while preserving actual producer math.
package.loaded['ui/ui_request_router']={route_owner_hero_stats=function()return false end}
local bridge=require("ui/combat_stats_ui_service");bridge.init()
bus.handle_request(events.CONTENT_INVENTORY_GET_REQUEST,function()return {ok=true,snapshot={counts={}}}end)
bus.handle_request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST,function()return {ok=true,totals={}}end)
local hero=summon(101,0);indexed[101]=hero
equipment[0]={main_hand_content_id=abyss.content_id,main_hand_name=abyss.display_name}
bus.emit(events.WEAPON_EQUIPPED_CHANGED,{player_id=0,slot="main_hand",content_id=abyss.content_id})
local requests,events_count={},{}
local request_original,emit_original=bus.request,bus.emit
bus.request=function(name,payload)requests[name]=(requests[name]or 0)+1;return request_original(name,payload)end
bus.emit=function(name,payload)events_count[name]=(events_count[name]or 0)+1;return emit_original(name,payload)end
local hits=tonumber(arg[1])or 600
native_tables={};table_first=nil;table_last=nil
local before_calc=recalculations[0]or 0;local before_pub=publications[0]or 0;local writes=copy_counts(hero)
local started=os.clock()
for n=1,hits do
 -- Native OnTakeDamage emits this outer event once per legal damaged target.
 bus.emit(events.COMBAT_DAMAGE_RESOLVED,{player_id=0,attacker=hero,owner_hero=hero,
  target={IsNull=function()return false end},final_damage=100,attacker_entindex=101})
 if arg[3]then now=now+tonumber(arg[3]);scheduler.think()end
end
now=now+0.101;scheduler.think() -- tail must publish even when attacks stop
local elapsed=(os.clock()-started)*1000
assert((recalculations[0]or 0)-before_calc==hits,'every damaged target still recomputes authority')
assert((native_tables.survival_combat_debug or 0)==0,'hidden debug must not publish')
local measured_calc=(recalculations[0]or 0)-before_calc
local measured_pub=(publications[0]or 0)-before_pub
local native_diff={};for key,value in pairs(counts[hero])do local d=value-(writes[key]or 0);if d~=0 then native_diff[key]=d end end
local grown=bus.request(events.WEAPON_GROWTH_GET_REQUEST,{player_id=0}).snapshot
near(grown.growth_attack,hits*20);near(grown.growth_strength,hits*5)
near(grown.growth_agility,hits*5);near(grown.growth_intellect,hits*5)
local fields,changed=0,0
for key,value in pairs(table_last or {})do fields=fields+1;if table_first[key]~=value then changed=changed+1 end end
local json=require("core/json_encoder")
local lookup=require('config/generated/ui_static_catalog_lookup')
local factory=assert(require('ui/compact_selected_projection').new(lookup))
local a,b={},{};for k,v in pairs(table_first or {})do a[k]=v end;for k,v in pairs(table_last or {})do b[k]=v end
a.success=1;b.success=1
local selected,full_ops=assert(factory.initialize(a,101,1))
local delta_ops,delta_metrics=assert(selected.update(b))
local wire=require('ui/compact_wire');local wire_schema=assert(wire.compile_lookup(lookup,1))
local packets=assert(wire.encode(wire_schema,{schema=1,schema_sha256=lookup.sha256,session=600,epoch=1,view=5},2,delta_ops,{}))
local bytes,max_bytes=0,0;for _,p in ipairs(packets)do bytes=bytes+#p.d+25;max_bytes=math.max(max_bytes,#p.d+25)end
print=print_original
print(json.encode({status="REAL_ABYSS_PRODUCER_COMBAT_AND_UI_COUNTS",damage_targets=hits,
 source_requests=requests,event_emissions=events_count,recalculations=measured_calc,
 publications=measured_pub,native_nettables=native_tables,native_writes=native_diff,
 full_combat_dto_fields=fields,changed_fields_first_last=changed,
 last_combat_dto_json_bytes=#json.encode(table_last),growth_attack=grown.growth_attack,
 growth_each_attribute=grown.growth_strength,isolated_lua_ms=elapsed,native_time_measured=false,
 network_bytes_measured=false,live_calls=0,source_changes=0,
 current_view5_delta={ops=#delta_ops,frames=#packets,calibrated_native_bytes=bytes,max_calibrated_native_bytes=max_bytes,
 fixed_metric_visits=delta_metrics.fixed_metric_visits,full_ops=#full_ops,native_measurement=false}}))
