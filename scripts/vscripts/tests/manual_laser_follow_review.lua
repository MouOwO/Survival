-- Opt-in Tools fixture; no saved building, player owner, economy or event-bus writes.
-- script require("tests/manual_laser_follow_review").run({count=1,seconds=25})
-- script require("tests/manual_laser_follow_review").run({count=4,seconds=30})
-- script SURVIVAL_LASER_FOLLOW_REVIEW:status()
-- script require("tests/manual_laser_follow_review").cleanup()
local M = {}
local KEY = "SURVIVAL_LASER_FOLLOW_REVIEW"
-- Start with a real native ranged attacker, then apply the production tower
-- stats/model/skills. A NO_ATTACK presentation proxy can report a forced
-- target without ever entering native attacks, even after capability changes.
local TOWER = "npc_dota_creep_goodguys_ranged"
local ENEMY = "npc_survival_wave_monster"
local MOTION_RETRY_INTERVAL = 0.35
local skills = require("systems/tower_skill_runtime")
local visuals = require("systems/building_visual_service")
local rules = require("config/tower_combat_rules")
local rows = require("config/generated/tower_class_mystery").rows
local function valid(unit) return unit and not unit:IsNull() end
local function tools_only() return IsServer() and IsInToolsMode() end
local function log(text) print("[LASER_FOLLOW_REVIEW] " .. text) end
local function ground(p) return Vector(p.x, p.y, GetGroundHeight(p, nil)) end
local function usable(p) return GridNav:IsTraversable(p) and not GridNav:IsBlocked(p) end
local function empty(fixture)
    local flags = (DOTA_UNIT_TARGET_FLAG_INVULNERABLE or 0)
        + (DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES or 0)
        + (DOTA_UNIT_TARGET_FLAG_OUT_OF_WORLD or 0)
    local units = FindUnitsInRadius(DOTA_TEAM_GOODGUYS, fixture.origin, nil,
        fixture.clear_radius, DOTA_UNIT_TARGET_TEAM_BOTH,
        DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC + DOTA_UNIT_TARGET_BUILDING,
        flags, FIND_ANY_ORDER, false)
    for _, unit in ipairs(units or {}) do
        if valid(unit) and not fixture.owned[unit] then return false end
    end
    return true
end

