-- Real early-final spawning/deaths -> archive admission -> four hubs. Native
-- entities/time and the durable outbox are the existing fixture boundaries.
-- A dev/monster pause must not empty the archive roster or earn clear credit.
package.path = "scripts/vscripts/?.lua;" .. package.path
package.loaded["config/player_web_auth"] = {enabled = false}

SURVIVAL_WAVE_POPULATION_FIXTURE = function(f)
    local wave = require("systems/wave_system")
    local archive = require("systems/archive_challenge_service")
    local cooperative = require("systems/archive_cooperative_reward_service")
    -- Keep the real rich mode marker/routing/placement services. Supply its
    -- Hammer player-0/portal positions inside the existing flat-terrain native
    -- fixture; this does not stand in for native pathfinding acceptance.
    local original_find = Entities.FindByName
    Entities.FindByName = function(self, previous, name)
        local point = name == "mode_rich_monster_0_spawn" and Vector(-2848, -9888, 128)
            or name == "mode_rich_player_0_spawn" and Vector(0, -9984, 128)
        if point then return {IsNull = function() return false end,
            GetAbsOrigin = function() return point end} end
        return original_find(self, previous, name)
    end
    GridNav.CanFindPath = function() return true end
    local original_height = GetGroundHeight
    GetGroundHeight = function(position, unit)
        if require("systems/match_setup_service").get_mode() == "rich" then return 128 end
        return original_height(position, unit)
    end
    local completed = 0
    local function start(difficulty, development, ids, mode, bots)
        local state = f.restart(difficulty, false, ids, mode)
        for _, id in ipairs(bots or {}) do f.set_fake(id, true) end
        f.bus.emit(f.events.GAME_STARTED, {})
        f.set_clock(60)
        if development then
            assert(wave.set_dev_mode(true), "the real Tools pause must be enabled")
        end
        local response = f.bus.request(f.events.WAVE_EARLY_FINAL_REQUEST, {})
        assert(response.ok and response.final_wave == state.total_waves)
        assert(not state.victory_settled and #f.winners() == 0)
        local callbacks = {}
        for key, callback in pairs(f.scheduled()) do
            if type(key) == "number" then callbacks[#callbacks + 1] = callback end
        end
        for _, callback in ipairs(callbacks) do callback() end
        assert(state.failed_spawn == 0 and state.spawned == state.planned and state.alive > 1,
            "use every real final-wave batch, without injecting a terminal state")
        assert(f.scheduled().wave_generation_complete)()
        assert(state.final_wave_generation_completed and not state.victory_settled)
        local victims = {}
        for _, meta in pairs(f.upvalue("enemies")) do
            assert(meta.wave_number == state.total_waves)
            victims[#victims + 1] = meta.unit
        end
        assert(#victims == state.planned)
        return state, victims
    end
    local function kill(unit)
        unit.alive = false
        f.bus.emit(f.events.ENGINE_ENTITY_KILLED, {victim = unit, victim_entindex = unit:entindex()})
    end
    local function clear(state, victims)
        for index = 1, #victims - 1 do kill(victims[index]) end
        assert(not state.victory_settled and #f.winners() == 0,
            "early completion still waits for the last real monster")
        kill(victims[#victims])
        assert(state.victory_settled and state.post_clear_frozen)
    end

    for _, case in ipairs({
        {difficulty = "N1", development = true, ids = {0}},
        {difficulty = "N10", development = true, ids = {0, 1}},
        {difficulty = "N10", development = true, ids = {0}, mode = "pure"},
        {difficulty = "N1", development = true, ids = {0}, mode = "rich"},
        {difficulty = "N20", development = true, ids = {0}, mode = "rich"},
        {difficulty = "N1", development = false, ids = {0}},
    }) do
        local state, victims = start(case.difficulty, case.development, case.ids, case.mode)
        clear(state, victims)
        assert(state.status == "archive_challenges" and not state.archive_admission_error
            and #f.winners() == 0, "a valid human early clear must enter archives before native victory")
        assert(wave.is_dev_mode() == case.development,
            "opening archives must not turn off development reward isolation")
        assert(#f.clears() == (case.development and 0 or #case.ids),
            "dev suppresses clear credit; ordinary early clears retain their one clear event")
        local players = archive._test.players()
        for _, id in ipairs(case.ids) do
            assert(players[id] and #players[id].hubs == 4 and not players[id].finished,
                "every surviving player owns four usable archive hubs")
            for index, hub in ipairs(players[id].hubs) do
                assert(hub.owner == id and hub.survival_archive_hub == index
                    and hub.survival_archive_hub_ready == true)
            end
        end
        assert(cooperative.matches_session(case.mode or "standard", case.difficulty),
            "the real cooperative authority must freeze the same mode/difficulty")
        f.final_check()
        kill(victims[#victims])
        assert(#f.winners() == 0 and archive._test.players() == players,
            "duplicate death/final checks cannot restart or prematurely finish archives")
        assert(#f.clears() == (case.development and 0 or #case.ids))

        -- Even after every player finishes, an already earned recipient intent
        -- must save. A dev pause is not permission to bypass this barrier.
        local pending_id = case.ids[#case.ids]
        f.set_pending(pending_id, true)
        for _, id in ipairs(case.ids) do assert(archive.finish_player(id, true)) end
        assert(#f.winners() == 0 and f.scheduled().archive_challenge_save_barrier,
            "pending earned rewards preserve the existing final save barrier")
        f.set_pending(pending_id, false)
        assert(f.scheduled().archive_challenge_save_barrier() == false)
        assert(#f.winners() == 1 and f.winners()[1] == DOTA_TEAM_GOODGUYS)
        assert(f.scheduled().archive_challenge_save_barrier() == false and #f.winners() == 1)
        completed = completed + 1
    end

    -- A bot-only dev final must not open a human or permanent reward route.
    -- It retains the finite admission failure and waits earlier earned saves.
    local state, victims = start("N1", true, {0}, nil, {0})
    f.set_pending(0, true)
    clear(state, victims)
    assert(state.archive_admission_error == "cooperative_roster_empty"
        and next(archive._test.players()) == nil and #f.clears() == 0)
    assert(#f.winners() == 0 and not f.scheduled().archive_challenge_begin_retry)
    local saved = assert(f.scheduled().archive_challenge_admission_save)
    assert(saved() == true and #f.winners() == 0)
    f.set_pending(0, false)
    assert(saved() == false and #f.winners() == 1)
    assert(not cooperative.matches_session("standard", "N1"))
    print("EARLY_FINAL_ARCHIVE_PHASE_PASS: " .. completed
        .. " real full-wave handoffs; dev clear credit suppressed; four hubs; normal clears; bot-only/save barriers")
end

dofile("scripts/vscripts/tests/test_wave_population_endgame.lua")
SURVIVAL_WAVE_POPULATION_FIXTURE = nil
