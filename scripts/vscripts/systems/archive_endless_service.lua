local bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local phase_guard = require("systems/gameplay_phase_guard")
local config = require("systems/archive_endless_config")
local cooperative_rewards = require("systems/archive_cooperative_reward_service")
local visual_config = require("systems/archive_endless_visual_config")
local visual_service = require("visual/endless_monster_visual_service")
local rules = config.rules
local M = {}
local runs, enemies, changed, finished = {}, {}, nil, nil
local skip_indices, skip_choices = {}, {2, 5, 10, 20}
local started_variants = {}
local subscriptions, timer_active = {}, false
local try_spawn_wave, try_spawn_next, killed
local function valid(unit) return unit and not unit:IsNull() end
local function now() return GameRules:GetGameTime() end
function M.is_running(id) return runs[id] and runs[id].status == "running" or false end
function M.skip_step(id) return skip_choices[skip_indices[id] or 0] or 1 end
function M.cycle_skip(id)
    if type(id) ~= "number" or id < 0 or id ~= math.floor(id) then return false, "player_invalid" end
    local next_index = (skip_indices[id] or 0) + 1
    if next_index > #skip_choices then return false, "已达到20层间隔，无法退回" end
    skip_indices[id] = next_index
    if runs[id] then
        -- The new interval is consumed only when the next wave is created.
        if changed then changed(id) end
    end
    return true, M.skip_step(id)
end
function M.can_rebuild_wall(id)
    if require("systems/player_context_service").is_defeated(id) then return false end
    return runs[id] and runs[id].started == true or false
end
function M.on_wall_destroyed(id)
    if not M.can_rebuild_wall(id) then return false end
    M.cancel(id, "城墙被摧毁，无尽结束，可重建城墙继续其他挑战")
    return true
end
function M.snapshot(id)
    local run = runs[id]
    if not run then return { status = "idle", wave = 0, score = 0, remaining = 0, pending = 0, seconds = 0 } end
    return { status = run.preparing and run.status == "running" and "preparing" or run.status, variant = run.variant, skip_step = M.skip_step(id),
        wave = run.wave, cleared = run.cleared, score = run.score,
        remaining = run.remaining + (run.pending or 0), pending = run.pending or 0,
        seconds = math.max(0, math.ceil((run.preparing and run.start_at or run.deadline or now()) - now())),
        reason = run.reason or "", health = tostring(run.row and run.row.health or 0),
        attack = tostring(run.row and run.row.attack or 0), armor = tostring(run.row and run.row.war3_armor or 0) }
end
local function publish(run, availability_changed)
    -- Counts and countdown ticks do not change challenge-button availability.
    -- Rebuilding all archive hubs here rewrote every ability once a second.
    if availability_changed and changed then changed(run.player_id) end
    -- Preparation has its own player notifications; the battle HUD must not
    -- show a fictitious wave zero or treat preparation as a finished battle.
    if run.preparing and run.status == "running" then return end
    if PlayerResource and CustomGameEventManager then
        local player = PlayerResource:GetPlayer(run.player_id)
        if player then CustomGameEventManager:Send_ServerToPlayer(player, "survival_endless_state", M.snapshot(run.player_id)) end
    end
end
local function cleanup(run)
    scheduler.cancel("archive_endless_next:" .. run.player_id)
    scheduler.cancel("archive_endless_spawn:" .. run.player_id)
    run.generation = (run.generation or 0) + 1
    local units = run.units
    run.units, run.remaining, run.pending, run.spawning = {}, 0, 0, false
    for id, unit in pairs(units) do
        enemies[id] = nil
        if valid(unit) then
            unit.survival_wave_cleanup = true
        end
        visual_service.clear(unit)
        require("systems/monster_hero_visual_service").clear(unit)
        if valid(unit) then
            UTIL_Remove(unit)
        end
    end
end
local function stop_idle_timer()
    for _, run in pairs(runs) do
        if run.status == "running" then return end
    end
    scheduler.cancel("archive_endless_timer")
    timer_active = false
