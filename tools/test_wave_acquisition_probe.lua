package.path='scripts/vscripts/?.lua;'..package.path
local probe=require('tests/manual_wave_acquisition_probe')
assert(_G.SURVIVAL_WAVE_ACQUISITION_PROBE==nil,'Require must remain inert/default off')
local mode,session,tools={},'acquisition_test',true
IsServer=function() return true end;IsInToolsMode=function() return tools end
GetMapName=function() return 'template_map' end
GameRules={GetGameModeEntity=function() return mode end,GetGameTime=function() return 50 end}
DOTA_TEAM_BADGUYS=3
package.loaded['systems/match_setup_service']={get_mode=function() return 'standard' end,get_session_id=function() return session end}
package.loaded['systems/wave_native_attack_cap']={is_bare_creature=function(name) return name=='known_bare' end,
    is_inert_native_warp=function(a,slot) return a.name=='inert_warp' and slot==0 end}
local bus=require('core/event_bus');local events=require('core/events')
local guard={mode=mode};_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION=guard
local fixture={mode=mode,guard=guard,status='ready'};_G.SURVIVAL_FOUR_PLAYER_LIVE_PERF=fixture
local serial=0
local function unit()
    serial=serial+1
    local u={index=serial,alive=true,team=3,name='known_bare',acquisition=700,idle=true,survival_is_wave_monster=true,
        abilities={},native_orders=0,stats={attack=10,attack_speed=1.4,BAT=0.714,range=600,health=1000},writes=0,target={}}
    function u:IsNull() return false end;function u:IsAlive() return self.alive end
    function u:entindex() return self.index end;function u:GetTeamNumber() return self.team end
    function u:IsRealHero() return self.hero==true end;function u:IsIllusion() return self.illusion==true end
    function u:GetClassname() return 'npc_dota_creature' end;function u:GetUnitName() return self.name end
    function u:GetAbilityCount() return #self.abilities end;function u:GetAbilityByIndex(index) return self.abilities[index+1] end
    function u:GetAcquisitionRange() return self.acquisition end
    function u:SetIdleAcquire(value) assert(value==false);self.idle=value;self.writes=self.writes+1 end
    function u:SetAcquisitionRange(value) assert(value==0);self.acquisition=value;self.writes=self.writes+1 end
    function u:FindModifierByName(name)
        if self.no_ai then return nil end
        assert(name=='modifier_enemy_wall_ai')
        return {IsNull=function() return false end,GetParent=function() return self end}
    end
    function u:Stop() error('Must not stop the original attack') end
    function u:SetForceAttackTarget() error('Must not modify native aggro') end
    function u:SetBaseAttackTime() error('Must not modify attack speed') end
    function u:SetHealth() error('Must not modify damage or health') end
    return u
end
local function spawn(u,source) bus.emit(events.MONSTER_SPAWNED,{unit=u,monster_source=source or 'wave'}) end
assert(probe.snapshot().enabled==false)
local old=unit()
tools=false;assert(not pcall(probe.enable),'Non-Tools invocation rejected');tools=true
probe.enable()
assert(old.writes==0,'Enabling must not scan or mutate preexisting units')
local u=unit();local target=u.target;spawn(u)
assert(u.idle==false and u.acquisition==700 and u.writes==1 and u.target==target and u.stats.attack_speed==1.4)
spawn(u);assert(u.writes==1,'Duplicate notifications must not replace original-state evidence')
local snapshot=probe.snapshot()
assert(snapshot.processed==1 and snapshot.modified==1 and snapshot.samples[1].initial_acquisition==700 and snapshot.samples[1].after_acquisition==700)
assert(snapshot.skipped_reasons.duplicate_spawn_notification==1 and snapshot.requires_map_reload_to_restore_modified_units)
local excluded={
    function(v) v.hero=true end,function(v) v.illusion=true end,function(v) v.survival_is_challenge_monster=true end,
    function(v) v.survival_training_id='worker' end,function(v) v.survival_blademaster_clone=true end,
    function(v) v.survival_hero_id='hero_doom' end,function(v) v.survival_visual_only=true end,
    function(v) v.team=2 end,function(v) v.survival_is_wave_monster=false end,function(v) v.no_ai=true end,
    function(v) v.name='unknown_native' end,function(v) v.abilities={{name='real_passive',IsNull=function() return false end}} end}
for _,change in ipairs(excluded) do local v=unit();change(v);spawn(v);assert(v.writes==0,'Excluded role/unknown native behavior must retain native parameters') end
local encounter=unit();spawn(encounter,'building_challenge');assert(encounter.writes==0)
local dead=unit();dead.alive=false;spawn(dead);assert(dead.writes==0)
local warp=unit();warp.abilities={{name='inert_warp',IsNull=function() return false end}};spawn(warp);assert(warp.writes==1)
probe.stop('candidate_end');assert(u.idle==false and u.acquisition==700 and u.writes==1,'Stop cannot invent an original idle boolean or restore mutated units')
local after_stop=unit();spawn(after_stop);assert(after_stop.writes==0)
probe.enable({zero_acquisition=true})
local both=unit();spawn(both)
assert(both.idle==false and both.acquisition==0 and both.writes==2)
snapshot=probe.snapshot();assert(snapshot.samples[1].initial_acquisition==700 and snapshot.samples[1].after_acquisition==0)
local partial=unit();partial.SetAcquisitionRange=function() error('native setter failed') end;spawn(partial)
snapshot=probe.snapshot();assert(snapshot.failed==1 and snapshot.modified==2 and partial.idle==false and partial.acquisition==700)
assert(snapshot.samples[2].failure=='acquisition_set_failed' and not snapshot.samples[2].success,'Partial native mutation requires map reload; never fake rollback')
for _=1,60 do spawn(unit()) end
snapshot=probe.snapshot();assert(snapshot.processed==61 and #snapshot.samples==32,'All counters remain complete with bounded first-32 evidence')
session='another_session';local stale=unit();spawn(stale)
assert(stale.writes==0 and probe.snapshot().enabled==false and probe.snapshot().stop_reason=='fixture_or_session_changed')
session='acquisition_test';probe.enable();mode={};local other_world=unit();spawn(other_world)
assert(other_world.writes==0 and not probe.snapshot().enabled,'No writes after GameMode replacement')
print('WAVE_ACQUISITION_PROBE_PASS: inert Tools gate; new formal waves only; bare-native/owned-AI exclusions; no scan/orders/stats mutation; exact initial range; bounded samples; duplicate guard; partial failure evidence; no invented idle restoration; session/world stop')
