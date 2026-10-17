-- Offline integration regression: real archive authority, runtime builder/service,
-- event bus and scheduler. Native entities, appearance and durable archive boundary
-- are fixtures. No production files are changed by this test.
package.path = 'scripts/vscripts/?.lua;' .. package.path
local bus = require('core/event_bus')
local events = require('core/events')
local scheduler = require('core/scheduler')
local definitions = require('config/generated/archive_challenge_definitions')
local function read(path)
    local handle=assert(io.open(path,'rb'));local text=handle:read('*a');handle:close();return text
end
local native_abilities=read('scripts/npc/npc_archive_challenges_abilities.txt')
local last_spawn_stats,last_spawn_visual,reward_events
local clock, serial, rewards, winners = 100, 1000, 0, 0
local errors, rows, writes, entities, registered = {}, {}, {}, {}, {}
local original_print = print
print = function(message)
    message = tostring(message)
    if message:find('handler error',1,true) or message:find('task failed',1,true)
        or message:find('hubs pending',1,true) then errors[#errors+1] = message end
end
local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}; for key,child in pairs(value) do result[key] = copy(child) end; return result
end
local function equal(a,b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= 'table' then return a == b end
    for key,value in pairs(a) do if not equal(value,b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
DOTA_TEAM_GOODGUYS = 2
Vector = function(x,y,z) return {x=x,y=y,z=z} end
local mode = {}
GameRules = {GetGameTime=function() return clock end,
    GetGameModeEntity=function() return mode end,
    SetGameWinner=function(_,team) assert(team==2); winners=winners+1 end}
PlayerResource = {GetTeam=function() return 2 end,
    GetPlayer=function(_,id) return id end,
    IsValidPlayerID=function(_,id) return id==0 or id==1 end,
    IsFakeClient=function() return false end}
CustomNetTables = {
    SetTableValue = function(_,table_name,key,row)
        if table_name == 'survival_ability_runtime' then
            rows[key], writes[key] = copy(row), (writes[key] or 0)+1
        end
    end,
    GetTableValue = function() return nil end,
}
local function unit(name,position)
    serial=serial+1
    local u={id=serial,name=name,position=position,abilities={},ordered={},alive=true}
    function u:IsNull() return self.removed==true end
    function u:IsAlive() return self.alive end
    function u:entindex() return self.id end
    function u:GetAbsOrigin() return self.position end
    function u:GetTeamNumber() return 2 end
    function u:GetPlayerOwnerID() return self.owner end
    function u:GetUnitName() return self.name end
    function u:GetAbilityCount() return #self.ordered end
    function u:GetAbilityByIndex(index) return self.ordered[index+1] end
    function u:FindAbilityByName(n) return self.abilities[n] end
    function u:AddAbility(n)
        assert(native_abilities:find('"'..n..'"',1,true),'Ability is missing its native KV declaration: '..n)
        serial=serial+1
        local a={id=serial,name=n,active=true,level=0,activation_writes=0,hidden=false}
        function a:IsNull() return u.removed==true end
        function a:entindex() return self.id end
        function a:GetAbilityName() return self.name end
        function a:GetCaster() return u end
        function a:GetLevel() return self.level end
        function a:SetLevel(v) self.level=v end
        function a:IsActivated() return self.active end
        function a:SetActivated(v)
            assert(type(v)=='boolean','native activation requires boolean')
            self.active=v; self.activation_writes=self.activation_writes+1
        end
        function a:IsPassive() return false end
        function a:IsHidden() return self.hidden end
        function a:StartCooldown(v) self.cooldown=v end
        function a:EndCooldown() self.cooldown=0 end
        self.abilities[n]=a;self.ordered[#self.ordered+1]=a;entities[a.id]=a;return a
    end
    function u:SetControllableByPlayer(id) self.owner=id end
    u.SetModel=function() end;u.SetOriginalModel=function() end
    u.SetModelScale=function() end;u.AddNewModifier=function() end
    entities[u.id]=u;return u
end
CreateUnitByName = unit
EntIndexToHScript = function(id) return entities[id] end
UTIL_Remove = function(u) u.removed=true end
Entities = {FindByName=function(_,_,name)
    local id,index=name:match('^player_(%d+)_archive_hub_(%d+)$'); if not id then id=name:match('^player_(%d+)_builder_spawn$'); index=0 end
    if not id then return nil end
    return {IsNull=function() return false end,
        GetAbsOrigin=function() return Vector(tonumber(id)*2000,tonumber(index)*300,0) end}
end}
package.loaded['systems/player_context_service'] = {
    register_unit=function(id,u) u.owner=id;registered[u.id]=u end,
    unregister_unit=function(u) registered[u.id]=nil end,
    owner_player_id=function(u) return u.owner end,
    slot=function(id) return {builder_spawn_marker='player_'..id..'_builder_spawn'} end,
}
package.loaded['systems/wave_system'] = {
    get_player_spawn_marker=function(id)
        return {IsNull=function() return false end,
            GetAbsOrigin=function() return Vector(id*2000,0,0) end}
    end,
    spawn_challenge_monster=function(stats,visual) last_spawn_stats,last_spawn_visual=stats,visual;return unit('boss',Vector(0,0,0)) end,
}
reward_events={}
package.loaded['systems/archive_service'] = {has_pending=function() return false end,
    record_challenge=function(id,challenge,sequence,difficulty)
        rewards=rewards+1;reward_events[#reward_events+1]={id=id,challenge=challenge,sequence=sequence,difficulty=difficulty};return {ok=true}
    end}
package.loaded['systems/monster_hero_visual_service'] = {clear=function() end,on_death=function() end}
package.loaded['systems/challenge_guardian_visual_service'] = {apply=function() end,clear=function() end}
local endless_running,endless_callback={}
package.loaded['systems/archive_endless_service'] = {
    init=function(callback) endless_callback=callback end,
    is_running=function(id) return endless_running[id]==true end,
    start=function(id) endless_running[id]=true; return true end,
    cancel=function(id) endless_running[id]=nil end,
}
package.loaded['systems/archive_endless_config'] = {group=function() return {} end}
bus.reset();scheduler.clear()
bus.handle_request(events.RESOURCE_GET_REQUEST,function() return {gold=0,wood=0,version=7} end)
bus.handle_request(events.HERO_PROGRESSION_GET_REQUEST,function() return {ok=true,snapshot={rebirth_level=10}} end)
local runtime_service=require('ui/ability_runtime_service')
runtime_service.init()
local archive=require('systems/archive_challenge_service')
archive.init()
local checks=0
local function no_errors() assert(#errors==0,table.concat(errors,'\n')) end
local function value(a) return assert(rows[tostring(a.id)],'missing runtime '..a.name) end
local function verify(state,label)
    no_errors()
    for index,hub in pairs(state.hubs) do
        for _,a in ipairs(hub.ordered) do
            local row=value(a)
            assert(row.ability_name==a.name and row.ability_entindex==a.id and row.owner_entindex==hub.id,
                label..': listener/tick identity differs for '..a.name)
            assert(row.archive_challenge==1,label..': lacks archive marker '..a.name)
            local expected
            if a.name=='ability_archive_finish' then expected=not state.finished
            elseif a.name=='ability_archive_endless' then
                expected=not state.finished and not state.used.endless and not state.active_boss and not endless_running[state.player_id]
            else
                local id=a.name:sub(#'ability_archive_'+1)
                local d=assert(definitions.by_id[id])
                expected=not state.finished and state.difficulty>=d.min_difficulty
                    and not state.used[id] and not state.active_boss and not endless_running[state.player_id]
                assert(row.upgrade_description==d.description,label..': description overwritten '..a.name)
                assert(row.fields and row.fields[1] and row.fields[1].value,label..': unlock tooltip lost '..a.name)
            end
            assert(row.available==(expected and 1 or 0),label..': wrong available '..a.name)
            assert(a.active==expected and row.engine_activated==(expected and 1 or 0),label..': engine state differs '..a.name)
            assert(type(row.status_text)=='string' and #row.status_text>0,label..': empty status '..a.name)
            assert(row.prerequisite_met~=nil,label..': missing stable shading prerequisite '..a.name)
        end
        local count=assert(rows['unit:'..hub.id],label..': missing unit count')
        assert(count.owner_entindex==hub.id and count.ability_count==#hub.ordered,label..': wrong unit identity/count')
    end
    checks=checks+1
end
local semantic_fields={'ability_name','ability_entindex','owner_entindex','archive_challenge','available',
    'prerequisite_met','status_text','upgrade_description','fields','engine_activated','engine_level'}
local function interleave(state,label)
    local baseline,activation={},{ }
    for _,hub in pairs(state.hubs) do for _,a in ipairs(hub.ordered) do
        baseline[a.id]=copy(value(a));activation[a.id]=a.activation_writes
    end end
    for _,event in ipairs({events.HERO_PROGRESSION_CHANGED,events.HERO_SUMMON_STATE_CHANGED,events.ROGUE_REWARD_CHANGED}) do
        for iteration=1,3 do
            bus.emit(event,{player_id=state.player_id,reason='archive_regression_refresh',hero_summoned=1})
            verify(state,label..':'..event..':'..iteration)
            for _,hub in pairs(state.hubs) do for _,a in ipairs(hub.ordered) do
                local row=value(a)
                assert(a.activation_writes==activation[a.id],label..': repeat native activation '..a.name)
                for _,field in ipairs(semantic_fields) do
                    assert(equal(row[field],baseline[a.id][field]),label..': refresh replaced '..field..' '..a.name)
                end
            end end
        end
    end
end
assert(archive.begin({difficulty_id='N5',player_ids={0,1}}).keep_running)
local state=archive._test.players()[0]
local wife=assert(definitions.by_id.social_wife,'Wife challenge is absent from the runtime definitions')
assert(wife.building_id==3 and wife.slot_order==11 and wife.reward_kind=='social_ticket' and wife.reward_key=='wife',
    'Wife challenge must occupy the third hub slot eleven and award only its own currency')
assert(#state.hubs[3].ordered==12 and state.hubs[3].ordered[11].name=='ability_archive_social_wife'
    and state.hubs[3].ordered[12].name=='ability_archive_finish','The last two native slots retain wife and finish')
local wife_asset=require('config/asset_catalog').resolve(wife.default_wearable_asset_id)
assert(wife_asset and wife_asset.primary_model==wife.model_path and #wife_asset.components==5
    and #wife_asset.effects==2 and #wife_asset.activity_modifiers==1,'Wife challenge uses its complete declared outfit')
assert(read('scripts/npc/npc_units_custom.txt'):find('"'..wife_asset.async_unit_name..'"',1,true),
    'Wife outfit is missing the asynchronous native preload proxy')
verify(state,'first archive publish')
-- Explicit registration reproduces cross-system refreshes affecting the hubs.
for _,player in pairs(archive._test.players()) do for _,hub in pairs(player.hubs) do
    bus.emit(events.BUILDING_CHANGED,{unit=hub,entindex=hub.id,team=2,player_id=player.player_id,
        building_id='archive_challenge',level=1})
end end
verify(state,'generic initial publish');interleave(state,'N5 difficulty locked')
assert(not state.hubs[1].abilities.ability_archive_hunt_02.active,'N6 requirement fixture')
local hub=state.hubs[1]
local a=hub.abilities.ability_archive_shadow_1
assert(archive.summon(hub,'shadow_1',a));verify(state,'active boss and used');interleave(state,'active boss and used')
local boss=state.active_boss
boss.alive=false
bus.emit(events.ENGINE_ENTITY_KILLED,{victim=boss,victim_entindex=boss.id})
assert(rewards==2 and not state.active_boss, 'one shared boss gives both winning accounts a reward')
verify(state,'boss death');interleave(state,'used persists after death')
assert(not a.active and hub.abilities.ability_archive_shadow_2.active,'used/unused transition')
local wife_hub=state.hubs[3]
local wife_ability=assert(wife_hub.abilities.ability_archive_social_wife)
local reward_count=#reward_events
assert(archive.summon(wife_hub,'social_wife',wife_ability),'Wife challenge native ability can summon its configured monster')
assert(last_spawn_stats.challenge_id=='social_wife' and last_spawn_stats.difficulty_id=='N5'
    and last_spawn_visual.default_wearable_asset_id==wife.default_wearable_asset_id,
    'Wife entry forwards the current difficulty stats and its complete outfit')
verify(state,'wife boss active');interleave(state,'wife active and used')
local wife_boss=state.active_boss;wife_boss.alive=false
bus.emit(events.ENGINE_ENTITY_KILLED,{victim=wife_boss,victim_entindex=wife_boss.id})
assert(#reward_events==reward_count+2,'One wife boss awards one independent event to each winning account')
for index=reward_count+1,#reward_events do
    assert(reward_events[index].challenge=='social_wife' and reward_events[index].difficulty=='N5',
        'Wife kill cannot award an ex or friend ticket')
end
assert(not archive.summon(wife_hub,'social_wife',wife_ability),'Wife challenge is limited to once per player per match')
bus.emit(events.ENGINE_ENTITY_KILLED,{victim=wife_boss,victim_entindex=wife_boss.id})
assert(#reward_events==reward_count+2,'Repeated native death events cannot repeat wife rewards')
assert(not wife_ability.active and wife_hub.abilities.ability_archive_social_ex.active,
    'Using the wife challenge does not consume the ex challenge')
verify(state,'wife death');interleave(state,'wife used persists after death')
local hub2=state.hubs[2]
assert(archive.start_endless(hub2,hub2.abilities.ability_archive_endless))
verify(state,'endless busy');interleave(state,'endless busy')
assert(not hub.abilities.ability_archive_shadow_2.active,'endless locks other challenge')
endless_running[0]=nil;endless_callback(0)
verify(state,'endless ended');interleave(state,'endless used')
assert(hub.abilities.ability_archive_shadow_2.active and not hub2.abilities.ability_archive_endless.active)
-- Repeated phase notifications must not perform native activation writes.
local before={}
for _,h in pairs(state.hubs) do for _,ability in ipairs(h.ordered) do before[ability.id]=ability.activation_writes end end
assert(archive.begin({difficulty_id='N5',player_ids={0,1}}).keep_running)
verify(state,'duplicate begin')
for _,h in pairs(state.hubs) do for _,ability in ipairs(h.ordered) do
    assert(ability.activation_writes==before[ability.id],'duplicate begin toggled native activation')
end end
local old_hubs=copy({})
for index,h in pairs(state.hubs) do old_hubs[index]=h end
assert(archive.finish(state.hubs[3]));assert(state.finished and winners==0)
no_errors()
for _,h in pairs(old_hubs) do
    assert(h.removed and not registered[h.id])
    assert(rows['unit:'..h.id].removed==1,'finished hub unit row not retired')
    for _,ability in ipairs(h.ordered) do assert(value(ability).removed==1,'finished ability row not retired') end
end
for _,event in ipairs({events.HERO_PROGRESSION_CHANGED,events.HERO_SUMMON_STATE_CHANGED,events.ROGUE_REWARD_CHANGED}) do
    bus.emit(event,{player_id=0,reason='after_finish',hero_summoned=1})
end
no_errors()
for _,h in pairs(old_hubs) do for _,ability in ipairs(h.ordered) do
    assert(value(ability).removed==1,'finished ability resurrected by refresh')
end end
local other=archive._test.players()[1]
verify(other,'teammate unaffected')
assert(archive.finish(other.hubs[3]));assert(winners==1)
assert(scheduler.task_count()==0,'phase/runtime tasks accumulate after finish')
no_errors()

-- Finishing one's own challenge does not withdraw a legitimate winner from
-- another teammate's later team reward. The real dispatcher owns this rule.
bus.reset();scheduler.clear();archive.init()
assert(archive.begin({difficulty_id='N5',player_ids={0,1}}).keep_running)
local first,teammate=archive._test.players()[0],archive._test.players()[1]
assert(archive.finish(teammate.hubs[3]))
local handed_off={}
package.loaded['systems/archive_service'].record_challenge=function(id)
    handed_off[id]=(handed_off[id] or 0)+1;return {ok=true}
end
local first_hub=first.hubs[1]
assert(archive.summon(first_hub,'shadow_1',first_hub.abilities.ability_archive_shadow_1))
local first_boss=first.active_boss;first_boss.alive=false
bus.emit(events.ENGINE_ENTITY_KILLED,{victim=first_boss,victim_entindex=first_boss.id})
assert(handed_off[0]==1 and handed_off[1]==1,'finished teammate keeps the full shared reward')
assert(archive.finish(first.hubs[3]))
no_errors()

-- The last player's finish cannot close the archive queue until even a
-- pre-enqueue exception has handed off every previously-earned team intent.
bus.reset();scheduler.clear();archive.init()
assert(archive.begin({difficulty_id='N5',player_ids={0,1}}).keep_running)
first,teammate=archive._test.players()[0],archive._test.players()[1]
local fail_before_enqueue,finalizations=true,0
handed_off={}
package.loaded['systems/archive_service'].record_challenge=function(id)
    if id==1 and fail_before_enqueue then error('fixture before enqueue') end
    handed_off[id]=(handed_off[id] or 0)+1;return {ok=true}
end
package.loaded['systems/archive_service'].begin_finalization=function()
    finalizations=finalizations+1
    assert(not require('systems/archive_cooperative_reward_service').has_pending(),
        'finalization cannot lock the queue before all earned team intents enqueue')
end
first_hub=first.hubs[1]
assert(archive.summon(first_hub,'shadow_1',first_hub.abilities.ability_archive_shadow_1))
first_boss=first.active_boss;first_boss.alive=false
bus.emit(events.ENGINE_ENTITY_KILLED,{victim=first_boss,victim_entindex=first_boss.id})
assert(require('systems/archive_cooperative_reward_service').has_pending())
local prior_winners=winners
assert(archive.finish(first.hubs[3]));assert(archive.finish(teammate.hubs[3]))
assert(winners==prior_winners and finalizations==0 and archive.phase_snapshot().saving==1,
    'all finished players still wait for an earned intent that has not queued')
fail_before_enqueue=false
clock=clock+1;scheduler.think();clock=clock+0.3;scheduler.think()
assert(handed_off[0]==1 and handed_off[1]==1,'missing account retries while successful account stays once')
assert(winners==prior_winners+1 and finalizations==1 and scheduler.task_count()==0,
    'winner follows successful handoff and finalization exactly once')
no_errors()
original_print('ARCHIVE_RUNTIME_FLICKER_REGRESSION_PASS '..checks..' UI checks plus team early-finish and reward handoff barrier: identity, N gates, used, active boss, endless busy/end, shared refresh, activation and cleanup')