end
local function stop(run, reason)
    if run.status ~= "running" then return end
    run.status, run.reason = "finished", reason
    run.preparing = false
    phase_guard.set_endless_active(run.player_id, false)
    cleanup(run)
    stop_idle_timer()
    publish(run, true)
    -- Ending a challenge must not leave its last completed waves waiting for
    -- the next periodic online batch.
    cooperative_rewards.flush_endless_rewards()
    if run.started and not run.finish_notified and finished then
        run.finish_notified = true
        local ok, error = pcall(finished, run.player_id, run.variant, reason)
        if not ok then print("[ArchiveEndless] finish callback failed: " .. tostring(error)) end
    end
end
function M.cancel(id, reason)
    if M.is_running(id) then stop(runs[id], reason or "主动结束") end
end
local function check_deadline(run)
    if run.preparing and require("systems/player_context_service").is_defeated(run.player_id) then
        stop(run, "本局失败"); return false, "本局失败"
    end
    local phase = bus.request("archive.challenge_state", {})
    if phase and phase.expired == 1 then stop(run, "挑战阶段时间已到"); return false, "挑战阶段时间已到" end
    if run.deadline and now() >= run.deadline then stop(run, "本波60秒超时"); return false, "本波60秒超时" end
    return true
end
local function complete_wave(run)
    if run.status ~= "running" or run.creating or run.pending > 0 or run.remaining > 0
        or run.wave_cleared then return end
    local ok, score = pcall(function()
        local next_score = run.score + config.score(run.wave, run.variant)
        local result = cooperative_rewards.record_endless_wave(run.player_id, run.wave, run.difficulty, run.variant)
        assert(type(result) == "table" and result.ok == true,
            result and result.error or "endless_reward_not_accepted")
        return next_score
    end)
    if not ok then
        stop(run, "本波结算失败，无尽已停止")
        print("[ArchiveEndless] wave settlement failed player=" .. tostring(run.player_id)
            .. " wave=" .. tostring(run.wave) .. " error=" .. tostring(score))
        return
    end
    if runs[run.player_id] ~= run or run.status ~= "running" then return end
    run.wave_cleared = true
    run.cleared, run.score = run.wave, score
    local generation = run.generation
    -- Never create the next wave recursively inside a death event.
    scheduler.after(0, function()
        if runs[run.player_id] == run and run.status == "running" and run.generation == generation then
            try_spawn_wave(run, run.wave + M.skip_step(run.player_id))
        end
    end, "archive_endless_next:" .. run.player_id)
end
local function spawn_next(run)
    local ready, reason = check_deadline(run)
    if not ready then return false, reason end
    run.creating = true
    local unit, spawn_error = require("systems/wave_system").spawn_challenge_monster({
        health = run.row.health, attack = run.row.attack, war3_armor = run.row.war3_armor,
        attack_speed = rules.attack_speed,
    }, { unit_name = "npc_survival_wave_monster", model_path = run.visual.model_path,
        model_scale = run.visual.model_scale, movement_type = "ground", attack_type = "melee",
        move_speed = rules.move_speed, attack_range = rules.attack_range, endless = true }, run.player_id)
    if not valid(unit) then error(spawn_error or "无尽怪物生成失败") end
    -- A spawn-event subscriber can end the run before the factory returns.
    if runs[run.player_id] ~= run or run.status ~= "running" then
        unit.survival_wave_cleanup = true
        visual_service.clear(unit)
        require("systems/monster_hero_visual_service").clear(unit)
        UTIL_Remove(unit)
        run.creating = false
        return false, run.reason
    end
    local id = unit:entindex()
    run.units[id] = unit
    enemies[id] = { run = run, unit = unit }
    run.remaining = run.remaining + 1
    run.pending = run.pending - 1
    run.spawning = run.pending > 0
    unit.survival_display_name = (run.variant == "tower" and "通天塔第" or "无尽第") .. run.wave .. "波 · " .. run.visual.display_name
    -- Own the unit before dressing it: failed or reentrant assembly must be
    -- cleaned with the run. A factory listener can already have killed it.
    if not unit.IsAlive or unit:IsAlive() then
        local applied, visual_error = visual_service.apply(unit, run.visual)
        if not applied then error(visual_error or "无尽怪物外观装配失败") end
    end
    if runs[run.player_id] ~= run or run.status ~= "running" then
        visual_service.clear(unit)
        run.creating = false
        return false, run.reason
    end
    if not valid(unit) then error("无尽怪物装配过程中已失效") end
    if unit.SetDeathXP then unit:SetDeathXP(0) end
    if unit.SetMinimumGoldBounty then unit:SetMinimumGoldBounty(0) end
    if unit.SetMaximumGoldBounty then unit:SetMaximumGoldBounty(0) end
    if unit.SetBaseMagicalResistanceValue then unit:SetBaseMagicalResistanceValue(rules.magic_resistance) end
    run.creating = false
    -- Cover a synchronous spawn listener killing a newborn before registration.
    if unit.IsAlive and not unit:IsAlive() then killed({ victim = unit, victim_entindex = id }) end
    if run.status ~= "running" then return false, run.reason end
    if run.pending > 0 then
        local generation = run.generation
        -- Schedule from now: a late engine tick must not create several units
        -- in the same frame to catch up with missed birth deadlines.
        scheduler.after(math.max(0.1, tonumber(rules.spawn_interval) or 0.5), function()
            if runs[run.player_id] == run and run.status == "running" and run.generation == generation then
                try_spawn_next(run)
            end
        end, "archive_endless_spawn:" .. run.player_id)
    else
        complete_wave(run)
    end
    publish(run)
    return true
