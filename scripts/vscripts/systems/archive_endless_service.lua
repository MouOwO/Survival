local bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local config = require("systems/archive_endless_config")
local rules = config.rules
local M = {}
local runs, enemies, changed = {}, {}, nil
local function valid(unit) return unit and not unit:IsNull() end
local function now() return GameRules:GetGameTime() end
function M.is_running(id) return runs[id] and runs[id].status == "running" or false end
function M.can_rebuild_wall(id)
    return runs[id] and runs[id].started == true or false
end
function M.on_wall_destroyed(id)
    if not M.can_rebuild_wall(id) then return false end
    M.cancel(id, "城墙被摧毁，无尽结束，可重建城墙继续其他挑战")
    return true
end
function M.snapshot(id)
    local run = runs[id]
    if not run then return { status = "idle", wave = 0, score = 0, remaining = 0, seconds = 0 } end
    return { status = run.status, wave = run.wave, cleared = run.cleared, score = run.score,
        remaining = run.remaining, seconds = math.max(0, math.ceil((run.deadline or now()) - now())),
        reason = run.reason or "", health = tostring(run.row and run.row.health or 0),
        attack = tostring(run.row and run.row.attack or 0), armor = tostring(run.row and run.row.war3_armor or 0) }
end
local function publish(run)
    if changed then changed(run.player_id) end
    if PlayerResource and CustomGameEventManager then
        local player = PlayerResource:GetPlayer(run.player_id)
        if player then CustomGameEventManager:Send_ServerToPlayer(player, "survival_endless_state", M.snapshot(run.player_id)) end
    end
end
local function cleanup(run)
    scheduler.cancel("archive_endless_next:" .. run.player_id)
    for id, unit in pairs(run.units) do
        enemies[id] = nil
        if valid(unit) then
            require("systems/monster_hero_visual_service").clear(unit)
            UTIL_Remove(unit)
        end
    end
    run.units, run.remaining = {}, 0
end
local function stop(run, reason)
    run.status, run.reason = "finished", reason
    cleanup(run)
    publish(run)
end
function M.cancel(id, reason)
    if M.is_running(id) then stop(runs[id], reason or "主动结束") end
end
local function spawn_wave(run, number)
    local row = config.wave(run.difficulty, number)
    if not row then stop(run, "已完成全部配置波次"); return true end
    run.wave, run.row, run.remaining, run.units = number, row, 0, {}
    run.spawning = true
    for _ = 1, rules.monsters_per_wave do
        local ok, unit = pcall(function()
            return require("systems/wave_system").spawn_challenge_monster({
                health = row.health, attack = row.attack, war3_armor = row.war3_armor, attack_speed = rules.attack_speed,
            }, { unit_name = "npc_survival_wave_monster", model_path = rules.model_path,
                model_scale = rules.model_scale, movement_type = "ground", attack_type = "melee",
                move_speed = rules.move_speed, attack_range = rules.attack_range, endless = true }, run.player_id)
        end)
        if not ok or not valid(unit) then
            run.spawning = false
            stop(run, "怪物生成失败，本波不计分")
            return false, "无尽怪物生成失败"
        end
        run.units[unit:entindex()] = unit
        enemies[unit:entindex()] = { run = run, unit = unit }
        run.remaining = run.remaining + 1
        unit.survival_display_name = "无尽第" .. number .. "波"
        if unit.SetDeathXP then unit:SetDeathXP(0) end
        if unit.SetMinimumGoldBounty then unit:SetMinimumGoldBounty(0) end
        if unit.SetMaximumGoldBounty then unit:SetMaximumGoldBounty(0) end
        if unit.SetBaseMagicalResistanceValue then unit:SetBaseMagicalResistanceValue(rules.magic_resistance) end
    end
    run.spawning = false
    run.deadline = now() + rules.time_limit_seconds
    publish(run)
    return true
end
function M.start(id, difficulty)
    if M.is_running(id) then return false, "无尽挑战正在进行" end
    if runs[id] and runs[id].started then return false, "本局已开启无尽挑战" end
    if not config.wave(difficulty, 1) then return false, "该难度无尽属性尚未配置" end
    local run = { player_id = id, difficulty = difficulty, status = "running", wave = 0,
        cleared = 0, score = 0, units = {}, remaining = 0 }
    runs[id] = run
    local ok, reason = spawn_wave(run, 1)
    run.started = ok == true
    return ok, reason
end
local function killed(payload)
    local unit = payload and payload.victim
    local id = tonumber(payload and payload.victim_entindex) or (valid(unit) and unit:entindex())
    local meta = id and enemies[id]
    if not meta or (unit and unit ~= meta.unit) then return end
    local run = meta.run
    if run.status ~= "running" or run.spawning then return end
    if now() >= run.deadline then stop(run, "本波60秒超时"); return end
    enemies[id], run.units[id] = nil, nil
    run.remaining = run.remaining - 1
    require("systems/monster_hero_visual_service").clear(meta.unit)
    if run.remaining == 0 then
        run.cleared = run.wave
        run.score = run.score + config.score(run.wave)
        require("systems/archive_service").record_endless_wave(run.player_id, run.wave, run.difficulty)
        -- Queue at zero delay to avoid recursive spawning inside a death event.
        scheduler.after(0, function()
            if runs[run.player_id] == run and run.status == "running" then spawn_wave(run, run.wave + 1) end
        end, "archive_endless_next:" .. run.player_id)
    end
    publish(run)
end
function M.init(on_changed)
    runs, enemies, changed = {}, {}, on_changed
    bus.subscribe(events.ENGINE_ENTITY_KILLED, killed)
    scheduler.every(0.1, function()
        for _, run in pairs(runs) do
            if run.status == "running" and run.remaining > 0 and not run.spawning then
                if now() >= run.deadline then stop(run, "本波60秒超时")
                elseif run.last_second ~= math.ceil(run.deadline - now()) then
                    run.last_second = math.ceil(run.deadline - now()); publish(run)
                end
            end
        end
    end, "archive_endless_timer")
end
return M
