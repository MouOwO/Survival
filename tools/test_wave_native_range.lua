-- Real generated KV, real range/cap helpers, real formal/challenge birth code.
package.path="scripts/vscripts/?.lua;"..package.path
local original_kv=dofile(assert(arg[1],"actual parsed NPC fixture required"))
local kv=original_kv
local server,tools,map=true,true,"template_map"
local world={GetMaximumAttackSpeed=function() return 7 end}
IsServer=function() return server end;IsInToolsMode=function() return tools end
GetMapName=function() return map end
GameRules={GetGameModeEntity=function() return world end,GetGameTime=function() return 0 end}
_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION={mode=world}
DOTA_UNIT_CAP_MELEE_ATTACK,DOTA_UNIT_CAP_RANGED_ATTACK,DOTA_UNIT_CAP_MOVE_GROUND=1,2,1
DOTA_TEAM_GOODGUYS,DOTA_TEAM_BADGUYS=2,3
MODIFIER_EVENT_ON_DEATH,MODIFIER_PROPERTY_ATTACK_RANGE_BONUS,MODIFIER_PROPERTY_ATTACK_RANGE_BASE_OVERRIDE=3,4,5
class=function(t) return t end;LinkLuaModifier=function() end
local no_op=function() end
local load_calls,precache_calls,precache_arity_failures,callbacks=0,0,0,{}
LoadKeyValues=function(path)
    load_calls=load_calls+1
    if path=="scripts/npc/npc_abilities_custom.txt" then return {} end
    assert(path=="scripts/npc/npc_units_custom.txt");return kv
