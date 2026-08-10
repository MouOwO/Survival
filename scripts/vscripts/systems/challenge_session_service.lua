local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local armor_balance = require("config/armor_balance")

local challenge_runtime_rules = require("config/challenge_runtime_rules")
local challenges = challenge_runtime_rules.apply(
    require("config/generated/challenge_definitions")
)
local encounters = require("config/generated/monster_encounters")
local locations = require("config/generated/challenge_locations")
local members = require("config/generated/encounter_members")
local archetypes = require("config/generated/monster_archetypes")
local combat_profiles = require("config/challenge_combat_profile_config")
local difficulty_config = require("config/difficulty_config")
local weapons = require("config/generated/weapon_definitions")
local seven_sins_essences = require("config/seven_sins_essences")
local molten_core_rules = require("config/molten_core_challenge_rules")
local hero_return_home = require("systems/hero_return_home_service")
local monster_visual = require("systems/challenge_monster_visual_service")

local M = {}
local sessions = {}
local foreground_encounter_by_player = {}
local monster_meta = {}
local auto_test_started = {}
local abyss_cleared_stage_by_player = {}
-- Set true only when validating the seven-sins / ten-sins map markers.
-- Normal challenge purchases must not create unrelated boss encounters.
local AUTO_START_CHALLENGE_TESTS = false
local WOOD_STRENGTH_ENCOUNTERS = {
    encounter_challenge_02 = true,
    encounter_challenge_03 = true,
    encounter_challenge_04 = true,
    encounter_challenge_05 = true,
    encounter_challenge_06 = true,
    encounter_challenge_07 = true,
    encounter_challenge_08 = true,
    encounter_challenge_09 = true,
}

local function valid(unit)
    return unit and not unit:IsNull()
end

local function alive(unit)
    return valid(unit) and unit:IsAlive()
end

local function challenge_for_encounter(encounter_id)
    for _, row in ipairs(challenges.rows or {}) do
        if row.enabled ~= false and row.encounter_id == encounter_id then
            return row
        end
    end
    return nil
end

