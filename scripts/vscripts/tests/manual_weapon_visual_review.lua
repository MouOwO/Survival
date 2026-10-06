-- Tools-only, manually loaded. Does not equip weapons or publish hero events.
-- script require("tests/manual_weapon_visual_review").run()
-- script SURVIVAL_WEAPON_VISUAL_REVIEW:status()
-- script SURVIVAL_WEAPON_VISUAL_REVIEW:swing() -- all five, animation only
-- script SURVIVAL_WEAPON_VISUAL_REVIEW:move(5,120,0) -- short trail demonstration
-- script require("tests/manual_weapon_visual_review").cleanup()
local M = {}
local ACTIVE_KEY = "SURVIVAL_WEAPON_VISUAL_REVIEW"
local scheduler = require("core/scheduler")
local visuals = require("systems/weapon_visual_service")
local content_ids = {
    "weapon_growth_sword_max", "weapon_frost_blade_max", "weapon_ice_blade_max",
    "weapon_epic_icefire_06", "weapon_legend_abyss_10",
}

local function valid(unit) return unit and not unit:IsNull() end
local function tools_only() return IsServer() and IsInToolsMode() end
local function log(message) print("[WEAPON_VISUAL_REVIEW] " .. tostring(message)) end
local function active(fixture)
    return tools_only() and not fixture.finished
        and fixture.world == GameRules:GetGameModeEntity() and _G[ACTIVE_KEY] == fixture
end
local function ground(point) return Vector(point.x, point.y, GetGroundHeight(point, nil)) end
local function open_position(team, point, ignored)
    if not GridNav:IsTraversable(point) or GridNav:IsBlocked(point) then
        return false, "position_not_traversable"
    end
    local flags = DOTA_UNIT_TARGET_FLAG_INVULNERABLE + DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES
    local occupants = FindUnitsInRadius(team, point, nil, 75, DOTA_UNIT_TARGET_TEAM_BOTH,
        DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC + DOTA_UNIT_TARGET_BUILDING,
        flags, FIND_ANY_ORDER, false)
    for _, unit in ipairs(occupants or {}) do
        if unit ~= ignored then return false, "position_occupied" end
    end
    return true
end
local function current_slot(fixture, index)
    assert(active(fixture), "fixture is no longer active in this world")
    local slot = assert(fixture.slots[tonumber(index)], "unknown fixture slot")
    assert(valid(slot.unit) and slot.unit:IsAlive(), "fixture slot is dead or removed")
    return slot
end

