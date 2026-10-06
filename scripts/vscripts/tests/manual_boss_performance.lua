-- Explicit tools-only capture: script_reload_code tests/manual_boss_performance
-- Inclusive callback clock costs and API counts; no FPS/GPU/particle-alive claims.
local M = {}
local KEY, THINK = "SURVIVAL_BOSS_PERFORMANCE_CAPTURE", "SurvivalBossPerformanceCapture"
local unpack_values = table.unpack or unpack
local LIMIT = 64

local function write(line) print("[BOSS_PERF] " .. line) end
local function pack(...) return { n = select("#", ...), ... } end
local function clock_available(fn)
    if type(fn) ~= "function" then return false end
    local ok, value = pcall(fn)
    return ok and type(value) == "number"
end
local function read(module, name)
    local owner = package.loaded[module]
    if type(owner) ~= "table" or type(owner[name]) ~= "function" then return "unavailable" end
    local ok, value = pcall(owner[name])
    return ok and tostring(value) or "unavailable"
end
local function snapshot(capture, phase)
    local heap = "unavailable"
    if type(collectgarbage) == "function" then
        local ok, value = pcall(collectgarbage, "count")
        if ok and tonumber(value) then heap = string.format("%.1f", value) end
    end
    write(string.format("snapshot phase=%s wave=%s difficulty=%s tasks=%s damage_records=%s lua_kib=%s",
        phase, read("systems/wave_system", "current_wave_number"),
        read("systems/wave_system", "get_difficulty"), read("core/scheduler", "task_count"),
        read("combat/damage_transaction_repository", "count"), heap))
end
local function count_detail(bucket, name)
    if type(name) ~= "string" then return end
    if not bucket.values[name] and bucket.size >= LIMIT then name = "<other>" end
    if not bucket.values[name] then bucket.size = bucket.size + 1 end
    bucket.values[name] = (bucket.values[name] or 0) + 1
