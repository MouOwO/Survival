-- Tools server console: script_reload_code tests/manual_combat_performance
-- Opt-in, 15-second call counts. Does not spawn, move, pause or damage units.
-- These are Lua workload counts, NOT FPS, frame time or whole-process memory.
local M = {}
local ACTIVE_KEY = "SURVIVAL_COMBAT_PERFORMANCE_CAPTURE"
local THINK_KEY = "SurvivalCombatPerformanceCapture"

local function clock()
    if type(Time) == "function" then return Time() end
    return GameRules:GetGameTime()
end

local function heap_kib()
    if type(collectgarbage) ~= "function" then return nil end
    local ok, size = pcall(collectgarbage, "count")
    return ok and tonumber(size) or nil
end

local function write(line)
    print("[COMBAT_PERF] " .. line)
end

local function install(capture, owner, name, label, event_kind)
    if type(owner) ~= "table" or type(owner[name]) ~= "function" then return end
    local original = owner[name]
    local wrapper = function(...)
        capture.calls[label] = (capture.calls[label] or 0) + 1
        if event_kind then
            local event = select(1, ...)
            if type(event) == "string" then
                local key = event_kind .. ":" .. event
                capture.events[key] = (capture.events[key] or 0) + 1
            end
        end
        return original(...)
    end
    owner[name] = wrapper
    capture.hooks[#capture.hooks + 1] = {
        owner = owner, name = name, original = original, wrapper = wrapper,
    }
end

function M.stop(reason)
    local capture = _G[ACTIVE_KEY]
    if not capture then return false end
    _G[ACTIVE_KEY] = nil
    for _, hook in ipairs(capture.hooks) do
        -- Do not undo a legitimate script reload made during this capture.
        if hook.owner[hook.name] == hook.wrapper then
            hook.owner[hook.name] = hook.original
        end
    end
    local elapsed = math.max(0.001, clock() - capture.started)
    local scheduler = package.loaded["core/scheduler"]
    local task_count = scheduler and scheduler.task_count and scheduler.task_count() or -1
    local heap = heap_kib()
    write(string.format("done reason=%s seconds=%.2f tasks_start=%d tasks_end=%d lua_heap_start_kib=%s lua_heap_end_kib=%s",
        reason or "manual", elapsed, capture.tasks, task_count,
        capture.heap and string.format("%.1f", capture.heap) or "unavailable",
        heap and string.format("%.1f", heap) or "unavailable"))
    local labels = {}
    for label in pairs(capture.calls) do labels[#labels + 1] = label end
    table.sort(labels)
    for _, label in ipairs(labels) do
        write(string.format("calls name=%s count=%d per_second=%.1f",
            label, capture.calls[label], capture.calls[label] / elapsed))
    end
    local rows = {}
    for name, count in pairs(capture.events) do rows[#rows + 1] = { name = name, count = count } end
    table.sort(rows, function(a, b)
        if a.count == b.count then return a.name < b.name end
        return a.count > b.count
    end)
    for i = 1, math.min(15, #rows) do
        write(string.format("event name=%s count=%d per_second=%.1f",
            rows[i].name, rows[i].count, rows[i].count / elapsed))
    end
    write("capture_complete metrics=call_counts_only")
    print("COMBAT_PERF_DONE")
    return true
end

function M.run(seconds)
    if not IsServer or not IsServer() or not IsInToolsMode or not IsInToolsMode() then
        return false
    end
    if _G[ACTIVE_KEY] then
        write("already_running")
        return false
    end
    local mode = GameRules and GameRules:GetGameModeEntity()
    if not mode or not mode.SetContextThink then
        write("unavailable reason=active_match_required")
        return false
    end
    local scheduler = package.loaded["core/scheduler"]
    local capture = { started = clock(), calls = {}, events = {}, hooks = {},
        heap = heap_kib(), tasks = scheduler and scheduler.task_count and scheduler.task_count() or -1 }
    _G[ACTIVE_KEY] = capture
    seconds = math.max(5, math.min(30, tonumber(seconds) or 15))
    install(capture, scheduler, "think", "scheduler.think")
    install(capture, package.loaded["core/event_bus"], "emit", "event_bus.emit", "emit")
    install(capture, package.loaded["core/event_bus"], "request", "event_bus.request", "request")
    install(capture, package.loaded["systems/tree_damage_rules"], "clear_basic_attack", "tree.clear_basic_attack")
    install(capture, package.loaded["systems/tree_damage_rules"], "clear_basic_attack_token", "tree.clear_basic_attack_token")
    for _, row in ipairs({
        { "modifier_tower_auto_attack", "OnIntervalThink" },
        { "modifier_tower_auto_attack", "OnAttackStart" },
        { "modifier_tree_progression", "OnAttackRecordDestroy" },
        { "modifier_tree_progression", "OnTakeDamage" },
        { "modifier_lumberjack_ai", "OnIntervalThink" },
        { "modifier_lumberjack_ai", "OnAttackLanded" },
        { "modifier_single_health_bar", "OnIntervalThink" },
    }) do
        local owner = _G[row[1]] or package.loaded["modifiers/" .. row[1]]
        install(capture, owner, row[2], row[1] .. "." .. row[2])
    end
    mode:SetContextThink(THINK_KEY, function()
        if _G[ACTIVE_KEY] ~= capture then return nil end
        if clock() - capture.started >= seconds then M.stop("complete"); return nil end
        return 0.25
    end, 0.25)
    write(string.format("started seconds=%.1f hooks=%d", seconds, #capture.hooks))
    return true
end

if IsServer and IsServer() and IsInToolsMode and IsInToolsMode() then M.run(15) end
return M
