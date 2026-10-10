local stage = assert(arg[1], "source root required")
local fixture = assert(arg[2], "temporary real-NPC KV fixture required")
local root = assert(arg[3], "repository root required")
package.path = stage .. "/scripts/vscripts/?.lua;" .. root .. "/scripts/vscripts/?.lua;" .. package.path
local path = stage .. "/scripts/vscripts/systems/wave_native_attack_cap.lua"
local archetypes = dofile(stage .. "/scripts/vscripts/config/generated/monster_archetypes.lua")
local waves = require("config/generated/wave_definitions")
local original_kv = dofile(fixture)
local assertions, loads, reads = 0, 0, 0
local function check(value, message) assertions=assertions+1;assert(value,message) end
local function copy(value)
    if type(value)~="table" then return value end
    local result={};for key,item in pairs(value) do result[key]=copy(item) end;return result
end
local kv, maximum, custom_abilities, custom_loads = original_kv, 7, {}, 0
DOTA_TEAM_BADGUYS = 3
GameRules={GetGameModeEntity=function() return {GetMaximumAttackSpeed=function() return maximum end} end}
LoadKeyValues=function(path)
    if path=="scripts/npc/npc_abilities_custom.txt" then custom_loads=custom_loads+1;return custom_abilities end
    loads=loads+1;assert(path=="scripts/npc/npc_units_custom.txt");return kv
end
local function forbidden() error("unexpected world scan, timer, current-AS read, or mutation") end
Entities, Timers=setmetatable({}, {__index=forbidden}),setmetatable({}, {__index=forbidden})
local function unit(name,count)
    return {slots_read=0, IsNull=function() return false end,
        GetUnitName=function() return name end, GetClassname=function() return "npc_dota_creature" end,
        IsRealHero=function() return false end, GetTeamNumber=function() return 3 end,
        HasModifier=function() return false end, GetAbilityCount=function() return count or 24 end,
        GetAbilityByIndex=function(self) self.slots_read=self.slots_read+1;return nil end,
        GetAttackSpeed=forbidden,GetDisplayAttackSpeed=forbidden,SetBaseAttackTime=forbidden,
        AddNewModifier=forbidden,RemoveModifierByName=forbidden}
end
local policy=dofile(path)
local seen,n1_wave15={},0
for _,row in ipairs(waves.rows) do
    local definition=assert(archetypes.by_id[row.archetype_id]);local native=unit(definition.unit_name)
    check(policy.can_omit(native,definition,true),row.wave_id)
    check(native.slots_read==24,"empty engine slots still inspected")
    seen[row.archetype_id]=true
    if tostring(row.difficulty_id):lower()=="n1" and row.wave_number==15 then n1_wave15=n1_wave15+row.monster_count end