end
local function spawn_failed(run, err)
    run.creating = false
    stop(run, "怪物生成失败，本波不计分")
    print("[ArchiveEndless] wave setup failed player=" .. tostring(run.player_id)
        .. " wave=" .. tostring(run.wave) .. " error=" .. tostring(err))
    return false, "无尽怪物生成失败"
end
try_spawn_next = function(run)
    local ok, result, reason = pcall(spawn_next, run)
    if ok then return result, reason end
    return spawn_failed(run, result)
end
local function spawn_wave(run, number)
    local phase = bus.request("archive.challenge_state", {})
    if phase and phase.expired == 1 then stop(run, "挑战阶段时间已到"); return false, "挑战阶段时间已到" end
    local row = config.wave(run.difficulty, number, run.mode)
    if not row then stop(run, "已完成全部配置波次"); return true end
    run.wave, run.row, run.remaining, run.units = number, row, 0, {}
    -- Resolve once for the whole wave, keeping all five births identical and
    -- leaving countdowns and death notifications free of model work.
    local visual, visual_error = visual_config.resolve(number)
    if not visual then error(visual_error or "无尽怪物外观配置缺失") end
    run.visual = visual
    run.generation = (run.generation or 0) + 1
    run.pending = math.max(1, math.floor(tonumber(rules.monsters_per_wave) or 5))
    run.wave_cleared = false
    run.spawning = true
    -- The absolute limit covers spawning too; births cannot extend the wave.
    run.deadline = now() + rules.time_limit_seconds
    run.last_second = math.ceil(rules.time_limit_seconds)
    local ok, reason = try_spawn_next(run)
    if not ok then return false, reason end
    bus.emit("commerce.endless_wave", {player_id = run.player_id, wave = number})
    return true
end
try_spawn_wave = function(run, number)
    local ok, result, reason = pcall(spawn_wave, run, number)
    if ok then return result, reason end
    return spawn_failed(run, result)
end
local function announce_start(run, seconds)
    bus.emit(events.UI_NOTIFICATION, {player_id = run.player_id, level = "info", kind = "endless_tip",
        message = seconds > 0 and ("还有" .. seconds .. "秒开启无尽挑战") or "无尽挑战现在开始！"})
