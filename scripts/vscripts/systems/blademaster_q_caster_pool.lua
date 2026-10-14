-- Default-OFF, isolated Tools candidate. Only Q casters created here are pooled.
local bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local M = {}
local FLAG = "SURVIVAL_BLADEMASTER_Q_CASTER_POOL_PROBE"
local IDLE = "modifier_blademaster_q_caster_idle"
local UNIT = "npc_dota_hero_legion_commander"
local ABILITY = "legion_commander_overwhelming_odds"
local OWNER_IDLE_CAP, TOTAL_CAP = 4, 32
local state
local serial = 0

local function valid(unit)
    local ok, result = pcall(function()
        return unit and type(unit.IsNull) == "function" and not unit:IsNull()
    end)
    return ok and result == true
end
local function alive(unit)
    local ok, result = pcall(function() return valid(unit) and unit:IsAlive() end)
    return ok and result == true
end
local function world()
    return GameRules and GameRules.GetGameModeEntity and GameRules:GetGameModeEntity()
end
local function generation()
    return type(bus.get_generation) == "function" and bus.get_generation() or nil
end
local function tools()
    return IsServer and IsServer() and IsInToolsMode and IsInToolsMode()
        and GetMapName and GetMapName() == "template_map"
end
local function scope(current)
    local guard = _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION
    return current and state == current and current.enabled and tools()
        and world() == current.world and generation() == current.bus_generation
        and guard == current.guard and guard and guard.mode == current.world
end
local function count(current, name)
    current.counters[name] = (current.counters[name] or 0) + 1
end
local function invoke(unit, name, ...)
    assert(valid(unit) and type(unit[name]) == "function", "Q pool API missing: " .. name)
    local result = unit[name](unit, ...)
    assert(result ~= false, "Q pool API rejected: " .. name)
    return result
end

local function destroy(current, entry, reason)
    if current.entries[entry.unit] ~= entry then return end
    current.entries[entry.unit] = nil
    current.total = current.total - 1
    local lease = entry.lease
    entry.lease, entry.status = nil, "removed"
    if lease and lease.task then scheduler.cancel(lease.task) end
    if lease and lease.cast_task then scheduler.cancel(lease.cast_task) end
    count(current, "removed")
    current.last_remove_reason = reason
    -- Never send an old-world handle to a new world's native APIs.
    if world() == current.world and valid(entry.unit) then
        pcall(function() entry.unit.survival_blademaster_q_pool_entry = nil end)
        if UTIL_Remove then pcall(UTIL_Remove, entry.unit)
        elseif entry.unit.RemoveSelf then pcall(entry.unit.RemoveSelf, entry.unit) end
    end
