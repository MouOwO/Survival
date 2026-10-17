-- Reproduces the current native bool-arity contract at entity boundaries.
-- Uses actual HERO_SUMMONED/recalculation and selected-unit UI routes; does
-- not claim the undocumented bool's semantics or change raw getter units.
package.path = "scripts/vscripts/?.lua;" .. package.path
local reads, arity_errors, native_failures = {}, {}, {}
local function strict_getter(name, field)
    return function(self,...)
        reads[name]=(reads[name] or 0)+1
        if select("#",...)~=1 or type((...))~="boolean" then
            arity_errors[name]=(arity_errors[name] or 0)+1
            error(name.." called with 1 arguments - expected 2")
        end
        assert((...)==false,"all audited callers explicitly select the existing false mode")
        if self.fail and self.fail[name] then
            native_failures[name]=(native_failures[name] or 0)+1
            error("native reader failed")
        end
        return self[field]
    end
end
for _,name in ipairs({"systems/effect_handler_registry","systems/equipment_effect_service",
    "systems/equipment_stat_aggregation_service","systems/triggered_proc_service",
    "systems/building_system","ui/weapon_synthesis_snapshot_service",
    "systems/hero_summon_projection","systems/building_batch_upgrade_service",
    "systems/gold_mine_batch_upgrade_service"}) do package.loaded[name]={init=function() end} end
package.loaded["systems/startup_loading_service"]={is_player_ready=function() return true end}
package.loaded["systems/player_context_service"]={is_defeated=function() return false end}
package.loaded["systems/technology_stat_manager"]={get=function() return {final={hero={}}} end}
package.loaded["config/global_rules"]={number=function(_,fallback) return fallback end,
    hero_strength_health_per_point=0,hero_intellect_attack_per_point=0}
local definitions={
    configured={hero_id="configured",unit_name="npc_cadence_configured",attack_speed=2,
        base_damage_min=112,base_damage_max=120,base_health=1000,
        base_strength=10,base_agility=20,base_intellect=30},
    native_only={hero_id="native_only",unit_name="npc_cadence_native_only",
        base_damage_min=112,base_damage_max=120,base_health=1000,
        base_strength=10,base_agility=20,base_intellect=30},
}
package.loaded["config/generated/hero_definitions"]={by_id=definitions}
package.loaded["systems/hero_stat_adapter"]={
    configured_max_health=function(definition) return definition.base_health end,
    apply_configured_health=function(unit) return unit.maximum,0,unit.maximum end,
    reapply_projectile_stats=function() end,
}
local now, entities, listeners, packets, players = 0, {}, {}, {}, {[0]={},[1]={},[2]={},[3]={}}
GameRules={GetGameTime=function() return now end}
PlayerResource={IsValidPlayerID=function(_,id) return players[id]~=nil end,
    GetPlayer=function(_,id) return players[id] end,GetTeam=function() return 2 end}