function M.run(options)
    if not tools_only() then return { ok = false, error = "tools_server_required" } end
    local world = GameRules:GetGameModeEntity()
    local old = _G[KEY]
    if old and old.world == world and not old.finished then
        return { ok = false, error = "fixture_already_active" }
    end
    options = options or {}
    if options.attack_shell ~= nil and options.attack_shell ~= "native_ranged" then
        return { ok = false, error = "unsupported_attack_shell" }
    end
    local tower_name = TOWER
    local count = tonumber(options.count) or 1
    local level = tonumber(options.level) or 1
    if (count ~= 1 and count ~= 4) or level < 1 or level > 5 or level ~= math.floor(level) then
        return { ok = false, error = "count_must_be_1_or_4_level_1_to_5" }
    end
    if type(PrecacheUnitByNameAsync) ~= "function" then
        return { ok = false, error = "unit_precache_unavailable" }
    end
    local row = assert(rows[level], "missing production mystery row")
    local fixture = { ok = true, world = world, finished = false, phase = "loading",
        origin = ground(options.origin or Vector(12416, -3072, 0)),
        seconds = math.max(5, math.min(90, tonumber(options.seconds) or 25)),
        clear_radius = count == 4 and 1800 or 1500,
        created_at = GameRules:GetGameTime(), units = {}, owned = {}, slots = {}, plans = {},
        row = row, count = count, level = level, attack_shell = tower_name }
    for i = 1, count do
        local y = (i - (count + 1) / 2) * 360
        local plan = {
            tower = ground(fixture.origin + Vector(-220, y, 0)),
            enemy = ground(fixture.origin + Vector(230, y - 110, 0)),
            left = ground(fixture.origin + Vector(230, y - 110, 0)),
            right = ground(fixture.origin + Vector(230, y + 110, 0)),
        }
        for _, point in pairs(plan) do
            if not usable(point) or math.abs(point.z - fixture.origin.z) > 24 then
                return { ok = false, error = "fixture_ground_not_clear", slot = i }
            end
        end
        fixture.plans[i] = plan
    end
    if not empty(fixture) then return { ok = false, error = "fixture_area_occupied" } end
    _G[KEY] = fixture
    local think_key = "SurvivalLaserFollowReview_" .. tostring(math.floor(Time() * 1000))
    local function current()
        return not fixture.finished and _G[KEY] == fixture
            and fixture.world == GameRules:GetGameModeEntity()
    end

    function fixture:status()
        local result = { phase = self.phase, level = self.level, count = self.count, slots = {} }
        if self.world ~= GameRules:GetGameModeEntity() then return result end
        for i, slot in ipairs(self.slots) do
            local modifier = valid(slot.tower)
                and slot.tower:FindModifierByName("modifier_tower_attack_effects")
            local target = modifier and modifier.laser_target
            local cp = {}
            for _, segment in ipairs(modifier and modifier.laser_particles or {}) do
                cp[#cp + 1] = { id = segment.index, source = segment.source_follows,
                    target = segment.target_follows }
            end
            local item = { tower = slot.tower_id, enemy = slot.enemy_id,
                attack_target = valid(target) and target:entindex() or -1,
                laser_ticks = modifier and modifier.laser_ticks or 0, segments = cp,
                hp_drop = valid(slot.enemy) and slot.initial_hp - slot.enemy:GetHealth() or nil,
                turns = slot.turns or 0, move_retries = slot.move_retries or 0,
                travelled = slot.travelled or 0,
                moving = valid(slot.enemy) and slot.enemy:IsMoving() or false }
            result.slots[i] = item
            log(string.format("SLOT phase=%s slot=%d tower=%d enemy=%d target=%d ticks=%d segments=%d hp_drop=%s turns=%d",
                self.phase, i, item.tower, item.enemy, item.attack_target,
                item.laser_ticks, #cp, tostring(item.hp_drop), item.turns))
            if valid(slot.enemy) and slot.destination then
                local position = slot.enemy:GetAbsOrigin()
                log(string.format("MOTION slot=%d moving=%s travelled=%.1f retries=%d turns=%d position=%.1f,%.1f destination=%.1f,%.1f remaining=%.1f",
                    i, tostring(item.moving), item.travelled, item.move_retries, item.turns,
                    position.x, position.y, slot.destination.x, slot.destination.y,
                    (position - slot.destination):Length2D()))
            end
            for _, bound in ipairs(cp) do
                log(string.format("CP slot=%d particle=%d source=%s target=%s", i,
                    bound.id, tostring(bound.source), tostring(bound.target)))
            end
        end
        return result
    end

    function fixture:diagnose()
        if not current() then return { ok = false, error = "fixture_inactive" } end
        local function read(owner, method, ...)
            if not owner or type(owner[method]) ~= "function" then return "unavailable" end
            local ok, value = pcall(owner[method], owner, ...)
            if ok then return value end
            return "unavailable"
        end
        for i, slot in ipairs(self.slots) do
            local tower, enemy = slot.tower, slot.enemy
            local auto = valid(tower) and tower:FindModifierByName("modifier_tower_auto_attack")
            local native_target = valid(tower) and tower:GetAttackTarget()
            local forced = auto and auto.forced_target
            local candidates = valid(tower) and FindUnitsInRadius(tower:GetTeamNumber(), tower:GetAbsOrigin(), nil,
                rules.current_attack_range(tower) + 64, DOTA_UNIT_TARGET_TEAM_ENEMY,
                DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC,
                DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES, FIND_ANY_ORDER, false) or {}
            log(string.format("AI slot=%d tower=%d team=%s enemy_team=%s range=%s cap=%s aps=%s disarmed=%s stack=%s forced=%s native=%s candidates=%d",
                i, slot.tower_id, tostring(read(tower, "GetTeamNumber")), tostring(read(enemy, "GetTeamNumber")),
                tostring(read(tower, "Script_GetAttackRange")), tostring(read(tower, "GetAttackCapability")),
                tostring(read(tower, "GetAttacksPerSecond", false)), tostring(read(tower, "IsDisarmed")),
                tostring(read(auto, "GetStackCount")), tostring(valid(forced) and forced:entindex() or -1),
                tostring(valid(native_target) and native_target:entindex() or -1), #candidates))
            for _, candidate in ipairs(candidates) do
                log("CANDIDATE slot=" .. i .. " unit=" .. candidate:entindex()
                    .. " name=" .. candidate:GetUnitName())
            end
            for _, owner in ipairs({ tower, enemy }) do
                local modifiers = read(owner, "FindAllModifiers")
                if type(modifiers) == "table" then
                    for _, modifier in ipairs(modifiers) do
                        log("MOD unit=" .. owner:entindex() .. " name=" .. tostring(read(modifier, "GetName")))
                    end
                end
            end
        end
        return { ok = true }
    end

    function fixture:cleanup(reason)
        if self.finished then return { ok = true } end
        pcall(self.status, self)
        self.finished, self.phase = true, reason or "cleaned"
        if reason and reason ~= "manual" and reason ~= "complete" then
            self.ok, self.error = false, reason
        end
        local remaining = 0
        if self.world == GameRules:GetGameModeEntity() then
            self.world:SetContextThink(think_key, nil, 0)
            -- Stop production modifiers before removing targets: no more attacks
            -- or beam segments can be created during teardown.
            for _, slot in ipairs(self.slots) do
                if valid(slot.tower) then
                    pcall(slot.tower.RemoveModifierByName, slot.tower, "modifier_tower_auto_attack")
                    pcall(slot.tower.RemoveModifierByName, slot.tower, "modifier_tower_attack_effects")
                    pcall(skills.apply, slot.tower, {})
                    pcall(visuals.clear, slot.tower)
                    pcall(slot.tower.Stop, slot.tower)
                end
            end
            for _, unit in ipairs(self.units) do
                if valid(unit) then pcall(UTIL_Remove, unit) end
                if valid(unit) then remaining = remaining + 1 end
            end
        end
        if _G[KEY] == self then _G[KEY] = nil end
        log(string.format("END reason=%s seconds=%.2f remaining=%d",
            self.phase, GameRules:GetGameTime() - self.created_at, remaining))
        return { ok = remaining == 0, remaining = remaining }
    end

    local function spawn(name, point, team, role, i)
        local unit = assert(CreateUnitByName(name, point, false, nil, nil, team), "unit_create_failed")
        fixture.units[#fixture.units + 1], fixture.owned[unit] = unit, true
        unit:SetEntityName(think_key .. "_" .. role .. "_" .. i)
        unit.survival_is_building = false
        unit.survival_laser_fixture_role = role
        unit:SetBaseMaxHealth(10000000)
        unit:SetMaxHealth(10000000)
        unit:SetHealth(10000000)
        unit:SetBaseHealthRegen(0)
        unit:SetIdleAcquire(false)
        unit:SetAcquisitionRange(0)
        unit:SetAttackCapability(DOTA_UNIT_CAP_NO_ATTACK)
        return unit
    end
    local function setup()
        if not current() then return end
        assert(empty(fixture), "fixture_area_became_occupied")
        for i, plan in ipairs(fixture.plans) do
            local tower = spawn(tower_name, plan.tower, DOTA_TEAM_GOODGUYS, "tower", i)
            -- The shell supplies native attack initialization only. Its creep
            -- damage-class modifier is unrelated to the production tower row.
            tower:RemoveModifierByName("modifier_creep_piercing")
            local slot = { tower = tower, tower_id = tower:entindex(), plan = plan, turns = 0 }
            fixture.slots[i] = slot
            local enemy = spawn(ENEMY, plan.enemy, DOTA_TEAM_BADGUYS, "target", i)
            slot.enemy, slot.enemy_id, slot.initial_hp = enemy, enemy:entindex(), enemy:GetHealth()
            enemy:SetMoveCapability(DOTA_UNIT_CAP_MOVE_GROUND)
            enemy:SetBaseMoveSpeed(300)
            enemy:SetDayTimeVisionRange(1200)
            enemy:SetNightTimeVisionRange(1200)
            tower:SetMoveCapability(DOTA_UNIT_CAP_MOVE_NONE)
            tower:SetBaseDamageMin(row.base_attack_damage)
            tower:SetBaseDamageMax(row.base_attack_damage)
            tower:SetBaseAttackTime(1 / math.max(0.01, row.base_attack_speed))
            tower:SetDayTimeVisionRange(1200)
            tower:SetNightTimeVisionRange(1200)
            rules.set_attack_range(tower, rules.attack_range())
            skills.apply(tower, row.skill_ids)
            for _, skill in ipairs(row.skill_ids) do
                local ability = tower:AddAbility(skill)
                if ability then ability:SetLevel(1) end
            end
            local ok, err = visuals.apply(tower, { model_asset_id = row.model_asset_id, model_name = row.model_name })
            assert(ok, "production_visual_failed:" .. tostring(err))
            log(string.format("SPAWN slot=%d tower=%d target=%d row=%s x=%.0f y=%.0f z=%.0f",
                i, slot.tower_id, slot.enemy_id, row.record_id, plan.tower.x, plan.tower.y, plan.tower.z))
        end
        fixture.phase = "models"
    end
    world:SetContextThink(think_key, function()
        if not current() then return nil end
        local ok, err = pcall(function()
            local now = GameRules:GetGameTime()
            if not empty(fixture) then fixture:cleanup("foreign_unit_entered"); return end
            if fixture.phase ~= "running" and now - fixture.created_at > 20 then
                fixture:cleanup("loading_timeout"); return
            end
            if fixture.phase == "models" then
                for _, slot in ipairs(fixture.slots) do
                    assert(valid(slot.tower) and valid(slot.enemy), "fixture_unit_lost")
                    if slot.tower.survival_pending_model_asset_id
                        or slot.tower:GetModelName() ~= row.model_name then return end
                end
                LinkLuaModifier("modifier_tower_attack_effects", "modifiers/modifier_tower_attack_effects", LUA_MODIFIER_MOTION_NONE)
                LinkLuaModifier("modifier_tower_auto_attack", "modifiers/modifier_tower_auto_attack", LUA_MODIFIER_MOTION_NONE)
                for _, slot in ipairs(fixture.slots) do
                    slot.tower:SetAttackCapability(DOTA_UNIT_CAP_RANGED_ATTACK)
                    assert(slot.tower:AddNewModifier(slot.tower, nil, "modifier_tower_attack_effects", {}))
                    assert(slot.tower:AddNewModifier(slot.tower, nil, "modifier_tower_auto_attack", {}))
                    slot.destination = slot.plan.right
                    slot.last_position = slot.enemy:GetAbsOrigin()
                    slot.next_motion_check = now + MOTION_RETRY_INTERVAL
                    slot.enemy:MoveToPosition(slot.destination)
                end
                fixture.phase, fixture.started_at = "running", now
                log(string.format("START count=%d row=%s duration=%.1f range=%.0f shell=%s", count,
                    row.record_id, fixture.seconds, rules.attack_range(), tower_name))
                fixture:status()
            elseif fixture.phase == "running" then
                if now - fixture.started_at >= fixture.seconds then fixture:cleanup("complete"); return end
                if not fixture.diagnosed and now - fixture.started_at >= 2 then
                    fixture.diagnosed = true
                    fixture:diagnose()
                end
                for _, slot in ipairs(fixture.slots) do
                    assert(valid(slot.tower) and slot.tower:IsAlive()
                        and valid(slot.enemy) and slot.enemy:IsAlive(), "fixture_unit_lost")
                    local position = slot.enemy:GetAbsOrigin()
                    slot.travelled = (slot.travelled or 0) + (position - slot.last_position):Length2D()
                    slot.last_position = position
                    if (position - slot.destination):Length2D() < 28 then
                        slot.destination = slot.destination == slot.plan.right and slot.plan.left or slot.plan.right
                        slot.enemy:MoveToPosition(slot.destination)
                        slot.turns = slot.turns + 1
                        slot.next_motion_check = now + MOTION_RETRY_INTERVAL
                    elseif now >= slot.next_motion_check then
                        slot.next_motion_check = now + MOTION_RETRY_INTERVAL
                        -- Damage can interrupt a creature's native movement.
                        -- Reissue only a dropped order; healthy walking keeps
                        -- its current path and animation between turns.
                        if not slot.enemy:IsMoving() then
                            slot.enemy:MoveToPosition(slot.destination)
                            slot.move_retries = (slot.move_retries or 0) + 1
                        end
                    end
                end
            end
        end)
        if not ok then
            log("ERROR " .. tostring(err):gsub("[\r\n]", " "):sub(1, 300))
            fixture:cleanup("exception")
        end
        return not fixture.finished and 0.1 or nil
    end, 0.1)
    local function loaded_enemy()
        if not current() then return end
        local ok, err = pcall(setup)
        if not ok then log("ERROR " .. tostring(err):sub(1, 300)); fixture:cleanup("setup_exception") end
    end
    local ok, err = pcall(PrecacheUnitByNameAsync, tower_name, function()
        if current() then
            local queued, failure = pcall(PrecacheUnitByNameAsync, ENEMY, loaded_enemy, -1)
            if not queued then log("ERROR " .. tostring(failure)); fixture:cleanup("precache_exception") end
        end
    end, -1)
    if not ok then log("ERROR " .. tostring(err)); fixture:cleanup("precache_exception") end
    return fixture
end

function M.cleanup()
    if not tools_only() then return { ok = false, error = "tools_server_required" } end
    return _G[KEY] and _G[KEY]:cleanup("manual") or { ok = true }
end
return M
