local stage, fixture = assert(arg[1]), assert(arg[2])
package.path = stage .. "/scripts/vscripts/?.lua;scripts/vscripts/?.lua;" .. package.path
for _, name in ipairs({'worker_system','worker_native_attack_cap','wave_native_attack_cap','rogue_effect_registry','buff_manager'}) do
    local path=stage..'/scripts/vscripts/systems/'..name..'.lua'
    local f=io.open(path,'rb')
    if f then f:close();package.preload['systems/'..name]=assert(loadfile(path)) end
end
local kv = dofile(fixture)
LoadKeyValues = function(path) return assert(kv[path], path) end
IsServer = function() return true end
local policy = require("systems/worker_native_attack_cap")
local contracts = require("systems/wave_native_attack_cap")
local definitions = require("config/generated/training_definitions")
local CAP, FLAG = "modifier_debug_attack_cap", "survival_worker_native_cap_omitted"
local maximum = 7
local function mode() return {GetMaximumAttackSpeed = function() return maximum end} end
GameRules = {GetGameModeEntity = mode}
local function modifier(unit, name)
    local m = {value=0}
    function m:IsNull() return self.dead == true end
    function m:GetName() return name end
    function m:SetStackCount(v)
        if name == "modifier_lumberjack_cheer" and v > 0 then assert(unit:HasModifier(CAP), "cap before cheer stack") end
        self.value=v
    end
    function m:Destroy() self.dead=true;unit.mods[name]=nil end
    function m:RefreshManaged(v)
        if v~=0 then assert(unit:HasModifier(CAP), "cap before managed refresh") end
        self.value=v
    end
    function m:ApplyManaged(v) self:RefreshManaged(v) end
    return m