CustomGameEventManager={RegisterListener=function(_,name,fn) listeners[name]=fn end,
    Send_ServerToPlayer=function(_,player,name,data) packets[#packets+1]={player=player,name=name,data=data} end}
EntIndexToHScript=function(index) return entities[index] end
local function unit(index,player_id,bat)
    local u={index=index,player_id=player_id,health=500,maximum=1000,bat=bat,
        factor=1,aps=1/bat,seconds=bat,modifiers={},damage_min=112,damage_max=120}
    function u:IsNull() return false end
    function u:IsAlive() return true end
    function u:entindex() return self.index end
    function u:GetPlayerOwnerID() return self.player_id end
    function u:GetTeamNumber() return 2 end
    function u:GetLevel() return 1 end
    function u:GetUnitName() return self.unit_name or "npc_cadence_generic" end
    function u:GetHealth() return self.health end
    function u:SetHealth(value) self.health=value end
    function u:GetMaxHealth() return self.maximum end
    function u:GetMana() return 0 end
    function u:GetMaxMana() return 0 end
    function u:GetStrength() return 10 end
    function u:GetAgility() return 20 end
    function u:GetIntellect() return 30 end
    function u:GetPhysicalArmorValue() return 0 end
    function u:GetPhysicalArmorBaseValue() return 0 end
    function u:GetBaseDamageMin() return self.damage_min end
    function u:GetBaseDamageMax() return self.damage_max end
    function u:GetDamageMin() return self.damage_min end
    function u:GetDamageMax() return self.damage_max end
    function u:SetBaseDamageMin(value) self.damage_min=value end
    function u:SetBaseDamageMax(value) self.damage_max=value end
    function u:SetBaseAttackTime(value) self.bat=value;self.aps=self.factor/value;self.seconds=value/self.factor end
    function u:CalculateStatBonus() end
    function u:FindModifierByName(name) return self.modifiers[name] end
    function u:HasModifier(name) return self.modifiers[name]~=nil end
    function u:FindAllModifiersByName() return {} end
    function u:AddNewModifier(_,_,name,params)
        local mod={interval=params and params.attack_interval}
        function mod:GetModifierFixedAttackRate() return self.interval end
        function mod:ForceRefresh() end
        self.modifiers[name]=mod;return mod
    end
    u.GetBaseAttackTime=strict_getter("GetBaseAttackTime","bat")
    u.GetAttackSpeed=strict_getter("GetAttackSpeed","factor")
    u.GetSecondsPerAttack=strict_getter("GetSecondsPerAttack","seconds")
    u.GetAttacksPerSecond=strict_getter("GetAttacksPerSecond","aps")
    entities[index]=u
    return u
end
package.loaded["core/modifier_registry"]={ensure=function(u,name,params)
    return u:FindModifierByName(name) or u:AddNewModifier(u,nil,name,params or {})
end}
local bus,events=require("core/event_bus"),require("core/events")
local service=require("systems/hero_combat_stat_service")
local print_original=print
print=function(message)
    if tostring(message):find("%[EventBus%] handler error") then error(message) end
end
service.init()
local function near(a,b,label)
    assert(type(a)=="number" and math.abs(a-b)<1e-8,(label or "number")..": "..tostring(a).." != "..b)
end
local function stats(id)
    local r=bus.request(events.HERO_COMBAT_STATS_GET_REQUEST,{player_id=id})
    assert(r and r.ok,"real public stat request failed");return r.snapshot
end
local first,second=unit(101,0,1.8),unit(102,1,.8)
first.survival_hero_id,first.unit_name="configured",definitions.configured.unit_name
second.survival_hero_id,second.unit_name="native_only",definitions.native_only.unit_name
bus.emit(events.HERO_SUMMONED,{player_id=0,hero_id="configured",unit=first})
bus.emit(events.HERO_SUMMONED,{player_id=1,hero_id="native_only",unit=second})
near(stats(0).attack_speed,2,"configured source remains authoritative")
near(stats(1).attack_speed,1/.8,"missing config uses the actual native BAT, not silent default 2")
near(stats(1).attack_cadence.base_interval,.8)
near(stats(0).attack_speed_stat,1,"raw native factor is not converted to 100 in this patch")
near(stats(1).attack_speed_stat,1)
assert((reads.GetBaseAttackTime or 0)==2,"real initialization captures each source BAT once")
local before_as_reads=reads.GetAttackSpeed
for _=1,25 do
    bus.emit(events.TECHNOLOGY_STATS_CHANGED,{player_id=0})
    near(stats(0).attack_speed_stat,1)
end
assert(reads.GetAttackSpeed==before_as_reads+25,"real recalculation consistently reaches correct native getter")
first.modifiers.modifier_debug_fixed_attack_rate={GetModifierFixedAttackRate=function() return .1 end}
near(stats(0).attack_speed,10,"fixed addspeed interval still owns authoritative cadence")
near(stats(1).attack_speed,1/.8,"another player remains isolated")
local stable_as_reads=reads.GetAttackSpeed
for _=1,25 do near(stats(0).attack_speed,10) end
assert(reads.GetAttackSpeed==stable_as_reads,"stable reads do not repeatedly recalculate")
first.fail={GetAttackSpeed=true}
bus.emit(events.TECHNOLOGY_STATS_CHANGED,{player_id=0})
near(stats(0).attack_speed_stat,100,"existing true native failure fallback remains exactly unchanged")
first.fail=nil
bus.emit(events.TECHNOLOGY_STATS_CHANGED,{player_id=0})
near(stats(0).attack_speed_stat,1)
local unreadable=unit(103,2,.6);unreadable.fail={GetBaseAttackTime=true}
bus.emit(events.HERO_SUMMONED,{player_id=2,hero_id="native_only",unit=unreadable})
near(stats(2).attack_cadence.base_interval,2,"existing failed BAT fallback remains 2")
local unavailable=unit(104,3,.6);unavailable.GetBaseAttackTime=nil
bus.emit(events.HERO_SUMMONED,{player_id=3,hero_id="native_only",unit=unavailable})
near(stats(3).attack_cadence.base_interval,2,"missing legacy getter fallback remains 2")
assert((arity_errors.GetAttackSpeed or 0)==0 and (arity_errors.GetBaseAttackTime or 0)==0,
    "pcall must not silently swallow native arity exceptions")

local router=require("ui/ui_request_router");router.init()
local function select(index,id)
    local before=#packets
    listeners.ui_selected_unit_stats_request(nil,{PlayerID=id or 0,entindex=index})
    assert(#packets==before+1,"real selected UI request must deliver one packet")
    local packet=packets[#packets]
    assert(packet.name=="ui_selected_unit_stats_snapshot" and packet.data.success==1)
    return packet.data
end
local generic=unit(201,0,.4);generic.factor=2.5;generic.aps=6.25;generic.seconds=.16
local normal=select(201)
near(normal.attack_speed,6.25,"normal current native APS")
near(normal.attack_speed_stat,2.5,"raw GetAttackSpeed diagnostic unchanged")
near(normal.attack_cadence.base_interval,.4)
near(normal.attack_cadence.reduced_interval,.4)
near(normal.attack_cadence.percentage,250,"pre-existing separate percentage projection unchanged")
generic.GetAttacksPerSecond=nil
near(select(201).attack_speed,6.25,"legacy APS missing falls back to strict SecondsPerAttack(false)")
generic.GetSecondsPerAttack=nil
near(select(201).attack_speed,2.5,"legacy interval missing retains original BAT-only fallback algorithm")
generic.GetBaseAttackTime=nil
near(select(201).attack_speed,.5,"legacy missing BAT fallback remains 2")
generic.GetBaseAttackTime=strict_getter("GetBaseAttackTime","bat")
generic.GetSecondsPerAttack=strict_getter("GetSecondsPerAttack","seconds")
generic.GetAttacksPerSecond=strict_getter("GetAttacksPerSecond","aps")
generic.fail={GetAttacksPerSecond=true}
near(select(201).attack_speed,6.25,"genuine APS read failure follows existing interval fallback")
generic.fail={GetAttackSpeed=true}
local failure=select(201)
near(failure.attack_speed_stat,100)
near(failure.attack_cadence.percentage,100)
generic.fail=nil
local hero_selected=select(101)
near(hero_selected.attack_speed,10,"main hero selected snapshot remains fixed-rate authoritative")

-- Real v3 admission/release reads diagnostic BAT only at the two endpoints.
-- Current native bool arity must not silently erase those cadence samples.
local mode={}
IsServer=function() return true end;IsInToolsMode=function() return true end
GameRules.GetGameModeEntity=function() return mode end
DOTA_TEAM_BADGUYS,DOTA_UNIT_CAP_RANGED_ATTACK,MODIFIER_STATE_ROOTED=3,2,3
package.loaded["core/team_alignment"]={are_enemies=function(a,b) return a:GetTeamNumber()~=b:GetTeamNumber() end}
local v3=require("systems/enemy_ranged_stationary")
assert(v3.set_probe_enabled(true))
local shooter,wall=unit(301,-1,.71428573131561),unit(302,0,1)
shooter.survival_is_wave_monster,shooter.survival_wave_movement_type=true,"ground"
function shooter:GetTeamNumber() return 3 end
function shooter:GetClassname() return "npc_dota_creature" end
function shooter:GetAttackCapability() return 2 end
function shooter:GetAbsOrigin() return {x=-735,y=0,z=0} end
function wall:GetAbsOrigin() return {x=0,y=0,z=0} end
function shooter:Script_GetAttackRange() return 600 end
function shooter:GetHullRadius() return 32 end
function wall:GetHullRadius() return 128 end
function shooter:GetForceAttackTarget() return wall end
function shooter:GetAttackTarget() return wall end
function shooter:CanEntityBeSeenByMyTeam() return true end
local ai={contact_mode=0,wall_entindex=wall:entindex(),goal_wall=wall,ai_state="chase",
    GetParent=function() return shooter end,SetContactMode=function(self,value) self.contact_mode=value end}
function shooter:FindAllModifiers() return {ai} end
function shooter:IsRooted() return ai.contact_mode==6 end
v3.observe(ai,shooter,wall,"fired",{record=12001})
now=.3;v3.observe(ai,shooter,wall,"landed",{record=12001})
assert(ai.ranged_stationary_hold)
near(v3.snapshot().bat_samples[1].bat_before,.71428573131561)
v3.release(ai,shooter,"released")
near(v3.snapshot().bat_samples[1].bat_after,.71428573131561)
assert(ai.contact_mode==0 and not ai.ranged_stationary_hold)
assert(v3.set_probe_enabled(false))
for _,name in ipairs({"GetBaseAttackTime","GetAttackSpeed","GetSecondsPerAttack","GetAttacksPerSecond"}) do
    assert((reads[name] or 0)>0,"strict getter not exercised: "..name)
    assert((arity_errors[name] or 0)==0,"native signature silently failed: "..name)
end
print=print_original
print("PASS native cadence bool-arity: actual hero summon/recalc/stable-read/fixed-rate and player isolation; native BAT config fallback; real selected UI all four getters plus missing/error fallbacks; raw factor versus existing percent kept distinct; real v3 entry/exit BAT samples; implicit arity failures=0")