end
local function ensure_timer()
    if timer_active then return end
    timer_active = true
    scheduler.every(0.25, function()
        for _, run in pairs(runs) do
            if run.status == "running" and not run.wave_cleared and check_deadline(run) then
                if run.preparing then
                    local seconds = math.max(0, math.ceil(run.start_at - now()))
                    if seconds == 0 then
                        run.preparing = false
                        local ok = try_spawn_wave(run, 1)
                        run.started = ok == true
                        if ok and run.status == "running" then announce_start(run, 0); publish(run, true) end
                    elseif now() >= run.next_notice_at then
                        announce_start(run, seconds)
                        run.next_notice_at = now() + 5
                    end
                else
                    local second = math.ceil(run.deadline - now())
                    if run.last_second ~= second then run.last_second = second; publish(run) end
                end
            end
        end
        stop_idle_timer()
        if not timer_active then return false end
    end, "archive_endless_timer")
end
function M.start(id, difficulty, variant)
    variant = variant or "endless"
    if require("systems/player_context_service").is_defeated(id) then return false, "player_defeated" end
    if M.is_running(id) then return false, "无尽挑战正在进行" end
    if started_variants[id] and started_variants[id][variant] then return false, "本局已开启该挑战" end
    local setup = package.loaded["systems/match_setup_service"]
    local mode = setup and type(setup.get_mode) == "function" and setup.get_mode() or "standard"
    if not cooperative_rewards.matches_session(mode, difficulty) then return false, "cooperative_session_invalid" end
    if not config.allowed_variant(difficulty, mode, variant) then return false, "endless_variant_unavailable" end
    if not config.wave(difficulty, 1, mode) then return false, "该难度无尽属性尚未配置" end
    local phase = bus.request("archive.challenge_state", {})
    if phase and phase.expired == 1 then return false, "挑战阶段时间已到" end
    if not phase_guard.set_endless_active(id, true) then return false, "本局已结束" end
    local previous = runs[id]
    local previous_skip = skip_indices[id]
    if previous and previous.variant ~= variant then skip_indices[id] = nil end
    local run = { player_id = id, difficulty = difficulty, mode = mode, variant = variant, status = "running", wave = 0,
        cleared = 0, score = 0, units = {}, remaining = 0, pending = 0 }
    runs[id] = run
    -- Keep ordinary gameplay alive, including the queued frame between waves.
    local delay = variant == "endless" and math.max(0, tonumber(rules.start_delay_seconds) or 20) or 0
    local ok, reason
    if delay > 0 then
        run.preparing, run.start_at, run.next_notice_at = true, now() + delay, now() + 5
        ok = true
        announce_start(run, math.ceil(delay))
        if runs[id] ~= run or run.status ~= "running" then return false, run.reason or "无尽准备已取消" end
    else
        ok, reason = try_spawn_wave(run, 1)
    end
    run.started = ok == true and not run.preparing
    if ok then
        started_variants[id] = started_variants[id] or {}
        started_variants[id][variant] = true
    else
        skip_indices[id] = previous_skip
    end
    if ok and run.status == "running" then ensure_timer(); publish(run, true) end
    return ok, reason
end
killed = function(payload)
    local unit = payload and payload.victim
    local id = tonumber(payload and payload.victim_entindex) or (valid(unit) and unit:entindex())
    local meta = id and enemies[id]
    if not meta or (unit and unit ~= meta.unit) then return end
    local run = meta.run
    if run.status ~= "running" or not check_deadline(run) then return end
    enemies[id], run.units[id] = nil, nil
    run.remaining = run.remaining - 1
    visual_service.on_death(meta.unit)
    require("systems/monster_hero_visual_service").on_death(meta.unit)
    complete_wave(run)
    publish(run)
end
function M.init(on_changed, on_finished)
    scheduler.cancel("archive_endless_timer")
    timer_active = false
    for _, subscription in ipairs(subscriptions) do bus.unsubscribe(subscription) end
    subscriptions = {}
    for id, run in pairs(runs) do
        run.status = "finished"
        phase_guard.set_endless_active(id, false)
        cleanup(run)
    end
    runs, enemies, skip_indices, changed, finished = {}, {}, {}, on_changed, on_finished
    started_variants = {}
    subscriptions[#subscriptions + 1] = bus.subscribe(events.ENGINE_ENTITY_KILLED, killed)
    subscriptions[#subscriptions + 1] = bus.subscribe(events.PLAYER_DEFEATED, function(payload)
        M.cancel(tonumber(payload.player_id), "本局失败")
    end)
end
return M
