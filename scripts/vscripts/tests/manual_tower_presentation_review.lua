-- Explicit Tools-only visual fixture. Never auto-loaded by the game.
-- script require("tests/manual_tower_presentation_review").run()
-- script SURVIVAL_TOWER_PRESENTATION_REVIEW:levels(16) -- or 6/11/25
-- script SURVIVAL_TOWER_PRESENTATION_REVIEW:move(3,180,0)
-- script SURVIVAL_TOWER_PRESENTATION_REVIEW:kill(3)
-- script require("tests/manual_tower_presentation_review").cleanup()
-- These are non-building proxy units. Test the real D grid separately on a
-- normally constructed tower; this fixture does not create gameplay buildings.
local M = {}
local ACTIVE_KEY = "SURVIVAL_TOWER_PRESENTATION_REVIEW"
-- The production fallback sweeps run at 0.5 s (effects) and 1 s (rank).
-- A proxy can be removed before the native death event resolves a handle.
local DEATH_CHECK_DELAY = 1.25
local scheduler = require("core/scheduler")
local routes = require("config/tower_route_config")
local rank = require("systems/tower_rank_presentation_service")
local effects = require("systems/tower_visual_service")
local visuals = require("systems/building_visual_service")
local fusion = require("config/generated/tower_fusion_runtime")

local function valid(unit) return unit and not unit:IsNull() end
local function tools_only()
    return IsServer() and IsInToolsMode()
end
local function ground(point)
    return Vector(point.x, point.y, GetGroundHeight(point, nil))
end
local function log(message) print("[TOWER_PRESENTATION_REVIEW] " .. tostring(message)) end
local function alive_fixture(fixture)
    return tools_only() and not fixture.finished
        and fixture.world == GameRules:GetGameModeEntity()
        and _G[ACTIVE_KEY] == fixture
end
local function current_slot(fixture, index)
    assert(alive_fixture(fixture), "fixture is no longer active in this world")
    local slot = assert(fixture.slots[tonumber(index)], "unknown fixture slot")
    assert(valid(slot.unit) and slot.unit:IsAlive(), "fixture slot is dead or removed")
    return slot
end

local function apply_slot(fixture, slot)
    local unit = slot.unit
    if not alive_fixture(fixture) or not valid(unit) or not unit:IsAlive() then return end
    local state = slot.state
    unit.survival_level = state.level
    unit.survival_tower_class = state.tower_class
    -- A proxy name also avoids the upgrade service's legacy recovery-by-name.
    -- Main building state uses the explicit false flag; neither may recover it.
    if state.building_id == "ultimate_tower" then
        unit.survival_display_name = "【UR】" .. fusion.by_id.ultimate_tower.display_name
        local expected_generation = slot.model_generation
        local model = assert(fusion.by_id.ultimate_tower.model_name)
        slot.model_status = "loading"
        -- Load the production ultimate unit's declared model before SetModel.
        PrecacheUnitByNameAsync("npc_dota_unit_ultimate_tower", function()
            if alive_fixture(fixture) and valid(unit) and unit:IsAlive()
                and slot.model_generation == expected_generation then
                unit:SetModel(model)
                unit:SetOriginalModel(model)
                unit:SetModelScale(0.8)
                slot.model_status = "ready"
            end
        end, -1)
    else
        local row = assert(routes.current(state), "missing authoritative route row")
        local model = assert(routes.model_for(row), "missing authoritative route model")
        unit.survival_display_name = routes.display_name(row)
        unit.survival_route_level = row.level
        local ok, status = visuals.apply(unit, {
            model_name = model, model_asset_id = row.model_asset_id,
        })
        slot.model_status = status
        assert(ok, "fixture model failed: " .. tostring(status))
    end
    rank.publish(state)
    assert(effects.apply(state), "fixture effect projection failed")
end

