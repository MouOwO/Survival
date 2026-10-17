-- Real progression + skill + choice services, real public request/event bus.
-- Engine ability/hero APIs and match admission are simulated, not live Dota.
package.path='scripts/vscripts/?.lua;'..package.path
local world,now,session={},0,'isolated_skill_fixture_session'
IsServer=function() return true end;IsInToolsMode=function() return true end;GetMapName=function() return 'template_map' end
DOTA_TEAM_GOODGUYS=2
GameRules={GetGameModeEntity=function() return world end,GetGameTime=function() return now end}
CustomNetTables={SetTableValue=function() end}
local bus,ev=require('core/event_bus'),require('core/events')
local scheduler=require('core/scheduler')
local profile_reads,real_writes,real_profiles,memory,profile_override=0,0,{}, {},nil
local profile={}
function profile.get_profile(id) profile_reads=profile_reads+1;return id==1 and profile_override or memory[id] or real_profiles[id] end
function profile.apply_snapshot() real_writes=real_writes+1;error('No profile writes allowed') end
package.loaded['systems/player_profile_service']=profile
package.loaded['systems/match_setup_service']={get_mode=function() return 'standard' end,get_session_id=function() return session end}
package.loaded['systems/player_context_service']={is_owned_by=function(id,u) return id==u.owner end}
local definitions=require('config/generated/hero_exclusive_skills')
local actual_skill=require('systems/hero_skill_system')
local actual_progression=require('systems/hero_progression_system')
local actual_choice=require('systems/hero_skill_choice_service')
local real_fixture=require('tests/manual_real_game_stress')
local wrapper=require('tests/manual_four_player_live_perf')
local native_heroes,grants,changes,profile_changes={},{},{},{}
local serial=0
local function hero(id,hero_id)
    serial=serial+1;local u={owner=id,index=serial,abilities={},health=500,max=1000,hero_id=hero_id}
    function u:IsNull() return false end;function u:IsAlive() return true end;function u:GetPlayerOwnerID() return self.owner end
    function u:entindex() return self.index end;function u:GetHealth() return self.health end;function u:GetMaxHealth() return self.max end
    function u:SetHealth(n) self.health=n end;function u:CalculateStatBonus() end;function u:SetAbilityPoints(n) assert(n==0) end
    function u:GetAbilityCount() return #self.abilities end;function u:GetAbilityByIndex(n) return self.abilities[n+1] end
    function u:FindAbilityByName(name) for _,a in ipairs(self.abilities) do if a.name==name then return a end end end
    function u:RemoveAbility(name) for i,a in ipairs(self.abilities) do if a.name==name then table.remove(self.abilities,i);return end end end
    function u:AddAbility(name)
        serial=serial+1;local a={name=name,index=serial,level=0,activated=false}
        function a:IsNull() return false end;function a:GetAbilityName() return self.name end;function a:entindex() return self.index end
        function a:SetLevel(n) self.level=n end;function a:SetHidden(n) self.hidden=n end;function a:SetActivated(n) self.activated=n end
        function a:IsActivated() return self.activated end;function a:GetCooldownTimeRemaining() return 0 end
        self.abilities[#self.abilities+1]=a;return a
    end
    return u
end
PlayerResource={IsValidPlayerID=function(_,id) return native_heroes[id]~=nil end,
    GetPlayer=function(_,id) return native_heroes[id] end,GetTeam=function() return 2 end}
local function snapshot(id) return bus.request(ev.HERO_SKILL_STATE_GET_REQUEST,{player_id=id}).snapshot end
local function levels(id)
    local r={};for _,s in ipairs(snapshot(id).skills) do r[s.skill_id]=s end;return r
end
local function advance(seconds) local finish=now+seconds;while now<finish do now=now+.05;scheduler.think() end end
local function prepare()
    bus.reset();scheduler.clear();now=0;world={};session='isolated_skill_fixture_session';memory={};native_heroes={};grants={};changes={};profile_changes={}
    actual_progression.init();actual_skill.init();actual_choice.init()
    bus.handle_request(ev.HERO_SUMMON_GET_REQUEST,function(p) local u=native_heroes[p.player_id]
        return u and {ok=true,unit=u,hero_id=u.hero_id} or {ok=false} end)
    bus.subscribe(ev.HERO_SKILL_CHANGED,function(p) changes[#changes+1]=p end)
    bus.subscribe(ev.PLAYER_PROFILE_CHANGED,function(p) profile_changes[#profile_changes+1]=p end)
    local guard={mode=world,bots={},four_live_profiles=memory}
    _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION=guard
    local ids={'hero_monkey_king','hero_blademaster','hero_drow_ranger','hero_doom'}
    local scene={mode=world,status='ready',hero_guard=guard,hero_match_mode='standard',hero_session_id=session,
        hero_bus_generation=bus.get_generation(),options={simulated_rebirth_level=3,simulate_exclusive_skill_rewards=true},players={}}
    for id=0,3 do
        local p={account_id='tools_skill_owner_'..id,revision=id+1,save={gameplay_stats={map_level=({1,9,17,24})[id+1]},content_inventory={}}}
        memory[id]=p;real_profiles[id]={account_id='original_untouched_'..id,revision=99,save={gameplay_stats={map_level=70+id}}}
        local u=hero(id,ids[id+1]);native_heroes[id]=u
        scene.players[#scene.players+1]={id=id,desired_hero_id=u.hero_id,combat_hero=u,combat_hero_id=u.hero_id}
        bus.emit(ev.HERO_SUMMONED,{player_id=id,unit=u,hero_id=u.hero_id})
    end
    _G.SURVIVAL_REAL_GAME_STRESS=scene
    _G.SURVIVAL_FOUR_PLAYER_LIVE_PERF={mode=world,status='ready',guard=guard,match_mode='standard',session=session,
        ids={0,1,2,3},defender_scene=scene,memory_profiles=memory,
        options={hero_ids={[0]=ids[1],[1]=ids[2],[2]=ids[3],[3]=ids[4]}}}
    advance(.4)
    return scene,guard
end
local checks=0
local function check(v,msg) checks=checks+1;assert(v,msg) end
local function rank(id,n)
    local r=bus.request(ev.HERO_PROGRESSION_APPLY_REQUEST,{player_id=id,effects={{effect_type='set_rebirth_level',value=n}},reason='tools_stress_simulated_rebirth_prerequisite'})
    assert(r and r.ok and r.snapshot.rebirth_level==n)
end
local scene,guard=prepare()
rank(1,3)
check(levels(1).skill_blademaster_exclusive.level==0 and levels(1).skill_blademaster_agility.level==0,'original bug reproduced: rank-only does not claim skills')
check(native_heroes[1]:FindAbilityByName('ability_survival_blademaster_exclusive').level==1
    and levels(1).skill_blademaster_exclusive.locked==1,'native level 1 is not formal learned evidence')
local before_changes=#changes
bus.emit(ev.PLAYER_PROFILE_CHANGED,{player_id=1,reason='tools_profile_refresh'})
check(levels(1).skill_blademaster_exclusive.level==0 and #changes==before_changes,'profile refresh alone cannot fabricate skill activation')
local refreshed=wrapper.refresh_simulated_hero_skills({enabled=true,player_id=1,rebirth_level=3})
check(refreshed.ok and #refreshed.granted==2 and refreshed.map_level==9,'public refresh grants exactly first two legal blade rewards')
check(levels(1).skill_blademaster_exclusive.level==1 and levels(1).skill_blademaster_exclusive.locked==0
    and levels(1).skill_blademaster_agility.level==1 and levels(1).skill_blademaster_agility.locked==0,'real skill system unlocks Q/W')
check(levels(1).skill_blademaster_swiftness.level==0 and levels(1).skill_blademaster_swiftness.locked==1
    and levels(1).skill_blademaster_mobility.level==0,'6/10 gates remain locked at rank3')
check(native_heroes[1]:FindAbilityByName('ability_survival_blademaster_exclusive'):IsActivated(),'actual native ability projection activated by real service')
check(#changes>before_changes and #profile_changes==2,'formal grant publishes actual skill events; memory profile refresh recorded')
local version=snapshot(1).version;refreshed=wrapper.refresh_simulated_hero_skills({enabled=true,player_id=1,rebirth_level=3})
check(#refreshed.granted==0 and snapshot(1).version==version,'repeat refresh is idempotent, no level upgrades')
check(bus.request(ev.HERO_PROGRESSION_GET_REQUEST,{player_id=1}).snapshot.all_attributes==0
    and #bus.request(ev.HERO_PROGRESSION_GET_REQUEST,{player_id=1}).snapshot.pending_skill_rewards==0,'no boss/attribute/extra skill choice rewards forged')
for _,gate in ipairs({6,10}) do
    rank(1,gate);refreshed=wrapper.refresh_simulated_hero_skills({enabled=true,player_id=1,rebirth_level=gate})
    check(#refreshed.granted==1,'one additional blade exclusive at gate '..gate)
    check(levels(1)[gate==6 and 'skill_blademaster_swiftness' or 'skill_blademaster_mobility'].locked==0,'actual configured gate unlocked')
end
check(#refreshed.eligible==4,'all four learned by rank10')
for id=0,3 do if id~=1 then check(snapshot(id).skills[1].level==0,'other player skill state untouched') end
    check(memory[id].save.gameplay_stats.map_level==({1,9,17,24})[id+1] and real_profiles[id].save.gameplay_stats.map_level==70+id,'different map levels and real archive preserved')
end
check(real_writes==0,'never apply/save a real profile')
-- All four configured heroes through every meaningful boundary, with actual
-- progression/skill state reset between independent fresh scenarios.
for _,gate in ipairs({0,1,2,3,5,6,9,10}) do
    prepare()
    for id=0,3 do rank(id,gate)
        local r=wrapper.refresh_simulated_hero_skills({enabled=true,player_id=id,rebirth_level=gate})
        check(r.ok,'four-owner formal rank refresh')
        for _,row in ipairs(definitions.rows) do if row.hero_id==native_heroes[id].hero_id and row.enabled~=false and row.guaranteed==true then
            local actual=levels(id)[row.skill_id]
            local unlocked=gate>=(tonumber(row.unlock_rebirth_level) or 1)
            check(actual and actual.level==(unlocked and row.initial_level or 0) and actual.locked==(unlocked and 0 or 1),'CSV gate matches actual skill service '..row.skill_id..' '..gate)
        end end
    end
end
scene,guard=prepare();rank(1,1)
local r=wrapper.refresh_simulated_hero_skills({enabled=true,player_id=1,rebirth_level=3})
check(not r.ok and r.error=='formal_rebirth_prerequisite_not_met' and levels(1).skill_blademaster_exclusive.level==0,'insufficient rank rejected without granting lower/higher rewards')
check(not pcall(wrapper.refresh_simulated_hero_skills,{player_id=1}),'explicit opt-in required')
check(not pcall(wrapper.refresh_simulated_hero_skills,{enabled=true,player_id=1,rebirth_level=11}),'out-of-range rank rejected')
scene.players[2].desired_hero_id='hero_monkey_king'
check(not pcall(wrapper.refresh_simulated_hero_skills,{enabled=true,player_id=1}),'wrong hero rejected');scene.players[2].desired_hero_id='hero_blademaster'
local old=memory[1];profile_override={account_id='wrong',revision=old.revision,save=old.save}
check(not pcall(wrapper.refresh_simulated_hero_skills,{enabled=true,player_id=1}),'profile alias mismatch rejected');profile_override=nil
_G.SURVIVAL_FOUR_PLAYER_LIVE_PERF.options.hero_ids[2]=nil
check(not pcall(wrapper.refresh_simulated_hero_skills,{enabled=true,player_id=2}),'wall-only participant cannot gain hero rewards')
session='other_session';check(not pcall(wrapper.refresh_simulated_hero_skills,{enabled=true,player_id=1}),'cross-session rejected');session='isolated_skill_fixture_session'
_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION={mode=world}
check(not pcall(wrapper.refresh_simulated_hero_skills,{enabled=true,player_id=1}),'guard replacement rejected');_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION=guard
world={};check(not pcall(wrapper.refresh_simulated_hero_skills,{enabled=true,player_id=1}),'cross-world rejected');world=scene.mode
scene.hero_bus_generation=nil
check(not pcall(wrapper.refresh_simulated_hero_skills,{enabled=true,player_id=1}),'old scene cannot silently adopt bus generation')
check(wrapper.refresh_simulated_hero_skills({enabled=true,player_id=1,allow_legacy_scene=true}).ok,'explicit legacy adoption after formal profile/hero/rank/skill agreement')
bus.reset();check(not pcall(real_fixture.refresh_simulated_hero_skills,{enabled=true,player_id=1}),'same-world bus generation replaced rejected')
check(real_writes==0,'all negative cases still avoid persistent profile APIs')
print('FOUR_PLAYER_SIMULATED_EXCLUSIVES_PASS '..checks..' checks (real services, simulated engine only)')