end
local function install(capture, owner, name, label, detail)
    -- Engine globals can be userdata with read-only methods. Only replace a
    -- writable method slot; never modify native metatables to force a hook.
    local owner_type = type(owner)
    local readable, original = pcall(function() return owner and owner[name] end)
    if (owner_type ~= "table" and owner_type ~= "userdata")
        or not readable or type(original) ~= "function" then
        capture.unavailable[#capture.unavailable + 1] = label
        return
    end
    local row = { label = label, calls = 0, total = 0, maximum = 0, errors = 0 }
    local wrapper = function(...)
        if detail == "world_reset" then M.stop("world_reset"); return original(...) end
        row.calls = row.calls + 1
        if detail == "event" then count_detail(capture.events, select(1, ...)) end
        if detail == "particle" then count_detail(capture.particles, select(2, ...)) end
        local started = capture.measure()
        local result = pack(pcall(original, ...))
        local elapsed = math.max(0, capture.measure() - started)
        row.total, row.maximum = row.total + elapsed, math.max(row.maximum, elapsed)
        if not result[1] then row.errors = row.errors + 1; error(result[2], 0) end
        return unpack_values(result, 2, result.n)
    end
    local ok = pcall(function() owner[name] = wrapper end)
    if not ok or owner[name] ~= wrapper then
        capture.unavailable[#capture.unavailable + 1] = label
        return
    end
    capture.rows[#capture.rows + 1] = row
    capture.hooks[#capture.hooks + 1] = { owner = owner, name = name, original = original, wrapper = wrapper }
end
local function print_details(capture, kind, bucket, elapsed)
    local rows = {}
    for name, count in pairs(bucket.values) do rows[#rows + 1] = { name = name, count = count } end
    table.sort(rows, function(a, b)
        if a.count == b.count then return a.name < b.name end
        return a.count > b.count
    end)
    for i = 1, math.min(20, #rows) do
        local row = rows[i]
        write(string.format("%s name=%s count=%d per_second=%.2f", kind, row.name, row.count, row.count / elapsed))
    end
end

function M.stop(reason)
    local capture = _G[KEY]
    if not capture then return false end
    _G[KEY] = nil
    for _, hook in ipairs(capture.hooks) do
        if hook.owner[hook.name] == hook.wrapper then hook.owner[hook.name] = hook.original end
    end
    local elapsed = math.max(0.001, capture.wall() - capture.started)
    write(string.format("done reason=%s seconds=%.2f clock=%s hooks=%d unavailable=%d",
        reason or "manual", elapsed, capture.clock_kind, #capture.hooks, #capture.unavailable))
    snapshot(capture, "end")
    table.sort(capture.rows, function(a, b)
        if a.total == b.total then return a.label < b.label end
        return a.total > b.total
    end)
    for i = 1, math.min(20, #capture.rows) do
        local row = capture.rows[i]
        write(string.format("callback name=%s calls=%d total_ms=%.3f max_ms=%.3f errors=%d",
            row.label, row.calls, row.total * 1000, row.maximum * 1000, row.errors))
    end
    print_details(capture, "event", capture.events, elapsed)
    print_details(capture, "particle_created", capture.particles, elapsed)
    if #capture.unavailable > 0 then write("unavailable_hooks=" .. table.concat(capture.unavailable, ",")) end
    write("scope=inclusive_callback_clocks_and_api_counts nested_totals_overlap particle_releases_are_not_particle_deaths")
    print("BOSS_PERF_DONE")
    return true
end

function M.run(seconds)
    if type(IsServer) ~= "function" or not IsServer()
        or type(IsInToolsMode) ~= "function" or not IsInToolsMode() then return false, "tools_server_only" end
    if _G[KEY] then return false, "already_running" end
    if _G.SURVIVAL_COMBAT_PERFORMANCE_CAPTURE then return false, "combat_capture_already_running" end
    local mode = GameRules and GameRules:GetGameModeEntity()
    if not mode or type(mode.SetContextThink) ~= "function" then return false, "active_match_required" end
    local measure, clock_kind
    if clock_available(os and os.clock) then measure, clock_kind = os.clock, "os_clock"
    elseif clock_available(Time) then measure, clock_kind = Time, "engine_Time"
    else return false, "clock_unavailable" end
    local wall = clock_available(Time) and Time or measure
    local capture = { wall = wall, measure = measure, clock_kind = clock_kind,
        started = wall(), rows = {}, hooks = {}, unavailable = {},
        events = { values = {}, size = 0 }, particles = { values = {}, size = 0 } }
    seconds = math.max(1, math.min(30, tonumber(seconds) or 15))
    _G[KEY] = capture
    snapshot(capture, "start")
    install(capture, package.loaded["core/scheduler"], "think", "scheduler.think")
    install(capture, package.loaded["core/scheduler"], "init", "scheduler.init", "world_reset")
    install(capture, package.loaded["core/event_bus"], "emit", "event_bus.emit", "event")
    install(capture, package.loaded["core/event_bus"], "request", "event_bus.request", "event")
    install(capture, package.loaded["combat/damage_service"], "Deal", "damage_service.Deal")
    install(capture, _G, "FindUnitsInRadius", "FindUnitsInRadius")
    install(capture, ParticleManager, "CreateParticle", "ParticleManager.CreateParticle", "particle")
    install(capture, ParticleManager, "DestroyParticle", "ParticleManager.DestroyParticle")
    install(capture, ParticleManager, "ReleaseParticleIndex", "ParticleManager.ReleaseParticleIndex")
    for _, entry in ipairs({
        { "modifier_tower_auto_attack", "OnIntervalThink" },
        { "modifier_tower_attack_effects", "OnIntervalThink" },
        { "modifier_tower_attack_effects", "OnAttack" },
        { "modifier_tower_attack_effects", "OnAttackLanded" },
        { "modifier_tower_attack_effects", "OnTakeDamage" },
        { "modifier_enemy_wall_ai", "OnIntervalThink" },
        { "modifier_lumberjack_ai", "OnIntervalThink" },
        { "modifier_lumberjack_ai", "OnAttackLanded" },
        { "modifier_single_health_bar", "OnIntervalThink" },
    }) do
        install(capture, _G[entry[1]] or package.loaded["modifiers/" .. entry[1]],
            entry[2], entry[1] .. "." .. entry[2])
    end
    local ok, err = pcall(mode.SetContextThink, mode, THINK, function()
        if _G[KEY] ~= capture then return nil end
        if capture.wall() - capture.started >= seconds then M.stop("complete"); return nil end
        return 0.25
    end, 0.25)
    if not ok then M.stop("timer_failed"); return false, err end
    write(string.format("started seconds=%.1f clock=%s hooks=%d", seconds, clock_kind, #capture.hooks))
    return true
end

if IsServer and IsServer() and IsInToolsMode and IsInToolsMode() then
    local ok, reason = M.run(15)
    if not ok then write("unavailable reason=" .. tostring(reason)) end
end
return M