function M.run(options)
    if not tools_only() then return { ok = false, error = "tools_server_required" } end
    if _G[ACTIVE_KEY] then return { ok = false, error = "fixture_already_exists_call_cleanup" } end
    options = options or {}
    local player_id = tonumber(options.player_id) or 0
    if not PlayerResource:IsValidPlayerID(player_id) then
        return { ok = false, error = "invalid_player_id" }
    end
    local center = options.origin or Vector(320, 5460, 384)
    local spacing = math.max(220, tonumber(options.spacing) or 280)
    local class_level = math.floor(tonumber(options.class_level) or 6)
    if class_level < 6 or class_level > 25 then
        return { ok = false, error = "class_level_must_be_6_to_25" }
    end
    local team = PlayerResource:GetTeam(player_id)
    local plans = {}
    for index = 1, 10 do
        local column, row = (index - 1) % 5, math.floor((index - 1) / 5)
        local point = ground(center + Vector((column - 2) * spacing, (row - 0.5) * spacing, 0))
        local flags = DOTA_UNIT_TARGET_FLAG_INVULNERABLE + DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES
        local occupants = FindUnitsInRadius(team, point, nil, 90, DOTA_UNIT_TARGET_TEAM_BOTH,
            DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC + DOTA_UNIT_TARGET_BUILDING,
            flags, FIND_ANY_ORDER, false)
        if #(occupants or {}) > 0 then
            return { ok = false, error = "fixture_position_occupied", slot = index }
        end
        plans[index] = point
    end
    local fixture = { ok = true, slots = {}, death_checks = {},
        world = GameRules:GetGameModeEntity(), finished = false }
    _G[ACTIVE_KEY] = fixture

    function fixture:cleanup()
        if self.finished then return end
        self.finished = true
        for key in pairs(self.death_checks) do scheduler.cancel(key) end
        self.death_checks = {}
        for _, slot in ipairs(self.slots) do
            local unit = slot.unit
            if self.world == GameRules:GetGameModeEntity() then
                pcall(rank.remove, slot.state.entindex, unit)
                pcall(effects.remove, slot.state.entindex, unit)
                if valid(unit) then
                    -- Invalidate pending visual requests before removing only
                    -- this fixture's appearance components and native entity.
                    unit.survival_building_destroyed = true
                    unit.survival_model_asset_id = nil
                    local cleared, clear_error = pcall(visuals.clear, unit)
                    if not cleared then log("appearance cleanup failed: " .. tostring(clear_error)) end
                    local removed, remove_error = pcall(UTIL_Remove, unit)
                    if not removed then log("fixture removal failed: " .. tostring(remove_error)) end
                end
            end
        end
        if _G[ACTIVE_KEY] == self then _G[ACTIVE_KEY] = nil end
        log("CLEANED units=" .. tostring(#self.slots))
    end

    function fixture:levels(level)
        assert(alive_fixture(self), "fixture is no longer active")
        level = math.floor(tonumber(level) or 0)
        assert(level >= 6 and level <= 25, "class level must be 6 to 25")
        for _, slot in ipairs(self.slots) do
            if slot.state.tower_class and valid(slot.unit) and slot.unit:IsAlive() then
                slot.state.level = level
                slot.model_generation = slot.model_generation + 1
                apply_slot(self, slot)
            end
        end
        log("CLASS_LEVEL=" .. level .. " (N/UR unchanged)")
    end

    function fixture:status()
        assert(alive_fixture(self), "fixture is no longer active")
        local result = {}
        for index, slot in ipairs(self.slots) do
            local unit = slot.unit
            local row = slot.state.building_id == "arrow_tower" and routes.current(slot.state) or nil
            local expected = row and routes.model_for(row) or fusion.by_id.ultimate_tower.model_name
            local actual = valid(unit) and unit:GetModelName() or "removed"
            local ready = actual == expected and unit.survival_pending_model_asset_id == nil
            result[index] = { entindex = slot.state.entindex, model_ready = ready,
                model = actual, particles = effects.debug_snapshot(slot.state.entindex).particle_ids }
            log("STATUS slot=" .. index .. " model_ready=" .. tostring(ready)
                .. " particles=" .. #result[index].particles .. " model=" .. actual)
        end
        return result
    end

    function fixture:move(index, dx, dy)
        local slot = current_slot(self, index)
        local before = effects.debug_snapshot(slot.state.entindex)
        slot.unit:SetAbsOrigin(ground(slot.unit:GetAbsOrigin()
            + Vector(tonumber(dx) or 180, tonumber(dy) or 0, 0)))
        -- Same event data that relocation republishes; no gameplay/grid event.
        rank.publish(slot.state)
        effects.apply(slot.state)
        local after = effects.debug_snapshot(slot.state.entindex)
        assert(before.key == after.key and #before.particle_ids == #after.particle_ids)
        for i, id in ipairs(before.particle_ids) do assert(after.particle_ids[i] == id) end
        log("FOLLOW_PASS slot=" .. index .. " ids=" .. table.concat(after.particle_ids, ",")
            .. " (direct fixture move, not D-grid validation)")
        return after
    end

    function fixture:kill(index)
        local slot = current_slot(self, index)
        -- Cache identity while the unit is alive. Never query the dead handle
        -- from the delayed assertion; engine removal may already have happened.
        local entindex = slot.state.entindex
        local task_key = "tower_presentation_review_death_" .. tostring(entindex)
        self.last_death_passed = nil
        self.death_checks[task_key] = true
        slot.unit:ForceKill(false)
        scheduler.after(DEATH_CHECK_DELAY, function()
            if not alive_fixture(self) then return end
            self.death_checks[task_key] = nil
            local snapshot = effects.debug_snapshot(entindex)
            local replicated = CustomNetTables:GetTableValue("survival_tower_rank", "unit_" .. entindex)
            local effects_cleared = not snapshot.tracked and #snapshot.particle_ids == 0
            local rank_cleared = not replicated or tonumber(replicated.removed) == 1
            self.last_death_passed = effects_cleared and rank_cleared
            self.last_death_check = { entindex = entindex, delay = DEATH_CHECK_DELAY,
                effects_cleared = effects_cleared, rank_cleared = rank_cleared }
            log((self.last_death_passed and "DEATH_PASS" or "DEATH_FAIL") .. " slot=" .. index
                .. " entity=" .. entindex .. " after=" .. DEATH_CHECK_DELAY
                .. "s effects=" .. tostring(effects_cleared) .. " rank=" .. tostring(rank_cleared))
        end, task_key)
    end

    local ok, error_message = pcall(function()
        for index = 1, 10 do
            local unit = assert(CreateUnitByName("npc_survival_grid_preview_proxy", plans[index], false, nil, nil, team))
            local state = { unit = unit, entindex = unit:entindex(), player_id = player_id,
                team = team, building_id = index == 10 and "ultimate_tower" or "arrow_tower",
                level = index == 1 and 1 or (index == 2 and 5 or (index == 10 and 1 or class_level)),
                tower_class = index >= 3 and index <= 9 and "class_" .. (index - 2) or nil }
            local slot = { unit = unit, state = state, model_generation = 1 }
            fixture.slots[#fixture.slots + 1] = slot
            unit.survival_manual_presentation_fixture = true
            unit.survival_is_building = false
            unit:SetAcquisitionRange(0)
            unit:SetAttackCapability(DOTA_UNIT_CAP_NO_ATTACK)
            unit:SetMoveCapability(DOTA_UNIT_CAP_MOVE_NONE)
            unit:SetHullRadius(0)
            unit:SetDayTimeVisionRange(0)
            unit:SetNightTimeVisionRange(0)
            unit:SetControllableByPlayer(player_id, false)
            unit:AddNewModifier(unit, nil, "modifier_invulnerable", {})
            unit:AddNewModifier(unit, nil, "modifier_phased", {})
            unit:SetAbsOrigin(plans[index])
            apply_slot(fixture, slot)
            log("SLOT=" .. index .. " entity=" .. state.entindex
                .. " label=" .. unit.survival_display_name .. " model=" .. tostring(slot.model_status))
        end
    end)
    if not ok then fixture:cleanup(); log("FAILED " .. tostring(error_message)); return { ok = false, error = error_message } end
    log("READY 10 display-only units; normal game economy and authorization unchanged")
    return fixture
end

function M.cleanup()
    if not tools_only() then return { ok = false, error = "tools_server_required" } end
    local fixture = _G[ACTIVE_KEY]
    if fixture then fixture:cleanup() end
    return { ok = true }
end

return M