function M.run(options)
    if not tools_only() then return { ok = false, error = "tools_server_required" } end
    local existing = _G[ACTIVE_KEY]
    if existing and existing.world ~= GameRules:GetGameModeEntity() then
        -- No Destroy/Remove calls against handles retained from a previous Run.
        _G[ACTIVE_KEY] = nil
        existing = nil
    end
    if existing then return { ok = false, error = "fixture_already_exists_call_cleanup" } end
    options = options or {}
    local player_id = tonumber(options.player_id) or 0
    if not PlayerResource:IsValidPlayerID(player_id)
        or require("systems/multiplayer_player_service").is_defeated(player_id) then
        return { ok = false, error = "active_player_required" }
    end
    local player = PlayerResource:GetPlayer(player_id)
    if not player then return { ok = false, error = "player_not_connected" } end
    if type(PrecacheUnitByNameAsync) ~= "function" then
        return { ok = false, error = "unit_precache_unavailable" }
    end
    local center = options.origin or Vector(320, 4800, 384)
    local spacing = math.max(220, tonumber(options.spacing) or 240)
    local team = PlayerResource:GetTeam(player_id)
    local plans = {}
    for index = 1, #content_ids do
        local point = ground(center + Vector((index - 3) * spacing, 0, 0))
        local ok, reason = open_position(team, point)
        if not ok then return { ok = false, error = reason, slot = index } end
        plans[index] = point
    end
    local fixture = { ok = true, phase = "loading", slots = {},
        world = GameRules:GetGameModeEntity(), finished = false }
    _G[ACTIVE_KEY] = fixture

    function fixture:cleanup()
        if self.finished then return end
        self.finished, self.phase = true, "cleaned"
        if self.world == GameRules:GetGameModeEntity() then
            scheduler.cancel("weapon_visual_review_timeout")
            scheduler.cancel("weapon_visual_review_binding")
            for _, slot in ipairs(self.slots) do
                if slot.motion_task then scheduler.cancel(slot.motion_task) end
                if slot.visual then slot.visual:dispose() end
                if valid(slot.unit) then UTIL_Remove(slot.unit) end
            end
        end
        if _G[ACTIVE_KEY] == self then _G[ACTIVE_KEY] = nil end
        log("CLEANED units=" .. #self.slots)
    end

    function fixture:status()
        assert(active(self), "fixture is no longer active")
        local result = { phase = self.phase, slots = {} }
        for index, slot in ipairs(self.slots) do
            local status = slot.visual and slot.visual:status() or {}
            result.slots[index] = status
            log("SLOT=" .. index .. " content=" .. content_ids[index]
                .. " anchor=" .. tostring(status.anchor)
                .. " model=" .. tostring(status.model_name)
                .. " binding=" .. tostring(status.binding_state)
                .. " particles=" .. tostring(status.particle_count))
        end
        return result
    end

    function fixture:swing(index)
        assert(active(self) and self.phase == "ready", "fixture not ready")
        local first, last = 1, #self.slots
        if index ~= nil then first, last = tonumber(index), tonumber(index) end
        assert(first and last, "invalid slot")
        for slot_index = first, last do
            local slot = current_slot(self, slot_index)
            -- Gesture only: no attack order, target, damage or attack event.
            slot.unit:RemoveGesture(ACT_DOTA_ATTACK)
            slot.unit:StartGesture(ACT_DOTA_ATTACK)
        end
        return true
    end

    function fixture:move(index, dx, dy)
        local slot = current_slot(self, index)
        dx, dy = tonumber(dx) or 120, tonumber(dy) or 0
        assert(dx * dx + dy * dy <= 200 * 200, "preview move limited to 200 units")
        local start = slot.unit:GetAbsOrigin()
        local steps = 20
        local points = {}
        for step = 1, steps do
            local point = ground(start + Vector(dx * step / steps, dy * step / steps, 0))
            local ok, reason = open_position(team, point, slot.unit)
            assert(ok, "preview movement rejected: " .. tostring(reason))
            points[step] = point
        end
        if slot.motion_task then scheduler.cancel(slot.motion_task) end
        self:swing(index)
        local step = 0
        slot.motion_task = scheduler.every(0.05, function()
            if not active(self) or not valid(slot.unit) or not slot.unit:IsAlive() then return false end
            step = step + 1
            slot.unit:SetAbsOrigin(points[step])
            if step >= steps then slot.motion_task = nil; return false end
        end)
        return true
    end

    local function build()
        if not active(fixture) or fixture.phase ~= "loading" then return end
        fixture.phase = "building"
        scheduler.cancel("weapon_visual_review_timeout")
        -- Recheck after asynchronous loading; another building may now be here.
        local ok, err = pcall(function()
            assert(not require("systems/multiplayer_player_service").is_defeated(player_id),
                "player became defeated while loading")
            for index, point in ipairs(plans) do
                local clear, reason = open_position(team, point)
                assert(clear, "slot " .. index .. ": " .. tostring(reason))
            end
            for index, point in ipairs(plans) do
                local unit = CreateUnitByName("npc_dota_hero_juggernaut", point,
                    false, nil, nil, team)
                assert(valid(unit), "display unit creation failed")
                local slot = { unit = unit }
                fixture.slots[index] = slot
                unit.survival_manual_presentation_fixture = true
                unit.survival_hide_custom_health_bar = true
                require("systems/unit_health_bar_service").exclude(unit)
                unit:SetOwner(player)
                unit:SetControllableByPlayer(player_id, false)
                unit:SetRespawnsDisabled(true)
                unit:SetIdleAcquire(false)
                unit:SetAcquisitionRange(0)
                unit:SetAttackCapability(DOTA_UNIT_CAP_NO_ATTACK)
                unit:SetMoveCapability(DOTA_UNIT_CAP_MOVE_NONE)
                unit:SetHullRadius(0)
                unit:SetDayTimeVisionRange(0)
                unit:SetNightTimeVisionRange(0)
                unit:AddNewModifier(unit, nil, "modifier_invulnerable", {})
                unit:AddNewModifier(unit, nil, "modifier_phased", {})
                unit:SetForwardVector(Vector(0, -1, 0))
                unit:SetAbsOrigin(point)
            end
        end)
        if not ok then
            fixture:cleanup()
            fixture.ok, fixture.error = false, tostring(err)
            log("FAILED " .. tostring(err))
            return
        end
        fixture.phase = "binding"
        local started = GameRules:GetGameTime()
        scheduler.every(0.05, function()
            if not active(fixture) then return false end
            local ready = true
            local bound, failure = pcall(function()
                for index, slot in ipairs(fixture.slots) do
                    assert(valid(slot.unit) and slot.unit:IsAlive(), "display unit disappeared")
                    local model = slot.unit:GetModelName()
                    if type(model) ~= "string" or model == "" then
                        ready = false
                    else
                        if not slot.visual then
                            local reason
                            slot.visual, reason = visuals.preview(slot.unit, content_ids[index])
                            assert(slot.visual, "visual preview failed: " .. tostring(reason))
                        end
                        local status = slot.visual:status()
                        if status.binding_state ~= "ready" or status.particle_count == 0 then ready = false end
                    end
                end
            end)
            if not bound or (not ready and GameRules:GetGameTime() - started >= 10) then
                fixture:cleanup()
                fixture.ok, fixture.error = false, tostring(failure or "model_binding_timeout")
                log("FAILED " .. fixture.error)
                return false
            end
            if ready then
                fixture.phase = "ready"
                log("READY five display units; left to right growth/frost/ice/icefire/abyss")
                fixture:status()
                return false
            end
        end, "weapon_visual_review_binding")
    end
    scheduler.after(30, function()
        if active(fixture) and fixture.phase == "loading" then
            fixture:cleanup()
            fixture.ok, fixture.error = false, "unit_precache_timeout"
            log("FAILED unit_precache_timeout")
        end
    end, "weapon_visual_review_timeout")
    -- One native async request precedes all five units. There is no SetModel,
    -- private precache context, shared model queue reset, or live hero loadout.
    local loaded, result = pcall(PrecacheUnitByNameAsync,
        "npc_dota_hero_juggernaut", build, -1)
    if not loaded or result == false then
        fixture:cleanup()
        return { ok = false, error = "unit_precache_failed: " .. tostring(result) }
    end
    return fixture
end

function M.cleanup()
    if not tools_only() then return { ok = false, error = "tools_server_required" } end
    if _G[ACTIVE_KEY] then _G[ACTIVE_KEY]:cleanup() end
    return { ok = true }
end

return M
