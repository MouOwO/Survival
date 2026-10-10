-- Offline integration of actual formal/challenge/encounter spawn closures.
-- Run through test_wave_native_attack_cap.py; no Dota process is needed.
package.path = "scripts/vscripts/?.lua;" .. package.path
DOTA_UNIT_CAP_MOVE_NONE, DOTA_UNIT_CAP_MOVE_GROUND, DOTA_UNIT_CAP_MOVE_FLY = 0, 1, 2
DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS, DOTA_TEAM_NEUTRALS = 2, 3, 4
DOTA_UNIT_CAP_MELEE_ATTACK, DOTA_UNIT_CAP_RANGED_ATTACK = 1, 2
local no_op = function() end
local created, appearances = {}, {}
local marker = {IsNull=function() return false end,
    GetAbsOrigin=function() return {x=64,y=128,z=32} end,
    GetForwardVector=function() return {x=0,y=1,z=0} end,
    GetName=function() return "test_spawn" end}
-- Native GetAbilityKeyValues captured in Tools from the built-in warp.
local warp_kv = {["AbilityBehavior"]="DOTA_ABILITY_BEHAVIOR_UNIT_TARGET | DOTA_ABILITY_BEHAVIOR_CHANNELLED | DOTA_ABILITY_BEHAVIOR_DONT_RESUME_ATTACK | DOTA_ABILITY_BEHAVIOR_DONT_CANCEL_CHANNEL | DOTA_ABILITY_BEHAVIOR_HIDDEN | DOTA_ABILITY_BEHAVIOR_IGNORE_SILENCE | DOTA_ABILITY_BEHAVIOR_ROOT_DISABLES | DOTA_ABILITY_BEHAVIOR_NOT_LEARNABLE",["AbilityCastAnimation"]="ACT_DOTA_GENERIC_CHANNEL_1",["AbilityCastPoint"]="0",["AbilityCastRange"]="200",["AbilityCastRangeBuffer"]=250,["AbilityChannelTime"]="4.000000",["AbilityChargeRestoreTime"]="0",["AbilityCharges"]="0",["AbilityCooldown"]="0",["AbilityDamage"]="0 0 0 0",["AbilityDuration"]="0",["AbilityManaCost"]="30",["AbilityModifierSupportBonus"]=0,["AbilityModifierSupportValue"]=1,["AbilityOvershootCastRange"]=0,["AbilitySharedCooldown"]="",["AbilityType"]="ABILITY_TYPE_BASIC",["AbilityUnitTargetFlags"]="DOTA_UNIT_TARGET_FLAG_INVULNERABLE",["AbilityUnitTargetTeam"]="DOTA_UNIT_TARGET_TEAM_ENEMY",["AbilityValues"]={["animation_rate"]="0.800000",["stop_distance"]="500"},["FightRecapLevel"]=0,["ID"]=8873,["IsCastableWhileHidden"]=1,["ItemCombinable"]=1,["ItemCost"]=0,["ItemDeclaresPurchase"]=0,["ItemDisassemblable"]=0,["ItemDroppable"]=1,["ItemInitialCharges"]=0,["ItemIsNeutralDrop"]=0,["ItemKillable"]=1,["ItemPermanent"]=1,["ItemPurchasable"]=1,["ItemRecipe"]=0,["ItemRequiresCharges"]=0,["ItemSellable"]=1,["ItemShareability"]="ITEM_NOT_SHAREABLE",["ItemStackable"]=0,["MaxLevel"]=1,["OnCastbar"]=1,["OnLearnbar"]=1}
local function native_warp()
    return {IsNull=function() return false end,
        GetAbilityName=function() return "twin_gate_portal_warp" end,
        GetClassname=function() return "twin_gate_portal_warp" end,
        GetAbilityType=function() return 0 end,IsPassive=function() return false end,
        IsHidden=function() return true end,GetLevel=function() return 1 end,
        GetIntrinsicModifierName=function() end,GetAbilityKeyValues=function() return warp_kv end}
