package.path = "scripts/vscripts/?.lua;" .. package.path
require("tests/development_release_profile")
-- Actual production public clear and public four-channel spawn, with an engine
-- fixture reused from the existing lifecycle regression. No private clear call.
local file=assert(io.open("scripts/vscripts/tests/test_wave_population_endgame.lua","rb"))
local source=file:read("*a");file:close()
local boundary=assert(source:find("-- The real rules admit",1,true))
local cases=[=[
local tools,server,map=true,true,"template_map"
IsInToolsMode=function() return tools end;IsServer=function() return server end
GetMapName=function() return map end
DOTA_GAMERULES_STATE_GAME_IN_PROGRESS=7
class=function(t) return t end
local world={}
GameRules.GetGameModeEntity=function() return world end
local context=package.loaded["systems/player_context_service"]
context.max_players=function() return 4 end
context.is_owned_by=function(id,value) return value and value.survival_player_id==id end
local match=package.loaded["systems/match_setup_service"]
match.get_session_id=function() return "comparison_test_session" end
package.loaded["config/asset_catalog"].for_model=function() return nil end
package.loaded["systems/monster_visual_service"].queue_wave=noop
local release_calls,death_unregisters={},{}
package.loaded["systems/enemy_attack_observer"]={unregister_death=function(ai) death_unregisters[ai]=(death_unregisters[ai] or 0)+1 end}
package.loaded["systems/enemy_ranged_stationary"]={release=function(ai,parent,reason)
    assert(reason=="destroyed" and ai:GetParent()==parent)
    release_calls[parent]=(release_calls[parent] or 0)+1;ai.ranged_stationary_hold=nil
end}
local native_ai=require("modifiers/modifier_enemy_wall_ai")
local native_refs,cleanup_order,profile_reads={}, {}, 0
EntIndexToHScript=function(index) return native_refs[index] end
local original_create=CreateUnitByName
CreateUnitByName=function(name)
    local value=original_create(name);native_refs[value:entindex()]=value
    value.GetClassname=function() return "npc_dota_creature" end
    value.GetTeamNumber=function() return DOTA_TEAM_BADGUYS end
    value.IsRealHero=function() return false end
    value.GetUnitName=function(self) return self.name end
    value.GetPlayerOwnerID=function() return -1 end -- Formal ownership is metadata, not native owner.
    value.SetForceAttackTarget=function(self,target) self.force_target=target end
    value.AddNewModifier=function(self,_,_,name,params)
        if name=="modifier_enemy_wall_ai" then
            local ai=setmetatable({wall_entindex=params.wall_entindex,wall_target_player_id=params.wall_target_player_id,
                ranged_stationary_hold={},contact_range_delta=0,IsNull=function() return false end,
                GetParent=function() return self end},{__index=native_ai})
            self.ai=ai;return ai
        end
    end
    value.FindModifierByName=function(self,name) return name=="modifier_enemy_wall_ai" and self.ai or nil end
    value.ForceKill=function() error("NoPayout cannot simulate deaths") end
    return value
end
package.loaded["systems/monster_hero_visual_service"].clear=function(value)
    assert(upvalue("enemies")[value:entindex()]==nil,"Unregister must precede native/visual teardown")
    cleanup_order[value]="hero_visual"
end
package.loaded["systems/monster_visual_service"].cleanup=function(value)
    assert(cleanup_order[value]=="hero_visual" and value.survival_wave_cleanup==true)
    cleanup_order[value]="visual"
end
local reenter_result
UTIL_Remove=function(value)
    assert(cleanup_order[value]=="visual","Both original visual paths retire before native remove")
    if not reenter_result then reenter_result=wave.debug_clear_wave_for_comparison() end
    value.ai:OnDestroy();value.removed=true;native_refs[value:entindex()]=nil
    cleanup_order[value]="removed"
end
local protected,profile_memory,stale_callback
local function prepare(scenario,difficulty)
    package.loaded["systems/player_profile_service"].get_progression=function() return {loaded=true,clear_counts={}} end
    restart(difficulty or "N1",true,{0,1,2,3})
    native_refs,cleanup_order,release_calls,death_unregisters,reenter_result={},{},{},{},nil
    protected,profile_memory={}, { [0]={count=3},[1]={count=7},[2]={count=11},[3]={count=19} }
    local scene={mode=world,status="ready",players={},attack_hold={token=true},wall_survival={}}
    local fixture={mode=world,status="ready",guard={mode=world},write_isolated=true,
        scenario=scenario or "A",ids={0,1,2,3},defender_scene=scene,owners={},
        match_mode="standard",session="comparison_test_session",profile_memory=profile_memory}
    local function saved(id,kind)
        local value={survival_player_id=id,kind=kind,health=1000,model="protected_model",fx={marker=true},
            IsNull=function() return false end,IsAlive=function(self) return self.alive~=false end}
        protected[#protected+1]=value;return value
    end
    for id=0,3 do
        local owner={id=id,phase="ready",builder=saved(id,"builder"),units={wall=saved(id,"wall")},
            towers={},hero=saved(id,"hero")}
        for i=1,7 do owner.towers[i]=saved(id,"tower") end
        if scenario=="B" and id~=0 then
            owner.wall=owner.units.wall;owner.units=nil;fixture.owners[id]=owner
        else scene.players[#scene.players+1]=owner end
    end
    _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION=fixture.guard
    _G.SURVIVAL_REAL_GAME_STRESS=scene;_G.SURVIVAL_FOUR_PLAYER_LIVE_PERF=fixture
    assert(wave.debug_spawn_wave_for_players(15,fixture.ids))
    clock=100;assert(scheduled.dev_wave_preload)();scheduled.dev_wave_preload=nil
    local callbacks={}
    for key,callback in pairs(scheduled) do if type(key)=="number" then callbacks[#callbacks+1]=callback;scheduled[key]=nil end end
    stale_callback=assert(callbacks[1]);for _,callback in ipairs(callbacks) do callback() end
    assert(scheduled.dev_wave_complete)();scheduled.dev_wave_complete=nil
    assert(#created==244 and upvalue("state").alive==244 and upvalue("state").pending==0)
    profile_reads=0
    package.loaded["systems/player_profile_service"].get_progression=function() profile_reads=profile_reads+1;error("Comparison cleanup cannot read profiles") end
    return fixture,scene
end
local function unchanged_protected(fixture,scene)
    assert(_G.SURVIVAL_FOUR_PLAYER_LIVE_PERF==fixture and _G.SURVIVAL_REAL_GAME_STRESS==scene
        and _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION==fixture.guard and scene.attack_hold.token==true)
    for _,value in ipairs(protected) do assert(not value.removed and value.health==1000 and value.model=="protected_model" and value.fx.marker) end
    assert(fixture.profile_memory==profile_memory and profile_memory[0].count==3 and profile_memory[3].count==19)
    assert(profile_reads==0 and #boss_rewards==0 and #granted==0 and #archive_clears==0
        and #winners==0 and #finalized==0 and #personal_finalized==0)
end
local function assert_no_handles(value)
    if type(value)~="table" then assert(type(value)~="function" and type(value)~="userdata");return end
    assert(not value.IsNull and not value.GetParent)
    for key,item in pairs(value) do assert(type(key)~="table");assert_no_handles(item) end
end
for _,scenario in ipairs({"A","B"}) do
    local fixture,scene=prepare(scenario)
    local before=upvalue("generation_token")
    local result=wave.debug_clear_wave_for_comparison()
    assert(result.ok and result.removed==244 and result.alive==0 and result.pending==0
        and result.resource_snapshot.session_count==0 and result.generation_after==before+1)
    assert(result.resource_snapshot.lease_count>0,"Dev model residency survives the matched warm-world comparison")
    assert(reenter_result.error=="comparison_clear_reentrant")
    for _,value in ipairs(created) do
        assert(value.removed and cleanup_order[value]=="removed" and release_calls[value]==1
            and death_unregisters[value.ai]==1 and value.ai.contact_mode==0 and value.force_target==nil)
        bus.emit(events.ENGINE_ENTITY_KILLED,{victim=value,victim_entindex=value:entindex()})
    end
    unchanged_protected(fixture,scene);assert_no_handles(result)
    local created_before=#created;stale_callback()
    assert(#created==created_before and upvalue("state").pending==0,"Actual old spawn callback is generation-invalidated")
    result=wave.debug_clear_wave_for_comparison()
    assert(result.ok and result.removed==0 and result.generation_after==before+1,"Repeated empty clear is a true no-op")
    unchanged_protected(fixture,scene)
end
local fixture,scene=prepare("A","N2") -- Difficulty-independent metadata; no hard-coded N1 range/name.
local function failed(edit,restore,expected_error)
    local before=upvalue("generation_token");edit()
    local edited_pending=upvalue("state").pending
    local result=wave.debug_clear_wave_for_comparison()
    assert(not result.ok and result.error==(expected_error or "comparison_clear_preflight_failed"))
    assert(upvalue("generation_token")==before and upvalue("state").alive==244 and upvalue("state").pending==edited_pending)
    for _,value in ipairs(created) do assert(not value.removed and cleanup_order[value]==nil and release_calls[value]==nil) end
    assert_no_handles(result);restore();unchanged_protected(fixture,scene)
end
failed(function() tools=false end,function() tools=true end,"release_debug_disabled")
failed(function() server=false end,function() server=true end,"release_debug_disabled")
failed(function() map="foreign_map" end,function() map="template_map" end)
failed(function() engine_state=8 end,function() engine_state=7 end)
failed(function() fixture.status="preparing" end,function() fixture.status="ready" end)
failed(function() fixture.scenario="unknown" end,function() fixture.scenario="A" end)
failed(function() fixture.write_isolated=false end,function() fixture.write_isolated=true end)
failed(function() fixture.guard={} end,function() fixture.guard=_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION end)
failed(function() fixture.defender_scene={} end,function() fixture.defender_scene=scene end)
failed(function() fixture.session="foreign_session" end,function() fixture.session="comparison_test_session" end)
failed(function() fixture.ids[4]=2 end,function() fixture.ids[4]=3 end)
failed(function() active_players={0,1,2} end,function() active_players={0,1,2,3} end)
failed(function() scene.players[1].builder.survival_player_id=3 end,function() scene.players[1].builder.survival_player_id=0 end)
failed(function() scene.players[1].builder.alive=false end,function() scene.players[1].builder.alive=true end)
failed(function() scene.players[1].units.wall.alive=false end,function() scene.players[1].units.wall.alive=true end)
failed(function() upvalue("state").status="dev_preloading" end,function() upvalue("state").status="dev_mode" end)
failed(function() upvalue("state").pending=1 end,function() upvalue("state").pending=0 end)
failed(function() upvalue("state").victory_settled=true end,function() upvalue("state").victory_settled=false end)
local session=next(upvalue("wave_resource_sessions"))
local resource=upvalue("wave_resource_sessions")[session]
failed(function() resource.generation_completed=false end,function() resource.generation_completed=true end)
failed(function() resource.pending=1 end,function() resource.pending=0 end)
local actual_session_id,actual_generation=resource.session_id,resource.generation_token
failed(function() resource.session_id="foreign_session_identity" end,function() resource.session_id=actual_session_id end)
failed(function() resource.generation_token=actual_generation-1 end,function() resource.generation_token=actual_generation end)
failed(function()
    resource.alive=243
    upvalue("wave_resource_sessions").orphan={session_id="orphan",generation_token=actual_generation,
        dev_mode=true,pending=0,generation_completed=true,wave_number=15,alive=1}
end,function() resource.alive=244;upvalue("wave_resource_sessions").orphan=nil end)
local enemy=created[1];local meta=upvalue("enemies")[enemy:entindex()]
failed(function() meta.wave_number=14 end,function() meta.wave_number=15 end)
failed(function() enemy.survival_player_id=3-meta.player_id end,function() enemy.survival_player_id=meta.player_id end)
failed(function() enemy.alive=false end,function() enemy.alive=true end)
failed(function() native_refs[enemy:entindex()]={} end,function() native_refs[enemy:entindex()]=enemy end)
failed(function() enemy.ai.wall_target_player_id=3-meta.player_id end,function() enemy.ai.wall_target_player_id=meta.player_id end)
local native_class_getter=enemy.GetClassname
failed(function() enemy.GetClassname=function() error("native_read_failed") end end,function() enemy.GetClassname=native_class_getter end)
failed(function() upvalue("enemies")[10000]={unit=protected[1],player_id=0,wave_number=15} end,
    function() upvalue("enemies")[10000]=nil end)
local unregistered={survival_is_wave_monster=true,IsNull=function() return false end}
native_refs[20000]=unregistered
local mode_reads,original_mode_getter=0,GameRules.GetGameModeEntity
GameRules.GetGameModeEntity=function() mode_reads=mode_reads+1;if mode_reads==2 then error("second_native_read_failed") end;return world end
local failed_generation=upvalue("generation_token")
local native_failure=wave.debug_clear_wave_for_comparison()
assert(not native_failure.ok and native_failure.error=="comparison_clear_authority_changed"
    and upvalue("generation_token")==failed_generation and upvalue("state").alive==244)
GameRules.GetGameModeEntity=original_mode_getter
local result=wave.debug_clear_wave_for_comparison()
assert(result.ok and result.removed==244 and not unregistered.removed and native_refs[20000]==unregistered)
unchanged_protected(fixture,scene)
print("WAVE_COMPARISON_CLEAR_PASS: actual production public 244 spawn/clear for A+B+N2, native AI teardown, no payout/profile/hero/tower/wall changes, stale callbacks, repeated clear, reentry and complete failed-preflight no mutation")
]=]
assert(loadstring(source:sub(1,boundary-1)..cases,"test_wave_comparison_clear"))()
