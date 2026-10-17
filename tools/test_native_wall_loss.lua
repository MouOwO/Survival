-- Real event bus; native entities and public read endpoints are isolated.
-- The observer is forbidden from manufacturing damage/defeat or real writes.
package.path='scripts/vscripts/?.lua;'..package.path
local probe=require('tests/manual_native_wall_loss')
assert(_G.SURVIVAL_NATIVE_WALL_LOSS==nil,'require is inert')
assert(probe.start().error=='probe_default_off' and _G.SURVIVAL_NATIVE_WALL_LOSS==nil)
local bus,events=require('core/event_bus'),require('core/events')
local mode,session,engine_state={},'native_wall_regression',10
local tools,roster,defeated,profiles,rows,walls,floors,builders,workers,heroes,logs,recalc
local old_print=print
print=function(message) logs[#logs+1]=message end
IsServer=function() return true end;IsInToolsMode=function() return tools end
GetMapName=function() return 'template_map' end
DOTA_GAMERULES_STATE_GAME_IN_PROGRESS,DOTA_GAMERULES_STATE_POST_GAME=10,11
GameRules={GetGameModeEntity=function() return mode end,State_Get=function() return engine_state end,
    GetGameTime=function() return 321 end,SetGameWinner=function() error('Observer must never settle the match') end}
local context={}
context.owner_player_id=function(unit) return unit.context_owner end
context.is_owned_by=function(id,unit) return unit.context_owner==id end
context.active_player_ids=function() local r={};for _,id in ipairs(roster) do if not defeated[id] then r[#r+1]=id end end;return r end
package.loaded['systems/player_context_service']=context
package.loaded['systems/multiplayer_player_service']={participating_player_ids=function() return roster end,
    is_defeated=function(id) return defeated[id]==true end,
    all_participants_defeated=function() for _,id in ipairs(roster) do if not defeated[id] then return false end end;return #roster>0 end,
    defeat=function() error('Observer must never defeat a player directly') end}
package.loaded['systems/match_setup_service']={get_mode=function() return 'standard' end,get_session_id=function() return session end}
package.loaded['systems/player_profile_service']={get_profile=function(id) return profiles[id] end,
    update_save_sections=function() error('Observer must never write a profile') end}
local function unit(id,index)
    local u={index=index,context_owner=id,native_owner=-1,health=100,alive=true}
    function u:IsNull() return self.removed==true end
    function u:IsAlive() return self.alive end
    function u:entindex() return self.index end
    function u:GetPlayerOwnerID() return self.native_owner end
    function u:GetHealth() return self.health end
    function u:GetMaxHealth() return 100 end
    function u:GetUnitName() return 'isolated_native_unit' end
    function u:GetAbsOrigin()
        if self.invalid_native then error('Invalid object passed to GetOrigin') end
        return {x=1,y=2,z=3}
    end
    function u:FindModifierByName(name) return name=='modifier_manual_real_game_stress_wall' and floors[self.context_owner] or nil end
    for _,name in ipairs({'SetHealth','Kill','ForceKill','RemoveModifierByName'}) do
        u[name]=function() error('Observer forbidden native mutation '..name) end
    end
    return u
end
local function reset()
    probe.stop('test_reset');bus.reset()
    _G.SURVIVAL_NATIVE_WALL_LOSS=nil
    tools,roster,defeated,profiles,rows,walls,floors,builders,workers,heroes,logs,recalc=true,{0,1,2,3},{},{},{},{},{},{},{},{},{},{}
    engine_state,session=10,'native_wall_regression'
    local scene={mode=mode,status='ready',wall_survival={}}
    local guard={mode=mode,wall_targets={}}
    local fixture={mode=mode,status='ready',guard=guard,defender_scene=scene,memory_profiles={},
        status_query=function() error('Do not invoke ready fixture validation after a legal personal loss') end}
    _G.SURVIVAL_FOUR_PLAYER_LIVE_PERF=fixture
    _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION=guard
    _G.SURVIVAL_REAL_GAME_STRESS=scene
    for id=0,3 do
        profiles[id]={account_id='PRIVATE_ACCOUNT_'..id,revision=id+1,auth_token='DO_NOT_PRINT',
            save={gameplay_stats={map_level=({1,9,17,24})[id+1],tower_attack_bonus_pct=id*7},private_save='DO_NOT_PRINT'}}
        fixture.memory_profiles[id]={account_id=profiles[id].account_id,revision=id+1,
            save={gameplay_stats={map_level=profiles[id].save.gameplay_stats.map_level,tower_attack_bonus_pct=id*7}}}
        walls[id]=unit(id,10+id)
        rows[id]={{unit=walls[id],player_id=id,building_id='wall',level=1},
            {unit=unit(id,20+id),player_id=id,building_id='main_city',level=1}}
        builders[id]=unit(id,30+id);heroes[id]=unit(id,40+id)
        workers[id]={{unit=unit(id,50+id),player_id=id,level=id+1}}
        local floor={scene=scene,guard=guard,parent=walls[id],stack=1,destroy_calls=0}
        function floor:IsNull() return self.destroyed==true end
        function floor:GetParent() return self.parent end
        function floor:GetStackCount() return self.stack end
        function floor:GetMinHealth() return self.stack end
        function floor:SetStackCount(value) self.stack=value end
        function floor:Destroy()
            assert(guard.wall_targets[self.parent]==nil and scene.wall_survival[self.parent]==nil,
                'Exact modifier destruction happens after both selected protections release')
            self.destroy_calls=self.destroy_calls+1;self.destroyed=true
        end
        floors[id]=floor;guard.wall_targets[walls[id]]=scene;scene.wall_survival[walls[id]]=floor
    end
    bus.handle_request(events.BUILDING_LIST_REQUEST,function(p)
        local result={};for _,row in ipairs(rows[p.player_id]) do if not p.building_id or row.building_id==p.building_id then result[#result+1]=row end end
        return {ok=true,buildings=result}
    end)
    bus.handle_request(events.BUILDING_QUERY_REQUEST,function(p)
        assert(p.read_only==true)
        for _,list in pairs(rows) do for _,row in ipairs(list) do if row.unit.index==p.entindex then return row end end end
    end)
    bus.handle_request(events.BUILDER_GET_REQUEST,function(p)
        assert(p.caster==nil and p.builder==nil,'Current registry read must not use an old builder candidate')
        return {ok=builders[p.player_id]~=nil,player_id=p.player_id,builder=builders[p.player_id],error=not builders[p.player_id] and 'builder_unavailable' or nil}
    end)
    bus.handle_request(events.WORKER_LIST_REQUEST,function(p) return workers[p.player_id] end)
    bus.handle_request(events.HERO_SUMMON_GET_REQUEST,function(p) return {ok=heroes[p.player_id]~=nil,unit=heroes[p.player_id],hero_id='test_hero_'..p.player_id} end)
    bus.handle_request(events.WAVE_STATE_GET_REQUEST,function(p)
        return {alive=defeated[p.player_id] and 0 or 30+p.player_id,alive_limit=90,current_wave=15,total_waves=30,
            player_defeated=defeated[p.player_id]==true,defeat_settled=false,status='all_waves_spawned',game_started=true}
    end)
    bus.handle_request(events.RESOURCE_GET_REQUEST,function(p) return {wood=1000+p.player_id,gold=2000+p.player_id,
        population=p.player_id+1,max_population=300,debug_mode=0,auth='DO_NOT_COPY'} end)
    bus.handle_request(events.RESEARCH_STATE_GET_REQUEST,function(p) return {levels={RS_TEST=p.player_id+1},account_id='DO_NOT_COPY'} end)
    bus.subscribe(events.PERMANENT_REWARD_EFFECTS_CHANGED,function(p)
        assert(p.changed_section=='wall' and p.reason=='tools_wall_protection_released')
        recalc[#recalc+1]=p
    end)
    return fixture,guard,scene
end
local function privacy(value)
    if type(value)=='table' then for key,child in pairs(value) do
        assert(key~='account_id' and key~='auth_token' and key~='save' and key~='private_save' and key~='auth')
        privacy(child)
    end elseif type(value)=='string' then
        assert(not value:find('PRIVATE_ACCOUNT_',1,true) and not value:find('DO_NOT_',1,true))
    end
end
local fixture,guard,scene=reset()
local initial=probe.start({enabled=true})
assert(initial.ok and initial.native_state==10 and initial.native_game_in_progress_enum==10 and initial.native_post_game_enum==11)
assert(initial.network_clients_verified==false and #initial.owners==4 and #initial.active_player_ids==4)
privacy(initial)
for id=0,3 do
    local row=initial.owners[id+1]
    assert(row.player_id==id and row.map_level==({1,9,17,24})[id+1] and row.profile_revision==id+1)
    assert(row.isolated_profile_matches and row.counts.wall==1 and row.workers==1 and row.worker_entities[1].level==id+1)
    assert(row.builder.formal_ownership_valid and row.builder.native_origin_valid and row.wave.alive==30+id)
end
local released=probe.release(0)
assert(released.ok and walls[0].health==100 and walls[0].alive and #recalc==1)
assert(guard.wall_targets[walls[0]]==nil and scene.wall_survival[walls[0]]==nil and floors[0].stack==0 and floors[0].destroy_calls==1)
for id=1,3 do assert(guard.wall_targets[walls[id]]==scene and scene.wall_survival[walls[id]]==floors[id]
    and floors[id].stack==1 and floors[id].destroy_calls==0) end
assert(probe.release(0).error=='wall_already_released' and #recalc==1)

-- These fixture events represent observations of an external native death;
-- the observer does not drive lifecycle or alter engine/participant status.
defeated[0],walls[0].alive,walls[0].health=true,false,0
rows[0],workers[0],heroes[0],builders[0]={},{},nil,nil
bus.emit(events.BUILDING_DESTROYED,{player_id=0,building_id='wall',entindex=10,auth_token='DO_NOT_COPY'})
bus.emit(events.PLAYER_DEFEATED,{player_id=0,reason='wall_destroyed',account_id='DO_NOT_COPY'})
bus.emit(events.PLAYER_DISCONNECTED,{player_id=0,defeat_cleanup=true,reason='wall_destroyed'})
local after=probe.snapshot({quiet=true});privacy(after)
assert(after.native_state==10 and #after.active_player_ids==3 and not after.all_participants_defeated)
assert(after.owners[1].is_defeated and not after.owners[1].wall.present and not after.owners[1].builder.present
    and after.owners[1].workers==0 and #after.owners[1].buildings==0)
assert(after.event_total==3 and after.owners[1].events.wall_destroyed==1 and after.owners[1].events.player_defeated==1
    and after.owners[1].events.player_disconnected==1 and after.owners[1].events.defeat_cleanup==1)
for id=1,3 do assert(after.owners[id+1].counts.wall==1 and after.owners[id+1].events.player_defeated==0) end
assert(#logs>=5,'Short event summaries retain evidence before the final native match end')
local external=0;bus.subscribe(events.PLAYER_DEFEATED,function() external=external+1 end)
probe.stop('test_stop');bus.emit(events.PLAYER_DEFEATED,{player_id=1,reason='external_after_stop'})
assert(external==1 and probe.snapshot({quiet=true}).event_total==3,'stop unhooks only this observer')

-- Invalid preflight paths cause no protection/event/profile mutations.
for _,change in ipairs({
    function() tools=false end,
    function() engine_state=11 end,
    function() roster={0,1,2} end,
    function() profiles[1].revision=99 end,
    function() walls[1].context_owner=0 end,
    function() walls[1].native_owner=2 end,
    function() rows[1][1].constructing=true end,
    function() guard.wall_targets[walls[1]]={} end,
    function() floors[1].parent=walls[2] end,
    function() scene.wall_survival[walls[1]]={} end,
}) do
    fixture,guard,scene=reset();change()
    assert(not pcall(probe.start,{enabled=true}),'Bad Tools/world/formal participant/profile/protection must refuse')
    assert(#recalc==0)
    for id=0,3 do assert(floors[id].destroy_calls==0 and walls[id].health==100) end
end

for _,change in ipairs({
    function() session='another_match' end,
    function() _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION={mode=mode} end,
    function() profiles[2].save.gameplay_stats.map_level=99 end,
    function() walls[0].context_owner=2 end,
    function() floors[0].guard={} end,
    function() rows[0][1].unit=unit(0,999) end,
}) do
    fixture,guard,scene=reset();probe.start({enabled=true,print_events=false});change()
    assert(not pcall(probe.release,0),'Release preflight must remain current before mutation')
    assert(#recalc==0 and floors[0].stack==1 and floors[0].destroy_calls==0)
end

fixture,guard,scene=reset();probe.start({enabled=true,print_events=false});builders[1].invalid_native=true
local broken=probe.snapshot({quiet=true})
assert(broken.owners[2].builder.formal_ownership_valid and broken.owners[2].builder.native_origin_valid==false)
builders[1]=nil;assert(not probe.snapshot({quiet=true}).owners[2].builder.present)
builders[1]=unit(1,333);assert(probe.snapshot({quiet=true}).owners[2].builder.entindex==333)
-- Event ring is bounded; wrong owners and old-world dispatch are ignored.
for i=1,140 do bus.emit(events.BUILDING_DESTROYED,{player_id=1,building_id='arrow_tower',entindex=100+i}) end
bus.emit(events.PLAYER_DEFEATED,{player_id=99,reason='ignored'})
local bounded=probe.snapshot({quiet=true});assert(bounded.event_total==140 and #bounded.events==128 and bounded.trace_dropped==12)
local before=bounded.event_total;session='new_world';bus.emit(events.PLAYER_DEFEATED,{player_id=1,reason='old_world'})
local stale=probe.snapshot({quiet=true});assert(not stale.current_world and stale.event_total==before)
fixture,guard,scene=reset();probe.start({enabled=true})
for id=0,3 do defeated[id]=true end
engine_state=DOTA_GAMERULES_STATE_POST_GAME
bus.emit(events.PLAYER_DEFEATED,{player_id=3,reason='wall_destroyed'})
local terminal=probe.snapshot({quiet=true})
assert(terminal.native_state==11 and terminal.all_participants_defeated and terminal.owners[4].events.player_defeated==1)
local final_log=logs[#logs]
assert(final_log:find('native_state=11',1,true) and final_log:find('survivors=0',1,true),
    'Final native-state event summary is available before the world closes')
assert(not pcall(probe.release,1),'Postgame cannot release another protection')
probe.stop('all_done');print=old_print
print('NATIVE_WALL_LOSS_PASS: inert/default-off; real public-read and bus observer; four complete owners/profiles; exact selected guard/floor release only; native damage required; preflight no-side-effect refusals; post-loss snapshots and event evidence; privacy; lifecycle/proxy replacement; bounded ring; old-world exclusion; own-subscription stop')