end
local function clear(current, reason)
    if not current then return end
    local pending = {}
    for _, entry in pairs(current.entries) do pending[#pending + 1] = entry end
    for _, entry in ipairs(pending) do destroy(current, entry, reason) end
end
local function clear_owner(current, owner, player_id, reason)
    local pending = {}
    for _, entry in pairs(current.entries) do
        if entry.owner == owner or player_id ~= nil and entry.player_id == player_id then
            pending[#pending + 1] = entry
        end
    end
    for _, entry in ipairs(pending) do destroy(current, entry, reason) end
end
local function identity(current, entry)
    if not scope(current) or not alive(entry.owner) or not alive(entry.unit) then return false end
    if entry.world ~= current.world or entry.guard ~= current.guard
        or entry.bus_generation ~= current.bus_generation then return false end
    local summoned = bus.request(events.HERO_SUMMON_GET_REQUEST, {player_id = entry.player_id})
    if not summoned or summoned.unit ~= entry.hero or not alive(entry.hero) then return false end
    local ok, result = pcall(function()
        return entry.owner:GetTeamNumber() == entry.team
            and entry.unit:GetTeamNumber() == entry.team
            and entry.unit:GetOwner() == entry.owner
            and entry.owner:GetPlayerOwnerID() == entry.player_id
            and entry.unit.survival_blademaster_q_pool_entry == entry
    end)
    return ok and result == true
end
local function stop_and_reset(entry, native)
    invoke(entry.unit, "Stop")
    -- Q's own native self buff is explicitly removed, not all game modifiers.
    invoke(entry.unit, "RemoveModifierByName", "modifier_legion_commander_overwhelming_odds")
    invoke(native, "EndCooldown")
    local maximum = invoke(entry.unit, "GetMaxMana")
    assert(type(maximum) == "number" and maximum >= 0, "Q pool invalid max mana")
    invoke(entry.unit, "SetMana", maximum)
    assert(invoke(native, "IsCooldownReady") == true, "Q pool cooldown not reset")
end
local function can_reuse(entry)
    if entry.lease or entry.status ~= "idle" then return false end
    local ok, result = pcall(function()
        return not entry.unit:IsChanneling()
            and (not entry.native.IsInAbilityPhase or not entry.native:IsInAbilityPhase())
    end)
    return ok and result == true
end
local function show(unit)
    invoke(unit, "RemoveNoDraw")
    if unit.FirstMoveChild then
        local child = unit:FirstMoveChild()
        local seen = {}
        while valid(child) and not seen[child] do
            seen[child] = true
            -- FirstMoveChild also includes abilities and items. The legacy
            -- hide helper only hides children exposing AddNoDraw.
            if type(child.AddNoDraw) == "function" then
                if type(child.RemoveNoDraw) == "function" then
                    invoke(child, "RemoveNoDraw")
                else
                    local no_draw = rawget(_G, "EF_NODRAW")
                    assert(type(no_draw) == "number", "Q pool no-draw flag unavailable")
                    invoke(child, "RemoveEffects", no_draw)
                end
            end
            child = child.NextMovePeer and child:NextMovePeer() or nil
        end
    end
end
local function idle_count(current, owner)
    local total = 0
    for _, entry in pairs(current.entries) do
        if entry.owner == owner and entry.status == "idle" then total = total + 1 end
    end
    return total
end

local function give_back(current, entry, lease)
    -- Exact lease identity prevents a late/duplicate old timer touching a new cast.
    if current.entries[entry.unit] ~= entry or entry.lease ~= lease then return end
    if lease.cast_task then scheduler.cancel(lease.cast_task) end
    entry.lease = nil
    if not identity(current, entry) or idle_count(current, entry.owner) >= OWNER_IDLE_CAP then
        destroy(current, entry, "return_scope_or_idle_cap")
        return
    end
    local ok = pcall(function()
        stop_and_reset(entry, entry.native)
        invoke(entry.native, "SetActivated", false)
        invoke(entry.native, "SetHidden", true)
        invoke(entry.unit, "SetIdleAcquire", false)
        invoke(entry.unit, "SetAcquisitionRange", 0)
        local modifier = invoke(entry.unit, "AddNewModifier", entry.unit, nil, IDLE, {})
        assert(modifier, "Q pool idle modifier rejected")
        invoke(entry.unit, "AddNoDraw")
        invoke(entry.unit, "SetAbsOrigin", Vector(0, 0, -10000))
    end)
    if not ok or not identity(current, entry) then destroy(current, entry, "idle_reset_failed"); return end
    entry.status = "idle"
    count(current, "returned")
end

local function create(current, owner, position, player_id, team, hero)
    local unit = CreateUnitByName(UNIT, position, false, owner, owner, team)
    assert(alive(unit), "Q pool create failed")
    local entry = {unit = unit, owner = owner, hero = hero, player_id = player_id, team = team,
        status = "preparing", world = current.world, guard = current.guard,
        bus_generation = current.bus_generation}
    current.entries[unit], current.total = entry, current.total + 1
    unit.survival_blademaster_q_pool_entry = entry
    count(current, "created")
    -- Own the new unit before configuration or nested native callbacks can fail.
    unit.survival_visual_only = true
    unit.survival_blademaster_visual_caster = true
    -- Native hero creation assigns the Player as owner even when both owner
    -- arguments are the source hero. Bind our exclusive caster explicitly.
    invoke(unit, "SetOwner", owner)
    invoke(unit, "SetControllableByPlayer", player_id, false)
    invoke(unit, "SetAttackCapability", DOTA_UNIT_CAP_NO_ATTACK)
    invoke(unit, "SetHullRadius", 0)
    invoke(unit, "SetIdleAcquire", false)
    invoke(unit, "SetAcquisitionRange", 0)
    if unit.SetDayTimeVisionRange then invoke(unit, "SetDayTimeVisionRange", 0) end
    if unit.SetNightTimeVisionRange then invoke(unit, "SetNightTimeVisionRange", 0) end
    assert(invoke(unit, "AddNewModifier", unit, nil, "modifier_invulnerable", {}))
    assert(invoke(unit, "AddNewModifier", unit, nil, "modifier_phased", {}))
    return entry
end

function M.try_play(owner, position, player_id, get_ability, hide, issue_order)
    local current = state
    if not current or not scope(current) or _G[FLAG] ~= true then
        if current then clear(current, "admission_scope_changed") end
        return false
    end
    local entry, lease, submitted
    local ok, err = pcall(function()
        assert(alive(owner) and position, "Q pool no living owner")
        local team = invoke(owner, "GetTeamNumber")
        assert(invoke(owner, "GetPlayerOwnerID") == player_id, "Q pool owner player mismatch")
        local summoned = bus.request(events.HERO_SUMMON_GET_REQUEST, {player_id = player_id})
        local hero = summoned and summoned.unit
        assert(alive(hero), "Q pool canonical hero unavailable")
        local stale = {}
        for _, candidate in pairs(current.entries) do
            if not identity(current, candidate) then stale[#stale + 1] = candidate
            elseif candidate.owner == owner and candidate.status == "idle" then
                if candidate.hero == hero and can_reuse(candidate) then entry = entry or candidate
                else stale[#stale + 1] = candidate end
            end
        end
        for _, candidate in ipairs(stale) do destroy(current, candidate, "checkout_stale") end
        if not entry then
            if current.total >= TOTAL_CAP then count(current, "overflow"); return end
            -- Capture even a partially configured create via the ownership table.
            entry = create(current, owner, position, player_id, team, hero)
        else
            count(current, "reused")
        end
        assert(identity(current, entry), "Q pool checkout superseded")
        serial = serial + 1
        lease = {token = {}, serial = serial}
        entry.lease, entry.status = lease, "busy"
        invoke(entry.unit, "RemoveModifierByName", IDLE)
        invoke(entry.unit, "SetAbsOrigin", position)
        show(entry.unit)
        entry.native = get_ability(entry.unit, ABILITY)
        assert(valid(entry.native), "Q pool native ability missing")
        stop_and_reset(entry, entry.native)
        assert(identity(current, entry) and entry.lease == lease, "Q pool preparation superseded")
        local delay = math.max(1, invoke(entry.native, "GetCastPoint") + 1)
        -- Install the original deadline before submitting native order. A failed
        -- scheduler allocation can still fall back without submitting two casts.
        lease.task = scheduler.after(delay, function() give_back(current, entry, lease) end,
            "blademaster_q_pool:" .. tostring(serial))
        lease.cast_task = issue_order(entry.unit, entry.native, position, player_id)
        submitted = true
        count(current, "submitted")
        hide(entry.unit)
    end)
    if not ok then
        count(current, "failed")
        current.last_error = tostring(err)
        -- Preserve the original cast deadline after submission. Immediate
        -- removal here could cancel the queued native cast; retry would double
        -- a cast that already succeeded. Best-effort hide, then normal return.
        if submitted then
            if current.entries[entry.unit] == entry then pcall(hide, entry.unit) end
            return true, entry.unit
        end
        -- Configuration can fail before create returns; all such unleased
        -- entries are ours and must be retired before the legacy path runs.
        local pending = {}
        for _, candidate in pairs(current.entries) do
            if candidate == entry or candidate.status == "preparing" then pending[#pending + 1] = candidate end
        end
        for _, candidate in ipairs(pending) do destroy(current, candidate, "play_failed") end
        return false
    end
    if not entry then return false end -- Overflow runs the original temporary path.
    return true, entry.unit
end

function M.reset(reason)
    local previous = state
    state = nil
    _G[FLAG] = false
    if previous then
        previous.enabled = false
        scheduler.cancel(previous.sweep_task)
        for _, subscription in ipairs(previous.subscriptions) do bus.unsubscribe(subscription) end
        clear(previous, reason or "reset")
    end
end
function M.set_probe(enabled)
    if enabled ~= true then M.reset("probe_disabled"); return true end
    local mode, guard = world(), _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION
    if not tools() or not mode or not guard or guard.mode ~= mode or not generation() then
        return false, "isolated_tools_scope_required"
    end
    if state and scope(state) and _G[FLAG] == true then return true end
    M.reset("probe_replaced")
    local linked = pcall(function()
        assert(LinkLuaModifier, "LinkLuaModifier unavailable")
        assert(rawget(_G, "MODIFIER_STATE_OUT_OF_GAME") ~= nil, "out-of-game state unavailable")
        LinkLuaModifier(IDLE, "modifiers/" .. IDLE, LUA_MODIFIER_MOTION_NONE)
    end)
    if not linked then return false, "idle_modifier_unavailable" end
    local current = {world = mode, guard = guard, bus_generation = generation(),
        enabled = true, total = 0, entries = {}, subscriptions = {},
        counters = {created = 0, reused = 0, submitted = 0, returned = 0,
            removed = 0, overflow = 0, failed = 0}}
    state, _G[FLAG] = current, true
    local function subscribe(event, callback)
        current.subscriptions[#current.subscriptions + 1] = bus.subscribe(event, function(payload)
            if state == current and generation() == current.bus_generation and world() == current.world then
                callback(payload or {})
            end
        end)
    end
    subscribe(events.ENGINE_ENTITY_KILLED, function(payload)
        local victim = payload.victim
        if current.entries[victim] then destroy(current, current.entries[victim], "caster_killed") end
        clear_owner(current, victim, nil, "owner_killed")
    end)
    subscribe(events.HERO_REMOVED, function(payload)
        if not payload.unit then
            clear_owner(current, nil, tonumber(payload.player_id), "hero_removed")
            return
        end
        local pending = {}
        for _, entry in pairs(current.entries) do
            if entry.owner == payload.unit or entry.hero == payload.unit then pending[#pending + 1] = entry end
        end
        for _, entry in ipairs(pending) do destroy(current, entry, "hero_removed") end
    end)
    subscribe(events.HERO_SUMMONED, function(payload)
        local pending = {}
        for _, entry in pairs(current.entries) do
            if entry.player_id == tonumber(payload.player_id) and entry.hero ~= payload.unit then
                pending[#pending + 1] = entry
            end
        end
        for _, entry in ipairs(pending) do destroy(current, entry, "hero_replaced") end
    end)
    subscribe(events.PLAYER_DEFEATED, function(payload)
        clear_owner(current, nil, tonumber(payload.player_id), "player_defeated")
    end)
    subscribe(events.PLAYER_DISCONNECTED, function(payload)
        clear_owner(current, nil, tonumber(payload.player_id), "player_disconnected")
    end)
    serial = serial + 1
    current.sweep_task = "blademaster_q_pool_scope:" .. tostring(serial)
    scheduler.every(0.25, function()
        if state ~= current then return false end
        if not scope(current) or _G[FLAG] ~= true then M.reset("scope_expired"); return false end
        local pending = {}
        for _, entry in pairs(current.entries) do
            if not identity(current, entry) then pending[#pending + 1] = entry end
        end
        for _, entry in ipairs(pending) do destroy(current, entry, "owner_or_caster_invalid") end
    end, current.sweep_task)
    return true
end
function M.snapshot()
    local result = {default_off = true, enabled = state and scope(state) and _G[FLAG] == true or false,
        owner_idle_cap = OWNER_IDLE_CAP, total_cap = TOTAL_CAP, total = 0, idle = 0, busy = 0,
        counters = {}, casters = {}, native_visual_or_fps_verified = false}
    if state then
        result.total = state.total
        result.last_error, result.last_remove_reason = state.last_error, state.last_remove_reason
        for key, value in pairs(state.counters) do result.counters[key] = value end
        for _, entry in pairs(state.entries) do
            result[entry.status] = (result[entry.status] or 0) + 1
            local ok, index = pcall(function() return entry.unit:entindex() end)
            result.casters[#result.casters + 1] = {entindex = ok and index or -1,
                player_id = entry.player_id, status = entry.status,
                lease = entry.lease and entry.lease.serial or nil}
        end
    end
    return result
end
return M
