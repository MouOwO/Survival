-- Tools server console: script require("tests/manual_tower_attack_recovery").run()
-- Uses real KV + the loaded production auto-attack modifier, never direct damage
-- or harness-issued attack orders. Refuses occupied areas and cleans up only its
-- own handles. This is an isolated engine smoke test, not a saved-building test.
local M = {}
local ACTIVE_KEY = "SURVIVAL_MANUAL_TOWER_ATTACK_RECOVERY"
local FIXTURE_MODIFIER = "modifier_manual_tower_attack_recovery_fixture"
local MAX_SECONDS, SAFE_RADIUS = 18, 1200

local function valid(unit)
    return unit ~= nil and not unit:IsNull()
end

local function log(tag, values)
    local fields = { "[TOWER_RUNTIME_TEST]", tag }
    for _, value in ipairs(values or {}) do fields[#fields + 1] = tostring(value) end
    print(table.concat(fields, " "))
end

local function log_exception(phase, value)
    -- Fixture/native API errors only; keep one bounded line rather than a raw
    -- console dump or arbitrary gameplay state.
    log("EXCEPTION", { "phase=" .. tostring(phase),
        "error=" .. tostring(value):gsub("[\r\n\t]", " "):sub(1, 320) })
end

local function attack_interval(tower, state)
    -- GetSecondsPerAttack is absent in current server builds (the UI adapter
    -- treats it as an optional legacy fallback). Use the server's existing APS
    -- signature; an observed fixture cadence is a fallback without that API.
    if tower.GetAttacksPerSecond then
        local ok, rate = pcall(tower.GetAttacksPerSecond, tower, false)
        if ok and tonumber(rate) and tonumber(rate) > 0 then
            return 1 / tonumber(rate), "server_attacks_per_second"
        end
    end
    if state.observed_attack_interval then
        return state.observed_attack_interval, "observed_attack_starts"
    end
    error("fixture_attack_interval_unavailable")
end

local function foreign_units(origin, owned)
    local flags = (DOTA_UNIT_TARGET_FLAG_INVULNERABLE or 0)
        + (DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES or 0)
        + (DOTA_UNIT_TARGET_FLAG_OUT_OF_WORLD or 0)
    local units = FindUnitsInRadius(DOTA_TEAM_GOODGUYS, origin, nil, SAFE_RADIUS,
        DOTA_UNIT_TARGET_TEAM_BOTH,
        DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC + DOTA_UNIT_TARGET_BUILDING,
        flags, FIND_ANY_ORDER, false)
    for _, unit in ipairs(units or {}) do
        if valid(unit) and not owned[unit] then return true end
    end
    return false
end

local function usable(point)
    return GridNav:IsTraversable(point) and not GridNav:IsBlocked(point)
end

local function ground(point)
    return Vector(point.x, point.y, GetGroundHeight(point, nil))
end

local function select_location()
    -- Search around map player spawns, then origin. Never relocate existing units.
    local anchors = {}
    for player = 1, 4 do
        local spawn = Entities:FindByName(nil, "player_" .. player .. "_spawn")
        if valid(spawn) then anchors[#anchors + 1] = spawn:GetAbsOrigin() end
    end
    anchors[#anchors + 1] = Vector(0, 0, 0)
    for _, anchor in ipairs(anchors) do
        for _, distance in ipairs({ 1600, 2400, 3200, 4800, 6400 }) do
            for direction = 0, 15 do
                local angle = direction * math.pi / 8
                local point = ground(anchor + Vector(math.cos(angle) * distance,
                    math.sin(angle) * distance, 0))
                local tree = ground(point + Vector(0, 130, 0))
                local enemy = ground(point + Vector(260, 0, 0))
                if usable(point) and usable(tree) and usable(enemy)
                    and math.abs(tree.z - point.z) < 24
                    and math.abs(enemy.z - point.z) < 24
                    and not foreign_units(point, {}) then
                    return point, tree, enemy
                end
            end
        end
    end
end

local function install_fixture_modifier()
    LinkLuaModifier(FIXTURE_MODIFIER, "tests/manual_tower_attack_recovery",
        LUA_MODIFIER_MOTION_NONE)
    -- Re-running after require-cache reset must also update this probe's
    -- callbacks. Production modifiers and unrelated unit classes are untouched.
    local fixture = _G[FIXTURE_MODIFIER] or class({})
    _G[FIXTURE_MODIFIER] = fixture
    function fixture:IsHidden() return true end
    function fixture:IsPurgable() return false end
    function fixture:CheckState() return { [MODIFIER_STATE_ROOTED] = true } end
    function fixture:DeclareFunctions() return { MODIFIER_EVENT_ON_ATTACK_START, MODIFIER_EVENT_ON_DEATH } end
    function fixture:OnAttackStart(event)
        if not IsServer() or event.attacker ~= self:GetParent() then return end
        local state = self:GetParent().survival_manual_attack_fixture
        if not state or state.finished then return end
        if event.target == state.tree then state.tree_attack_starts = state.tree_attack_starts + 1 end
        if event.target == state.enemy then
            state.enemy_attack_starts = state.enemy_attack_starts + 1
            local now = GameRules:GetGameTime()
            if state.last_enemy_attack_at then
                local elapsed = now - state.last_enemy_attack_at
                if elapsed > 0 then
                    state.observed_attack_interval = math.min(
                        state.observed_attack_interval or elapsed, elapsed)
                end
            end
            state.last_enemy_attack_at = now
        end
        if event.target == state.next_enemy then
            state.next_enemy_attack_starts = state.next_enemy_attack_starts + 1
            state.next_attack_at = state.next_attack_at or GameRules:GetGameTime()
        end
        if not state.owned[event.target] then state.interference = true end
    end
    function fixture:OnDeath(event)
        if not IsServer() then return end
        local state = self:GetParent().survival_manual_attack_fixture
        if state and not state.finished and event.unit == state.enemy then
            state.kill_at = state.kill_at or GameRules:GetGameTime()
        end
    end
end

-- The engine loads a linked modifier file in both realms. Register the class
-- there as well; only run() creates fixtures, exclusively on a Tools server.
if class and LinkLuaModifier then install_fixture_modifier() end

function M.run()
    if not IsServer() or not IsInToolsMode() then
        log("REFUSED", { "tools_server_required" })
        return { ok = false, error = "tools_server_required" }
    end
    if _G[ACTIVE_KEY] then
        log("REFUSED", { "already_running" })
        return { ok = false, error = "already_running" }
    end
    local startup = require("systems/startup_loading_service")
    if not startup.is_gameplay_ready or not startup.is_gameplay_ready() then
        log("REFUSED", { "gameplay_not_ready" })
        return { ok = false, error = "gameplay_not_ready" }
    end
    local state = { owned = {}, units = {}, tree_attack_starts = 0,
        enemy_attack_starts = 0, next_enemy_attack_starts = 0,
        phase = "initial_damage", started = GameRules:GetGameTime() }
    _G[ACTIVE_KEY] = state
    local function cleanup(reason, passed)
        if state.finished then return end
        state.finished = true
        local remaining = 0
        -- Tower first: no further attacks while removing the two targets.
        for _, unit in ipairs(state.units) do
            if valid(unit) then
                pcall(UTIL_Remove, unit)
                if valid(unit) then remaining = remaining + 1 end
            end
        end
        _G[ACTIVE_KEY] = nil
        log(passed and "PASS" or "FAIL", { reason,
            "seconds=" .. string.format("%.2f", GameRules:GetGameTime() - state.started),
            "tree_attack_starts=" .. state.tree_attack_starts,
            "enemy_attack_starts=" .. state.enemy_attack_starts,
            "next_enemy_attack_starts=" .. state.next_enemy_attack_starts,
            "remaining_handles=" .. remaining })
        log("DONE")
    end
    local ok, setup_error = pcall(function()
        local origin, tree_point, enemy_point = select_location()
        if not origin then cleanup("no_safe_ground", false); return end
        state.origin = origin
        install_fixture_modifier()
        LinkLuaModifier("modifier_tower_auto_attack", "modifiers/modifier_tower_auto_attack",
            LUA_MODIFIER_MOTION_NONE)
        local prefix = "manual_tower_attack_" .. tostring(math.floor(Time() * 1000))
        local function spawn(name, suffix, point, team)
            local unit = CreateUnitByName(name, point, false, nil, nil, team)
            if not valid(unit) then error("fixture_creation_failed") end
            state.units[#state.units + 1], state.owned[unit] = unit, true
            unit:SetEntityName(prefix .. "_" .. suffix)
            unit:SetMaxHealth(100000)
            unit:SetBaseMaxHealth(100000)
            unit:SetHealth(100000)
            unit:SetBaseHealthRegen(0)
            unit:SetMoveCapability(DOTA_UNIT_CAP_MOVE_NONE)
            unit:AddNewModifier(unit, nil, FIXTURE_MODIFIER, {})
            return unit
        end
        state.tower = spawn("building_arrow_tower", "tower", origin, DOTA_TEAM_GOODGUYS)
        state.tree = spawn("enemy_tree", "tree", tree_point, DOTA_TEAM_BADGUYS)
        state.enemy = spawn("npc_survival_wave_monster", "enemy", enemy_point, DOTA_TEAM_BADGUYS)
        state.tree:SetAttackCapability(DOTA_UNIT_CAP_NO_ATTACK)
        state.enemy:SetAttackCapability(DOTA_UNIT_CAP_NO_ATTACK)
        state.enemy:SetIdleAcquire(false)
        state.enemy:SetAcquisitionRange(0)
        state.tower.survival_manual_attack_fixture = state
        state.tower:SetBaseDamageMin(40)
        state.tower:SetBaseDamageMax(40)
        state.tower:SetBaseAttackTime(0.4)
        require("config/tower_combat_rules").set_attack_range(state.tower, 400)
        state.auto = state.tower:AddNewModifier(state.tower, nil, "modifier_tower_auto_attack", {})
        if not state.auto then error("auto_modifier_missing") end
        state.tree_hp, state.enemy_hp = state.tree:GetHealth(), state.enemy:GetHealth()
        log("START", { "isolated_ground=true", "clearance=" .. SAFE_RADIUS,
            "range=" .. require("config/tower_combat_rules").current_attack_range(state.tower),
            "deadline_seconds=" .. MAX_SECONDS })
        GameRules:GetGameModeEntity():SetContextThink(prefix, function()
            if state.finished then return nil end
            local tick_ok, tick_error = pcall(function()
                local now = GameRules:GetGameTime()
                if now - state.started >= MAX_SECONDS then cleanup("timeout_" .. state.phase, false); return end
                if not valid(state.tower) or not valid(state.tree) then cleanup("fixture_lost", false); return end
                if state.interference or foreign_units(origin, state.owned) then cleanup("area_interference", false); return end
                if state.tree:GetHealth() ~= state.tree_hp or state.tree_attack_starts > 0 then
                    cleanup("tree_was_attacked", false); return
                end
                if state.phase ~= "idle" and state.phase ~= "kill_retarget"
                    and (not valid(state.enemy) or not state.enemy:IsAlive()) then
                    cleanup("enemy_fixture_lost", false); return
                end
                if state.phase == "initial_damage" and state.enemy:GetHealth() < state.enemy_hp then
                    log("INITIAL_DAMAGE", { "hp_drop=" .. state.enemy_hp - state.enemy:GetHealth(), "tree_unchanged=true" })
                    -- Reproduce a lost engine order without resetting the Lua
                    -- target cache. Stop alone may retain the engine target.
                    state.tower:SetForceAttackTarget(nil)
                    state.tower:Stop()
                    state.phase, state.phase_at = "await_stop", now
                    if state.tower:GetAttackTarget() == nil then
                        state.phase = "settle_projectile"
                        log("STOP_CONFIRMED", { "target_nil=true", "cached_enemy=true" })
                    end
                    log("STOP", { "target_cleared=" .. tostring(state.tower:GetAttackTarget() == nil),
                        "cached_enemy=" .. tostring(state.auto.forced_target == state.enemy) })
                elseif state.phase == "await_stop" then
                    if state.auto.forced_target ~= state.enemy then
                        cleanup("stop_did_not_preserve_target_cache", false); return
                    end
                    if state.tower:GetAttackTarget() == nil then
                        log("STOP_CONFIRMED", { "target_nil=true", "cached_enemy=true" })
                        state.phase, state.phase_at = "settle_projectile", now
                    end
                elseif state.phase == "settle_projectile" and now - state.phase_at >= 0.6 then
                    -- A fresh decline after this baseline proves more than an old projectile landing.
                    state.resume_hp, state.phase = state.enemy:GetHealth(), "resume_damage"
                elseif state.phase == "resume_damage" and state.enemy:GetHealth() < state.resume_hp then
                    log("RECOVERED_DAMAGE", { "hp_drop=" .. state.resume_hp - state.enemy:GetHealth(), "tree_unchanged=true" })
                    local next_point = ground(origin + Vector(330, 0, 0))
                    if not usable(next_point) or math.abs(next_point.z - origin.z) >= 24 then
                        cleanup("next_target_no_safe_ground", false); return
                    end
                    state.next_enemy = spawn("npc_survival_wave_monster", "next_enemy", next_point, DOTA_TEAM_BADGUYS)
                    state.next_enemy:SetAttackCapability(DOTA_UNIT_CAP_NO_ATTACK)
                    state.next_enemy:SetIdleAcquire(false)
                    state.next_enemy:SetAcquisitionRange(0)
                    state.next_enemy_hp = state.next_enemy:GetHealth()
                    state.attack_interval, state.attack_interval_source = attack_interval(state.tower, state)
                    state.enemy:SetHealth(1) -- the production tower must land the killing attack
                    state.phase, state.phase_at = "kill_retarget", now
                elseif state.phase == "kill_retarget" and state.kill_at and state.next_attack_at then
                    local gap = state.next_attack_at - state.kill_at
                    if gap > state.attack_interval + 0.4 then
                        cleanup("retarget_delay_exceeds_natural_attack_interval", false); return
                    end
                    if state.next_enemy:GetHealth() < state.next_enemy_hp then
                        log("KILL_RETARGET", { "seconds_after_kill=" .. string.format("%.3f", gap),
                            "natural_attack_interval=" .. string.format("%.3f", state.attack_interval),
                            "attack_interval_source=" .. state.attack_interval_source,
                            "next_target_damaged=true", "tree_unchanged=true" })
                        UTIL_Remove(state.next_enemy)
                        state.phase, state.phase_at = "idle", now
                    end
                elseif state.phase == "idle" and now - state.phase_at >= 1.25 then
                    local idle = state.auto:GetStackCount() == 0 and state.tower:IsDisarmed()
                        and state.tower:GetAttackTarget() == nil
                    log("IDLE", { "stack=" .. state.auto:GetStackCount(),
                        "disarmed=" .. tostring(state.tower:IsDisarmed()),
                        "target_nil=" .. tostring(state.tower:GetAttackTarget() == nil), "tree_unchanged=true" })
                    cleanup(idle and "attack_kill_retarget_stop_recovery_tree_idle" or "idle_gate_failed", idle)
                end
            end)
            if not tick_ok then
                log_exception(state.phase, tick_error)
                cleanup("tick_exception_" .. state.phase, false)
            end
            return not state.finished and 0.1 or nil
        end, 0.1)
    end)
    if not ok then log_exception("setup", setup_error); cleanup("setup_exception", false) end
    return { ok = ok and not state.finished, pending = ok and not state.finished }
end

return M
