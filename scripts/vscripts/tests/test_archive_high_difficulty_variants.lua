-- Real mode admission, cooperative dispatcher, endless engine and reducer.
-- Engine/profile sinks are isolated fixtures; no network/account writes.
package.path="scripts/vscripts/?.lua;"..package.path
local bus,events=require("core/event_bus"),require("core/events")
local scheduler=require("core/scheduler")
local guard=require("systems/gameplay_phase_guard")
local multiplayer=require("systems/multiplayer_player_service")
local config=require("systems/archive_endless_config")
local difficulties=require("config/difficulty_config")
local reducer=require("systems/archive_settlement")
local clock,mode,difficulty,units,records,profiles,callbacks,checks=0,"standard",10,{},{},{},{},0
local function check(value,message) checks=checks+1; assert(value,message) end
local function copy(value)
    if type(value)~="table" then return value end
    local result={};for key,child in pairs(value) do result[key]=copy(child) end;return result
end
DOTA_TEAM_GOODGUYS=2
GameRules={GetGameTime=function() return clock end}
PlayerResource={IsValidPlayerID=function(_,id) return id==0 or id==1 end,
    IsFakeClient=function() return false end,GetTeam=function() return 2 end,
    GetPlayer=function(_,id) return (id==0 or id==1) and {id=id} or nil end}
CustomGameEventManager={Send_ServerToPlayer=function() end}
package.loaded["systems/player_context_service"]={is_defeated=function() return false end,
    active_player_ids=function() return {0,1} end}
package.loaded["systems/match_setup_service"]={get_mode=function() return mode end}
package.loaded["visual/endless_monster_visual_service"]={apply=function() return true end,
    clear=function() end,on_death=function() end}
