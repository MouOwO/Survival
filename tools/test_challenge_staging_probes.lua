-- Real staging, custom-bar, practice-AI and challenge checkout/cleanup modules.
-- Native scheduler/state replication are mocked; no game or console is used.
package.path = "scripts/vscripts/?.lua;" .. package.path
class = function(value) value.__index = value; return value end
LinkLuaModifier = function() end
LUA_MODIFIER_MOTION_NONE, MODIFIER_ATTRIBUTE_PERMANENT = 0, 1
DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS, DOTA_TEAM_NEUTRALS = 2, 3, 4
for number, name in ipairs({"INVULNERABLE", "STUNNED", "DISARMED", "SILENCED", "MUTED", "ROOTED",
    "COMMAND_RESTRICTED", "OUT_OF_GAME", "NO_HEALTH_BAR"}) do _G["MODIFIER_STATE_" .. name] = number end
local server, tools_mode, map_name, world = true, true, "template_map", {}
IsServer = function() return server end
IsInToolsMode = function() return tools_mode end
GetMapName = function() return map_name end
GameRules = {GetGameModeEntity = function() return world end, GetGameTime = function() return 10 end}
PlayerResource = {GetSelectedHeroEntity=function() end}
Vector = function(x, y, z) return {x=x, y=y, z=z} end
local guard = {mode=world}
_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION = guard
local tables, writes, native_events, entities, next_id = {}, 0, {}, {}, 0
CustomNetTables = {SetTableValue = function(_, _, key, value) tables[key]=value; writes=writes+1 end}
ListenToGameEvent = function(name, fn) native_events[name]=fn end
EntIndexToHScript = function(id) return entities[id] end
local schedule = {cancel=function() end, after=function() end, every=function() end}
package.loaded["core/scheduler"] = schedule
package.loaded["combat/endless_stat_projection"] = {for_ui=function(_, n) return n end}
package.loaded["systems/tower_laser_health_prediction"] = {snapshot=function() return {}, 0 end}
local staging = require("modifiers/modifier_challenge_11_staging")
local health_bar = require("modifiers/modifier_single_health_bar")
local practice = require("modifiers/modifier_practice_monster_ai")

