package.path = "scripts/vscripts/?.lua;" .. package.path
local bus = require("core/event_bus")
local events = require("core/events")
local tasks, created, heroes, snapshots, skill_enabled = {}, {}, {}, {}, {}
local serial, requests = 100, 0
local native_entities = {}
local RATE = "modifier_hero_exclusive_summon_attack_rate"
local DEBUG = "modifier_debug_fixed_attack_rate"
package.loaded["core/scheduler"] = {
    after = function(delay, callback, id) tasks[id] = {callback=callback, delay=delay}; return id end,
    every = function(delay, callback, id) tasks[id] = {callback=callback, delay=delay}; return id end,
    cancel = function(id) tasks[id] = nil end,
}
package.loaded["systems/hero_cosmetic_service"] = {
    sync_appearance=function(unit,source) unit.cosmetics=source;return true end,
    clear=function(unit) unit.cosmetics=false end,
}
local HEALTH = "modifier_survival_hero_base_health"
package.loaded["systems/hero_base_health_service"] = {apply=function(unit, bonus)
    local modifier = unit:FindModifierByName(HEALTH)
        or unit:AddNewModifier(unit, nil, HEALTH, {})
    modifier:SetHealthBonus(bonus)
    return modifier
end}
package.loaded["systems/gameplay_phase_guard"] = {post_clear_frozen=function() return false end}
package.loaded["core/sound_service"] = {play=function() end}
function class(value) return value end
function IsServer() return true end
MODIFIER_PROPERTY_FIXED_ATTACK_RATE = 1
local rate_definition = require("modifiers/modifier_hero_exclusive_summon_attack_rate")
local vector = {}; vector.__index=vector
function Vector(x,y,z) return setmetatable({x=x,y=y,z=z or 0},vector) end
vector.__add = function(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
RandomVector=function() return Vector(0,0,0) end
GetGroundPosition=function(position) return position end
FindClearSpaceForUnit=function() end
GameRules={GetGameTime=function() return 0 end}
PlayerResource={GetPlayer=function(_,id) return {id=id} end}
UTIL_Remove=function(unit) unit.removed=true end
local function near(actual,expected,label)
    assert(type(actual)=="number" and math.abs(actual-expected)<1e-8,
        (label or "value") .. ": " .. tostring(actual) .. " ~= " .. expected)
end
local function unit(player_id)
    serial=serial+1
    local u={id=serial,player_id=player_id,modifiers={},health=500,maximum=1000,
        bat=1.7,natural_bat=1.7,animation_point=0.5,bat_writes=0,
        modifier_adds=0,rate_transmissions=0,rate_refreshes=0,abilities={},hull=24,
        stat_bonus_calls=0,health_writes=0,health_bonus_writes=0,hull_writes=0,
        damage_min_writes=0,damage_max_writes=0}
    function u:IsNull() return self.removed == true end
    function u:IsAlive() return not self.removed and not self.dead end
    function u:entindex() return self.id end
    function u:GetUnitName() return "npc_dota_hero_monkey_king" end
    function u:GetAbsOrigin() return Vector(0,0,0) end
    function u:GetTeamNumber() return 2 end
    function u:GetPlayerOwnerID() return self.player_id end
    function u:SetPlayerID(value) self.player_id=value end
    function u:SetOwner(value) self.owner=value end
    function u:GetOwner() return self.owner end
    function u:GetAbilityCount() return 0 end
    function u:FindAbilityByName(name) return self.abilities[name] end
    function u:AddAbility(name)
        local ability={SetLevel=function() end,SetActivated=function() end,SetHidden=function() end}
        self.abilities[name]=ability; return ability
    end
    function u:GetHealth() return self.health end
    function u:GetMaxHealth() return self.maximum end
    function u:SetHealth(value) self.health=value;self.health_writes=self.health_writes+1 end
    function u:GetHullRadius() return self.hull end
    function u:SetHullRadius(value) self.hull=value;self.hull_writes=self.hull_writes+1 end
    -- These setters reject the signed native integer overflow that made the
    -- logical clone panel disagree with its actual attacks after addattack.
    local function native_attack(value)
        assert(type(value)=="number" and value>=0 and value<=2147483647,
            "native base attack exceeded signed int32: " .. tostring(value))
        assert(value==math.floor(value), "native base attack must be integer")
        return value
    end
    function u:SetBaseDamageMin(value)
        self.damage_min=native_attack(value);self.damage_min_writes=self.damage_min_writes+1
    end
    function u:SetBaseDamageMax(value)
        self.damage_max=native_attack(value);self.damage_max_writes=self.damage_max_writes+1
    end
    function u:GetBaseDamageMin() return self.damage_min end
    function u:GetBaseDamageMax() return self.damage_max end
    function u:HasModifier(name) return self.modifiers[name]~=nil end
    function u:IsRealHero() return false end
    function u:SetBaseAttackTime(value) self.bat=value;self.bat_writes=self.bat_writes+1 end
    function u:GetBaseAttackTime() return self.bat end
    function u:FindModifierByName(name) return self.modifiers[name] end
    function u:AddNewModifier(caster,_,name,params)
        local modifier
        if name == RATE then
            self.modifier_adds=self.modifier_adds+1
            modifier=setmetatable({caster=caster},{__index=rate_definition})
            function modifier:GetParent() return u end
            function modifier:SetHasCustomTransmitterData() end
            function modifier:SendBuffRefreshToClients() u.rate_transmissions=u.rate_transmissions+1 end
            function modifier:ForceRefresh()
                u.rate_refreshes=u.rate_refreshes+1
                self.native_interval=self:GetModifierFixedAttackRate()
                self:OnRefresh({})
            end
            modifier:OnCreated(params)
            modifier.native_interval=modifier:GetModifierFixedAttackRate()
        elseif name == HEALTH then
            modifier={bonus=0}
            function modifier:GetStackCount() return self.bonus end
            function modifier:SetHealthBonus(value)
                self.bonus=value;u.health_bonus_writes=u.health_bonus_writes+1
            end
        else
            modifier={SetCombatSnapshot=function(self,snapshot) self.snapshot=snapshot end,
                GetStackCount=function() return 0 end}
        end
        self.modifiers[name]=modifier
        return modifier
    end
    function u:GetAttacksPerSecond()
        local fixed=self.modifiers[DEBUG] or self.modifiers[RATE]
        if fixed then return 1/(fixed.native_interval or fixed:GetModifierFixedAttackRate()) end
        return self.runtime_aps or 1/self.bat
    end
    -- Regression approximation of the independently observed native failure:
    -- GetAttacksPerSecond alone still reports 10 when BAT=.1 stops the attack
    -- animation being accelerated. This fixture is not a Dota engine emulator.
    function u:FixtureAttackInterval()
        local interval=1/self:GetAttacksPerSecond()
        local animation_scale=self.bat/interval
        return math.max(interval,self.animation_point/animation_scale)
    end
    function u:AddNoDraw() self.hidden=true end
    function u:CalculateStatBonus()
        self.stat_bonus_calls=self.stat_bonus_calls+1
        local health_modifier=self.modifiers[HEALTH]
        self.maximum=1000+(health_modifier and health_modifier:GetStackCount() or 0)
        self.health=self.refill_on_stat_bonus and self.maximum or math.min(self.health,self.maximum)
    end
    for _,name in ipairs({"SetControllableByPlayer","SetBaseStrength",
        "SetBaseAgility","SetBaseIntellect"}) do u[name]=function() end end
    native_entities[u.id]=u
    return u
end
CreateUnitByName=function(_,_,_,owner)
    local clone=unit(owner.player_id);created[#created+1]=clone;return clone
end
local reenter_snapshot = false
bus.reset()
bus.handle_request(events.HERO_SUMMON_GET_REQUEST,function(payload)
    return {ok=heroes[payload.player_id]~=nil,unit=heroes[payload.player_id]}
end)
bus.handle_request(events.HERO_SKILL_STATE_GET_REQUEST,function(payload)
    return {ok=true,snapshot={skills=skill_enabled[payload.player_id]
        and {{skill_id="skill_monkey_king_fury",level=1}} or {}}}
end)
bus.handle_request(events.HERO_COMBAT_STATS_GET_REQUEST,function(payload)
    requests=requests+1
    if reenter_snapshot then
        reenter_snapshot=false
        bus.emit(events.HERO_COMBAT_STATS_CHANGED,{player_id=payload.player_id,
            snapshot=snapshots[payload.player_id]})
    end
    return {ok=true,snapshot=snapshots[payload.player_id]}
end)
local original_print=print
print=function(message)
    if tostring(message):find("%[EventBus%] handler error") then error(message) end
end
local service=require("systems/monkey_king_exclusive_service")
service.init()
local function fixed(hero,aps)
    hero.modifiers[DEBUG]={GetModifierFixedAttackRate=function() return 1/aps end}
end
local function summon(player_id,aps)
    local hero=unit(player_id);hero.survival_hero_id="hero_monkey_king"
    heroes[player_id]=hero;skill_enabled[player_id]=true
    snapshots[player_id]={entindex=hero.id,max_health=1000,engine_attack_min=30,
        engine_attack_max=40,attack_min=300,attack_max=400,attack_speed=1.4,
        strength=10,agility=20,intellect=30}
    if aps then fixed(hero,aps) else hero.runtime_aps=2 end
    bus.emit(events.HERO_SKILL_CHANGED,{player_id=player_id})
    return hero,created[#created]
end
local function interval(clone,aps)
    local modifier=assert(clone.modifiers[RATE],"clone requires an engine FIXED_ATTACK_RATE modifier")
    near(modifier:GetModifierFixedAttackRate(),1/aps,"actual modifier interval")
    near(clone:GetAttacksPerSecond(),aps,"modifier-backed native APS")
    near(clone:GetBaseAttackTime(),clone.natural_bat,"carrier natural BAT must remain unchanged")
    assert(clone.bat_writes==0,"fixed-rate inheritance must never overwrite carrier BAT")
    near(clone:FixtureAttackInterval(),1/aps,"animation-aware fixture interval")
    near(clone.survival_attack_speed,aps,"HUD attack speed cache")
    assert(modifier.caster == heroes[clone.player_id],"modifier caster should be the source hero")
end

local first,clone=summon(0,10)
local second,other=summon(1,3)
interval(clone,10);interval(other,3)
-- Prove the fixture detects the reported mismatch even when the APS getter is
-- unchanged: shortening BAT to the fixed interval recreates a slow animation.
clone.bat=0.1
near(clone:GetAttacksPerSecond(),10,"legacy mutation still reports ten APS")
near(clone:FixtureAttackInterval(),0.5,"legacy BAT mutation exposes the animation bound")
clone.bat=clone.natural_bat
near(clone.damage_min,30);near(clone.damage_max,40)
near(clone.health,500,"speed synchronization may not heal")
near(clone.modifiers.modifier_monkey_king_clone.snapshot.attack_speed,10)
local additions,transmissions,refreshes=clone.modifier_adds,clone.rate_transmissions,clone.rate_refreshes
local bat_writes=clone.bat_writes
local function native_cost(unit)
    return {unit.stat_bonus_calls,unit.health_writes,unit.health_bonus_writes,
        unit.hull_writes,unit.damage_min_writes,unit.damage_max_writes}
end
local function unchanged_cost(unit, before, label)
    for index, count in ipairs(native_cost(unit)) do
        assert(count==before[index],label..": unchanged sync performed native write "..index)
    end
end
local stable_cost,other_cost=native_cost(clone),native_cost(other)
for _=1,10 do tasks.monkey_clone_sync.callback() end
unchanged_cost(clone,stable_cost,"ten stable first-player polls")
unchanged_cost(other,other_cost,"ten stable second-player polls")
assert(clone.modifier_adds==additions and clone.rate_transmissions==transmissions
    and clone.rate_refreshes==refreshes and clone.bat_writes==bat_writes,
    "unchanged polling must not recreate or republish the rate modifier")

-- Ordinary damage remains on the clone during stable polls. One immediate
-- growth event updates health/attack/rate together and preserves that ratio,
-- even when native stat recalculation momentarily refills the unit.
clone.health=250
clone.refill_on_stat_bonus=true
stable_cost=native_cost(clone)
for _=1,10 do tasks.monkey_clone_sync.callback() end
unchanged_cost(clone,stable_cost,"damaged clone polling")
near(clone.health,250,"stable polls preserve independent clone damage")
snapshots[0]={entindex=first.id,max_health=2000,engine_attack_min=60,
    engine_attack_max=80,attack_min=600,attack_max=800,attack_speed=1.4,
    strength=20,agility=40,intellect=60}
fixed(first,12)
local recalculations=clone.stat_bonus_calls
bus.emit(events.HERO_COMBAT_STATS_CHANGED,{player_id=0,snapshot=snapshots[0]})
assert(clone.stat_bonus_calls==recalculations+1,"one growth event must calculate native stats once")
interval(clone,12)
near(clone.maximum,2000,"growth updates the native health maximum immediately")
near(clone.health,500,"health growth preserves the damaged clone ratio")
near(clone.damage_min,60);near(clone.damage_max,80)
unchanged_cost(other,other_cost,"growth stays in the owning player")
stable_cost=native_cost(clone)
for _=1,10 do tasks.monkey_clone_sync.callback() end
unchanged_cost(clone,stable_cost,"unchanged polls after growth")
snapshots[0]={entindex=first.id,max_health=1000,engine_attack_min=30,
    engine_attack_max=40,attack_min=300,attack_max=400,attack_speed=1.4,
    strength=10,agility=20,intellect=30}
fixed(first,10)
recalculations=clone.stat_bonus_calls
bus.emit(events.HERO_COMBAT_STATS_CHANGED,{player_id=0,snapshot=snapshots[0]})
assert(clone.stat_bonus_calls==recalculations+1,"health decrease also uses one native recalculation")
interval(clone,10)
near(clone.maximum,1000);near(clone.health,250,"health decrease preserves the ratio")
clone.modifiers[HEALTH]=nil
tasks.monkey_clone_sync.callback()
assert(clone.modifiers[HEALTH],"polling must restore a missing health projection")
near(clone.health,250,"health projection restoration cannot heal")
clone.hull=32;clone.damage_min=1;clone.damage_max=2
tasks.monkey_clone_sync.callback()
near(clone.hull,0);near(clone.damage_min,30);near(clone.damage_max,40)
near(clone.health,250,"repairing external native values cannot heal")
clone.refill_on_stat_bonus=false
clone.health=500
refreshes=clone.rate_refreshes

fixed(first,5)
local reads=requests
bus.emit(events.HERO_COMBAT_STATS_CHANGED,{player_id=0,snapshot=snapshots[0]})
interval(clone,5);interval(other,3)
assert(clone.rate_refreshes==refreshes+1,"changing inherited APS must invalidate the native property cache")
assert(requests==reads,"immediate stat-change sync must use its supplied snapshot")
fixed(first,4)
tasks.monkey_clone_sync.callback()
interval(clone,4)
first.modifiers[DEBUG]=nil;first.runtime_aps=2.5
tasks.monkey_clone_sync.callback()
interval(clone,2.5)
clone.modifiers[RATE]=nil
tasks.monkey_clone_sync.callback()
interval(clone,2.5)
assert(clone.modifier_adds==additions+1,"polling must restore a missing fixed-rate modifier")

fixed(first,8)
bus.emit(events.HERO_COMBAT_STATS_CHANGED,{player_id=0,snapshot=snapshots[1]})
interval(clone,2.5)
reads=requests;reenter_snapshot=true
tasks.monkey_clone_sync.callback()
interval(clone,8)
assert(requests==reads+2,"nested snapshot publication must not recurse into another request")

-- Use the production clone synchronization and damage filter together, rather
-- than treating the selected-unit logical panel as proof of actual damage.
local damage_events=require("combat/combat_events")
local projection=require("combat/endless_stat_projection")
local filter=require("combat/damage_filter_service")
DOTA_DAMAGE_CATEGORY_ATTACK=1
DOTA_DAMAGE_CATEGORY_SPELL=0
DAMAGE_TYPE_PHYSICAL=1
DAMAGE_TYPE_PURE=4
EntIndexToHScript=function(index) return native_entities[index] end
local filtered,resolved={},{}
bus.subscribe(damage_events.DAMAGE_FILTERED,function(payload)
    filtered[#filtered+1]=payload
end)
bus.subscribe(damage_events.DAMAGE_RESOLVED,function(payload)
    resolved[#resolved+1]=payload
end)
filter.init({event_bus=bus,events=damage_events,
    repository={consume_pending=function() return nil end},
    config={global_post_bonus_pct=0,minimum_post_multiplier=0,
        boss_rules={enabled=false,default_damage_taken_multiplier=1}}})
local ordinary_target=unit(8)
local scaled_target=unit(9)
projection.prepare(scaled_target,{health=9e15,attack=10})
ordinary_target.health=1e8;ordinary_target.maximum=1e8
scaled_target.health=1e8;scaled_target.maximum=1e8
local damage_regression_results={}
local function relative(actual,expected,label)
    assert(type(actual)=="number" and math.abs(actual-expected)
        <=math.max(1e-7,math.abs(expected)*1e-12),
        (label or "damage") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function real_hit(target,native_damage,category,inflictor,expected)
    local keys={entindex_attacker_const=clone.id,entindex_victim_const=target.id,
        damage=native_damage,damagetype_const=DAMAGE_TYPE_PHYSICAL,
        damage_category_const=category,entindex_inflictor_const=inflictor}
    local before_filtered,before_resolved=#filtered,#resolved
    assert(filter._filter_for_test(filter,keys),"production damage filter rejected clone hit")
    assert(#filtered==before_filtered+1 and #resolved==before_resolved+1,
        "one attack must emit exactly one filtered/resolved pair")
    relative(resolved[#resolved].final_damage,expected,"logical resolved damage")
    relative(filtered[#filtered].final_damage,expected,"logical filtered damage")
    local expected_native=expected/(target.survival_endless_health_scale or 1)
    relative(keys.damage,expected_native,"native damage after target health scaling")
    -- Apply the filtered native amount to the target carrier and recover its
    -- logical HP loss. Large hits use the scaled target to avoid native overkill.
    target.health=1e8
    local before_health=target.health
    target:SetHealth(math.max(0,before_health-keys.damage))
    local logical_hp_loss=(before_health-target:GetHealth())
        *(target.survival_endless_health_scale or 1)
    -- Subtracting small native hits from 1e8 loses low mantissa bits; allow the
    -- equivalent of two Lua carrier subtraction ulps, not a percentage of the hit.
    local expected_hp_loss=math.min(expected,1e8*(target.survival_endless_health_scale or 1))
    assert(math.abs(logical_hp_loss-expected_hp_loss)<=math.max(
        1e-7,(target.survival_endless_health_scale or 1)*3e-8),
        "actual target HP loss differs from the logical clone hit")
    return keys.damage,logical_hp_loss
end
local function attack_snapshot(label,engine_min,engine_max,logical_min,logical_max,equipment_attack)
    local carrier=clone
    local old_health,old_maximum=clone.health,clone.maximum
    local old_rate=clone.modifiers[RATE]
    clone.survival_endless_health_scale=7.5
    clone.survival_endless_health=123456789
    local health_scale,logical_health=clone.survival_endless_health_scale,
        clone.survival_endless_health
    local snapshot={entindex=first.id,max_health=1000,
        engine_attack_min=engine_min,engine_attack_max=engine_max,
        engine_equipment_attack_bonus=equipment_attack,
        attack_min=logical_min,attack_max=logical_max,
        attack_speed=1.4,strength=10,agility=20,intellect=30,
        critical_chance_pct=100,critical_damage_pct=200}
    snapshots[0]=snapshot
    local before_requests=requests
    bus.emit(events.HERO_COMBAT_STATS_CHANGED,{player_id=0,snapshot=snapshot})
    assert(clone==carrier,"authoritative stat publication must update the existing live clone")
    assert(requests==before_requests,"snapshot event must not re-request combat stats")
    near(clone.health,old_health,"attack synchronization may not heal")
    near(clone.maximum,old_maximum,"attack synchronization may not replace native health")
    near(clone.survival_endless_health_scale,health_scale,"attack helper must preserve health scale")
    near(clone.survival_endless_health,logical_health,"attack helper must preserve logical health")
    assert(clone.modifiers[RATE]==old_rate,"attack synchronization must preserve fixed-rate modifier")
    interval(clone,8)
    interval(other,3)
    near(other.damage_min,30,"other player native minimum stays isolated")
    near(other.damage_max,40,"other player native maximum stays isolated")
    local inherited_min=(engine_min or logical_min)+(equipment_attack or 0)
    local inherited_max=(engine_max or logical_max)+(equipment_attack or 0)
    local expected_critical=(math.max(100,snapshot.critical_damage_pct or 200)
        +(tonumber(require("config/generated/monkey_king_exclusive_runtime")
            .by_id.monkey_king_exclusive.w_clone_critical_damage_bonus_pct) or 0))/100
    local scale=math.max(1,math.max(inherited_min,inherited_max)
        /math.max(1,math.floor(1e8/expected_critical)))
    near(tonumber(clone.survival_endless_attack_scale) or 1,scale,
        "logical/native attack conversion scale")
    local min_expected=math.floor(inherited_min/scale)
    local max_expected=math.floor(inherited_max/scale)
    near(clone.damage_min,min_expected,"bounded native attack minimum")
    near(clone.damage_max,max_expected,"bounded native attack maximum")
    assert(clone.damage_min<=1e8 and clone.damage_max<=1e8,
        "native attack must stay within the projection cap")
    local clone_snapshot=clone.modifiers.modifier_monkey_king_clone.snapshot
    near(clone_snapshot.attack_min,logical_min,"logical panel minimum stays authored")
    near(clone_snapshot.attack_max,logical_max,"logical panel maximum stays authored")
    -- The ordinary 30/40 carrier versus 300/400 logical fixture explicitly
    -- protects the existing engine_attack priority instead of redefining it.
    local min_damage=min_expected*scale
    local max_damage=max_expected*scale
    local critical_multiplier=clone_snapshot.critical_damage_pct/100
    assert(clone.damage_max*critical_multiplier<=1e8,
        "native critical input must stay within the projection cap")
    projection.prepare(scaled_target,{
        health=math.max(1e8,max_damage*critical_multiplier*100),attack=10})
    real_hit(ordinary_target,clone.damage_min,DOTA_DAMAGE_CATEGORY_ATTACK,nil,min_damage)
    real_hit(ordinary_target,clone.damage_max,DOTA_DAMAGE_CATEGORY_ATTACK,nil,max_damage)
    local scaled_native,scaled_loss=real_hit(scaled_target,clone.damage_max,
        DOTA_DAMAGE_CATEGORY_ATTACK,nil,max_damage)
    -- Critical damage is already present in the engine's submitted attack;
    -- restoring attack scale must multiply this amount only once.
    local crit_damage=clone.damage_max*critical_multiplier
    real_hit(ordinary_target,crit_damage,DOTA_DAMAGE_CATEGORY_ATTACK,nil,
        max_damage*critical_multiplier)
    real_hit(scaled_target,crit_damage,DOTA_DAMAGE_CATEGORY_ATTACK,nil,
        max_damage*critical_multiplier)
    real_hit(ordinary_target,clone.damage_max,nil,nil,max_damage)
    -- Spell/proc damage is expressed in authored values and must never receive
    -- the clone's base-attack scale, even for an attack-category inflictor.
    real_hit(ordinary_target,35,DOTA_DAMAGE_CATEGORY_SPELL,555,35)
    real_hit(ordinary_target,35,DOTA_DAMAGE_CATEGORY_ATTACK,555,35)
    real_hit(ordinary_target,35,DOTA_DAMAGE_CATEGORY_SPELL,nil,35)
    real_hit(ordinary_target,35,"0",nil,35)
    local spell_damage=math.min(1e9,scaled_target.survival_endless_health/100)
    real_hit(scaled_target,spell_damage,DOTA_DAMAGE_CATEGORY_SPELL,555,spell_damage)
    assert(clone.health==old_health and clone.survival_endless_health_scale==health_scale,
        "outgoing clone damage must never mutate the clone's own health")
    damage_regression_results[#damage_regression_results+1]={label=label,
        native_min=clone.damage_min,native_max=clone.damage_max,scale=scale,
        logical_min_damage=min_damage,logical_max_damage=max_damage,
        critical_multiplier=critical_multiplier,scaled_native_damage=scaled_native,
        scaled_logical_hp_loss=scaled_loss}
end
attack_snapshot("ordinary_engine_priority",30,40,300,400)
attack_snapshot("logical_fallback",nil,nil,60,80)
attack_snapshot("addattack_1e11",5e10,1e11,5e10,1e11)
attack_snapshot("addattack_9e15",4.5e15,9e15,4.5e15,9e15)
attack_snapshot("decrease_to_ordinary",30,40,300,400)
assert(clone.survival_endless_attack_scale==1,
    "decreasing attack must clear the previous large-attack conversion scale")
-- Native writes floor fractional low attacks instead of relying on an implicit
-- C++ integer conversion; ordinary logical UI metadata retains its precision.
attack_snapshot("fractional_native_floor",30.75,40.5,30.75,40.5)
attack_snapshot("equipment_flat_inheritance",30,40,300,400,25)
attack_snapshot("debug_override_no_double_equipment",1e11,1e11,1e11,1e11,0)
attack_snapshot("equipment_after_debug_cleared",30,40,300,400,25)
attack_snapshot("final_restore",30,40,300,400,0)

clone.dead=true
bus.emit(events.ENGINE_ENTITY_KILLED,{victim=clone})
fixed(first,6)
tasks["monkey_clone_respawn:0"].callback()
local respawned=created[#created]
assert(respawned~=clone)
interval(respawned,6)
first.removed=true;heroes[0]=nil
bus.emit(events.HERO_REMOVED,{player_id=0,unit=first,entindex=first.id})
assert(respawned.removed and not tasks["monkey_growth:0"])
interval(other,3)
local replacement,replacement_clone=summon(0,7)
bus.emit(events.HERO_COMBAT_STATS_CHANGED,{player_id=0,snapshot={entindex=first.id,attack_speed=99}})
interval(replacement_clone,7)
assert(replacement~=first)
print=original_print
print("MONKEY_CLONE_SYNC_COST_PASS: stable healthy/damaged polls produce zero native writes; immediate health/attack growth and decrease use one stat recalculation; HP ratio and missing/external native projection repairs")
print("MONKEY_CLONE_ATTACK_RATE_PASS: fixed-rate modifier, preserved natural BAT and animation-aware fixture, addspeed changes/removal, spawn/respawn/event/poll sync, stable refresh, identity isolation and deletion")
local report={}
for _,sample in ipairs(damage_regression_results) do
    report[#report+1]=string.format(
        '{"label":"%s","native_min":%.17g,"native_max":%.17g,"scale":%.17g,'
            ..'"logical_min_damage":%.17g,"logical_max_damage":%.17g,'
            ..'"critical_multiplier":%.17g,"scaled_native_damage":%.17g,'
            ..'"scaled_logical_hp_loss":%.17g}',
        sample.label,sample.native_min,sample.native_max,sample.scale,
        sample.logical_min_damage,sample.logical_max_damage,
        sample.critical_multiplier,sample.scaled_native_damage,
        sample.scaled_logical_hp_loss)
end
print("MONKEY_CLONE_DAMAGE_REGRESSION_JSON:{\"passed\":true,\"cases\":["
    ..table.concat(report,",").."]}")
print("MONKEY_CLONE_DAMAGE_PASS: real clone sync, native int32 guard, engine/fallback inheritance, addattack large values/decrease, critical/ability separation, real damage filter and scaled target HP loss")
