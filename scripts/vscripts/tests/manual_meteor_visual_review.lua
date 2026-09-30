-- Tools-only isolated visual review. Run in an empty area without active waves.
-- script require("tests/manual_meteor_visual_review").run({level=5,count=1})
-- script SURVIVAL_METEOR_VISUAL_REVIEW:status()
-- script require("tests/manual_meteor_visual_review").cleanup()
-- Cleanup drains the current real cast; it never calls global clear_meteors.
local M = {}
local ACTIVE_KEY = "SURVIVAL_METEOR_VISUAL_REVIEW"
local UNIT_NAME = "asset_proxy_monster_juggernaut"
local scheduler = require("core/scheduler")
local service = require("systems/hero_passive_skill_service")
local original_definition = require("config/hero_passive_skill_definitions").by_id.proto_meteor

local function tools_only() return IsServer() and IsInToolsMode() end
local function valid(unit) return unit and not unit:IsNull() end
local function log(message) print("[METEOR_VISUAL_REVIEW] " .. tostring(message)) end
local function active(fixture)
    return tools_only() and not fixture.finished and _G[ACTIVE_KEY] == fixture
        and fixture.world == GameRules:GetGameModeEntity()
end
local function ground(point) return Vector(point.x, point.y, GetGroundHeight(point, nil)) end
local function level_value(definition, key, level)
    local value = definition[key]
    return tonumber(type(value) == "table" and value[level] or value) or 0
end
local function empty_area(fixture)
    local flags = DOTA_UNIT_TARGET_FLAG_INVULNERABLE + DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES
    local units = FindUnitsInRadius(DOTA_TEAM_GOODGUYS, fixture.origin, nil,
        fixture.clear_radius, DOTA_UNIT_TARGET_TEAM_BOTH,
        DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC + DOTA_UNIT_TARGET_BUILDING,
        flags, FIND_ANY_ORDER, false)
    for _, unit in ipairs(units or {}) do
        if unit ~= fixture.caster and unit ~= fixture.target then return false end
    end
    return true
end