end
local function unit(native_name)
    local value = {index=#created+1,hull=32,modifiers={},native_name=native_name}
    function value:IsNull() return false end
    function value:GetUnitName() return self.native_name end
    function value:GetClassname() return "npc_dota_creature" end
    function value:IsRealHero() return false end
    function value:GetTeamNumber() return DOTA_TEAM_BADGUYS end
    local injected_warp=native_warp()
    function value:GetAbilityCount() return 1 end
    function value:GetAbilityByIndex(slot) if slot==0 then return injected_warp end end
    function value:IsAlive() return true end
    function value:entindex() return self.index end
    function value:GetAbsOrigin() return marker:GetAbsOrigin() end
    function value:GetHullRadius() return self.hull end
    function value:SetHullRadius(radius) self.hull=radius end
    function value:HasModifier(name) return self.modifiers[name]~=nil end
    function value:AddNewModifier(_,_,name,params) self.modifiers[name]=params end
    function value:FindAbilityByName() end
    for _,name in ipairs({"SetBaseMaxHealth","SetMaxHealth","SetHealth",
        "SetBaseDamageMin","SetBaseDamageMax","SetPhysicalArmorBaseValue",
        "SetBaseMoveSpeed","SetBaseAttackTime","Script_SetAttackRange",
        "SetAttackCapability","SetAcquisitionRange","SetForwardVector",
        "AddAbility","SetModel","SetOriginalModel","SetModelScale",
        "SetMoveCapability","SetRangedProjectileName","SetProjectileSpeed"}) do value[name]=no_op end
    created[#created+1]=value
    return value
end
local archetype = {native_attack_speed_policy="bat_only_v1",unit_name="npc_test",model_path="test.vmdl",movement_type="ground",
    model_scale=1,health=1000,attack=10,attack_speed=1,attack_type="melee",enabled=true}
GameRules={GetGameModeEntity=function() return {GetMaximumAttackSpeed=function() return 7 end} end}
LoadKeyValues=function(path)
    if path=="scripts/npc/npc_abilities_custom.txt" then return {} end
    assert(path=="scripts/npc/npc_units_custom.txt")
    return {npc_test={BaseClass="npc_dota_creature",ConsideredHero="0",HasInventory="0"}}
end
local events=require("core/events")
local deps={
    ["core/events"]=events,
    ["systems/wave_native_attack_cap"]=dofile(arg[1].."/wave_native_attack_cap.lua"),
    ["core/scheduler"]={cancel=no_op},
    ["core/team_alignment"]={enforce=no_op},
    ["systems/player_context_service"]={is_defeated=function() return false end},
    ["systems/monster_corpse_lifecycle_service"]={track=no_op},
    ["config/generated/monster_archetypes"]={by_id={test=archetype}},
    ["config/generated/monster_encounters"]={by_id={encounter_rebirth_1={encounter_id="encounter_rebirth_1",
        spawn_point_id="test",archetype_id="test",encounter_type="rebirth_boss"}}},
    ["config/generated/monster_spawn_points"]={by_id={test={spawn_point_id="test",hammer_target_name="test_spawn"}}},
    ["config/generated/archive_challenge_rules"]={by_id={default={}}},
    ["config/challenge_runtime_rules"]={apply=function(value) return value end},
    ["config/challenge_combat_profile_config"]={resolve=function() end},
    ["config/monster_visual_config"]={resolve=function() end},
    ["systems/monster_visual_service"]={apply=no_op},
    ["systems/rebirth_scene_display_service"]={hide=no_op},
    ["systems/challenge_monster_visual_service"]={apply=no_op},
    ["systems/challenge_session_service"]={handles=function() return false end},
    ["systems/monster_hero_visual_service"]={apply=function(target,_,options)
        appearances[target]=options
        return true
    end},
    ["systems/player_room_locations"]={resolve=function() return {home_target_name="test_spawn"} end,
        marker_name=function(name) return name end},
    ["core/event_bus"]={emit=no_op,request=function(name)
        if name==events.WAVE_STATE_GET_REQUEST then return {ok=true,difficulty_id="N1"} end
    end},
}
for _,name in ipairs({"systems/monster_navigation_policy","systems/monster_hull_scale",
    "systems/wave_monster_collision","systems/wave_spawn_sequence","systems/wave_population_limit",
    "config/generated/player_slots","config/global_rules","config/difficulty_config"}) do
    deps[name]=require(name)
end
local env=setmetatable({Vector=function(x,y,z) return {x=x,y=y,z=z} end,
    Entities={FindByName=function() return marker end},
    GridNav={IsBlocked=function() return false end,IsTraversable=function() return true end},
    PlayerResource={IsValidPlayerID=function() return true end,GetSelectedHeroEntity=function() end},
    GetGroundHeight=function() return 0 end,CreateUnitByName=unit,FindClearSpaceForUnit=no_op,
    require=function(name) return deps[name] or {rows={},by_id={}} end}, {__index=_G})
local function load_service(name)
    local path="scripts/vscripts/systems/"..name..".lua"
    if arg[1] and name=="wave_system" then path=arg[1].."/"..name..".lua" end
    local chunk=assert(loadfile(path));setfenv(chunk,env);return chunk()
end
local function find_function(module,wanted)
    local seen={}
    local function visit(fn)
        if type(fn)~="function" or seen[fn] then return end
        seen[fn]=true
        for index=1,math.huge do
            local name,value=debug.getupvalue(fn,index)
            if not name then break end
            if name==wanted then return value end
            if type(value)=="function" then local found=visit(value);if found then return found end end
        end
    end
    for _,fn in pairs(module) do local found=visit(fn);if found then return found end end
    error("missing spawn closure: "..wanted)
end
local function upvalue(fn,wanted,value)
    for index=1,math.huge do
        local name=debug.getupvalue(fn,index);if not name then break end
        if name==wanted then debug.setupvalue(fn,index,value);return end
    end
    error("missing fixture state: "..wanted)
end
deps["systems/wave_spawn_routing"]=load_service("wave_spawn_routing")
local wave=load_service("wave_system")
local spawn=find_function(wave,"spawn_one")
upvalue(spawn,"monster_spawn_marker",marker)
upvalue(spawn,"state",{pending=244,spawned=0,alive=0,alive_limit=math.huge,overflow_active=false})
for index=1,244 do
    spawn({archetype_id="test",member_role="normal",health=1000,attack=10,attack_speed=1},0,15,index)
end
upvalue(wave.spawn_challenge_monster,"wave_channels",{[0]={marker=marker}})
assert(wave.spawn_challenge_monster({health=200,attack=2},archetype,0))
local session=load_service("challenge_session_service")
assert(find_function(session,"spawn_member")({player_id=0,
    challenge={challenge_id="test_challenge"},encounter_id="test_encounter",encounter={},
    monsters={},monster_count=0},{archetype_id="test",location_id="test_room",
        member_id="test_member",spawn_target_name="test_spawn"}))
local encounter=load_service("monster_spawn_service")
local result=find_function(encounter,"start_encounter")({encounter_id="encounter_rebirth_1",player_id=0})
assert(result.ok,result.error)
assert(#created==247,"all four production paths must create a real fixture unit")
for index,target in ipairs(created) do
    assert(appearances[target] and appearances[target].fresh_unit==true,
        "new NPC appearance missed fresh fast path at index "..index)
end
assert(appearances[created[1]].formal_wave and appearances[created[1]].wave_number==15)
assert(appearances[created[245]].challenge and appearances[created[246]].challenge)
assert(appearances[created[247]].encounter)
for index=1,244 do
    assert(not created[index]:HasModifier("modifier_debug_attack_cap"),"audited wave cap omitted")
    assert(created[index].survival_wave_native_attack_cap==true,"explicit formal-spawn decision recorded")
end
assert(created[245]:HasModifier("modifier_debug_attack_cap"),"building challenge keeps cap despite opted-in archetype")
assert(created[247]:HasModifier("modifier_debug_attack_cap"),"encounter keeps cap despite opted-in archetype")
print("MONSTER_APPEARANCE_PATHS_PASS 244 wave spawns plus all three challenge/encounter paths, checked outside pcall")

local row={archetype_id="test",member_role="normal",health=1000,attack=10,attack_speed=1}
local function spawn_next()
    spawn(row,0,15,#created+1)
    return created[#created]
end
archetype.native_attack_speed_policy=nil
deps["systems/monster_hero_visual_service"].apply=function(target)
    target.test_cap_present_before_appearance=target:HasModifier("modifier_debug_attack_cap")
end
local unknown=spawn_next()
assert(unknown:HasModifier("modifier_debug_attack_cap"),"unknown formal archetype retains cap")
assert(unknown.test_cap_present_before_appearance,"unknown archetype retains original pre-appearance installation point")
archetype.native_attack_speed_policy="bat_only_v1"
archetype.passive_skill_ids={"native_bloodlust"}
local passive=spawn_next()
assert(passive:HasModifier("modifier_debug_attack_cap"),"configured native passive retains cap")
assert(passive.test_cap_present_before_appearance,"native passive retains original pre-appearance cap")
archetype.passive_skill_ids=nil
deps["systems/monster_hero_visual_service"].apply=function(target,_,options)
    local original=target.GetAbilityByIndex
    target.GetAbilityCount=function() return 24 end
    target.GetAbilityByIndex=function(self,slot)
        if slot==23 then return {IsNull=function() return false end} end
        return original(self,slot)
    end
    return true
end
assert(spawn_next():HasModifier("modifier_debug_attack_cap"),"visual-added skill checked before AI")
deps["systems/monster_hero_visual_service"].apply=function(target)
    target.modifiers.modifier_debug_attack_cap={existing=true}
    return true
end
local existing=spawn_next()
assert(existing.modifiers.modifier_debug_attack_cap.existing,"existing cap never overwritten/removed")
assert(existing.survival_wave_native_attack_cap==false,"existing cap decision remains conservative")
print("WAVE_NATIVE_ATTACK_CAP_SPAWN_PASS real formal/challenge/encounter spawn, passive/appearance/existing-cap fallback")
