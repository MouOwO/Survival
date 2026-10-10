-- Run from the addon root. Optional first argument selects pre-fix building_system.lua.
-- Execute production helper/callback slices; native handles and scheduling are mocked.
package.path = 'scripts/vscripts/?.lua;' .. package.path
local function read(path)
    local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return (s:gsub('\r\n','\n'))
end
local source=read(arg[1] or 'scripts/vscripts/systems/building_system.lua')
local function between(s,first,last)
    local a=assert(s:find(first,1,true),'missing source anchor '..first)
    local b=assert(s:find(last,a+#first,true),'missing end anchor '..last)
    return s:sub(a,b-1)
end
local function compile(code,environment,label)
    local f=assert(loadstring(code,'@'..label));setfenv(f,environment);return f()
end
local bus=require('core/event_bus');local events=require('core/events')
local sync=require('systems/research_lab_ability_sync')
local runtime_builder=require('ui/ability_runtime_builder')
local research=require('config/research_technology_config')
local config=require('config/buildings_config')
local arrows=require('config/generated/arrow_tower_base')
PlayerResource={GetTeam=function() return 2 end}
local env=setmetatable({print=function() end},{__index=_G})
env.arrow_data=function(level) for _,row in ipairs(arrows.rows) do if row.level==level then return row end end end
local add=compile(between(source,'local function add_ability(','local function completion_level_data(')
    ..'\nreturn add_building_abilities',env,'production_building_ability_helpers')
env.add_building_abilities=add
local runtime_source=read('scripts/vscripts/ui/ability_runtime_service.lua')
local activate=compile(between(runtime_source,'local function runtime_can_activate(','local function valid_entity(')
    ..'\nreturn sync_ability_active',env,'production_runtime_activation')
local pending,published={},{}
env.scheduler={after=function(delay,callback,key)
    assert(delay==0.1 and key=='activate_building_abilities_'..env.unit:entindex())
    pending[#pending+1]=callback
end}
env.valid_entity=function(u) return u and not u:IsNull() end
-- The actual public_state helper is evaluated too; unrelated tower metadata is inert.
env.tower_routes={current=function() return nil end}
env.tower_population_occupied=function() return 0 end
env.tower_class_counts=function() return {} end
env.state_display_name=function(s) return s.building_id end
env.public_state=compile(between(source,'local function public_state(','local function grid_position(')
    ..'\nreturn public_state',env,'production_public_building_state')
env.event_bus=bus;env.events=events
local callback_start=assert(source:find('        scheduler.after(0.1, function()',1,true))
local callback_end=assert(source:find('        end, "activate_building_abilities_" .. tostring(unit:entindex()))',callback_start,true))
local callback=source:sub(callback_start,callback_end+#'        end, "activate_building_abilities_" .. tostring(unit:entindex()))'-1)
local serial,checks=1000,0
local function unit()
    serial=serial+1
    local u={id=serial,abilities={},attempts=0,writes=0,fail={},alive=true}
    local function live(self) assert(not self.null,'expired native handle touched') end
    function u:IsNull() return self.null==true end
    function u:IsAlive() live(self);return self.alive end
    function u:entindex() live(self);return self.id end
    function u:GetMaxHealth() live(self);return 1000 end
    function u:GetPhysicalArmorBaseValue() live(self);return 0 end
    function u:FindAbilityByName(name) live(self);return self.abilities[name] end
    function u:RemoveAbility(name) live(self);self.abilities[name]=nil end
    function u:AddAbility(name)
        live(self);self.attempts=self.attempts+1
        if self.fail[name] then return nil end
        local a={name=name,level=0,hidden=false,active=true,index=0,writes=0}
        local function write(self,key,value) self[key]=value;self.writes=self.writes+1;u.writes=u.writes+1 end
        function a:SetLevel(v) write(self,'level',v) end
        function a:SetHidden(v) write(self,'hidden',v) end
        function a:SetActivated(v) write(self,'active',v) end
        function a:SetAbilityIndex(v) write(self,'index',v) end
        function a:GetLevel() return self.level end
        function a:IsHidden() return self.hidden end
        function a:IsActivated() return self.active end
        function a:GetAbilityIndex() return self.index end
        function a:GetAbilityName() return self.name end
        self.abilities[name]=a;return a
    end
    return u
end
local function project(state)
    if state.building_id~='building_research_lab' and state.building_id~='building_advanced_research_lab' then return end
    local levels=state.test_levels or {};local rank=state.test_rank or 10
    sync.sync(state.unit,state.building_id,levels,{},rank)
    state.runtimes={}
    for name,a in pairs(state.unit.abilities) do
        local runtime=runtime_builder.build(name,{player_id=0,building_id=state.building_id,
            unit=state.unit,research_levels=levels,research_transaction={},reincarnation_level=rank},
            {wood=1e12,gold=1e12})
        if runtime then activate(a,runtime,state.building_id=='building_advanced_research_lab');state.runtimes[name]=runtime end
    end
end
local function fixture(id,levels,rank)
    pending,published={},{};bus.reset()
    local u=unit();local state={unit=u,definition=config[id],building_id=id,entindex=u.id,
        player_id=0,team=2,level=1,cleaned=false,test_levels=levels,test_rank=rank}
    assert(state.definition,id)
    bus.subscribe(events.BUILDING_CHANGED,function(payload)
        assert(payload.unit==u and payload.entindex==u.id and payload.building_id==id)
        assert(payload.reason=='ability_recovery');published[#published+1]=payload;project(state)
    end)
    env.unit=u;env.state=state;env.check={definition=state.definition}
    local function schedule() compile(callback,env,'production_delayed_ability_callback');return pending[#pending] end
    return u,state,schedule
end
local T='ability_research_advanced_lumberjack_efficiency'
local function unlocked(group)
    local definition=assert(research.by_legacy_group[group]);local before=assert(research.by_id[definition.prerequisite.tech_id])
    return {[before.legacy_group]=definition.prerequisite.required_level}
end
for _,case in ipairs({
    {'building_research_lab',T,{},false},
    {'building_research_lab',T,unlocked('advanced_lumberjack_efficiency'),true},
    {'building_advanced_research_lab','ability_research_ars_03',{},false},
    {'building_advanced_research_lab','ability_research_ars_03',unlocked('researcher_super_wall_health'),true},
}) do
    local u,s,schedule=fixture(case[1],case[3],10)
    add(u,s.definition,false);add(u,s.definition,true);project(s)
    local a=assert(u.abilities[case[2]]);local native=a.active;local writes=u.writes
    assert((s.runtimes[case[2]].prerequisite_met==1)==case[4],'real config lock fixture mismatch')
    assert(native==(case[1]=='building_advanced_research_lab' or case[4]),'shared native availability contract')
    schedule()()
    assert(a.active==native,'delayed retry reactivated prerequisite-locked normal T')
    assert(u.writes==writes and #published==0,'existing research received delayed state writes or publication')
    checks=checks+1
end
-- Delayed repair must preserve arbitrary existing native hidden/level/activation state.
do
    local u,s,schedule=fixture('building_research_lab',{},10);add(u,s.definition,true)
    local a=u.abilities[T];a.level=3;a.hidden=true;a.active=false
    local writes=u.writes;schedule()()
    assert(a.level==3 and a.hidden and not a.active and u.writes==writes and #published==0)
    checks=checks+1
end
-- Recover a truly missing normal T, then synchronously publish its real locked state.
for _,id in ipairs({'building_research_lab','building_advanced_research_lab'}) do
    local name=id=='building_research_lab' and T or 'ability_research_ars_03'
    local u,s,schedule=fixture(id,{},10);add(u,s.definition,true);project(s)
    u:RemoveAbility(name);u.fail[name]=true
    schedule()();assert(not u.abilities[name] and #published==0,'failed creation published recovery')
    u.fail[name]=nil;schedule()()
    assert(u.abilities[name] and #published==1,'successful missing ability retry must publish once')
    assert(s.runtimes[name].prerequisite_met==0,'new ability runtime bypassed prerequisite')
    assert(u.abilities[name].active==(id=='building_advanced_research_lab'),'recovery native gate changed')
    local writes=u.writes;schedule()();assert(#published==1 and u.writes==writes,'repeat retry not idempotent')
    checks=checks+1
end
-- Finished normal research chains intentionally remove old abilities. Recovery publication
-- must run the authoritative sync before exposing the accidentally recreated old stage.
do
    local group='lumberjack_speed';local levels={[group]=research.by_legacy_group[group].max_level}
    local u,s,schedule=fixture('building_research_lab',levels,10)
    add(u,s.definition,true);project(s)
    assert(not u.abilities.ability_research_lumberjack_speed and u.abilities.ability_research_advanced_lumberjack_speed)
    schedule()();assert(#published==1 and not u.abilities.ability_research_lumberjack_speed)
    assert(u.abilities.ability_research_advanced_lumberjack_speed,'retry destroyed upgraded chain')
    checks=checks+1
end
for _,condition in ipairs({'dead','cleaned','expired'}) do
    local u,s,schedule=fixture('building_research_lab',{},10);local run=schedule()
    if condition=='dead' then u.alive=false elseif condition=='cleaned' then s.cleaned=true else u.null=true end
    run();assert(u.attempts==0 and u.writes==0 and #published==0,'inactive lifecycle performed repair: '..condition)
    checks=checks+1
end
-- Arrow towers must still get row.active_skill_ids, and native training remains hidden.
do
    local u,s,schedule=fixture('arrow_tower');add(u,s.definition,false)
    local row=assert(env.arrow_data(1));for _,name in ipairs(row.active_skill_ids) do assert(u.abilities[name] and not u.abilities[name].active) end
    add(u,s.definition,true);local writes=u.writes;schedule()();assert(u.writes==writes and #published==0)
    local name=assert(row.active_skill_ids[1]);u:RemoveAbility(name);schedule()();assert(u.abilities[name].active and #published==1)
    checks=checks+1
end
do
    local u=unit();local d={id='test_training',abilities={'ability_train_lumberjack'}}
    add(u,d,false);local a=u.abilities.ability_train_lumberjack;assert(a.hidden and not a.active and a.level==1)
    add(u,d,true);assert(a.hidden and a.active);local writes=u.writes
    add(u,d,true,true);assert(a.hidden and a.active and u.writes==writes)
    u:RemoveAbility(a.name);assert(add(u,d,true,true));assert(u.abilities[a.name].hidden)
    checks=checks+1
end
print('BUILDING_ABILITY_RECOVERY_PASS '..checks..' cases: real helper/callback/runtime gates, missing creation, lifecycle, towers, training')