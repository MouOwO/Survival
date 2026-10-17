-- Wrapper lifecycle/ownership tests only. Full gameplay consumers are covered
-- separately and actual rendered FPS must come from the running engine.
package.path='scripts/vscripts/?.lua;'..package.path
local wrapper=require('tests/manual_four_player_live_perf')
assert(not _G.SURVIVAL_FOUR_PLAYER_LIVE_PERF,'require must remain inert')
local mode,clock,session={},0,'four_player_live_fixture_session'
local admitted,tools,hook_installs=true,true,0
DOTA_TEAM_GOODGUYS,DOTA_GAMERULES_STATE_GAME_IN_PROGRESS=2,10
LUA_MODIFIER_MOTION_NONE,MODIFIER_PROPERTY_MIN_HEALTH=0,1
class=function(base) return base end
LinkLuaModifier=function(name,path) assert(name=='modifier_manual_four_player_live_perf_tower' and path=='tests/'..name) end
IsServer=function() return true end;IsInToolsMode=function() return tools end
GetMapName=function() return 'template_map' end
GameRules={GetGameModeEntity=function() return mode end,GetGameTime=function() return clock end,State_Get=function() return 10 end}
local meta={}
meta.__add=function(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
meta.__sub=function(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
meta.__mul=function(a,b) return Vector(a.x*b,a.y*b,a.z*b) end
meta.__index={Length2D=function(a) return math.sqrt(a.x*a.x+a.y*a.y) end,
    Normalized=function(a) local l=math.sqrt(a.x*a.x+a.y*a.y);return Vector(a.x/l,a.y/l,0) end}
Vector=function(x,y,z) return setmetatable({x=x,y=y,z=z or 0},meta) end
local serial=1000
local function unit(id,position)
    serial=serial+1
    local u={id=id,index=serial,position=position,modifiers={}}
    function u:IsNull() return false end;function u:IsAlive() return self.alive~=false end
    function u:GetPlayerOwnerID() return self.native_id or self.id end;function u:entindex() return self.index end
    function u:GetAbsOrigin() return self.position end;function u:GetHullRadius() return 32 end
    function u:GetHealth() return 1000 end;function u:GetMaxHealth() return 1000 end
    function u:SetHealth() error('Floor must not write health') end
    function u:SetMaxHealth() error('Floor must not write max health') end
    function u:SetBaseAttackTime() error('Floor must not write attack speed') end
    function u:SetPhysicalArmorBaseValue() error('Floor must not write armor') end
    function u:AddNewModifier(_,_,name)
        local m=setmetatable({parent=self,stack=0},{__index=_G[name] or {}})
        function m:IsNull() return self.destroyed==true end
        function m:GetParent() return self.parent end
        function m:GetStackCount() return self.stack end
        function m:SetStackCount(value) self.stack=value end
        function m:Destroy() self.destroyed=true;if self.parent.modifiers[name]==self then self.parent.modifiers[name]=nil end end
        self.modifiers[name]=m
        if m.OnCreated then m:OnCreated() end
        return m
    end
    return u
end
local builders,registry,guards={}, {},{}
for id=0,3 do builders[id]=unit(id,Vector(id*3000,4000,384));registry[id]={} end
PlayerResource={IsValidPlayerID=function(_,id) return builders[id]~=nil end,
    GetPlayer=function(_,id) return builders[id] end,GetTeam=function() return 2 end,
    GetSteamAccountID=function(_,id) return id==0 and 555 or 0 end,IsFakeClient=function(_,id) return id~=0 end}
FindClearSpaceForUnit=function(u,p) u.position=p end
local events=require('core/events')
local emitted,queued,spawns={},{},{}
local function register(id,kind,p)
    local u=unit(id,p);u.survival_building_id=kind
    local row={player_id=id,building_id=kind,unit=u,constructing=false}
    registry[id][#registry[id]+1]=row
    return u
end
local event_bus={emit=function(name,payload) emitted[#emitted+1]={name=name,payload=payload} end}
event_bus.request=function(name,p)
    local id=p and p.player_id
    if name==events.BUILDING_LIST_REQUEST then return {buildings=registry[id]} end
    if name==events.WORKER_LIST_REQUEST then return {} end
    if name==events.BUILDER_GET_REQUEST then return {ok=true,player_id=id,builder=builders[id]} end
    if name==events.BUILDING_QUERY_REQUEST then
        for _,list in pairs(registry) do for _,row in ipairs(list) do if row.unit:entindex()==p.entindex then return row end end end
    elseif name==events.RESOURCE_GET_REQUEST then return {wood=1000000000,gold=1000000000} end
    if name==events.BUILD_CAN_PLACE_REQUEST then return {ok=true,grid={world_position=p.position}} end
    if name==events.BUILD_REQUEST then
        assert(p.caster==builders[id] and p.building_id=='wall','Wall-only owners must use production wall construction')
        queued[#queued+1]=p
        register(id,'wall',p.position);return {ok=true}
    end
    if name==events.RESEARCH_STATE_GET_REQUEST then return {levels={}} end
    return {}
end
package.loaded['core/event_bus']=event_bus
local scheduled
package.loaded['core/scheduler']={every=function(_,callback) scheduled=callback end,cancel=function() scheduled=nil end}
package.loaded['systems/startup_loading_service']={is_gameplay_ready=function() return admitted end}
package.loaded['systems/match_setup_service']={get_mode=function() return 'standard' end,get_session_id=function() return session end}
package.loaded['systems/player_context_service']={is_owned_by=function(id,u) return id==(u.context_id or u.id) end}
package.loaded['systems/forbidden_region_service']={validate_hero_position=function() return true end}
package.loaded['systems/war3_armor_target']={apply=function() end}
package.loaded['systems/wave_system']={debug_spawn_wave_for_players=function(number,ids)
    spawns[#spawns+1]={number=number,ids=ids};return true
end}
local originals={}
local human={account_id='real_human_untouched',revision=9,save={gameplay_stats={map_level=77},content_inventory={rare=42}}}
local profiles={}
profiles.get_profile=function(id) return id==0 and human or {account_id='original_bot_'..id,save={gameplay_stats={map_level=0}}} end
profiles.get_account_profile=profiles.get_profile
profiles.get_progression=function() return {loaded=true} end
profiles.get_content_inventory_count=function(id,key) return id==0 and human.save.content_inventory[key] or 0 end
profiles.is_loading=function() return false end
profiles.load_player=function() return {ok=true} end
profiles.apply_snapshot=function() return {ok=true} end
profiles.apply_incremental=function() return {ok=true} end
for k,v in pairs(profiles) do originals[k]=v end
package.loaded['systems/player_profile_service']=profiles
local ordinary={}
ordinary.map_court_positions=function()
    local c={};for id=0,3 do c[id]={city=Vector(id*3000,4000,384),wall=Vector(id*3000,4600,384)} end;return c
end
ordinary.isolate_writes=function()
    hook_installs=hook_installs+1
    local guard={mode=mode,bots={},wall_targets={},blocked_http=0,blocked_saves=0}
    _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION=guard;guards[#guards+1]=guard;return guard
end
ordinary.admit_bots=function(ids) assert(#ids==4) end
ordinary.select_opening_reward=function() end
ordinary.prepare=function(opts)
    local scene={mode=mode,status='ready',players={},wall_survival={}}
    for _,id in ipairs(opts.player_ids) do
        local courts=opts.region_court_positions
        local wall=register(id,'wall',courts[id].wall)
        register(id,'main_city',courts[id].city)
        local towers={};for n=1,7 do towers[n]=register(id,'arrow_tower',courts[id].city+Vector(n*64,0,0)) end
        scene.players[#scene.players+1]={id=id,towers=towers,units={wall=wall,main_city=registry[id][2].unit}}
    end
    _G.SURVIVAL_REAL_GAME_STRESS=scene;return scene
end
ordinary.stop=function() _G.SURVIVAL_REAL_GAME_STRESS.status='stopped' end
ordinary.hold_tower_attacks=function(enabled) assert(type(enabled)=='boolean');return true end
package.loaded['tests/manual_real_game_stress']=ordinary
tools=false;assert(not pcall(wrapper.prepare,'A'),'Non-Tools entry must reject before hooks');tools=true
admitted=false;assert(not pcall(wrapper.prepare,'A'),'Host admission required');admitted=true
assert(hook_installs==0 and profiles.get_profile==originals.get_profile)
assert(not pcall(wrapper.prepare,'A',{map_levels={[0]=1,[1]=2}}),'Incomplete profile matrix must reject')
assert(hook_installs==0,'Input validation must precede read hooks')
builders[0].native_id=-1
local state=wrapper.prepare('A')
assert(state.options.benchmark_keep_towers_alive==false and state.tower_survival==nil,'Tower lifetime floor is explicitly opt-in')
assert(human.save.gameplay_stats.map_level==77 and human.save.content_inventory.rare==42,'Real human source must stay untouched')
assert(guards[1].bots[0]==nil,'No fallback bot hook may retain the human synthetic profile')
for id=0,3 do
    local p=profiles.get_profile(id);assert(p.account_id=='tools_four_perf_owner_'..id)
    assert(p.save.gameplay_stats.tower_attack_bonus_pct==id*7)
    assert(profiles.get_progression(id).loaded==true)
end
assert(profiles.get_content_inventory_count(0,'rare')==0,'Match inventory read uses the isolated memory baseline')
session='different_match_session';assert(profiles.get_profile(0)==human,'Session change must fall through to the original human read')
session='four_player_live_fixture_session';assert(profiles.get_profile(0).save.gameplay_stats.map_level==1)
scheduled();assert(state.status=='ready')
wrapper.spawn_wave(15);assert(#spawns[1].ids==4 and spawns[1].ids[4]==3)
wrapper.stop();for k,v in pairs(originals) do assert(profiles[k]==v,'stop restores exact reader '..k) end
assert(profiles.get_profile(0)==human and guards[1].four_live_profiles==nil)
local before=hook_installs
assert(not pcall(wrapper.prepare,'B'),'B must reject existing walls rather than move/rebuild')
assert(hook_installs==before,'Dirty B failure must not install profile hooks')
for id=0,3 do registry[id]={} end
_G.SURVIVAL_REAL_GAME_STRESS=nil
builders[0].native_id=1
assert(not pcall(wrapper.prepare,'B',{defender_id=2}),'A different valid native builder ID must reject')
assert(profiles.get_profile==originals.get_profile,'Rejected builder preflight must not install synthetic human read hooks')
for id=0,3 do builders[id].native_id=-1 end
state=wrapper.prepare('B',{defender_id=2,benchmark_keep_towers_alive=true})
assert(scheduled());assert(scheduled()==false)
assert(state.status=='ready' and #queued==3)
local snapshot=wrapper.status()
assert(snapshot.benchmark_keep_towers_alive and snapshot.protected_tower_count==7 and snapshot.tower_min_health_floor==1)
local protected_modifiers={}
for tower,modifier in pairs(state.tower_survival) do
    protected_modifiers[#protected_modifiers+1]=modifier
    assert(modifier:GetMinHealth()==1 and tower:GetHealth()==1000,'Explicit floor retains native health without writing stats')
end
assert(#protected_modifiers==7)
mode={};assert(protected_modifiers[1]:GetMinHealth()==0,'Stale world must immediately lose floor')
mode=state.mode;assert(protected_modifiers[1]:GetMinHealth()==1)
assert(snapshot.owners[1].fake_engine_client==false,'Human native fake-client false must remain explicit')
for _,owner in ipairs(snapshot.owners) do
    assert(owner.counts.wall==1)
    if owner.player_id~=2 then assert(owner.wall_only and #owner.buildings==1 and owner.workers==0)
    else assert(owner.counts.arrow_tower==7) end
end
local wall=registry[0][1].unit
wall.native_id=-1;assert(pcall(wrapper.status),'Native -1 is valid only with matching formal/context ownership')
wall.native_id=1;assert(not pcall(wrapper.status),'A different valid native player ID must reject');wall.native_id=-1
wall.native_id=-2;assert(not pcall(wrapper.status),'Other invalid native IDs must reject');wall.native_id=-1
wall.context_id=1;assert(not pcall(wrapper.status),'Native -1 cannot excuse context ownership mismatch');wall.context_id=nil
registry[0][1].player_id=1;assert(not pcall(wrapper.status),'Native -1 cannot excuse formal row ownership mismatch');registry[0][1].player_id=0
state.status='failed';state.error='old overly strict native-owner audit'
local queued_before=#queued
assert(wrapper.recover_ready().status=='ready' and #queued==queued_before,'Hot recovery must not rebuild or move existing assets')
wall.native_id=1;state.status='failed';assert(not pcall(wrapper.recover_ready),'Recovery must keep native valid-ID cross-ownership blocked');wall.native_id=-1
assert(wrapper.recover_ready().status=='ready')
wrapper.spawn_wave();assert(#spawns==2 and #spawns[2].ids==4)
wrapper.set_keep_towers_alive(false)
for _,modifier in ipairs(protected_modifiers) do assert(modifier:IsNull(),'Disable removes exact modifier handles') end
local dead_tower=state.defender_scene.players[1].towers[1]
dead_tower.alive=false
assert(not pcall(wrapper.set_keep_towers_alive,true),'Explicit protection must refuse dead peak towers rather than revive them')
assert(state.options.benchmark_keep_towers_alive==false and next(state.tower_survival)==nil,'Failed peak validation leaves no floor handles')
dead_tower.alive=true
wrapper.set_keep_towers_alive(true)
protected_modifiers={};for _,modifier in pairs(state.tower_survival) do protected_modifiers[#protected_modifiers+1]=modifier end
local original_request=event_bus.request
local large_totals={tower_attack_bonus_pct=21,diagnostic_payload=string.rep('x',14000)}
local large_key=string.rep('科技',900)
event_bus.request=function(name,payload)
    if name==events.PERMANENT_REWARD_EFFECTS_GET_REQUEST then return {ok=true,totals=large_totals,display_totals=large_totals} end
    if name==events.RESEARCH_STATE_GET_REQUEST then return {levels={[large_key]=1}} end
    return original_request(name,payload)
end
local original_print,printed=print,{}
print=function(...)
    local parts={};for index=1,select('#',...) do parts[index]=tostring(select(index,...)) end
    local text=table.concat(parts,'\t');assert(#text<=8192,'Every actual console line must be bounded');printed[#printed+1]=text
end
local full=wrapper.status({quiet=true})
assert(#printed==0,'Quiet status must print no lines')
assert(#full.owners[1].permanent_effects.totals.diagnostic_payload==14000,'Full source data must remain present in quiet return')
assert(full.owners[1].research.levels[large_key]==1)
full=wrapper.status()
local chunk_groups={}
for _,text in ipairs(printed) do
    local raw=text:match('^%[FOUR_PLAYER_LIVE_PERF%] status_chunk (.*)$')
    if raw then
        local chunk=assert(require('core/json_decoder').decode(raw))
        assert(chunk.protocol=='four_live_compact_chunk_v1' and #chunk.data<=1400)
        local group_key=chunk.tag..':'..chunk.report_id..':'..tostring(chunk.owner_id)
        local group=chunk_groups[group_key] or {};chunk_groups[group_key]=group
        group[chunk.index]=chunk.data;group.count=chunk.count;group.bytes=chunk.bytes
        local start=chunk.data:byte(1);assert(start<128 or start>191,'UTF-8 chunk cannot start with a continuation byte')
    end
end
local owner_chunks=0
for _,group in pairs(chunk_groups) do
    local pieces={};for index=1,group.count do pieces[index]=assert(group[index]) end
    local combined=table.concat(pieces);assert(#combined==group.bytes)
    local decoded=assert(require('core/json_decoder').decode(combined));assert(decoded.research_levels[large_key]==1)
    owner_chunks=owner_chunks+1
end
assert(owner_chunks==4,'Long default output must preserve all four compact owner payloads in bounded chunks')
print=original_print;event_bus.request=original_request
wrapper.stop();assert(profiles.get_profile(0)==human and human.save.gameplay_stats.map_level==77)
for _,modifier in ipairs(protected_modifiers) do assert(modifier:IsNull(),'Stop removes exact modifier handles') end
print('FOUR_LIVE_WRAPPER_PASS: inert Tools gating; admission; 4 distinct memory profiles; human/session isolation; native ownership; B three real queued walls; four spawn channels; exact read-hook restoration')