end
local unique=0;for _ in pairs(seen) do unique=unique+1 end
check(#waves.rows==873 and unique==44 and n1_wave15==61,"real roster contract changed")
check(loads==1,"KV parsed once for all 873 births")
for _,definition in ipairs(archetypes.rows) do
    if not seen[definition.archetype_id] then
        check(not policy.can_omit(unit(definition.unit_name),definition,true),"unknown archetypes default to cap")
    end
end
local definition=archetypes.by_id.dwarf_white_rifle
local name=definition.unit_name
local function rejected_definition(edit,label)
    local value=copy(definition);edit(value)
    check(not policy.can_omit(unit(name),value,true),label)
end
for _,value in ipairs({false,1,"true"}) do check(not policy.can_omit(unit(name),definition,value),"explicit formal birth only") end
check(not policy.can_omit(unit(name),definition),"no implicit formal birth")
check(not policy.can_omit(unit(name),nil,true),"unknown definition")
rejected_definition(function(d) d.native_attack_speed_policy=nil end,"new archetype defaults safe")
rejected_definition(function(d) d.native_attack_speed_policy="future_policy" end,"unknown policy defaults safe")
rejected_definition(function(d) d.enabled=false end,"disabled archetype")
rejected_definition(function(d) d.unit_name="wrong_name" end,"unit identity mismatch")
rejected_definition(function(d) d.passive_skill_ids={"native_buff"} end,"added passive")
rejected_definition(function(d) d.passive_skill_ids="" end,"malformed passive metadata")
for key,value in pairs({BaseClass="npc_dota_hero",HasInventory="1",ConsideredHero="1",Ability32="future_skill",AttackSpeed="100",BaseAttackSpeed="100"}) do
    kv=copy(original_kv);kv[name][key]=value
    check(not dofile(path).can_omit(unit(name),definition,true),"unsafe KV "..key)
end
for _,key in ipairs({"BaseClass","ConsideredHero","HasInventory"}) do
    kv=copy(original_kv);kv[name][key]=nil
    check(not dofile(path).can_omit(unit(name),definition,true),"unknown KV "..key)
end
for _,value in ipairs({false,"unknown"}) do
    kv=value;check(not dofile(path).can_omit(unit(name),definition,true),"missing KV safely retains cap")
end
kv={DOTAUnits=original_kv}
check(dofile(path).can_omit(unit(name),definition,true),"wrapped KV supported")
kv=original_kv
for _,value in ipairs({6,0/0,math.huge,"7",false}) do
    maximum=value;check(not policy.can_omit(unit(name),definition,true),"native cap metadata invalid")
end
maximum=7
for method,value in pairs({GetUnitName="wrong",GetClassname="npc_dota_hero",IsRealHero=true,GetTeamNumber=2,IsNull=true,HasModifier=true}) do
    local native=unit(name);native[method]=function() return value end
    check(not policy.can_omit(native,definition,true),"identity/existing modifier "..method)
end
for _,method in ipairs({"GetUnitName","GetClassname","IsRealHero","GetTeamNumber","IsNull","HasModifier","GetAbilityCount","GetAbilityByIndex"}) do
    local native=unit(name);native[method]=nil
    check(not policy.can_omit(native,definition,true),"missing native API "..method)
    native[method]=function() error("native unavailable") end
    check(not policy.can_omit(native,definition,true),"throwing native API "..method)
end
for _,count in ipairs({-1,65,1.5,"24",math.huge,0/0}) do
    local native=unit(name,count);check(not policy.can_omit(native,definition,true),"bounded slot count")
    check(native.slots_read==0,"invalid slot count never scans")
end
local native=unit(name,64)
native.GetAbilityByIndex=function(self,slot)
    self.slots_read=self.slots_read+1
    if slot==63 then return {IsNull=function() return false end} end
end
check(not policy.can_omit(native,definition,true),"appearance-added hidden/level-zero ability kept")
check(native.slots_read==64,"last valid slot visited")
native=unit(name);native.GetAbilityByIndex=function() return {} end
check(not policy.can_omit(native,definition,true),"unknown ability handle")
native.GetAbilityByIndex=function() return {IsNull=function() return true end} end
check(policy.can_omit(native,definition,true),"null native slots accepted")
check(policy.can_omit(unit(name,0),definition,true),"zero native slots accepted")
kv=setmetatable({}, {__index=function(_,key) if key~="DOTAUnits" then reads=reads+1 end;return original_kv[key] end})
policy=dofile(path);local initial=loads
for _=1,200 do check(policy.can_omit(unit(name),definition,true),"repeated cached birth") end
check(reads==1 and loads==initial+1,"per-type KV check cached; no per-frame work")
kv=copy(original_kv);kv[name].Ability1="future_skill"
check(not dofile(path).can_omit(unit(name),definition,true),"module reload rechecks changed KV")
local original_loader=LoadKeyValues;local failed_loads=0
LoadKeyValues=function() failed_loads=failed_loads+1;error("KV unavailable") end
policy=dofile(path)
for _=1,20 do check(not policy.can_omit(unit(name),definition,true),"KV exception retains cap") end
check(failed_loads==1,"broken KV load is not retried every birth")
LoadKeyValues=original_loader
kv=copy(original_kv)
policy=dofile(path)
policy.init()
local loaded_before=loads
check(policy.can_omit(unit(name),definition,true),"map init preloads KV before first birth")
check(loads==loaded_before,"first spawn performs no file load after map init")
kv=copy(original_kv);kv[name].Ability1="map_reloaded_skill"
policy.init()
check(not policy.can_omit(unit(name),definition,true),"new map init invalidates retained Lua module cache")
-- Actual native runtime GetAbilityKeyValues (ID8873 and engine Item defaults)
-- captured from the installed Dota twin_gate_portal_warp. This is not a generic
-- hidden/level-zero allowance. Real wave monsters inject exactly this at slot0.
local native_warp_kv = {["AbilityBehavior"]="DOTA_ABILITY_BEHAVIOR_UNIT_TARGET | DOTA_ABILITY_BEHAVIOR_CHANNELLED | DOTA_ABILITY_BEHAVIOR_DONT_RESUME_ATTACK | DOTA_ABILITY_BEHAVIOR_DONT_CANCEL_CHANNEL | DOTA_ABILITY_BEHAVIOR_HIDDEN | DOTA_ABILITY_BEHAVIOR_IGNORE_SILENCE | DOTA_ABILITY_BEHAVIOR_ROOT_DISABLES | DOTA_ABILITY_BEHAVIOR_NOT_LEARNABLE",["AbilityCastAnimation"]="ACT_DOTA_GENERIC_CHANNEL_1",["AbilityCastPoint"]="0",["AbilityCastRange"]="200",["AbilityCastRangeBuffer"]=250,["AbilityChannelTime"]="4.000000",["AbilityChargeRestoreTime"]="0",["AbilityCharges"]="0",["AbilityCooldown"]="0",["AbilityDamage"]="0 0 0 0",["AbilityDuration"]="0",["AbilityManaCost"]="30",["AbilityModifierSupportBonus"]=0,["AbilityModifierSupportValue"]=1,["AbilityOvershootCastRange"]=0,["AbilitySharedCooldown"]="",["AbilityType"]="ABILITY_TYPE_BASIC",["AbilityUnitTargetFlags"]="DOTA_UNIT_TARGET_FLAG_INVULNERABLE",["AbilityUnitTargetTeam"]="DOTA_UNIT_TARGET_TEAM_ENEMY",["AbilityValues"]={["animation_rate"]="0.800000",["stop_distance"]="500"},["FightRecapLevel"]=0,["ID"]=8873,["IsCastableWhileHidden"]=1,["ItemCombinable"]=1,["ItemCost"]=0,["ItemDeclaresPurchase"]=0,["ItemDisassemblable"]=0,["ItemDroppable"]=1,["ItemInitialCharges"]=0,["ItemIsNeutralDrop"]=0,["ItemKillable"]=1,["ItemPermanent"]=1,["ItemPurchasable"]=1,["ItemRecipe"]=0,["ItemRequiresCharges"]=0,["ItemSellable"]=1,["ItemShareability"]="ITEM_NOT_SHAREABLE",["ItemStackable"]=0,["MaxLevel"]=1,["OnCastbar"]=1,["OnLearnbar"]=1}
local function warp()
    return {IsNull=function() return false end,
        GetAbilityName=function() return "twin_gate_portal_warp" end,
        GetClassname=function() return "twin_gate_portal_warp" end,
        GetAbilityType=function() return 0 end,IsPassive=function() return false end,
        IsHidden=function() return true end,GetLevel=function() return 1 end,
        GetIntrinsicModifierName=function() end,
        GetAbilityKeyValues=function() return copy(native_warp_kv) end}
end
local function with_warp(count,extra)
    local native=unit(name,count or 1);local portal=warp()
    native.GetAbilityByIndex=function(self,slot)
        self.slots_read=self.slots_read+1
        if slot==0 then return portal end
        return extra and extra[slot]
    end
    return native,portal
end
kv=original_kv;custom_abilities={};policy=dofile(path)
local actual,portal=with_warp()
local previous_custom_loads=custom_loads
check(policy.can_omit(actual,definition,true),"actual native automatic slot0 warp accepted")
check(actual.slots_read==1 and custom_loads==previous_custom_loads+1,"real one-slot API and one cached custom KV load")
for _=1,50 do check(policy.can_omit(with_warp(),definition,true),"native warp cached custom identity") end
check(custom_loads==previous_custom_loads+1,"custom abilities parsed once, not each birth")
local function reject_warp(edit,label)
    local value,ability=with_warp();edit(ability)
    check(not policy.can_omit(value,definition,true),label)
end
for field,value in pairs({GetAbilityName="other_hidden_ability",GetClassname="dota_ability_lua",
    GetAbilityType=1,IsPassive=true,IsHidden=false,GetLevel=0,GetIntrinsicModifierName="modifier_future_attack_speed"}) do
    reject_warp(function(a) a[field]=function() return value end end,"native identity only "..field)
end
for _,field in ipairs({"GetAbilityName","GetClassname","GetAbilityType","IsPassive","IsHidden","GetLevel","GetIntrinsicModifierName","GetAbilityKeyValues"}) do
    reject_warp(function(a) a[field]=nil end,"missing portal metadata "..field)
    reject_warp(function(a) a[field]=function() error('native missing') end end,"throwing portal metadata "..field)
end
for field,value in pairs({ID=9999,MaxLevel=2,AbilityBehavior="DOTA_ABILITY_BEHAVIOR_PASSIVE",AbilityType="ABILITY_TYPE_ULTIMATE",
    BaseClass="ability_lua",ScriptFile="future_warp",Modifiers={},AbilitySpecial={},AttackSpeed=100,BaseAttackSpeed=100}) do
    reject_warp(function(a) local values=copy(native_warp_kv);values[field]=value;a.GetAbilityKeyValues=function() return values end end,"altered native KV "..field)
end
for _,field in ipairs({"animation_rate","stop_distance"}) do
    reject_warp(function(a) local values=copy(native_warp_kv);values.AbilityValues[field]=999;a.GetAbilityKeyValues=function() return values end end,"altered portal effect "..field)
end
reject_warp(function(a) local values=copy(native_warp_kv);values.AbilityValues.attack_speed_bonus=100;a.GetAbilityKeyValues=function() return values end end,"new effect field retains cap")
reject_warp(function(a) local values=copy(native_warp_kv);values.AbilityValues.animation_rate={value=.8};a.GetAbilityKeyValues=function() return values end end,"unknown nested effect values")
local hostile={IsNull=function() return false end,IsHidden=function() return true end,GetLevel=function() return 0 end}
actual=with_warp(64,{[63]=hostile})
check(not policy.can_omit(actual,definition,true) and actual.slots_read==64,"warp plus hidden last-slot unknown ability kept")
actual=with_warp(64,{[63]=warp()})
check(not policy.can_omit(actual,definition,true) and actual.slots_read==64,"second exact warp in a different slot kept")
actual=unit(name,1);actual.GetAbilityByIndex=function() return hostile end
check(not policy.can_omit(actual,definition,true),"generic hidden/level-zero never accepted")
actual=unit(name,2);actual.GetAbilityByIndex=function(_,slot) if slot==1 then return warp() end end
check(not policy.can_omit(actual,definition,true),"only automatic slot0 is audited")
for _,custom in ipairs({{twin_gate_portal_warp={BaseClass="ability_lua"}},{DOTAAbilities={twin_gate_portal_warp={}}},false,"unknown",{DOTAAbilities=false}}) do
    custom_abilities=custom;policy=dofile(path)
    check(not policy.can_omit(with_warp(),definition,true),"custom override or unknown custom KV kept")
end
local warp_loader=LoadKeyValues;local failed_custom_loads=0
LoadKeyValues=function(file)
    if file=="scripts/npc/npc_abilities_custom.txt" then failed_custom_loads=failed_custom_loads+1;error('custom KV unavailable') end
    return warp_loader(file)
end
policy=dofile(path)
for _=1,20 do check(not policy.can_omit(with_warp(),definition,true),"custom KV load exception keeps cap") end
check(failed_custom_loads==1,"broken custom KV not retried at every birth")
LoadKeyValues=warp_loader
custom_abilities={DOTAAbilities={}};policy=dofile(path)
check(policy.can_omit(with_warp(),definition,true),"wrapped custom KV with no override accepted")
custom_abilities={twin_gate_portal_warp={}}
policy.init();check(not policy.can_omit(with_warp(),definition,true),"new map clears cached custom absence")
custom_abilities={};policy.init();check(policy.can_omit(with_warp(),definition,true),"new map can restore audited native allowance")
kv=copy(original_kv);kv[name].Ability1="twin_gate_portal_warp";policy.init()
check(not policy.can_omit(with_warp(),definition,true),"static custom-unit portal declaration remains unsafe")
kv=original_kv
print('WAVE_NATIVE_WARP_PASS exact native slot0 identity/KV, no passive/intrinsic/AS, no generic hidden allowance, all slots, custom override/exception/map reset fallback')
print(string.format("WAVE_NATIVE_ATTACK_CAP_PASS %d assertions, 873 real rows/44 opt-ins/N1 wave15=61, bounded abilities, no scans/timers/mutations",assertions))