local function unit(owner, number)
    next_id=next_id+1
    local value={index=next_id, name=string.format("npc_survival_named_ten_sin_%02d", number or 1), alive=true,
        survival_challenge_11_staged=true, survival_challenge_11_staged_owner=owner,
        modifiers={}, health=5000, maximum=5000, health_reads=0, model="confirmed_model", wearables={"head","weapon"}}
    entities[next_id]=value
    function value:IsNull() return self.removed==true end
    function value:IsAlive() return self.alive end
    function value:entindex() return self.index end
    function value:IsRealHero() return self.real_hero==true end
    function value:IsBaseNPC() return true end
    function value:GetClassname() return self.classname or "npc_dota_creature" end
    function value:GetUnitName() return self.name end
    function value:GetTeamNumber() return self.team or DOTA_TEAM_BADGUYS end
    function value:GetHealth() self.health_reads=self.health_reads+1; return self.health end
    function value:GetMaxHealth() return self.maximum end
    function value:SetForceAttackTarget(target) self.force_target=target; self.force_calls=(self.force_calls or 0)+1 end
    function value:HasModifier(name) return self.modifiers[name]~=nil end
    function value:FindModifierByName(name) return self.modifiers[name] end
    function value:RemoveModifierByName(name)
        local modifier=self.modifiers[name]
        self.modifiers[name]=nil
        if modifier and modifier.OnDestroy then modifier:OnDestroy() end
    end
    function value:AddNewModifier(_, _, name, params)
        local definition=assert(({modifier_single_health_bar=health_bar, modifier_challenge_11_staging=staging,
            modifier_practice_monster_ai=practice})[name], "unexpected native modifier: " .. name)
        local modifier=setmetatable({parent=self, stack=0, intervals={}, stack_writes=0}, {__index=definition})
        function modifier:GetParent() return self.parent end
        function modifier:IsNull() return false end
        function modifier:SetStackCount(count) self.stack=count; self.stack_writes=self.stack_writes+1 end
        function modifier:GetStackCount() return self.stack end
        function modifier:StartIntervalThink(interval) self.interval=interval; self.intervals[#self.intervals+1]=interval end
        self.modifiers[name]=modifier
        if modifier.OnCreated then modifier:OnCreated(params or {}) end
        return modifier
    end
    return value
end
package.loaded["core/modifier_registry"] = {ensure=function(u, name, params) return u:AddNewModifier(u,nil,name,params) end}
local bar_service=require("systems/unit_health_bar_service")
bar_service.init()
local function attach_bar(u)
    native_events.npc_spawned({entindex=u:entindex()})
    return assert(u.modifiers.modifier_single_health_bar)
end
local function attach_stage(u) return u:AddNewModifier(u,nil,"modifier_challenge_11_staging",{}) end
local function probe(out_of_game, pause_health_bar)
    _G.SURVIVAL_CHALLENGE_STAGING_PROBE={mode=world, guard=guard, out_of_game=out_of_game, pause_health_bar=pause_health_bar}
end
local function ordinary_states(modifier, out_of_game)
    local s=modifier:CheckState()
    for _, key in ipairs({"INVULNERABLE","DISARMED","SILENCED","MUTED","ROOTED","COMMAND_RESTRICTED"}) do
        assert(s[_G["MODIFIER_STATE_"..key]], "legacy state lost: "..key)
    end
    assert(s[MODIFIER_STATE_STUNNED]~=true, "display must keep its idle pose")
    assert((s[MODIFIER_STATE_OUT_OF_GAME]==true)==out_of_game)
end

-- Default off does not sample flags, change stacks or suspend the normal sampler.
_G.SURVIVAL_CHALLENGE_STAGING_PROBE=nil
local normal=unit(0); local normal_bar=attach_bar(normal); local normal_stage=attach_stage(normal)
assert(normal_bar.interval==0.1 and normal_stage.stack_writes==0)
assert(normal_stage.survival_staging_probe_sampled==nil and normal_bar.health_bar_staging_probe_sampled==nil)
ordinary_states(normal_stage,false)
for _, invalid in ipairs({"wrong_world","wrong_guard","wrong_map","not_tools","hero","wrong_class","wrong_name","wrong_team","not_formal","fractional_owner","unknown_api"}) do
    probe(true,true)
    local u=unit(0)
    if invalid=="wrong_world" then _G.SURVIVAL_CHALLENGE_STAGING_PROBE.mode={}
    elseif invalid=="wrong_guard" then _G.SURVIVAL_CHALLENGE_STAGING_PROBE.guard={}
    elseif invalid=="wrong_map" then map_name="other_map"
    elseif invalid=="not_tools" then tools_mode=false
    elseif invalid=="hero" then u.real_hero=true
    elseif invalid=="wrong_class" then u.classname="npc_dota_hero"
    elseif invalid=="wrong_name" then u.name="npc_survival_practice_monster"
    elseif invalid=="wrong_team" then u.team=DOTA_TEAM_GOODGUYS
    elseif invalid=="not_formal" then u.survival_challenge_11_staged=nil
    elseif invalid=="fractional_owner" then u.survival_challenge_11_staged_owner=0.5
    elseif invalid=="unknown_api" then u.GetClassname=false end
    local m=attach_stage(u)
    assert(m.survival_staging_probe_sampled==nil and m.stack_writes==0, invalid.." must stay legacy")
    ordinary_states(m,false)
    map_name,tools_mode="template_map",true
end

-- Each candidate alone is independent; replicated stack is sufficient in the client VM.
probe(true,false)
local oog=unit(0); local oog_bar=attach_bar(oog); local oog_stage=attach_stage(oog)
assert(oog_stage.stack==1 and oog_bar.interval==0.1 and oog_bar.health_bar_staging_paused==nil)
ordinary_states(oog_stage,true)
server=false
local client=setmetatable({GetStackCount=function() return oog_stage.stack end}, {__index=staging})
ordinary_states(client,true)
client:OnCreated(); client:OnDestroy()
server=true
_G.SURVIVAL_CHALLENGE_STAGING_PROBE=nil
ordinary_states(oog_stage,true) -- Creation-time decision remains locked.
probe(false,true)
local early=unit(0); local early_bar=attach_bar(early); local early_stage=attach_stage(early)
ordinary_states(early_stage,false)
assert(early_stage.stack==2 and early_bar.interval==-1 and tables["unit_"..early.index].removed==1)
local early_reads, early_writes=early.health_reads,writes
for _=1,100 do early_bar:OnIntervalThink() end -- Even an already queued native callback cannot sample.
assert(early.health_reads==early_reads and writes==early_writes)
local late=unit(1); local late_stage=attach_stage(late); local late_bar=attach_bar(late)
assert(late_bar.interval==-1 and #late_bar.intervals==1 and tables["unit_"..late.index].removed==1)
ordinary_states(late_stage,false)

-- Real checkout and defeat cleanup functions, reached from the public module.
for _, name in ipairs({"hero_return_home_service","destination_validation_service","challenge_monster_visual_service",
    "monster_hero_visual_service","monster_hull_scale","monster_navigation_policy","wave_monster_collision"}) do
    package.loaded["systems/"..name]={clear=function() end, apply=function() end}
end
local bus, events=require("core/event_bus"),require("core/events")
local challenge=require("systems/challenge_session_service")
local function upvalue(fn, wanted)
    for i=1,100 do local name,value=debug.getupvalue(fn,i); if not name then break end; if name==wanted then return value end end
    error("missing real module upvalue "..wanted)
end
challenge.init()
local prepared=upvalue(challenge.init,"challenge_11_prepared_by_player")
local meta=upvalue(challenge.init,"monster_meta")
local fill_initial=upvalue(challenge.start,"fill_initial")
local activate=upvalue(fill_initial,"activate_prepared_challenge_11")
local fill_current=upvalue(fill_initial,"fill_current")
local activate_next=upvalue(fill_current,"activate_prepared_member")
local all, sessions={},{}
probe(true,true)
for owner=0,3 do
    local staged={monsters={}, prepared_monsters={}}
    local members={}
    all[owner]={}
    for number=1,10 do
        local u=unit(owner,number)
        local bar
        if number%2==0 then bar=attach_bar(u) end
        local m=attach_stage(u)
        if not bar then bar=attach_bar(u) end
        u:AddNewModifier(u,nil,"modifier_practice_monster_ai",{home_x=1,home_y=2,home_z=3})
        assert(u.modifiers.modifier_practice_monster_ai.interval==nil, "staged practice AI must stay suspended")
        assert(bar.interval==-1 and m.stack==3)
        local member={member_id="owner"..owner.."_member"..number}
        members[number]=member; all[owner][number]=u
        meta[u.index]={player_id=owner,member=member}
        staged.prepared_monsters[u.index]=u
    end
    prepared[owner]=staged
    sessions[owner]={player_id=owner,team=DOTA_TEAM_GOODGUYS,encounter_id="encounter_challenge_11",
        members={members[1]},monsters={},monster_count=0}
    local initial_writes=writes
    assert(activate(sessions[owner]))
    local first=all[owner][1]; local bar=first.modifiers.modifier_single_health_bar
    assert(first.survival_challenge_11_staged==nil and not first:HasModifier("modifier_challenge_11_staging"))
    assert(bar.interval==0.1 and tables["unit_"..first.index].health==5000 and writes==initial_writes+1)
    assert(first.modifiers.modifier_practice_monster_ai.interval==0.5 and first.force_calls==1)
    local second=all[owner][2]
    initial_writes=writes
    assert(activate_next(sessions[owner], members[2]))
    assert(second.modifiers.modifier_single_health_bar.interval==0.1 and writes==initial_writes+1)
    for _,u in ipairs(all[owner]) do
        assert(u.model=="confirmed_model" and #u.wearables==2 and not u.removed)
        assert(u.health==5000 and u.maximum==5000, "checkout must not alter combat stats")
    end
end
local health_reads_before=0
for _,group in pairs(all) do for number=3,10 do health_reads_before=health_reads_before+group[number].health_reads end end
local writes_before=writes
for _=1,100 do for _,group in pairs(all) do for number=3,10 do group[number].modifiers.modifier_single_health_bar:OnIntervalThink() end end end
local health_reads_after=0
for _,group in pairs(all) do for number=3,10 do health_reads_after=health_reads_after+group[number].health_reads end end
assert(health_reads_before==health_reads_after and writes_before==writes, "idle staged pool must not resume polling or publish spam")

-- Native Remove callbacks can report an alive parent. Real cleanup sets its
-- teardown marker first, preventing staged OnDestroy from publishing a new row.
UTIL_Remove=function(u)
    assert(u.survival_challenge_teardown==true, "formal teardown marker must precede native removal")
    assert(u.alive, "exercise the native alive-during-removal race")
    u:RemoveModifierByName("modifier_challenge_11_staging")
    local bar=u.modifiers.modifier_single_health_bar
    if bar then bar:OnDestroy() end
    u.removed=true
end
local live_sessions=upvalue(challenge.init,"sessions")
for owner=0,3 do
    sessions[owner].status="active"
    sessions[owner].encounter={display_name="ten sins"}
    live_sessions[owner]={encounter_challenge_11=sessions[owner]}
end
bus.emit(events.PLAYER_DISCONNECTED,{player_id=0,defeat_cleanup=true})
for _,u in ipairs(all[0]) do
    assert(u.removed and tables["unit_"..u.index].removed==1)
    local bar=u.modifiers.modifier_single_health_bar
    local previous=writes
    bar:publish_state(); bar:OnDestroy()
    assert(writes==previous, "removed parent cannot resurrect its custom row")
end
for owner=1,3 do for _,u in ipairs(all[owner]) do assert(not u.removed, "defeat cleanup cannot touch another owner") end end

-- Death and old-world removal also refuse a delayed resume.
for _,reason in ipairs({"dead","new_world"}) do
    probe(false,true)
    local u=unit(0); local m=attach_stage(u); local bar=attach_bar(u); local prior=writes
    if reason=="dead" then u.alive=false else world={} end
    u:RemoveModifierByName("modifier_challenge_11_staging")
    assert(bar.interval==-1 and tables["unit_"..u.index].removed==1 and writes==prior, reason.." must not republish")
    world=guard.mode
end
print("CHALLENGE_STAGING_PROBES_PASS: default-off/strict scope, independent replicated state, late attach with no polling, four-owner real checkout/next-stage, retained identity/stats/idle pose, alive-removal/defeat/death/world race")