package.loaded["systems/monster_hero_visual_service"]={clear=function() end,on_death=function() end}
package.loaded["systems/wave_system"]={get_difficulty=function() return "N"..difficulty end,
    spawn_challenge_monster=function(row,definition,id)
        local unit={index=#units+1,row=copy(row),owner=id,alive=true}
        function unit:IsNull() return self.removed==true end
        function unit:IsAlive() return self.alive end
        function unit:entindex() return self.index end
        function unit:SetDeathXP(value) check(value==0,"endless has no incidental XP") end
        function unit:SetMinimumGoldBounty(value) check(value==0,"endless has no incidental gold") end
        unit.SetMaximumGoldBounty=unit.SetMinimumGoldBounty
        function unit:SetBaseMagicalResistanceValue() end
        units[#units+1]=unit
        return unit
    end}
UTIL_Remove=function(unit) unit.removed=true end
local function reward(id,wave,tier,variant)
    records[#records+1]={id=id,wave=wave,tier=tier,variant=variant or "endless"}
    local command={id="offline-test:"..(variant or "endless")..":"..wave,kind="endless",
        wave=wave,difficulty=tier,day_key="20410"}
    if variant=="tower" then command.variant=variant end
    local result=reducer.settle(profiles[id],command,false)
    check(result.ok,"real reducer accepts configured high-tier intent")
    if result.ok then
        profiles[id].save.archive=result.archive
        profiles[id].save.gameplay_stats=result.gameplay_stats
    end
    return {ok=result.ok,error=result.error}
end
package.loaded["systems/archive_service"]={record_endless_wave=reward,
    record_challenge=function(id,challenge,sequence,tier)
        records[#records+1]={id=id,challenge=challenge,tier=tier};return {ok=true}
    end,flush_endless_rewards=function() end}
local cooperative=require("systems/archive_cooperative_reward_service")
-- This fixture isolates combat after entry; countdown has its own timing test.
require("systems/archive_endless_config").rules.start_delay_seconds = 0
local endless=require("systems/archive_endless_service")
local function reset(next_mode,tier)
    -- Reset the real engine before changing its native fixture world.
    endless.init()
    bus.reset();scheduler.clear();multiplayer._reset_for_test();guard.reset()
    clock,mode,difficulty,units,records,callbacks=0,next_mode,tier,{},{},{}
    profiles={[0]={save={archive={},gameplay_stats={}}},[1]={save={archive={},gameplay_stats={}}}}
    multiplayer.mark_connected(0);multiplayer.mark_connected(1)
    guard.set_post_clear_frozen(true)
    cooperative.init()
    endless.init(function() end,function(id,variant,reason)
        callbacks[#callbacks+1]={id=id,variant=variant,reason=reason}
    end)
    bus.handle_request("archive.challenge_state",function() return {expired=0} end)
end
local function begin()
    local ok,reason=cooperative.begin({0,1},"N"..difficulty)
    check(ok,reason or "legal frozen session")
end
local function kill_wave(id)
    local target=endless.snapshot(id).wave
    for _=1,50 do
        for _,unit in ipairs(units) do
            if unit.owner==id and unit.alive and not unit.removed then
                unit.alive=false
                bus.emit(events.ENGINE_ENTITY_KILLED,{victim=unit,victim_entindex=unit.index})
            end
        end
        local snapshot=endless.snapshot(id)
        if snapshot.cleared==target or snapshot.status~="running" then return snapshot end
        clock=clock+config.rules.spawn_interval;scheduler.think()
    end
    error("wave failed to complete")
end

check(config.score(1)==1 and config.score(10)==1 and config.score(11)==2 and config.score(21)==3,
    "video score is one base point plus 100 percent per ten cleared layers")
check(config.score(1,"tower")==2 and config.score(11,"tower")==4,
    "solo tower uses the explicit project multiplier over the same ten-layer blocks")

-- Admission follows each actual configured mode, not a universal N50 cap.
for id,rows in pairs(difficulties.rows_by_mode) do
    local maximum=#rows
    reset(id,maximum);begin()
    check(cooperative.matches_session(id,maximum),"frozen exact mode/tier")
    check(not cooperative.matches_session("unknown",maximum),"forged mode rejected")
    check(cooperative.record_challenge(0,"shadow_1",1,"N"..maximum).ok,"high-tier challenge dispatch accepted")
    check(#records==2,"both legitimate winners receive a challenge intent")
    reset(id,maximum+1)
    check(not cooperative.begin({0,1},"N"..difficulty),"next tier above this mode is rejected")
end
reset("standard",11)
check(not cooperative.begin({0,1},"N11"),"standard N11 is not admitted as a high mode")
reset("cold",50);begin()
check(config.wave(50,1,"cold")==config.wave(1,1,"standard"),"all difficulties query the same fixed endless stats")
check(config.wave(50,1,"standard")==nil,"explicit standard mode cannot query N50 as admission")
check(not endless.start(0,49),"caller cannot substitute the frozen difficulty")
check(endless.start(0,50),"rejected start does not consume the legitimate run")
local first=kill_wave(0)
check(first.cleared==1 and first.score==config.score(1),"actual wave alone earns score")
check(#records==2 and records[1].tier==50 and records[2].tier==50,"high-tier intent retains N50 for both recipients")
check(profiles[0].save.archive.endless_score==config.score(1)
    and profiles[1].save.archive.endless_score==config.score(1),"real reducer pays both accounts")
check(cooperative.record_endless_wave(1,1,50).duplicate and #records==2,"shared wave cannot pay twice")

-- Choosing a larger next-wave step does not clear or award skipped waves.
check(endless.skip_step(0)==1,"default wave increment is one")
for _,step in ipairs({2,5,10,20}) do
    local ok,value=endless.cycle_skip(0)
    check(ok and value==step and endless.skip_step(0)==step,"skip step only moves forward")
end
check(not endless.cycle_skip(0) and endless.skip_step(0)==20,"20 cannot wrap back to 2")
check(#records==2,"changing skip interval cannot award any wave")
scheduler.think()
check(endless.snapshot(0).wave==21,"the queued next wave consumes the selected increment")
local second=kill_wave(0)
check(second.cleared==21 and second.score==config.score(1)+config.score(21),"only actual waves 1 and 21 count")
check(#records==4,"jumped waves 2..20 have no reward intent")

-- Mutating the world mode after freezing cannot silently add local score.
mode="standard"
scheduler.think()
local rejected=kill_wave(0)
check(rejected.status=="finished" and rejected.score==second.score and #records==4,"failed reward admission stops without false score")
check(#callbacks==1 and callbacks[1].variant=="endless","finish callback fires once")
endless.cancel(0,"repeat")
check(#callbacks==1,"cancel cannot repeat the finish callback")

-- Solo tower is mode-gated and never copied to the teammate's account.
for _,id in ipairs({"standard","pure","rich"}) do
    reset(id,10);begin()
    check(not endless.start(0,10,"tower"),"tower unavailable outside cold/scourge")
    check(endless.start(0,10,"endless"),"invalid variant did not consume ordinary entry")
end
reset("cold",9);begin()
check(not endless.start(0,9,"tower"),"tower requires current N10")
for _,id in ipairs({"cold","scourge"}) do
    reset(id,10);begin()
    check(endless.start(0,10,"tower"),"legal solo tower starts at wave one")
    check(endless.snapshot(0).wave==1 and endless.snapshot(0).variant=="tower","tower has its own explicit identity")
    local snapshot=kill_wave(0)
    check(#records==1 and records[1].id==0 and records[1].variant=="tower","tower intent only belongs to the source")
    check(profiles[1].save.archive.endless_score==nil,"teammate receives no solo tower score")
    check(snapshot.score==config.score(1,"tower"),"tower runtime score follows configured multiplier")
    check(cooperative.record_endless_wave(0,1,10,"tower").duplicate,"same source cannot repeat tower reward")
    check(cooperative.record_endless_wave(1,1,10,"tower").ok and #records==2,"another source owns its independent tower wave")
    endless.cancel(0,"tower completed")
    check(#callbacks==1 and callbacks[1].variant=="tower" and callbacks[1].id==0,"root receives solo tower completion")
end
-- Each mode entrance is usable once. Ordinary endless need not prevent the
-- final solo tower, but no second run may coexist with the first.
reset("cold",10);begin()
check(endless.start(0,10,"endless"),"ordinary endless starts before the final tower")
for _=1,4 do check(endless.cycle_skip(0),"advance ordinary skip interval") end
check(not endless.start(0,10,"tower"),"a different variant cannot bypass the active-run guard")
kill_wave(0)
endless.cancel(0,"ordinary completed")
check(not endless.start(0,10,"endless"),"ordinary entrance remains once per match")
check(endless.start(0,10,"tower"),"finished ordinary endless leaves the final tower available")
check(endless.skip_step(0)==1 and endless.snapshot(0).wave==1,"a new variant starts from its own default step")
kill_wave(0)
check(profiles[0].save.archive.endless_score==3 and profiles[1].save.archive.endless_score==1,
    "ordinary shared points and solo tower points keep separate identities")
endless.cancel(0,"tower completed")
check(not endless.start(0,10,"tower"),"tower entrance is also once per match")
print("PASS archive high difficulty/variants: "..checks.." checks; mode bounds, frozen identities, exact score admission, skipped waves, solo tower and callbacks")