function M.run(options)
    if not tools_only() then return { ok = false, error = "tools_server_required" } end
    local existing = _G[ACTIVE_KEY]
    if existing and existing.world == GameRules:GetGameModeEntity() and not existing.finished then
        return { ok = false, error = "fixture_already_active" }
    end
    options = options or {}
    local level = math.floor(tonumber(options.level) or 5)
    local count = math.floor(tonumber(options.count) or 1)
    if level < 1 or level > 5 or count < 1 or count > 5 then
        return { ok = false, error = "level_and_count_must_be_1_to_5" }
    end
    local definition = {}
    for key, value in pairs(original_definition) do definition[key] = value end
    -- No combat stat queries and no debuff side effects. All visual timing,
    -- radii, meteor counts and source paths still come from the real runner.
    definition.lava_move_slow_pct = { 0, 0, 0, 0, 0 }
    local fall = level_value(definition, "fall_duration", level)
    local second = level_value(definition, "second_meteor_delay", level)
    local lava = level_value(definition, "lava_duration", level)
    local lifetime = fall + second + math.max(lava, 1.2) + 0.2
    local fixture = { ok = true, phase = "loading", finished = false, level = level,
        world = GameRules:GetGameModeEntity(), casts_started = 0, requested_count = count,
        origin = ground(options.origin or Vector(320, 3400, 384)), units = {},
        clear_radius = level_value(definition, "radius", level) + 384,
        interval = math.max(lifetime + 0.5, tonumber(options.interval) or 0) }
    local caster_point = ground(fixture.origin + Vector(-700, 0, 0))
    if not GridNav:IsTraversable(fixture.origin) or GridNav:IsBlocked(fixture.origin)
        or not GridNav:IsTraversable(caster_point) or GridNav:IsBlocked(caster_point) then
        return { ok = false, error = "fixture_position_not_traversable" }
    end
    if not empty_area(fixture) then return { ok = false, error = "fixture_area_not_empty" } end
    if type(PrecacheUnitByNameAsync) ~= "function" then
        return { ok = false, error = "unit_precache_unavailable" }
    end
    _G[ACTIVE_KEY] = fixture

    local function finish(phase)
        if fixture.finished then return end
        fixture.finished, fixture.phase = true, phase
        if fixture.world == GameRules:GetGameModeEntity() then
            if fixture.task then scheduler.cancel(fixture.task) end
            if fixture.load_task then scheduler.cancel(fixture.load_task) end
            for _, unit in ipairs(fixture.units) do
                if valid(unit) then UTIL_Remove(unit) end
            end
        end
        if phase == "cleaned" and _G[ACTIVE_KEY] == fixture then _G[ACTIVE_KEY] = nil end
        log(string.upper(phase) .. " casts=" .. fixture.casts_started)
    end

    function fixture:status()
        local current_world = self.world == GameRules:GetGameModeEntity()
        local cast = current_world and self.caster_key
            and service._test.active_meteor_casts()[self.caster_key] or nil
        local result = { phase = self.phase, level = self.level,
            casts_started = self.casts_started, requested_count = self.requested_count,
            active_cast = cast ~= nil, cleanup_requested = self.cleanup_requested == true,
            cast_finishes_at = self.visual_end_at, error = self.error }
        log("STATUS phase=" .. tostring(result.phase) .. " cast=" .. tostring(result.active_cast)
            .. " count=" .. result.casts_started .. "/" .. result.requested_count)
        return result
    end

    function fixture:cleanup()
        if self.finished then
            if _G[ACTIVE_KEY] == self then _G[ACTIVE_KEY] = nil end
            return { ok = true, pending = false }
        end
        self.cleanup_requested = true
        if self.world ~= GameRules:GetGameModeEntity() or not self.visual_end_at then
            finish("cleaned")
            return { ok = true, pending = false }
        end
        self.phase = "draining"
        log("CLEANUP queued; current real cast and impact particles finish naturally")
        return { ok = true, pending = true }
    end

    local function cast_once()
        if not empty_area(fixture) then
            fixture.ok, fixture.error = false, "fixture_area_became_occupied"
            fixture:cleanup()
            return false
        end
        local context = {
            attacker = fixture.caster, target = fixture.target, player_id = -1,
            skill_id = "proto_meteor", attack_id = "tools_meteor_" .. fixture.caster_key
                .. "_" .. tostring(fixture.casts_started + 1), level = level,
            attributes = { strength = 0, agility = 0, intelligence = 0,
                all_attributes = 0, attack = 0, attack_min = 0, attack_max = 0 },
        }
        if not service._test.runners.proto_meteor(context, definition) then
            fixture.ok, fixture.error = false, "real_meteor_runner_rejected"
            fixture:cleanup()
            return false
        end
        fixture.casts_started = fixture.casts_started + 1
        fixture.visual_end_at = GameRules:GetGameTime() + lifetime
        fixture.next_cast_at = GameRules:GetGameTime() + fixture.interval
        fixture.phase = "playing"
        log("CAST=" .. fixture.casts_started .. " level=" .. level .. " damage=0 radius=500")
        return true
    end

    local function poll()
        if not active(fixture) then return false end
        local now = GameRules:GetGameTime()
        local running = service._test.active_meteor_casts()[fixture.caster_key]
        if not running and now >= (fixture.visual_end_at or 0) then
            if fixture.cleanup_requested or fixture.casts_started >= count then
                finish(fixture.cleanup_requested and "cleaned" or "complete")
                return false
            end
            if now >= fixture.next_cast_at and not cast_once() then
                if fixture.finished then return false end
                return 0.05
            end
        end
        return 0.05
    end

    local function prepare_unit(point, hidden)
        local unit = CreateUnitByName(UNIT_NAME, point, false, nil, nil, DOTA_TEAM_GOODGUYS)
        assert(valid(unit), "proxy_create_failed")
        fixture.units[#fixture.units + 1] = unit
        unit.survival_manual_presentation_fixture = true
        require("systems/unit_health_bar_service").exclude(unit)
        unit:SetIdleAcquire(false)
        unit:SetAcquisitionRange(0)
        unit:SetAttackCapability(DOTA_UNIT_CAP_NO_ATTACK)
        unit:SetMoveCapability(DOTA_UNIT_CAP_MOVE_NONE)
        unit:SetHullRadius(0)
        unit:SetDayTimeVisionRange(0)
        unit:SetNightTimeVisionRange(0)
        unit:AddNewModifier(unit, nil, "modifier_invulnerable", {})
        unit:AddNewModifier(unit, nil, "modifier_phased", {})
        if hidden then unit:AddNoDraw() end
        unit:SetAbsOrigin(point)
        return unit
    end

    fixture.load_task = scheduler.after(30, function()
        if active(fixture) and fixture.phase == "loading" then
            fixture.ok, fixture.error = false, "unit_precache_timeout"
            fixture:cleanup()
        end
    end)
    local ok, result = pcall(PrecacheUnitByNameAsync, UNIT_NAME, function()
        if not active(fixture) or fixture.phase ~= "loading" then return end
        fixture.phase = "creating"
        scheduler.cancel(fixture.load_task)
        local built, reason = pcall(function()
            assert(empty_area(fixture), "fixture_area_became_occupied")
            fixture.caster = prepare_unit(caster_point, false)
            fixture.target = prepare_unit(fixture.origin, true)
            fixture.caster_key = tostring(fixture.caster:entindex())
            assert(cast_once(), fixture.error)
            fixture.task = scheduler.after(0.05, poll)
        end)
        if not built then
            fixture.ok, fixture.error = false, tostring(reason)
            fixture:cleanup()
        end
    end, -1)
    if not ok or result == false then
        fixture.ok, fixture.error = false, "unit_precache_failed: " .. tostring(result)
        fixture:cleanup()
    end
    return fixture
end

function M.cleanup()
    if not tools_only() then return { ok = false, error = "tools_server_required" } end
    if _G[ACTIVE_KEY] then return _G[ACTIVE_KEY]:cleanup() end
    return { ok = true, pending = false }
end

return M