end
local function rig(u, name)
    u.mods, u.abilities = {}, u.abilities or {}
    function u:GetUnitName() return name or "npc_survival_lumberjack" end
    function u:GetClassname() return "npc_dota_creature" end
    function u:IsRealHero() return false end
    function u:HasModifier(n) return self.mods[n] ~= nil end
    function u:FindModifierByName(n) return self.mods[n] end
    function u:FindAllModifiersByName(n) return self.mods[n] and {self.mods[n]} or {} end
    function u:FindAllModifiers() local a={};for _,m in pairs(self.mods) do a[#a+1]=m end;return a end
    function u:AddNewModifier(_, _, n, params)
        params=params or {}
        if n == CAP and self.fail_cap then return nil end
        if n == "modifier_rogue_lumberjack_attack_speed" and (params.value or 0)~=0 then assert(self:HasModifier(CAP), "cap before rogue") end
        if n == "modifier_survival_managed_buff" and (params.managed_value or 0)~=0 then assert(self:HasModifier(CAP), "cap before managed create") end
        local m=modifier(self,n);m.buff_id=params.buff_id;m.value=params.value or params.managed_value or 0
        self.mods[n]=m;return m
    end
    function u:RemoveModifierByName(n) self.mods[n]=nil end
    function u:GetAbilityCount() local n=0;for _ in pairs(self.abilities) do n=n+1 end;return n end
    function u:GetAbilityByIndex(i)
        local names={};for n in pairs(self.abilities) do names[#names+1]=n end;table.sort(names)
        return self.abilities[names[i+1]]
    end
    local function ability(n)
        local a={level=1}
        function a:GetLevel() return self.level end
        function a:SetLevel(v) self.level=v end
        function a:IsNull() return false end
        function a:GetAbilityName() return n end
        function a:IsPassive() return false end
        function a:GetIntrinsicModifierName() return nil end
        function a:GetAbilityKeyValues() return kv["scripts/npc/npc_abilities_custom.txt"][n] end
        return a
    end
    function u:AddAbility(n) self.abilities[n]=ability(n);return self.abilities[n] end
    function u:RemoveAbility(n) self.abilities[n]=nil end
    function u:FindAbilityByName(n) return self.abilities[n] end
    return u
end
local function fresh(level)
    local u=rig({IsNull=function()return false end,GetTeamNumber=function()return 2 end})
    local id=string.format("train_lumberjack_%02d",level or 1)
    u:AddAbility(definitions.by_id[id].active_skill_ids[1]);return u,id,definitions.by_id[id]
end
local checks=0
local function ok(v) checks=checks+1;assert(v,"check "..checks) end
for level=1,8 do
 local u,id,row=fresh(level);ok(policy.is_training_candidate(id,row,row.unit_name or 'npc_survival_lumberjack'));ok(policy.omit_new(u,id,row,true));ok(u[FLAG]==true and not u:HasModifier(CAP));ok(not policy.omit_new(u,id,row,true));ok(policy.restore(u));ok(u:HasModifier(CAP) and u[FLAG]==nil)
end
for _, field in ipairs({'survival_super_lumberjack','survival_commerce_immortal','survival_worker_type'}) do
 local u,id,row=fresh();u[field]=true;ok(not policy.omit_new(u,id,row,true));ok(u[FLAG]==nil)
end
for _, mutate in ipairs({
 function(u)u:GetAbilityByIndex(0).level=0 end,
 function(u)u:AddAbility('future_bloodlust')end,
 function(u)u.mods.unknown=modifier(u,'future_ias_aura')end,
 function(u)u.mods[CAP]=modifier(u,CAP)end,
 function(u)u.GetAbilityCount=function()return 65 end end,
 function(u)u.GetAbilityCount=function()return 0/0 end end,
 function(u)u.GetAbilityByIndex=function()error('engine unavailable')end end,
 function(u)u.GetUnitName=function()return 'npc_survival_super_lumberjack_01'end end,
 function(u)u.IsRealHero=function()return true end end,
 function(u)u:GetAbilityByIndex(0).GetIntrinsicModifierName=function()return 'future_native_ias'end end,
 function(u)u.FindAllModifiers=false end,
}) do local u,id,row=fresh();mutate(u);ok(not policy.omit_new(u,id,row,true)) end
local u,id,row=fresh();ok(not policy.omit_new(u,id,row,false));ok(not policy.is_training_candidate('train_lumberjack_09',row,'npc_survival_lumberjack'))
for key,value in pairs({level=9,unit_name='future_unit',active_skill_ids={'ability_fuse_lumberjack_01','future_ias'},passive_skill_ids={'future_ias'},enabled=false}) do
 local old=row[key];row[key]=value;ok(not policy.is_training_candidate(id,row,'npc_survival_lumberjack'));row[key]=old
end
local base=kv['scripts/npc/npc_units_custom.txt'].npc_survival_lumberjack
for key,value in pairs({BaseAttackSpeed='200',Ability1='future_ias',HasInventory='1'}) do
 local old=base[key];base[key]=value;contracts.init();ok(not policy.is_training_candidate(id,row,'npc_survival_lumberjack'));base[key]=old;contracts.init()
end
local ability=kv['scripts/npc/npc_abilities_custom.txt'].ability_fuse_lumberjack_01
for key,value in pairs({ScriptFile='future',Modifiers={},AbilityValues={attack_speed=100},BaseClass='ability_datadriven'}) do
 local old=ability[key];ability[key]=value;policy.init();ok(not policy.is_training_candidate(id,row,'npc_survival_lumberjack'));ability[key]=old;policy.init()
end
maximum=6.99;ok(not policy.omit_new(u,id,row,true));maximum=7
local u,id,row=fresh();ok(policy.omit_new(u,id,row,true));u.fail_cap=true;ok(not policy.restore(u) and u[FLAG]==true);u.fail_cap=false;ok(policy.restore(u) and u[FLAG]==nil)
local unknown=fresh();ok(policy.restore(unknown) and not unknown:HasModifier(CAP))
local omitted,id,row=fresh();ok(policy.omit_new(omitted,id,row,true));package.loaded['systems/worker_native_attack_cap']=nil;policy=require('systems/worker_native_attack_cap');policy.init();ok(policy.restore(omitted) and omitted:HasModifier(CAP))
local native_warp_kv = {["AbilityBehavior"]="DOTA_ABILITY_BEHAVIOR_UNIT_TARGET | DOTA_ABILITY_BEHAVIOR_CHANNELLED | DOTA_ABILITY_BEHAVIOR_DONT_RESUME_ATTACK | DOTA_ABILITY_BEHAVIOR_DONT_CANCEL_CHANNEL | DOTA_ABILITY_BEHAVIOR_HIDDEN | DOTA_ABILITY_BEHAVIOR_IGNORE_SILENCE | DOTA_ABILITY_BEHAVIOR_ROOT_DISABLES | DOTA_ABILITY_BEHAVIOR_NOT_LEARNABLE",["AbilityCastAnimation"]="ACT_DOTA_GENERIC_CHANNEL_1",["AbilityCastPoint"]="0",["AbilityCastRange"]="200",["AbilityCastRangeBuffer"]=250,["AbilityChannelTime"]="4.000000",["AbilityChargeRestoreTime"]="0",["AbilityCharges"]="0",["AbilityCooldown"]="0",["AbilityDamage"]="0 0 0 0",["AbilityDuration"]="0",["AbilityManaCost"]="30",["AbilityModifierSupportBonus"]=0,["AbilityModifierSupportValue"]=1,["AbilityOvershootCastRange"]=0,["AbilitySharedCooldown"]="",["AbilityType"]="ABILITY_TYPE_BASIC",["AbilityUnitTargetFlags"]="DOTA_UNIT_TARGET_FLAG_INVULNERABLE",["AbilityUnitTargetTeam"]="DOTA_UNIT_TARGET_TEAM_ENEMY",["AbilityValues"]={["animation_rate"]="0.800000",["stop_distance"]="500"},["FightRecapLevel"]=0,["ID"]=8873,["IsCastableWhileHidden"]=1,["ItemCombinable"]=1,["ItemCost"]=0,["ItemDeclaresPurchase"]=0,["ItemDisassemblable"]=0,["ItemDroppable"]=1,["ItemInitialCharges"]=0,["ItemIsNeutralDrop"]=0,["ItemKillable"]=1,["ItemPermanent"]=1,["ItemPurchasable"]=1,["ItemRecipe"]=0,["ItemRequiresCharges"]=0,["ItemSellable"]=1,["ItemShareability"]="ITEM_NOT_SHAREABLE",["ItemStackable"]=0,["MaxLevel"]=1,["OnCastbar"]=1,["OnLearnbar"]=1}
local function warp() return {IsNull=function()return false end,GetAbilityName=function()return 'twin_gate_portal_warp'end,GetClassname=function()return 'twin_gate_portal_warp'end,GetAbilityType=function()return 0 end,IsPassive=function()return false end,IsHidden=function()return true end,GetLevel=function()return 1 end,GetIntrinsicModifierName=function()end,GetAbilityKeyValues=function()return native_warp_kv end} end
local portal=warp();local wu,wi,wr=fresh();local fusion=wu:GetAbilityByIndex(0)
wu.GetAbilityCount=function()return 2 end;wu.GetAbilityByIndex=function(_,slot)return slot==0 and portal or fusion end
ok(policy.omit_new(wu,wi,wr,true));ok(policy.restore(wu))
local wu,wi,wr=fresh();local fusion=wu:GetAbilityByIndex(0);wu.GetAbilityCount=function()return 2 end
wu.GetAbilityByIndex=function(_,slot)return slot==0 and fusion or portal end;ok(not policy.omit_new(wu,wi,wr,true))
print('WORKER_CAP_POLICY_PASS checks='..checks..'; actual KV/8 tiers, unknowns, ability/intrinsic/KV drift, cap failure, module reload')

-- Reuse the real 104-worker production queue fixture, adding only engine APIs
-- needed by the new conservative birth contract. Do not mock worker_system.
local file=assert(io.open('scripts/vscripts/tests/test_worker_leader_refresh.lua','rb'));local source=file:read('*a');file:close()
source=assert(source:match('^(.-)local function full_refresh'))
local injection=[[
local old_create=CreateUnitByName
CreateUnitByName=function(name,position) return _G.WORKER_CAP_TEST_RIG(old_create(name,position),name) end
GameRules.GetGameModeEntity=_G.WORKER_CAP_TEST_MODE
]]
_G.WORKER_CAP_TEST_RIG,_G.WORKER_CAP_TEST_MODE=rig,mode
source=source:gsub('scheduler%.clear%(%)%; bus%.reset%(%)%; workers%.init%(%)',injection..'\nscheduler.clear(); bus.reset(); workers.init()',1)
local scene=assert(loadstring(source..'\nreturn {units=units,roster=roster,workers=workers,bus=bus,events=events,stats=stats_by_owner,errors=errors,cities=cities,step=function()now=now+1;scheduler.think()end}'))()
for _,unit in ipairs(scene.units) do ok(unit[FLAG]==true and not unit:HasModifier(CAP)) end
for owner=0,3 do
 scene.stats[owner].attack_speed_bonus_pct=6000
 scene.bus.emit(scene.events.TECHNOLOGY_STATS_CHANGED,{player_id=owner,reason='research_completed'})
 for _,state in ipairs(scene.roster[owner])do ok(state.unit[FLAG]==true and math.abs(state.unit.interval-0.05)<1e-9)end
end
-- Rogue current workers and new-worker recompute restore before native IAS.
local rogue=require('systems/rogue_effect_registry').get('lumberjack_attack_speed_bonus_pct')
rogue.apply({player_id=0,params={value=100}})
for _,state in ipairs(scene.roster[0])do ok(state.unit:HasModifier(CAP) and state.unit[FLAG]==nil)end
local r=scene.roster[1][1];rogue.recompute({player_id=1,params={value=800}},r);ok(r.unit:HasModifier(CAP))
-- Positive and negative managed buff values use the actual application entry.
local buffs=require('systems/buff_manager');local m=scene.roster[1][2].unit
buffs.apply(nil,m,'debuff_polar_attack_slow',{value=-20});ok(m[FLAG]==nil and m:HasModifier(CAP))
buffs.apply(nil,m,'debuff_polar_attack_slow',{value=800});ok(m:HasModifier(CAP) and m[FLAG]==nil)
m:RemoveModifierByName('modifier_survival_managed_buff');ok(m:HasModifier(CAP))
local m2=scene.roster[1][3].unit;buffs.apply(nil,m2,'debuff_polar_attack_slow',{value=800});ok(m2:HasModifier(CAP))
local def=require('config/generated/buff_definitions').by_id.debuff_polar_attack_slow
local old=def.effect_type;def.effect_type='attack_speed_bonus';local m3=scene.roster[1][4].unit;buffs.apply(nil,m3,'debuff_polar_attack_slow',{value=800});ok(m3:HasModifier(CAP));def.effect_type=old
-- Every nonzero native IAS restores first, without assuming a lower clamp.
local function omitted_subject()
 local target,id,row=fresh();ok(policy.omit_new(target,id,row,true));return target
end
for _,id in ipairs({'debuff_polar_attack_slow','debuff_airspace_attack_slow','debuff_hero_ice_cone_attack_slow'})do
 local target=omitted_subject();local m=buffs.apply(nil,target,id)
 ok(m and m.value==-20 and target:HasModifier(CAP) and target[FLAG]==nil)
 buffs.remove(target,id);ok(target:HasModifier(CAP))
end
for _,effect in ipairs({'attack_speed_pct','attack_speed_bonus'})do
 local def=buffs.get_definition('debuff_polar_attack_slow');local previous=def.effect_type;def.effect_type=effect
 for _,value in ipairs({-40,-1000})do
  local target=omitted_subject();local m=buffs.apply(nil,target,'debuff_polar_attack_slow',{value=0})
  ok(m and target[FLAG]==true and not target:HasModifier(CAP))
  ok(buffs.apply(nil,target,'debuff_polar_attack_slow',{value=value})==m and m.value==value and target:HasModifier(CAP) and target[FLAG]==nil)
  buffs.remove(target,'debuff_polar_attack_slow');ok(target:HasModifier(CAP))
 end
 local target=omitted_subject();target.fail_cap=true
 local success,reason=pcall(buffs.apply,nil,target,'debuff_polar_attack_slow',{value=-1000})
 ok(not success and tostring(reason):find('worker_attack_cap_restore_failed',1,true) and target[FLAG]==true and not target:HasModifier('modifier_survival_managed_buff'))
 local zero=buffs.apply(nil,target,'debuff_polar_attack_slow',{value=0});ok(zero and zero.value==0)
 ok(not pcall(buffs.apply,nil,target,'debuff_polar_attack_slow',{value=-40}) and zero.value==0 and target[FLAG]==true)
 target.fail_cap=false;ok(buffs.apply(nil,target,'debuff_polar_attack_slow',{value=-40})==zero and zero.value==-40 and target:HasModifier(CAP))
 def.effect_type=previous
end
local target=omitted_subject();local payload={player_id=1,worker_type='lumberjack',unit=target}
rogue.recompute({player_id=1,params={value=0}},payload);ok(target[FLAG]==true and not target:HasModifier(CAP))
target.fail_cap=true;local zero=target.mods.modifier_rogue_lumberjack_attack_speed
local success,reason=pcall(rogue.recompute,{player_id=1,params={value=-1000}},payload)
ok(not success and tostring(reason):find('worker_attack_cap_restore_failed',1,true) and zero.value==0 and target.mods.modifier_rogue_lumberjack_attack_speed==zero and target[FLAG]==true)
target.fail_cap=false;rogue.recompute({player_id=1,params={value=-1000}},payload);ok(target:HasModifier(CAP) and target.mods.modifier_rogue_lumberjack_attack_speed.value==-1000)
target:RemoveModifierByName('modifier_rogue_lumberjack_attack_speed');ok(target:HasModifier(CAP))
-- Fusion is the same native entity. Revoke before its personality ability is added.
local fused=scene.roster[2][1].unit;local add=fused.AddAbility
fused.AddAbility=function(self,name)assert(self:HasModifier(CAP),'cap before fusion ability');return add(self,name)end
local cheer=require('config/generated/lumberjack_personality_definitions').by_id.lumberjack_personality_cheer.ability_name
PlayerResource={GetTeam=function()return 2 end};HeroList={GetAllHeroes=function()return{}end}
scene.bus.handle_request(scene.events.BUILDING_LIST_REQUEST,function()return{}end)
ok(scene.workers.register_fused_lumberjack(fused,{player_id=2,team=2,level=1,base_attack=100,attack_speed=2/3,ability_names={cheer},fusion_count=1}).ok)
for _,state in ipairs(scene.roster[2])do ok(state.unit:HasModifier(CAP) and state.unit[FLAG]==nil)end
for _,state in ipairs(scene.roster[3])do ok(state.unit[FLAG]==true and not state.unit:HasModifier(CAP))end
-- Existing cheer and an already selected rogue card also protect later births.
scene.bus.subscribe(scene.events.WORKER_CHANGED,function(payload)
 if payload.player_id==0 and payload.unit then rogue.recompute({player_id=0,params={value=800}},payload)end
end)
for _,owner in ipairs({0,2}) do
 local before=#scene.units
 local result=scene.bus.request(scene.events.WORKER_TRAIN_REQUEST,{player_id=owner,city=scene.cities[owner],training_id='train_lumberjack_08'})
 ok(result and result.ok and result.queued);scene.step()
 ok(#scene.units==before+1)
 local born=scene.units[#scene.units];ok(born:HasModifier(CAP) and born[FLAG]==nil)
end
-- If the native modifier cannot be created, do not mutate a positive effect or fusion.
local failed=scene.roster[3][1].unit;failed.fail_cap=true
local succeeded,reason=pcall(buffs.apply,nil,failed,'debuff_polar_attack_slow',{value=800});ok(not succeeded and tostring(reason):find('worker_attack_cap_restore_failed',1,true) and failed[FLAG]==true)
local succeeded,reason=pcall(rogue.recompute,{player_id=3,params={value=800}},scene.roster[3][1]);ok(not succeeded and tostring(reason):find('worker_attack_cap_restore_failed',1,true) and not failed:HasModifier('modifier_rogue_lumberjack_attack_speed'))
ok(scene.workers.register_fused_lumberjack(failed,{player_id=3,team=2,level=1,ability_names={cheer}}).ok==false)
ok(not failed.survival_super_lumberjack and not failed.abilities[cheer])
-- Test the actual upstream application closure: native restore failure must not
-- report success or mark a selected effect active/completed.
local f=assert(io.open('scripts/vscripts/systems/rogue_effect_runtime_service.lua','rb'));local runtime=f:read('*a');f:close()
local first=assert(runtime:find('local function apply_instance',1,true));local last=assert(runtime:find('local function create_instance',first,true))
local apply=assert(loadstring(runtime:sub(first,last-1)..'return apply_instance'))
setfenv(apply,setmetatable({effect_registry=require('systems/rogue_effect_registry'),schedule_expiry=function()error('must not schedule failed reward')end},{__index=_G}))
local instance={player_id=3,params={value=800},status='pending',effect={effect_type='lumberjack_attack_speed_bonus_pct',execution_mode='timed'}}
local succeeded,reason=pcall(apply(),instance);ok(not succeeded and tostring(reason):find('worker_attack_cap_restore_failed',1,true) and instance.status=='pending')
instance.params.value=-1000;local succeeded,reason=pcall(apply(),instance);ok(not succeeded and tostring(reason):find('worker_attack_cap_restore_failed',1,true) and instance.status=='pending')
-- Existing mutually exclusive buff survives a failed nonzero-AS preflight.
local old_exclusive=modifier(failed,'old_exclusive');old_exclusive.definition={exclusive_group='test_ias',priority=0,buff_id='old'}
failed.FindAllModifiersByName=function()return{old_exclusive}end
local def=require('config/generated/buff_definitions').by_id.debuff_polar_attack_slow
local previous_group,previous_priority=def.exclusive_group,def.priority;def.exclusive_group='test_ias';def.priority=1
local succeeded=pcall(buffs.apply,nil,failed,'debuff_polar_attack_slow',{value=800});ok(not succeeded and not old_exclusive.dead)
local succeeded=pcall(buffs.apply,nil,failed,'debuff_polar_attack_slow',{value=-1000});ok(not succeeded and not old_exclusive.dead)
def.exclusive_group,def.priority=previous_group,previous_priority
-- The actual cheer helper emits an explicit failure before changing the stat.
local f=assert(io.open(stage..'/scripts/vscripts/systems/worker_system.lua','rb'));local code=f:read('*a');f:close()
local first=assert(code:find('local function apply_cheer_buff',1,true));local last=assert(code:find('local function cheer_native_candidate',first,true))
local apply=assert(loadstring(code:sub(first,last-1)..'return apply_cheer_buff'))
local env={valid_entity=function()return true end,workers={[failed:entindex()]={worker_type='lumberjack'}},cheer_owner_id=function()return 3 end,worker_attack_cap=policy}
setfenv(apply,setmetatable(env,{__index=_G}));local old_bonus=failed.survival_cheer_attack_speed_pct
local succeeded,reason=pcall(apply(),failed,3,800);ok(not succeeded and tostring(reason):find('worker_attack_cap_restore_failed',1,true) and failed.survival_cheer_attack_speed_pct==old_bonus)
failed.fail_cap=false
-- Removing cheer never strips the restored cap, and no unknown old entity gains one.
fused.abilities[cheer]=nil;scene.bus.emit(scene.events.HERO_SUMMONED,{player_id=2})
for _,state in ipairs(scene.roster[2])do ok(state.unit:HasModifier(CAP))end
local immortal=fresh();immortal.survival_commerce_immortal=true;ok(policy.restore(immortal));ok(not immortal:HasModifier(CAP))
ok(#scene.errors==0)
_G.WORKER_CAP_TEST_RIG,_G.WORKER_CAP_TEST_MODE=nil,nil
print('WORKER_CAP_LIFECYCLE_PASS: 104 actual queued workers; BAT technology; rogue + managed create/refresh + cheer restore-before-mutation; same-entity fusion; owner isolation; expiry keeps cap; old/immortal unchanged; checks='..checks)