end
PrecacheUnitByNameAsync=function(...)
    if select("#",...)~=3 then
        precache_arity_failures=precache_arity_failures+1
        error("native_precache_expected_3_arguments")
    end
    local name,callback,player_id=...
    assert(type(name)=="string" and type(callback)=="function" and player_id==-1,
        "formal aliases must use explicit non-player native precache -1")
    assert(name:match("^npc_survival_range_"));precache_calls=precache_calls+1;callbacks[#callbacks+1]=callback
end
ExecuteOrderFromTable=function() error("range candidate sent an order") end
local range=arg[2] and dofile(arg[2]) or require("systems/wave_native_attack_range")
package.loaded["systems/wave_native_attack_range"]=range
assert(load_calls==0 and precache_calls==0 and _G.SURVIVAL_FORMAL_WAVE_NATIVE_RANGE_PROBE==nil,
    "require changed flags or performed native work")
local bus=require("core/event_bus")
local definitions=require("config/generated/monster_archetypes")
local rows=require("config/generated/wave_definitions").rows
local manifest=require("config/generated/wave_native_range_aliases")
local cap=require("systems/wave_native_attack_cap")
local function enable(prepare)
    assert(range.set_probe_enabled(false));assert(range.set_probe_enabled(true));cap.init()
    callbacks={}
    if prepare~=false then
        assert(range.prepare_aliases())
        assert(#callbacks==0,"all formal sources already have melee range; no aliases should be precached")
        for _,fn in ipairs(callbacks) do fn() end
        assert(range.snapshot().ready_aliases==0 and range.snapshot().pending_aliases==0)
    end
end
package.loaded["core/team_alignment"]={enforce=no_op}
package.loaded["systems/enemy_attack_observer"]={is_ready=function() return true end}
package.loaded["systems/wall_navigation_service"]={}
local ai=require("modifiers/modifier_enemy_wall_ai")
local range_modifier=require("modifiers/modifier_survival_hero_attack_range")
local marker={GetAbsOrigin=function() return {x=0,y=0,z=0} end}
local units,attempts={},{}
local creation_failure,edit_birth,edit_visual
local function create(name)
    attempts[#attempts+1]=name
    if creation_failure and creation_failure(name) then return nil end
    local native_kv=assert(kv[name],"unknown native unit name")
    local u={index=#units+1,name=name,modifiers={},base_range=tonumber(native_kv.AttackRange),range_bonus=0,
        attack_cap=native_kv.AttackCapabilities=="DOTA_UNIT_CAP_RANGED_ATTACK" and 2 or 1,
        alive=true,stats={},hull=32}
    function u:IsNull() return false end
    function u:IsAlive() return self.alive end
    function u:GetClassname() return "npc_dota_creature" end
    function u:IsRealHero() return false end
    function u:GetTeamNumber() return 3 end
    function u:GetUnitName() return self.name end
    function u:entindex() return self.index end
    function u:GetAttackCapability() return self.attack_cap end
    function u:SetAttackCapability(value) self.attack_cap=value end
    function u:GetAbilityCount() return 0 end
    function u:GetAbilityByIndex() return nil end
    function u:FindAbilityByName() return nil end
    function u:HasModifier(name) return self.modifiers[name]~=nil end
    function u:FindAllModifiers()
        local result={};for name in pairs(self.modifiers) do result[#result+1]={GetName=function() return name end} end
        return result
    end
    function u:Script_GetAttackRange()
        local m=self.modifiers.modifier_survival_hero_attack_range
        local contact=self.modifiers.modifier_enemy_wall_ai
        return (m and m:GetModifierAttackRangeOverride() or self.base_range)+self.range_bonus
            +(contact and contact:GetModifierAttackRangeBonus() or 0)
    end
    function u:AddNewModifier(_,_,name,params)
        if name=="modifier_survival_hero_attack_range" then
            local m=self.modifiers[name]
            if m then m:OnRefresh(params);return m end
            m=setmetatable({GetStackCount=function(self) return self.stack end,
                SetStackCount=function(self,value) self.stack=value end},{__index=range_modifier})
            self.modifiers[name]=m;m:OnCreated(params);return m
        elseif name=="modifier_enemy_wall_ai" then
            assert(self.visual_complete,"AI declared before final appearance proof")
            assert(not self.survival_is_wave_monster or self.modifiers.modifier_survival_hero_attack_range or self.survival_wave_native_base_range==true,
                "unproven native base reached AI")
            local m=setmetatable({GetParent=function() return self end,StartIntervalThink=no_op,
                SetHasCustomTransmitterData=no_op},{__index=ai})
            m.declarations=m:DeclareFunctions();m:OnCreated(params);self.modifiers[name]=m;return m
        end
        self.modifiers[name]=params or {};return self.modifiers[name]
    end
    for _,method in ipairs({"SetBaseMaxHealth","SetMaxHealth","SetHealth","SetBaseDamageMin",
        "SetBaseDamageMax","SetPhysicalArmorBaseValue","SetBaseMoveSpeed","SetBaseAttackTime",
        "SetModelScale","SetModel","SetOriginalModel","SetMoveCapability"}) do
        u[method]=function(self,value) self.stats[method]=value end
    end
    function u:AddAbility() error("candidate changed ability roster") end
    function u:Stop() error("candidate stopped attacks") end
    function u:SetAttackRange() error("candidate called nonexistent range setter") end
    function u:RemoveModifierByName() error("candidate removed an existing modifier") end
    if edit_birth then edit_birth(u) end
    units[#units+1]=u
    return u
end
local dependencies={
    ["visual/model_scale"]=require("visual/model_scale"),
    ["core/event_bus"]={emit=no_op},["core/events"]={MONSTER_SPAWNED="spawned"},
    ["core/team_alignment"]={enforce=no_op},["config/generated/monster_archetypes"]=definitions,
    ["config/generated/wave_definitions"]={rows=rows},["config/generated/archive_challenge_rules"]={by_id={default={}}},
    ["systems/monster_navigation_policy"]=require("systems/monster_navigation_policy"),
    ["systems/wave_monster_collision"]=require("systems/wave_monster_collision"),
    ["systems/wave_spawn_sequence"]=require("systems/wave_spawn_sequence"),
    ["systems/wave_native_attack_range"]=range,["systems/wave_native_attack_cap"]=cap,
    ["config/monster_visual_config"]={resolve=function() end},
    ["systems/monster_visual_service"]={apply=no_op},
    ["systems/monster_hero_visual_service"]={apply=function(u)
        if edit_visual then edit_visual(u) end;u.visual_complete=true
    end},["systems/monster_hull_scale"]={apply=function() return true end},
    ["systems/monster_corpse_lifecycle_service"]={track=no_op},
}
local env=setmetatable({require=function(name) return dependencies[name] or {} end,
    GetGroundHeight=function() return 0 end,CreateUnitByName=create,FindClearSpaceForUnit=no_op},{__index=_G})
local chunk=assert(loadfile("scripts/vscripts/systems/wave_system.lua"));setfenv(chunk,env);local wave=chunk()
local function find(module,wanted)
    local visited={}
    local function visit(fn)
        if type(fn)~="function" or visited[fn] then return end;visited[fn]=true
        for i=1,100 do
            local name,value=debug.getupvalue(fn,i);if not name then break end
            if name==wanted then return value end
            local found=visit(value);if found then return found end
        end
    end
    for _,fn in pairs(module) do local result=visit(fn);if result then return result end end
    error("missing actual birth fixture upvalue "..wanted)
end
local function set(fn,wanted,value)
    for i=1,100 do local name=debug.getupvalue(fn,i);if not name then break end
        if name==wanted then debug.setupvalue(fn,i,value);return end end
    error("missing actual birth state "..wanted)
end
local spawn=find(wave,"spawn_one")
local state={pending=10000,spawned=0,alive=0,failed_spawn=0}
set(spawn,"monster_spawn_marker",marker);set(spawn,"state",state);set(spawn,"publish",no_op)
local by_id={};for _,row in ipairs(rows) do if not by_id[row.archetype_id] then by_id[row.archetype_id]=row end end
local function birth(id)
    local row=assert(by_id[id]);spawn(row,0,row.wave_number,1);return units[#units]
end
-- Off keeps the normal range modifier on all 44 now-melee source names.
local old_calls=load_calls
for identity in pairs(manifest.by_id) do
    local u=birth(identity);assert(u.name==definitions.by_id[identity].unit_name)
    assert(u.modifiers.modifier_survival_hero_attack_range)
    assert(u:Script_GetAttackRange()==definitions.by_id[identity].attack_range)
end
assert(load_calls==old_calls or load_calls==old_calls+1,"default off read range contract")
assert(precache_calls==0 and range.snapshot().enabled==false)
-- Every source has the native 128 melee reach; there is no async alias wait.
enable(false)
local u=birth("dwarf_white_rifle")
assert(u.name==definitions.by_id.dwarf_white_rifle.unit_name and not u.modifiers.modifier_survival_hero_attack_range)
assert(range.snapshot().rejections.alias_not_ready==nil)
enable()
local original_count,alias_count=0,0
for identity,metadata in pairs(manifest.by_id) do
    local source=definitions.by_id[identity];u=birth(identity)
    local reasons={}
    for reason,count in pairs(range.snapshot().rejections) do reasons[#reasons+1]=reason.."="..count end
    assert(u.name==metadata.unit_name and u.survival_wave_native_base_range==true,
        identity.." native proof rejected: "..table.concat(reasons,","))
    assert(not u.modifiers.modifier_survival_hero_attack_range and not u.modifiers.modifier_debug_attack_cap,
        "range alias regressed attack-cap omission")
    assert(u:Script_GetAttackRange()==source.attack_range and source.unit_name==metadata.source_unit_name)
    assert(u.stats.SetBaseMaxHealth==by_id[identity].health and u.stats.SetBaseDamageMin==by_id[identity].attack)
    assert(u.stats.SetBaseAttackTime==1/by_id[identity].attack_speed)
    assert(u.attack_cap==(source.attack_type=="ranged" and 2 or 1))
    u.range_bonus=50
    if source.attack_type=="melee" then u.modifiers.modifier_enemy_wall_ai.contact_range_delta=80 end
    assert(u:Script_GetAttackRange()==source.attack_range+50+(source.attack_type=="melee" and 80 or 0))
    if metadata.alias then alias_count=alias_count+1 else original_count=original_count+1 end
end
assert(original_count==44 and alias_count==0 and range.snapshot().omitted==44)
-- The exact engine-injected inert warp stays accepted; arbitrary hidden
-- native abilities do not gain a range exemption from their appearance.
local warp_kv={ID=8873,MaxLevel=1,AbilityType="ABILITY_TYPE_BASIC",
    AbilityBehavior="DOTA_ABILITY_BEHAVIOR_UNIT_TARGET | DOTA_ABILITY_BEHAVIOR_CHANNELLED | DOTA_ABILITY_BEHAVIOR_DONT_RESUME_ATTACK | DOTA_ABILITY_BEHAVIOR_DONT_CANCEL_CHANNEL | DOTA_ABILITY_BEHAVIOR_HIDDEN | DOTA_ABILITY_BEHAVIOR_IGNORE_SILENCE | DOTA_ABILITY_BEHAVIOR_ROOT_DISABLES | DOTA_ABILITY_BEHAVIOR_NOT_LEARNABLE",
    AbilityValues={animation_rate=.8,stop_distance=500}}
local warp={IsNull=function() return false end,GetAbilityName=function() return "twin_gate_portal_warp" end,
    GetClassname=function() return "twin_gate_portal_warp" end,GetAbilityType=function() return 0 end,
    IsPassive=function() return false end,IsHidden=function() return true end,GetLevel=function() return 1 end,
    GetIntrinsicModifierName=function() end,GetAbilityKeyValues=function() return warp_kv end}
enable();edit_birth=function(v) v.GetAbilityCount=function() return 1 end
    v.GetAbilityByIndex=function(_,slot) if slot==0 then return warp end end end
u=birth("dwarf_white_rifle");edit_birth=nil
assert(not u.modifiers.modifier_survival_hero_attack_range and not u.modifiers.modifier_debug_attack_cap)
enable();edit_birth=function(v) v.GetAbilityCount=function() return 1 end
    v.GetAbilityByIndex=function() return {IsNull=function() return false end,GetAbilityName=function() return "future_hidden_buff" end} end end
u=birth("dwarf_white_rifle");edit_birth=nil
assert(u.modifiers.modifier_survival_hero_attack_range and u.modifiers.modifier_debug_attack_cap)
-- Any unknown or throwing birth API retains the exact old range modifier.
for _,edit in ipairs({
    function(v) v.base_range=v.base_range+1 end,
    function(v) v.Script_GetAttackRange=function() error("native getter failed") end end,
    function(v) v.Script_GetAttackRange=function() return "600" end end,
    function(v) v.Script_GetAttackRange=function() return 0/0 end end,
    function(v) v.GetUnitName=function() return "foreign" end end,
    function(v) v.GetAttackCapability=function() return 0 end end,
    function(v) v.FindAllModifiers=function() error("native mods failed") end end,
    function(v) v.modifiers.modifier_external_range={} end,
    function(v) v.GetAbilityByIndex=function() error("native slot failed") end;v.GetAbilityCount=function() return 1 end end,
    function(v) v.GetAbilityByIndex=function() return false end;v.GetAbilityCount=function() return 1 end end,
    function(v) v.range_bonus=100 end,
}) do
    enable();edit_birth=edit;u=birth("dwarf_white_rifle");edit_birth=nil
    assert(u.modifiers.modifier_survival_hero_attack_range and u.survival_wave_native_base_range==false)
    assert(range.snapshot().omitted==0)
end
enable();edit_visual=function(v) v.range_bonus=100 end;u=birth("dwarf_white_rifle");edit_visual=nil
assert(u.modifiers.modifier_survival_hero_attack_range and u:Script_GetAttackRange()==228)
assert(range.snapshot().birth_proven==1 and range.snapshot().late_fallback==1 and range.snapshot().omitted==0)
enable();edit_visual=function(v) v.modifiers.unknown_native={} end;u=birth("dwarf_white_rifle");edit_visual=nil
assert(u.modifiers.modifier_survival_hero_attack_range and range.snapshot().late_fallback==1)
-- Retired alias failures cannot affect the now-original-only birth path.
enable();creation_failure=function(name) return name:match("^npc_survival_range_") end
local spawned,pending,failed=state.spawned,state.pending,state.failed_spawn
u=birth("dwarf_white_rifle");creation_failure=nil
assert(state.spawned==spawned+1 and state.pending==pending-1 and state.failed_spawn==failed)
assert(attempts[#attempts]==definitions.by_id.dwarf_white_rifle.unit_name)
assert(not u.modifiers.modifier_survival_hero_attack_range and range.snapshot().creation_fallback==0)
enable();creation_failure=function(name) if name:match("^npc_survival_range_") then error("native alias registration missing") end end
spawned,pending,failed=state.spawned,state.pending,state.failed_spawn
u=birth("dwarf_white_rifle");creation_failure=nil
assert(state.spawned==spawned+1 and state.pending==pending-1 and state.failed_spawn==failed)
assert(u.name==definitions.by_id.dwarf_white_rifle.unit_name)
assert(not u.modifiers.modifier_survival_hero_attack_range and range.snapshot().creation_fallback==0)
-- Corrupt/missing native source metadata cannot authorize an exemption.
local rifle=definitions.by_id.dwarf_white_rifle
local alias_name=manifest.by_id.dwarf_white_rifle.unit_name
local original_capability=kv[alias_name].AttackCapabilities
enable();kv[alias_name].AttackCapabilities="DOTA_UNIT_CAP_RANGED_ATTACK"
local e,t=range.select_for_formal_spawn(rifle)
assert(e==rifle and t==nil and range.snapshot().rejections.source_kv_unknown==1)
kv[alias_name].AttackCapabilities=original_capability
local saved_alias=kv[alias_name]
enable();kv[alias_name]=nil;e,t=range.select_for_formal_spawn(rifle)
assert(e==rifle and t==nil);kv[alias_name]=saved_alias
local entry=manifest.by_id.dwarf_white_rifle;local saved_reach=entry.attack_range
enable();entry.attack_range=601;e,t=range.select_for_formal_spawn(rifle)
assert(e==rifle and t==nil and range.snapshot().rejections.manifest_unknown==1);entry.attack_range=saved_reach
-- Engine unit precache failure is bounded and never blocks normal spawning.
local precache=PrecacheUnitByNameAsync
enable(false);PrecacheUnitByNameAsync=function() error("native unit precache failed") end
assert(range.prepare_aliases());assert(range.snapshot().failed_aliases==0 and range.snapshot().pending_aliases==0)
u=birth("dwarf_white_rifle");assert(not u.modifiers.modifier_survival_hero_attack_range)
PrecacheUnitByNameAsync=precache
-- Closed config manifest, reused ticket/unit, shared name and unexpected policy.
enable();local d=definitions.by_id.humanoid_white_melee
local duplicate={unit_name=d.unit_name};definitions.rows[#definitions.rows+1]=duplicate
range.set_probe_enabled(false);assert(range.set_probe_enabled(true))
local effective,ticket=range.select_for_formal_spawn(d)
assert(effective==d and ticket==nil and range.snapshot().rejections.shared_native_name==1)
definitions.rows[#definitions.rows]=nil
for _,edit in ipairs({function() d.attack_range=129 end,function() d.passive_skill_ids={"future_native"} end,
    function() d.native_attack_speed_policy="future" end}) do
    local saved_range,saved_skills,saved_policy=d.attack_range,d.passive_skill_ids,d.native_attack_speed_policy
    enable();edit();effective,ticket=range.select_for_formal_spawn(d);assert(effective==d and ticket==nil)
    d.attack_range,d.passive_skill_ids,d.native_attack_speed_policy=saved_range,saved_skills,saved_policy
end
enable();effective,ticket=range.select_for_formal_spawn(d);u=create(effective.unit_name)
assert(not range.can_omit_override(u,effective,ticket),"unbound old unit was accepted as fresh")
assert(range.bind_birth(u,ticket,true));assert(range.can_omit_override(u,effective,ticket))
local foreign=create(effective.unit_name)
assert(not range.can_omit_override(foreign,effective,ticket),"ticket reused across native units")
bus.reset();assert(not range.finalize(u,effective,ticket))
-- Stale async callbacks and world/guard/Tools changes never promote readiness.
enable(false);range.prepare_aliases();local stale=callbacks
assert(range.set_probe_enabled(false));assert(range.set_probe_enabled(true))
for _,fn in ipairs(stale) do fn() end;assert(range.snapshot().ready_aliases==0)
local original_world=world;world={};assert(not range.enabled());world=original_world
_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION={mode=world};assert(not range.enabled())
enable(false);tools=false;assert(not range.enabled());tools=true
server=false;assert(not range.enabled());server=true
map="other_map";assert(not range.enabled());map="template_map"
-- Challenge birth with probe on remains the original name and old setter path.
-- The fixture exposes a forbidden setter, so temporarily remove it as native does.
enable();local original_create=env.CreateUnitByName
env.CreateUnitByName=function(name) local v=original_create(name);v.SetAttackRange=nil;return v end
set(wave.spawn_challenge_monster,"wave_channels",{[0]={marker=marker}})
local old_omits=range.snapshot().omitted
local challenge=assert(wave.spawn_challenge_monster({health=100,attack=2},definitions.by_id.dwarf_white_rifle,0))
assert(challenge.name==definitions.by_id.dwarf_white_rifle.unit_name)
assert(not challenge.modifiers.modifier_survival_hero_attack_range and challenge.base_range==128)
assert(challenge.survival_wave_native_base_range==nil and range.snapshot().omitted==old_omits)
range.set_probe_enabled(false)
assert(precache_arity_failures==0,"native arity failed during actual alias preparation")
print("WAVE_NATIVE_RANGE_REAL_BIRTH_PASS: 44 melee originals, zero aliases/precache; strict native getters, name/cap/ability/mod scope; range/cap/contact/buff/stat parity; closed manifest/shared/new sources fallback; stale tickets/world; challenge unchanged; native registration/frames UNVERIFIED")
