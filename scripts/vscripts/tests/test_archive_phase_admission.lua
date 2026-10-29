-- Real final-wave handoff/classification and save barrier. The reused fixture
-- supplies native entities/time and durable outbox boundaries, never rewards.
package.path="scripts/vscripts/?.lua;"..package.path
package.loaded["core/test_access_policy"]={enabled=function() return false end,
    enforce=function() return true end,allowed=function() return true end}
SURVIVAL_WAVE_POPULATION_FIXTURE=function(f)
    local cooperative=require("systems/archive_cooperative_reward_service")
    local archive=require("systems/archive_service")
    local retry_key="archive_challenge_begin_retry"
    local save_key="archive_challenge_admission_save"
    local finalizations,cooperative_pending,notifications=0,false,0
    cooperative.has_pending=function() return cooperative_pending end
    archive.begin_finalization=function() finalizations=finalizations+1 end
    local function setup(players)
        finalizations,cooperative_pending,notifications=0,false,0
        local state=f.restart("N1",true,players or {0,1})
        cooperative.init()
        f.bus.subscribe(f.events.UI_NOTIFICATION,function() notifications=notifications+1 end)
        return state
    end
    local function admit(payload)
        local ok,reason=cooperative.begin(payload.player_ids,payload.difficulty_id)
        return {ok=ok,keep_running=ok,error=reason}
    end
    local function terminal(state)
        f.final_ready(state)
        f.final_check()
        assert(state.victory_settled and state.post_clear_frozen)
    end
    local function run(key)
        local callback=assert(f.scheduled()[key],"expected scheduled "..key)
        local again=callback()
        if again==false then f.scheduled()[key]=nil end
        return again
    end

    -- The genuine strict cooperative admission rejects a bot-only victory.
    -- Its former infinite retry now waits both real reward outboxes then wins.
    local state=setup()
    f.set_fake(0,true);f.set_fake(1,true)
    f.bus.handle_request("archive.challenge_begin",admit)
    f.set_pending(1,true);cooperative_pending=true
    terminal(state)
    assert(state.archive_admission_error=="cooperative_roster_empty")
    assert(not f.scheduled()[retry_key] and f.scheduled()[save_key])
    assert(#f.winners()==0 and finalizations==0 and notifications==2)
    f.upvalue("stop_defeated_match")()
    assert(not state.defeat_settled and state.challenge_saving==1 and f.scheduled()[save_key],
        "late personal disconnect defeat cannot cancel the already won match's save barrier")
    assert(run(save_key)==true and finalizations==0,"unhanded cooperative intent precedes finalization")
    cooperative_pending=false
    assert(run(save_key)==true and finalizations==1 and #f.winners()==0)
    f.set_pending(1,false)
    assert(run(save_key)==false and #f.winners()==1 and finalizations==1)

    -- A disconnected account is absent from active_player_ids but remains a
    -- participant; rewards earned before its disconnect cannot be abandoned.
    state=setup()
    f.set_active_players({})
    f.set_pending(0,true)
    f.bus.handle_request("archive.challenge_begin",admit)
    terminal(state)
    assert(state.archive_admission_error=="cooperative_roster_empty")
    assert(#f.winners()==0 and finalizations==1)
    f.set_pending(0,false)
    assert(run(save_key)==false and #f.winners()==1)

    -- A late-loading handler receives the original frozen tier and clears
    -- exactly once, without skipping a normal challenge phase.
    state=setup()
    terminal(state)
    assert(state.status=="archive_challenges_pending" and state.archive_admission_deadline==30)
    assert(#f.clears()==2 and #f.winners()==0 and finalizations==0)
    f.set_clock(10)
    f.bus.handle_request("archive.challenge_begin",admit)
    assert(run(retry_key)==false and state.status=="archive_challenges")
    assert(#f.clears()==2 and #f.winners()==0 and finalizations==0)

    -- Transient profile loading has the same finite budget; repeated attempts
    -- cannot slide the deadline. Existing clear rewards still gate victory.
    state=setup()
    f.bus.handle_request("archive.challenge_begin",function()
        return {ok=false,error="profile_not_loaded"}
    end)
    f.set_pending(0,true)
    terminal(state)
    f.set_clock(29)
    assert(run(retry_key)==true and state.archive_admission_deadline==30)
    f.set_clock(30)
    assert(run(retry_key)==false and state.archive_admission_error=="archive_admission_timeout")
    assert(state.challenge_saving==1 and state.challenge_ended==1 and #f.winners()==0)
    assert(#f.clears()==2 and finalizations==1 and notifications==2)
    f.set_pending(0,false)
    assert(run(save_key)==false and #f.winners()==1)

    -- A permanent mode/config mismatch must not repeatedly consume admission.
    state=setup()
    local difficulties=require("config/difficulty_config")
    local original_get=difficulties.get
    f.bus.handle_request("archive.challenge_begin",admit)
    f.final_ready(state)
    difficulties.get=function() return nil end
    f.final_check()
    difficulties.get=original_get
    assert(state.archive_admission_error=="archive_mode_difficulty_unavailable")
    assert(not f.scheduled()[retry_key] and #f.winners()==1 and finalizations==1)

    -- Unexpected invariant errors notify and settle, while a successful no-
    -- phase response still observes the previously enqueued save barrier.
    state=setup()
    f.bus.handle_request("archive.challenge_begin",function()
        return {ok=false,error="cooperative_roster_already_started"}
    end)
    terminal(state)
    assert(state.archive_admission_error=="cooperative_roster_already_started")
    assert(not f.scheduled()[retry_key] and notifications==2 and #f.winners()==1)
    state=setup()
    f.bus.handle_request("archive.challenge_begin",function() return {ok=true,keep_running=false} end)
    f.set_pending(1,true)
    terminal(state)
    assert(state.challenge_saving==1 and #f.winners()==0 and notifications==0)
    f.set_pending(1,false)
    assert(run(save_key)==false and #f.winners()==1)

    -- Final online credit can enqueue another reward during finalization. A
    -- transient flush exception retains a save retry instead of losing it.
    state=setup()
    local flush_attempts=0
    archive.begin_finalization=function()
        flush_attempts=flush_attempts+1
        if flush_attempts==1 then error("offline fixture provider temporarily unavailable") end
        finalizations=finalizations+1
        f.set_pending(0,true)
    end
    f.bus.handle_request("archive.challenge_begin",function() return {ok=true,keep_running=false} end)
    terminal(state)
    assert(flush_attempts==1 and #f.winners()==0 and f.scheduled()[save_key])
    assert(run(save_key)==true and flush_attempts==2 and finalizations==1 and #f.winners()==0)
    f.set_pending(0,false)
    assert(run(save_key)==false and flush_attempts==2 and #f.winners()==1)
end
dofile("scripts/vscripts/tests/test_wave_population_endgame.lua")
SURVIVAL_WAVE_POPULATION_FIXTURE=nil
print("ARCHIVE_PHASE_ADMISSION_PASS: strict human/config failures, late handler, fixed 30s retry, disconnected/cooperative/clear save barriers")