local function members_for(encounter_id)
    local result = {}
    for _, row in ipairs(members.rows or {}) do
        if row.enabled ~= false and row.encounter_id == encounter_id then
            result[#result + 1] = row
        end
    end
    table.sort(result, function(a, b)
        return (tonumber(a.sequence_index) or 0)
            < (tonumber(b.sequence_index) or 0)
    end)
    return result
end

local function owned_series_stage(player_id, series_id)
    local inventory = event_bus.request(
        events.CONTENT_INVENTORY_GET_REQUEST,
        { player_id = player_id }
    )
    local counts = inventory and inventory.snapshot and inventory.snapshot.counts
    if not counts then return nil, "challenge_inventory_unavailable" end

    local current = nil
    for _, definition in ipairs(weapons.rows or {}) do
        if definition.enabled ~= false
            and definition.series_id == series_id
            and (tonumber(counts[definition.content_id]) or 0) > 0
            and (not current
                or (tonumber(definition.stage) or -1)
                    > (tonumber(current.stage) or -1)) then
            current = definition
        end
    end
    return current and tonumber(current.stage) or nil, nil
end

local function hero_for(player_id)
    local result = event_bus.request(
        events.HERO_SUMMON_GET_REQUEST,
        { player_id = player_id }
    )
    local hero = result and result.unit
        or PlayerResource:GetSelectedHeroEntity(player_id)
    return valid(hero) and hero or nil
end

local function marker(name)
    if not name or name == "" then return nil end
    local entity = Entities:FindByName(nil, name)
    return valid(entity) and entity or nil
end

local function teleport(unit, target)
    if not alive(unit) or not valid(target) then return false end
    local position = target:GetAbsOrigin()
    unit:SetAbsOrigin(position)
    FindClearSpaceForUnit(unit, position, true)
    unit:Stop()
    return true
end

local function player_sessions(player_id)
    sessions[player_id] = sessions[player_id] or {}
    return sessions[player_id]
end

local function get_session(player_id, encounter_id)
    local owned = sessions[player_id]
    return owned and owned[encounter_id] or nil
end

local function set_session(session)
    player_sessions(session.player_id)[session.encounter_id] = session
end

local function set_foreground(session)
    foreground_encounter_by_player[session.player_id] = session.encounter_id
end

local function should_teleport_after_completion(session)
    return session.challenge.completion_teleport_policy == "reset_to_stage_entry"
        and foreground_encounter_by_player[session.player_id] == session.encounter_id
end

local function on_foreground_encounter_changed(payload)
    if payload and payload.status == "active"
        and payload.foreground_entry == true
        and payload.encounter then
        local player_id = tonumber(payload.player_id)
        local encounter_id = tostring(payload.encounter.encounter_id or "")
        if player_id and player_id >= 0 and encounter_id ~= "" then
            foreground_encounter_by_player[player_id] = encounter_id
        end
    end
end

local function spawn_marker(location, allow_occupied)
    local candidates = {}
    for _, name in ipairs(location.spawn_target_names or {}) do
        local point = marker(name)
        if point then
            if allow_occupied then
                candidates[#candidates + 1] = point
            else
                local occupied = FindUnitsInRadius(
                    DOTA_TEAM_BADGUYS, point:GetAbsOrigin(), nil, 96,
                    DOTA_UNIT_TARGET_TEAM_BOTH,
                    DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC,
                    DOTA_UNIT_TARGET_FLAG_NONE,
                    FIND_ANY_ORDER, false
                ) or {}
                if #occupied == 0 then candidates[#candidates + 1] = point end
            end
        end
    end
    if #candidates == 0 then return nil end
    return candidates[RandomInt(1, #candidates)]
end

local function remove_dead(session)
    local count = 0
    for entindex, unit in pairs(session.monsters) do
        if not alive(unit) then
            session.monsters[entindex] = nil
        else
            count = count + 1
        end
    end
    session.monster_count = count
end

local function destroy_session_monsters(session)
    for entindex, unit in pairs(session.monsters or {}) do
        monster_meta[entindex] = nil
        if valid(unit) then monster_visual.clear(unit) end
        if alive(unit) then UTIL_Remove(unit) end
    end
    session.monsters = {}
    session.monster_count = 0
end

local function apply_combat_stats(unit, archetype, profile)
    profile = profile or archetype
    local health = tonumber(profile.health or archetype.health)
    if health and health > 0 then
        unit:SetBaseMaxHealth(health)
        unit:SetMaxHealth(health)
        unit:SetHealth(health)
    end
    local attack = tonumber(profile.attack or archetype.attack)
    if attack then
        unit:SetBaseDamageMin(attack)
        unit:SetBaseDamageMax(attack)
    end
    local war3_armor = tonumber(
        profile.war3_armor or profile.armor
            or archetype.war3_armor or archetype.armor
    )
    if war3_armor then
        local runtime_armor = armor_balance.from_war3(war3_armor)
        unit:SetPhysicalArmorBaseValue(runtime_armor)
        unit.survival_war3_armor = war3_armor
        unit.survival_armor = runtime_armor
    end
    local minimum_war3_armor = tonumber(
        archetype.minimum_war3_armor or archetype.minimum_armor
    )
    -- Only explicitly configured archetypes have an armor floor. A default
    -- floor would silently block hero research armor reduction on normal mobs.
    unit.survival_minimum_armor = minimum_war3_armor ~= nil
        and armor_balance.from_war3(minimum_war3_armor) or nil
    local attack_speed = math.max(0.01, tonumber(archetype.attack_speed) or 1)
    unit:SetBaseAttackTime(1 / attack_speed)
    unit.survival_attack_speed = attack_speed
end

local function spawn_point_for(session, member, location)
    if session.local_spawn_fallback then
        local expected = (location.spawn_target_names or {})[1] or "unknown"
        return nil, expected
    end
    if member.spawn_target_name and member.spawn_target_name ~= "" then
        return marker(member.spawn_target_name), member.spawn_target_name
    end
    -- Practice rooms may intentionally expose only one marker. Units are
    -- spread by FindClearSpaceForUnit after creation, so occupancy must not
    -- make the marker unavailable for the remaining configured count.
    local point = spawn_marker(location, member.spawn_mode == "maintain_count")
    if not point and WOOD_STRENGTH_ENCOUNTERS[session.encounter_id] then
        point = marker(location.entry_target_name)
    end
    local expected = (location.spawn_target_names or {})[1] or "unknown"
    return point, expected
end

local function spawn_member(session, member)
    local location = locations.by_id[member.location_id]
    local archetype = archetypes.by_id[member.archetype_id]
    if not location then return nil, "challenge_location_not_found" end
    if not archetype or archetype.enabled == false then
        return nil, "challenge_archetype_not_found:" .. tostring(member.archetype_id)
    end
    local combat_profile, profile_error = combat_profiles.resolve(
        member.member_id,
        session.difficulty_id
    )
    if profile_error then return nil, profile_error end

    local point, expected = spawn_point_for(session, member, location)
    local position = point and point:GetAbsOrigin() or nil
    if position and session.challenge.challenge_id == "challenge_10" then
        session.spawn_serial = (tonumber(session.spawn_serial) or 0) + 1
        local slot = (session.spawn_serial - 1) % 10
        local angle = math.rad(slot * 36)
        local radius = slot % 2 == 0 and 300 or 460
        local candidate = GetGroundPosition(position + Vector(
            math.cos(angle) * radius,
            math.sin(angle) * radius,
            0
        ), point)
        if not GridNav:IsBlocked(candidate) and GridNav:IsTraversable(candidate) then
            position = candidate
        end
    end
    if not position and WOOD_STRENGTH_ENCOUNTERS[session.encounter_id] then
        local hero = hero_for(session.player_id)
        if alive(hero) then
            local origin = hero:GetAbsOrigin()
            for _ = 1, 8 do
                local candidate = GetGroundPosition(
                    origin + RandomVector(RandomInt(240, 420)),
                    hero
                )
                if not GridNav:IsBlocked(candidate)
                    and GridNav:IsTraversable(candidate) then
                    position = candidate
                    break
                end
            end
            if not position and not GridNav:IsBlocked(origin)
                and GridNav:IsTraversable(origin) then
                position = origin
            end
        end
    end
    if not position then
        return nil, "hammer_marker_not_found:" .. tostring(expected)
    end
    if GridNav:IsBlocked(position) or not GridNav:IsTraversable(position) then
        return nil, "challenge_spawn_blocked:" .. tostring(
            point and point:GetName() or expected
        )
    end

    local unit = CreateUnitByName(
        archetype.unit_name, position, true, nil, nil, DOTA_TEAM_BADGUYS
    )
    if not valid(unit) then return nil, "challenge_unit_create_failed" end
    FindClearSpaceForUnit(unit, position, true)
    if archetype.model_path and archetype.model_path ~= "" then
        unit:SetModel(archetype.model_path)
        unit:SetOriginalModel(archetype.model_path)
    end
    unit:SetModelScale(tonumber(archetype.model_scale) or 1)
    local combat_archetype = archetypes.by_id[
        tostring(member.combat_archetype_id or "")
    ] or archetype
    if unit.SetBaseMoveSpeed and combat_archetype.move_speed then
        unit:SetBaseMoveSpeed(tonumber(combat_archetype.move_speed) or 270)
    end
    if unit.Script_SetAttackRange and combat_archetype.attack_range then
        unit:Script_SetAttackRange(tonumber(combat_archetype.attack_range) or 128)
    end
    apply_combat_stats(unit, combat_archetype, combat_profile)
    monster_visual.apply(unit, archetype)
    if unit.SetAcquisitionRange then unit:SetAcquisitionRange(0) end

    local home = nil
    if member.spawn_mode == "maintain_count" then
        -- FindClearSpaceForUnit may fan several practice monsters out from one
        -- marker. Preserve each resolved position as its own leash origin so
        -- the AI does not repeatedly force all of them back into one point.
        home = unit:GetAbsOrigin()
    elseif member.spawn_target_name and member.spawn_target_name ~= "" and point then
        home = point:GetAbsOrigin()
    else
        local home_marker = marker(location.home_target_name) or point
        home = home_marker and home_marker:GetAbsOrigin() or position
    end
    local hero = hero_for(session.player_id)
    unit:AddNewModifier(unit, nil, "modifier_practice_monster_ai", {
        hero_entindex = hero and hero:entindex() or -1,
        home_x = home.x,
        home_y = home.y,
        home_z = home.z,
        aggro_radius = tonumber(session.encounter.aggro_radius) or 700,
        leash_radius = tonumber(session.encounter.leash_radius) or 1200,
    })

    session.monsters[unit:entindex()] = unit
    session.monster_count = session.monster_count + 1
    monster_meta[unit:entindex()] = {
        player_id = session.player_id,
        team = session.team,
        encounter_id = session.encounter_id,
        member = member,
    }
    event_bus.emit(events.MONSTER_SPAWNED, {
        unit = unit,
        entindex = unit:entindex(),
        encounter_id = session.encounter_id,
        player_id = session.player_id,
        team = session.team,
        archetype_id = member.archetype_id,
        reward_profile_id = member.reward_profile_id,
    })
    return unit
end

local function current_member(session)
    return session.members[session.stage]
end

local function current_location(session)
    local member = current_member(session) or session.members[1]
    return member and locations.by_id[member.location_id] or nil
end

local function current_entry_marker_name(session)
    local member = current_member(session) or session.members[1]
    if session.challenge.challenge_id == "challenge_11" and member then
        return string.format(
            "challenge_11_stage_%02d_entry",
            math.max(1, tonumber(member.sequence_index) or 1)
        )
    end
    local location = current_location(session)
    return location and location.entry_target_name or nil
end

local function validate_member_marker(member)
    local location = locations.by_id[member.location_id]
    if not location then return false, "challenge_location_not_found" end
    local name = member.spawn_target_name
    if name and name ~= "" and not marker(name) then
        return false, "hammer_marker_not_found:" .. name
    end
    return true
end

local function validate_session_markers(session)
    local location = current_location(session)
    if not location then return false, "challenge_location_not_found" end
    local entry_target_name = current_entry_marker_name(session)
    if session.teleport_hero and not marker(entry_target_name) then
        if WOOD_STRENGTH_ENCOUNTERS[session.encounter_id] then
            session.teleport_hero = false
            session.local_spawn_fallback = true
        else
            return false, "hammer_marker_not_found:" .. tostring(entry_target_name)
        end
    end
    for _, member in ipairs(session.members) do
        local ok, error_message = validate_member_marker(member)
        if not ok then return false, error_message end
    end
    return true
end

local function validate_session_combat_profiles(session)
    for _, member in ipairs(session.members) do
        local _, profile_error = combat_profiles.resolve(
            member.member_id,
            session.difficulty_id
        )
        if profile_error then return false, profile_error end
    end
    return true, nil
end

local function teleport_to_current(session)
    if not session.teleport_hero then return true end
    local hero = hero_for(session.player_id)
    local location = current_location(session)
    if not hero then return false, "hero_not_ready" end
    if not location then return false, "challenge_location_not_found" end
    local entry_target_name = current_entry_marker_name(session)
    local entry = marker(entry_target_name)
    if not entry then
        return false, "hammer_marker_not_found:" .. tostring(entry_target_name)
    end
    return teleport(hero, entry), nil
end

local function camera_target_for_session(session)
    if not session or not session.teleport_hero then return nil end
    local entry = marker(current_entry_marker_name(session))
    if not entry then return nil end
    local position = entry:GetAbsOrigin()
    return { x = position.x, y = position.y, z = position.z }
end

local function teleport_to_active_monster(session)
    local hero = hero_for(session.player_id)
    if not alive(hero) then return false, "hero_not_ready" end
    remove_dead(session)
    for _, unit in pairs(session.monsters) do
        if alive(unit) then
            local position = unit:GetAbsOrigin() - unit:GetForwardVector() * 160
            hero:SetAbsOrigin(position)
            FindClearSpaceForUnit(hero, position, true)
            hero:Stop()
            return true
        end
    end
    return false, "challenge_active_monster_not_found"
end

local function fill_member(session, member)
    local target = math.max(1, tonumber(member.max_alive) or 1)
    for _ = 1, target do
        local unit, error_message = spawn_member(session, member)
        if not unit then return false, error_message end
    end
    return true
end

local function fill_current(session)
    local member = current_member(session)
    if not member then return false, "challenge_member_not_found" end
    if member.spawn_mode == "maintain_count" then
        remove_dead(session)
        local target = math.max(1, tonumber(member.max_alive) or 1)
        while session.monster_count < target do
            local unit, error_message = spawn_member(session, member)
            if not unit then return false, error_message end
        end
        return true
    end
    return fill_member(session, member)
end

local function fill_initial(session)
    if session.spawn_mode ~= "simultaneous" then return fill_current(session) end
    for _, member in ipairs(session.members) do
        local ok, error_message = fill_member(session, member)
        if not ok then return false, error_message end
    end
    return true
end

local function publish(session, status, extra)
    local payload = {
        player_id = session.player_id,
        status = status or session.status,
        stage = session.display_stage or session.stage,
        total_members = session.display_total_members or #session.members,
        killed_members = session.killed_members,
        alive = session.monster_count,
        encounter = {
            encounter_id = session.encounter_id,
            display_name = session.encounter.display_name,
        },
    }
    for key, value in pairs(extra or {}) do payload[key] = value end
    event_bus.emit(events.MONSTER_ENCOUNTER_CHANGED, payload)
end

local block_session

local function complete_session(session)
    if session.status == "completed" then return end
    session.status = "completed"
    local reward_result = { ok = true, handled_by = "challenge_material" }
    if session.challenge.challenge_id ~= "challenge_10"
        and session.challenge.challenge_id ~= "challenge_11" then
        reward_result = event_bus.request(
            events.CHALLENGE_EQUIPMENT_REWARD_REQUEST,
            {
                player_id = session.player_id,
                challenge_id = session.challenge.challenge_id,
                encounter_id = session.encounter_id,
                completion_id = session.encounter_id .. ":" .. session.generation,
                position = (
                    session.challenge.challenge_id == "challenge_05"
                    or session.challenge.challenge_id == "challenge_08"
                    or session.challenge.challenge_id == "challenge_09"
                ) and session.completion_drop_position or nil,
                authoritative = true,
            }
        )
    end
    local repeatable = session.challenge.repeatable == true
    local delay = tonumber(session.challenge.respawn_seconds) or 2
    local completion_limit = math.max(
        1,
        tonumber(session.challenge.completion_limit) or 10
    )
    if repeatable and session.challenge.challenge_id == "challenge_11" then
        local abyss_stage, inventory_error = owned_series_stage(
            session.player_id,
            "legend_abyss"
        )
        if inventory_error then
            block_session(session, inventory_error)
            return
        end
        if abyss_stage == nil or abyss_stage >= completion_limit then
            publish(session, "completed", {
                reward_result = reward_result or {},
                entrance_closed = abyss_stage ~= nil,
            })
            return
        end
        if (tonumber(abyss_cleared_stage_by_player[session.player_id]) or -1)
            >= abyss_stage then
            publish(session, "completed", {
                reward_result = reward_result or {},
                material_pending = true,
            })
            return
        end
        local list = members_for(session.encounter_id)
        local target_member = list[abyss_stage + 1]
        if not target_member then
            block_session(session, "abyss_stage_member_missing")
            return
        end
        session.members = { target_member }
        session.stage = 1
        session.display_stage = abyss_stage + 1
        session.display_total_members = completion_limit
        session.spawn_mode = target_member.spawn_mode or "single"
    elseif repeatable then
        session.stage = 1
    else
        publish(session, "completed", { reward_result = reward_result or {} })
        return
    end

    session.status = "waiting_respawn"
    session.generation = DoUniqueString("challenge_completion")
    local scheduled_generation = session.generation
    session.completion_drop_position = nil
    publish(session, "waiting_respawn", {
        reward_result = reward_result or {},
        next_spawn_seconds = delay,
    })
    scheduler.after(delay, function()
        if get_session(session.player_id, session.encounter_id) ~= session
            or session.status ~= "waiting_respawn"
            or session.generation ~= scheduled_generation then
            return
        end
        session.killed_members = 0
        local ok, error_message = fill_initial(session)
        if not ok then
            block_session(session, error_message)
            return
        end
        if should_teleport_after_completion(session) then
            ok, error_message = teleport_to_current(session)
            if not ok then
                destroy_session_monsters(session)
                block_session(session, error_message)
                return
            end
        end
        session.status = "active"
        publish(session, "active")
    end, "challenge_respawn:" .. session.player_id .. ":" .. session.encounter_id)
end

function M.handles(encounter_id)
    return challenge_for_encounter(encounter_id) ~= nil
end

function M.query(encounter_id, player_id)
    local session = get_session(tonumber(player_id) or -1, encounter_id)
    return {
        ok = true,
        active = session ~= nil and session.status ~= "completed",
        stage = session and (session.display_stage or session.stage) or 0,
        status = session and session.status or "inactive",
        total_members = session
            and (session.display_total_members or #session.members) or 0,
        killed_members = session and session.killed_members or 0,
        alive = session and session.monster_count or 0,
        encounter = { encounter_id = encounter_id },
    }
end

function M.start(payload)
    local encounter_id = tostring(payload.encounter_id or "")
    local challenge = challenge_for_encounter(encounter_id)
    local encounter = encounters.by_id[encounter_id]
    if not challenge or not encounter then
        return { ok = false, error = "challenge_encounter_not_found" }
    end
    local player_id = tonumber(payload.player_id)
    if player_id == nil or player_id < 0 then
        return { ok = false, error = "player_id_invalid" }
    end
    local hero = hero_for(player_id)
    if not alive(hero) then return { ok = false, error = "hero_not_ready" } end
    local wave_state, wave_state_error = event_bus.request(
        events.WAVE_STATE_GET_REQUEST,
        {}
    )
    local difficulty_id = wave_state and wave_state.ok
        and tostring(wave_state.difficulty_id or "") or ""
    if difficulty_id == ""
        and wave_state_error == "no_request_handler:"
            .. tostring(events.WAVE_STATE_GET_REQUEST) then
        difficulty_id = difficulty_config.default_id
    end
    if difficulty_id == "" then
        return { ok = false, error = "challenge_difficulty_unavailable" }
    end

    if challenge.challenge_id == "challenge_10" then
        local abyss_stage, inventory_error = owned_series_stage(player_id, "legend_abyss")
        if inventory_error then return { ok = false, error = inventory_error } end
        if abyss_stage ~= nil then
            return {
                ok = false,
                error = "冰火裁决已升阶为深渊审判，七宗罪入口已关闭",
            }
        end
    end

    local existing = get_session(player_id, encounter_id)
    if existing and existing.status ~= "completed" then
        if payload.teleport_hero ~= false then
            local ok, error_message = teleport_to_current(existing)
            if not ok then return { ok = false, error = error_message } end
            set_foreground(existing)
        end
        return {
            ok = true,
            resumed = true,
            stage = existing.stage,
            alive = existing.monster_count,
            encounter_id = encounter_id,
            camera_target = camera_target_for_session(existing),
        }
    end

    local list = members_for(encounter_id)
    if #list == 0 then return { ok = false, error = "challenge_members_missing" } end
    local display_stage = 1
    local display_total_members = #list
    if challenge.challenge_id == "challenge_11" then
        local abyss_stage, inventory_error = owned_series_stage(
            player_id,
            "legend_abyss"
        )
        if inventory_error then return { ok = false, error = inventory_error } end
        if abyss_stage == nil then
            return {
                ok = false,
                error = "需要持有【传说：深渊审判】才能进入罪渊第一层",
            }
        end
        local completion_limit = math.max(
            1,
            tonumber(challenge.completion_limit) or 10
        )
        if abyss_stage >= completion_limit then
            return {
                ok = false,
                error = "【传说：深渊审判】已达到+"
                    .. tostring(completion_limit) .. "，罪渊挑战已完成",
            }
        end
        if (tonumber(abyss_cleared_stage_by_player[player_id]) or -1)
            >= abyss_stage then
            return {
                ok = false,
                error = "本层罪渊已通关，请先完成地面材料自动合成后再进入下一层",
            }
        end
        local target_member = list[abyss_stage + 1]
        if not target_member then
            return { ok = false, error = "abyss_stage_member_missing" }
        end
        list = { target_member }
        display_stage = abyss_stage + 1
        display_total_members = completion_limit
    end
    local session = {
        player_id = player_id,
        team = tonumber(payload.team) or PlayerResource:GetTeam(player_id),
        challenge = challenge,
        encounter = encounter,
        encounter_id = encounter_id,
        difficulty_id = difficulty_id,
        members = list,
        stage = 1,
        display_stage = display_stage,
        display_total_members = display_total_members,
        monsters = {},
        monster_count = 0,
        killed_members = 0,
        status = "active",
        spawn_mode = list[1].spawn_mode or "single",
        teleport_hero = payload.teleport_hero ~= false,
        generation = DoUniqueString("challenge_completion"),
        seven_sins_drop_total = 0,
        seven_sins_drop_counts = {},
        seven_sins_ground_items = {},
        spawn_serial = 0,
        molten_core_kill_serial = 0,
    }
    local profiles_ok, profile_error = validate_session_combat_profiles(session)
    if not profiles_ok then return { ok = false, error = profile_error } end
    local markers_ok, marker_error = validate_session_markers(session)
    if not markers_ok then return { ok = false, error = marker_error } end

    -- Create the whole encounter before moving the player. A failed spawn
    -- therefore never leaves the player in an empty challenge room.
    local ok, error_message = fill_initial(session)
    if ok then ok, error_message = teleport_to_current(session) end
    if not ok then
        destroy_session_monsters(session)
        return { ok = false, error = error_message }
    end
    set_session(session)
    if session.teleport_hero then set_foreground(session) end
    publish(session, "active")
    return {
        ok = true,
        stage = display_stage,
        alive = session.monster_count,
        encounter_id = encounter_id,
        camera_target = camera_target_for_session(session),
    }
end

local function owner_killed(meta, attacker)
    local attacker_owner = valid(attacker) and attacker.GetPlayerOwnerID
        and attacker:GetPlayerOwnerID() or -1
    local attacker_team = valid(attacker) and attacker.GetTeamNumber
        and attacker:GetTeamNumber() or DOTA_TEAM_NOTEAM
    return attacker_owner == meta.player_id
        or attacker == hero_for(meta.player_id)
        or attacker_team == meta.team
end

block_session = function(session, error_message)
    session.status = "blocked"
    publish(session, "blocked", { error = error_message })
    event_bus.emit(events.UI_NOTIFICATION, {
        player_id = session.player_id,
        message = error_message or "下一只挑战怪物无法生成",
        level = "error",
    })
end

local function seven_sins_drop_position(session, sequence_index)
    local location = current_location(session)
    local center_marker = location and (
        marker(location.home_target_name)
        or marker(location.entry_target_name)
        or spawn_marker(location, true)
    ) or nil
    if not center_marker then return nil, "seven_sins_drop_center_missing" end
    local center = center_marker:GetAbsOrigin()
    local angle = math.rad((sequence_index - 1) * (360 / #seven_sins_essences.rows) - 90)
    local position = GetGroundPosition(center + Vector(
        math.cos(angle) * seven_sins_essences.drop_radius,
        math.sin(angle) * seven_sins_essences.drop_radius,
        0
    ), center_marker)
    if GridNav:IsBlocked(position) or not GridNav:IsTraversable(position) then
        position = GetGroundPosition(center + Vector(
            math.cos(angle) * 220,
            math.sin(angle) * 220,
            0
        ), center_marker)
    end
    return position
end

local function drop_seven_sins_essence(session)
    if RandomFloat(0, 100) >= seven_sins_essences.drop_chance_pct then
        return { ok = true, dropped = false, chance_missed = true }
    end
    local total = tonumber(session.seven_sins_drop_total) or 0
    local total_weight = 0
    for _, row in ipairs(seven_sins_essences.rows) do
        total_weight = total_weight + math.max(0, tonumber(row.drop_weight) or 0)
    end
    if total_weight <= 0 then return { ok = false, error = "essence_weights_invalid" } end
    local roll = RandomFloat(0, total_weight)
    local sequence_index = #seven_sins_essences.rows
    local accumulated = 0
    for index, row in ipairs(seven_sins_essences.rows) do
        accumulated = accumulated + math.max(0, tonumber(row.drop_weight) or 0)
        if roll < accumulated then
            sequence_index = index
            break
        end
    end
    local definition = seven_sins_essences.rows[sequence_index]
    local dropped = tonumber(session.seven_sins_drop_counts[definition.content_id]) or 0
    local position, position_error = seven_sins_drop_position(session, sequence_index)
    if not position then return { ok = false, error = position_error } end
    local hero = hero_for(session.player_id)
    if not valid(hero) then return { ok = false, error = "hero_not_ready" } end
    local ground_item = session.seven_sins_ground_items[definition.content_id]
    local ground_container = valid(ground_item) and ground_item.GetContainer
        and ground_item:GetContainer() or nil
    if valid(ground_item) and valid(ground_container) then
        ground_item:SetCurrentCharges(
            math.max(1, tonumber(ground_item:GetCurrentCharges()) or 1) + 1
        )
        session.seven_sins_drop_counts[definition.content_id] = dropped + 1
        session.seven_sins_drop_total = total + 1
        return {
            ok = true,
            content_id = definition.content_id,
            legacy_id = definition.legacy_id,
            drop_total = session.seven_sins_drop_total,
            stacked = true,
        }
    end
    local item = CreateItem(definition.engine_item_name, hero, hero)
    if not valid(item) then return { ok = false, error = "essence_create_failed" } end
    item.survival_content_id = definition.content_id
    item.survival_owner_player_id = session.player_id
    if item.SetPurchaser then item:SetPurchaser(hero) end
    if item.SetCurrentCharges then item:SetCurrentCharges(1) end
    local container = CreateItemOnPositionSync(position, item)
    if not valid(container) then
        UTIL_Remove(item)
        return { ok = false, error = "essence_container_create_failed" }
    end
    session.seven_sins_ground_items[definition.content_id] = item
    session.seven_sins_drop_counts[definition.content_id] = dropped + 1
    session.seven_sins_drop_total = total + 1
    CustomNetTables:SetTableValue(
        "survival_inventory_item_identity",
        tostring(item:entindex()),
        { content_id = definition.content_id, removed = 0 }
    )
    return {
        ok = true,
        content_id = definition.content_id,
        legacy_id = definition.legacy_id,
        drop_total = session.seven_sins_drop_total,
    }
end

local function on_killed(payload)
    local victim = payload.victim
    if not valid(victim) then return end
    local entindex = victim:entindex()
    local meta = monster_meta[entindex]
    if not meta then return end
    monster_meta[entindex] = nil
    monster_visual.clear(victim)
    local session = get_session(meta.player_id, meta.encounter_id)
    if not session then return end
    session.monsters[entindex] = nil
    session.monster_count = math.max(0, session.monster_count - 1)
    session.killed_members = session.killed_members + 1

    local authorized_kill = owner_killed(meta, payload.attacker)
    if authorized_kill then
        session.completion_drop_position = victim:GetAbsOrigin()
    end
    if authorized_kill then
        event_bus.emit(events.MONSTER_KILLED, {
            victim = victim,
            attacker = payload.attacker,
            encounter_id = meta.encounter_id,
            archetype_id = meta.member.archetype_id,
            player_id = meta.player_id,
            team = meta.team,
            reward_profile_id = meta.member.reward_profile_id,
        })
    end

    local challenge_id = session.challenge.challenge_id
    if authorized_kill and challenge_id == molten_core_rules.challenge_id then
        session.molten_core_kill_serial =
            (tonumber(session.molten_core_kill_serial) or 0) + 1
        local dropped, roll = molten_core_rules.roll(RandomFloat)
        print(string.format(
            "[MOLTEN_CORE_DROP_ROLL] player=%s kill=%s roll=%.2f chance=%s dropped=%s",
            tostring(meta.player_id), tostring(session.molten_core_kill_serial),
            tonumber(roll) or -1, tostring(molten_core_rules.drop_chance_pct),
            tostring(dropped)))
        if dropped then
            local drop_result = event_bus.request(
                events.CHALLENGE_CONTENT_DROP_REQUEST,
                {
                    player_id = meta.player_id,
                    challenge_id = challenge_id,
                    content_id = molten_core_rules.content_id,
                    position = victim:GetAbsOrigin(),
                    drop_id = session.encounter_id .. ":" .. session.generation
                        .. ":" .. tostring(session.molten_core_kill_serial),
                    authoritative = true,
                }
            )
            if not drop_result or not drop_result.ok then
                event_bus.emit(events.UI_NOTIFICATION, {
                    player_id = meta.player_id,
                    message = "熔火核心Lv1掉落失败："
                        .. tostring(drop_result and drop_result.error or "handler_missing"),
                    level = "error",
                })
            end
        end
    elseif authorized_kill and challenge_id == "challenge_10" then
        local drop_result = drop_seven_sins_essence(session)
        if not drop_result or not drop_result.ok then
            event_bus.emit(events.UI_NOTIFICATION, {
                player_id = meta.player_id,
                message = "七宗罪精华掉落失败："
                    .. tostring(drop_result and drop_result.error or "handler_missing"),
                level = "error",
            })
        end
    elseif authorized_kill and challenge_id == "challenge_11" then
        local required_stage = math.max(
            0,
            (tonumber(meta.member.sequence_index) or 1) - 1
        )
        local drop_result = event_bus.request(
            events.CHALLENGE_MATERIAL_DROP_REQUEST,
            {
                player_id = meta.player_id,
                team = meta.team,
                challenge_id = challenge_id,
                required_stage = required_stage,
                position = victim:GetAbsOrigin(),
                completion_id = session.encounter_id .. ":"
                    .. session.generation .. ":" .. meta.member.member_id,
                authoritative = true,
            }
        )
        if drop_result and (drop_result.ok or drop_result.material_retained) then
            abyss_cleared_stage_by_player[meta.player_id] = math.max(
                tonumber(abyss_cleared_stage_by_player[meta.player_id]) or -1,
                required_stage
            )
        end
        if not drop_result or not drop_result.ok then
            event_bus.emit(events.UI_NOTIFICATION, {
                player_id = meta.player_id,
                message = "升阶材料生成或合成失败："
                    .. tostring(drop_result and drop_result.error or "handler_missing"),
                level = "error",
            })
        end
    end

    if session.spawn_mode == "maintain_count" then
        local delay = tonumber(meta.member.respawn_seconds)
            or tonumber(session.challenge.respawn_seconds) or 2
        publish(session, "active", { next_spawn_seconds = delay })
        scheduler.after(delay, function()
            if get_session(meta.player_id, meta.encounter_id) == session
                and session.status == "active" then
                local unit, error_message = spawn_member(session, meta.member)
                if not unit then
                    block_session(session, error_message)
                    return
                end
                publish(session, "active")
            end
        end, "challenge_respawn:" .. meta.player_id .. ":"
            .. meta.encounter_id .. ":" .. tostring(entindex))
        return
    end

    if session.spawn_mode == "simultaneous" then
        if session.monster_count == 0 then complete_session(session)
        else publish(session, "active") end
        return
    end

    if session.stage >= #session.members then
        complete_session(session)
        return
    end

    local delay = tonumber(meta.member.spawn_delay_seconds) or 0
    session.stage = session.stage + 1
    session.status = "waiting_next_stage"
    publish(session, "waiting_next_stage", { next_spawn_seconds = delay })
    scheduler.after(delay, function()
        if get_session(meta.player_id, meta.encounter_id) ~= session
            or session.status ~= "waiting_next_stage" then return end
        local ok, error_message = fill_current(session)
        if not ok then
            block_session(session, error_message)
            return
        end
        session.status = "active"
        publish(session, "active")
    end, "challenge_next:" .. meta.player_id .. ":" .. meta.encounter_id)
end

local function on_seven_sins_completed(payload)
    local player_id = tonumber(payload.player_id)
    local session = player_id and get_session(
        player_id,
        seven_sins_essences.encounter_id
    ) or nil
    if session and session.status ~= "completed" then
        session.status = "completed"
        destroy_session_monsters(session)
        publish(session, "completed", { entrance_closed = true })
    end
    local hero = payload.hero or (player_id and hero_for(player_id))
    if alive(hero) then
        hero_return_home.return_unit(hero, player_id)
    end
    event_bus.emit(events.UI_NOTIFICATION, {
        player_id = player_id,
        message = "冰火裁决已升阶为深渊审判，七宗罪入口永久关闭。",
        level = "success",
    })
end

local function start_auto_tests(payload)
    if not AUTO_START_CHALLENGE_TESTS then return end
    local player_id = tonumber(payload.player_id)
    if player_id == nil or player_id < 0 or auto_test_started[player_id] then return end
    auto_test_started[player_id] = true
    scheduler.after(0.5, function()
        local inventory = event_bus.request(
            events.CONTENT_INVENTORY_GET_REQUEST,
            { player_id = player_id }
        )
        local counts = inventory and inventory.snapshot and inventory.snapshot.counts or {}
        for _, setup in ipairs({
            { prefix = "weapon_epic_icefire_", content_id = "weapon_epic_icefire_00" },
            { prefix = "weapon_legend_abyss_", content_id = "weapon_legend_abyss_00" },
        }) do
            local has_series = false
            for owned_id, count in pairs(counts) do
                if tostring(owned_id):find(setup.prefix, 1, true) == 1
                    and (tonumber(count) or 0) > 0 then
                    has_series = true
                    break
                end
            end
            if not has_series then
                event_bus.request(events.CONTENT_INVENTORY_GRANT_REQUEST, {
                    player_id = player_id,
                    content_id = setup.content_id,
                    count = 1,
                    reason = "challenge_auto_test_setup",
                })
            end
        end
        for _, encounter_id in ipairs({
            "encounter_challenge_10",
            "encounter_challenge_11",
        }) do
            local result = M.start({
                encounter_id = encounter_id,
                player_id = player_id,
                team = payload.team,
                teleport_hero = false,
            })
            print(string.format(
                "[CHALLENGE_AUTO_TEST] encounter=%s ok=%s error=%s alive=%s",
                encounter_id,
                tostring(result.ok == true),
                tostring(result.error or ""),
                tostring(result.alive or 0)
            ))
        end
    end, "challenge_auto_test:" .. player_id)
end

function M.init()
    sessions = {}
    foreground_encounter_by_player = {}
    monster_meta = {}
    auto_test_started = {}
    abyss_cleared_stage_by_player = {}
    event_bus.subscribe(events.ENGINE_ENTITY_KILLED, on_killed)
    event_bus.subscribe(
        events.MONSTER_ENCOUNTER_CHANGED,
        on_foreground_encounter_changed
    )
    event_bus.subscribe(events.SEVEN_SINS_COMPLETED, on_seven_sins_completed)
    event_bus.subscribe(events.HERO_READY, start_auto_tests)
end

return M