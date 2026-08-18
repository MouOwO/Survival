local event_bus = require("core/event_bus")
local events = require("core/events")
local logger = require("core/logger")
local armor_balance = require("config/armor_balance")

local archetypes = require("config/generated/monster_archetypes")
local spawn_points = require("config/generated/monster_spawn_points")
local encounters = require("config/generated/monster_encounters")
local reward_profiles = require("config/generated/reward_profiles")
local reward_effects = require("config/generated/reward_effects")
local combat_profiles = require("config/challenge_combat_profile_config")
local difficulty_config = require("config/difficulty_config")
local challenge_sessions = require("systems/challenge_session_service")
local monster_hull_scale = require("systems/monster_hull_scale")
local wave_monster_collision = require("systems/wave_monster_collision")

local M = {}

local active_by_entindex = {}
local active_by_encounter = {}
local marker_cache = {}

local TEAM_BY_NAME = {
    DOTA_TEAM_GOODGUYS = DOTA_TEAM_GOODGUYS,
    DOTA_TEAM_BADGUYS = DOTA_TEAM_BADGUYS,
    DOTA_TEAM_NEUTRALS = DOTA_TEAM_NEUTRALS,
}

local function valid_entity(entity)
    return entity and not entity:IsNull()
end

local function valid_player_id(player_id)
    return player_id ~= nil
       and player_id >= 0
       and PlayerResource:IsValidPlayerID(player_id)
end

local function effects_for_profile(profile_id)
    local result = {}
    for _, effect in ipairs(reward_effects.rows or {}) do
        if effect.reward_profile_id == profile_id and effect.enabled ~= false then
            table.insert(result, effect)
        end
    end
    table.sort(result, function(a, b)
        return (a.sort_order or 0) < (b.sort_order or 0)
    end)
    return result
end

local function project_encounter(encounter)
    local profile = reward_profiles.by_id[encounter.reward_profile_id] or {}
    return {
        encounter_id = encounter.encounter_id,
        encounter_type = encounter.encounter_type,
        display_name = encounter.display_name,
        spawn_point_id = encounter.spawn_point_id,
        archetype_id = encounter.archetype_id,
        reward_profile_id = encounter.reward_profile_id,
        reward_text = profile.reward_text or "",
        reward_effects = effects_for_profile(encounter.reward_profile_id),
        rebirth_level = encounter.rebirth_level or 0,
        difficulty_level = encounter.difficulty_level or 0,
    }
end

local function find_marker(spawn_point)
    local cached = marker_cache[spawn_point.spawn_point_id]
    if valid_entity(cached) then
        return cached
    end

    local marker = Entities:FindByName(nil, spawn_point.hammer_target_name)
    if valid_entity(marker) then
        marker_cache[spawn_point.spawn_point_id] = marker
        return marker
    end
    return nil
end

local function validate_marker(spawn_point)
    local marker = find_marker(spawn_point)
    if marker then
        logger.info(
            "MonsterSpawn",
            "marker ready: " .. tostring(spawn_point.hammer_target_name)
        )
        return true
    end

    logger.warn(
        "MonsterSpawn",
        "missing Hammer marker: " .. tostring(spawn_point.hammer_target_name)
    )
    return false
end

local function is_active(encounter_id)
    local entindex = active_by_encounter[encounter_id]
    if not entindex then
        return false
    end
    local meta = active_by_entindex[entindex]
    if not meta or not valid_entity(meta.unit) or not meta.unit:IsAlive() then
        active_by_encounter[encounter_id] = nil
        active_by_entindex[entindex] = nil
        return false
    end
    return true
end

local function active_meta(encounter_id)
    if not is_active(encounter_id) then return nil end
    return active_by_entindex[active_by_encounter[encounter_id]]
end

local function hero_for(player_id)
    local summon = event_bus.request(
        events.HERO_SUMMON_GET_REQUEST,
        { player_id = player_id }
    )
    local hero = summon and summon.unit
        or PlayerResource:GetSelectedHeroEntity(player_id)
    if not valid_entity(hero) or not hero:IsAlive() then return nil end
    return hero
end

local function rebirth_entry(encounter_id)
    local suffix = string.match(encounter_id, "encounter_rebirth_(%d+)$")
    local entry_name = suffix and ("rebirth_" .. suffix .. "_entry") or nil
    local entry = entry_name and Entities:FindByName(nil, entry_name) or nil
    return valid_entity(entry) and entry or nil, entry_name
end

local function current_difficulty_id()
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
    if difficulty_id == "" then return nil, "monster_difficulty_unavailable" end
    return difficulty_id, nil
end

local function start_encounter(payload)
    local encounter_id = tostring(payload.encounter_id or "")
    if challenge_sessions.handles(encounter_id) then
        return challenge_sessions.start(payload)
    end
    local encounter = encounters.by_id[encounter_id]
    if not encounter or encounter.enabled == false then
        return { ok = false, error = "encounter_not_found" }
    end
    if is_active(encounter_id) then
        return { ok = false, error = "encounter_already_active" }
    end

    local spawn_point = spawn_points.by_id[encounter.spawn_point_id]
    local archetype = archetypes.by_id[encounter.archetype_id]
    if not spawn_point then
        return { ok = false, error = "spawn_point_not_found" }
    end
    if not archetype or archetype.enabled == false then
        return { ok = false, error = "archetype_not_found" }
    end
    local difficulty_id, difficulty_error = current_difficulty_id()
    if not difficulty_id then return { ok = false, error = difficulty_error } end
    local combat_profile, profile_error = combat_profiles.resolve(
        encounter.encounter_id,
        difficulty_id
    )
    if profile_error then return { ok = false, error = profile_error } end

    local marker = find_marker(spawn_point)
    if not marker then
        return {
            ok = false,
            error = "hammer_marker_not_found:" ..
                tostring(spawn_point.hammer_target_name),
        }
    end

    local hero_entry = nil
    if encounter.encounter_type == "rebirth_boss" then
        local entry_name
        hero_entry, entry_name = rebirth_entry(encounter_id)
        if not hero_entry then
            return {
                ok = false,
                error = "hammer_marker_not_found:" .. tostring(entry_name),
            }
        end
    end

    local team = TEAM_BY_NAME[spawn_point.team_name] or DOTA_TEAM_BADGUYS
    local origin = marker:GetAbsOrigin()
    local unit = CreateUnitByName(
        archetype.unit_name,
        origin,
        true,
        nil,
        nil,
        team
    )
    if not valid_entity(unit) then
        return { ok = false, error = "unit_create_failed" }
    end

    if marker.GetForwardVector and unit.SetForwardVector then
        unit:SetForwardVector(marker:GetForwardVector())
    end
    FindClearSpaceForUnit(unit, origin, true)
    local profile = combat_profile or archetype
    local collision_profile = wave_monster_collision.profile(encounter, archetype)
    monster_hull_scale.apply(unit, 1, collision_profile.base_hull_radius*0.1)
    unit.survival_movement_type = archetype.movement_type or "ground"
    unit.survival_movement_type_override = encounter.movement_type_override
    unit.survival_encounter_id = encounter_id
    unit.survival_is_boss = encounter.encounter_type == "rebirth_boss"
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
        local runtime_armor = 0
        unit:SetPhysicalArmorBaseValue(runtime_armor)
        unit.survival_war3_armor = war3_armor
        unit.survival_base_war3_armor = war3_armor
        unit.survival_armor_mapping_version = armor_balance.CUSTOM_WAR3_MAPPING_VERSION
        unit.survival_effective_war3_armor = war3_armor
        unit.survival_armor = runtime_armor
    end
    local minimum_war3_armor = tonumber(
        archetype.minimum_war3_armor or archetype.minimum_armor
    )
    -- Missing minimum_armor means unrestricted armor reduction. Preserve a
    -- floor only for archetypes that explicitly opt into one.
    unit.survival_minimum_armor = nil
    unit.survival_minimum_war3_armor = minimum_war3_armor
    local attack_speed = tonumber(archetype.attack_speed)
        or tonumber(archetype.base_attack_speed) or 0.5
    attack_speed = math.max(0.01, attack_speed)
    unit.survival_attack_speed = attack_speed
    unit:SetBaseAttackTime(1 / attack_speed)
    if unit.Script_SetAttackRange and archetype.attack_range then
        unit:Script_SetAttackRange(tonumber(archetype.attack_range) or 128)
    elseif unit.SetAttackRange and archetype.attack_range then
        unit:SetAttackRange(tonumber(archetype.attack_range) or 128)
    end
    if not unit:HasModifier("modifier_debug_attack_cap") then
        unit:AddNewModifier(unit, nil, "modifier_debug_attack_cap", {})
    end

    if hero_entry then
        local player_id = tonumber(payload.player_id)
        local hero = hero_for(player_id)
        if hero then
            local hero_origin = hero_entry:GetAbsOrigin()
            hero:SetAbsOrigin(hero_origin)
            FindClearSpaceForUnit(hero, hero_origin, true)
            hero:Stop()
        end
    end

    local player_id = tonumber(payload.player_id)
    local meta = {
        unit = unit,
        encounter_id = encounter_id,
        player_id = valid_player_id(player_id) and player_id or -1,
        team = tonumber(payload.team) or DOTA_TEAM_GOODGUYS,
        reward_profile_id = encounter.reward_profile_id,
        spawn_point_id = encounter.spawn_point_id,
        difficulty_id = difficulty_id,
        projection = project_encounter(encounter),
    }

    active_by_entindex[unit:entindex()] = meta
    active_by_encounter[encounter_id] = unit:entindex()

    event_bus.emit(events.MONSTER_SPAWNED, {
        unit = unit,
        entindex = unit:entindex(),
        encounter_id = encounter_id,
        player_id = meta.player_id,
        team = meta.team,
        reward_profile_id = meta.reward_profile_id,
    })
    event_bus.emit(events.MONSTER_ENCOUNTER_CHANGED, {
        player_id = meta.player_id,
        status = "active",
        foreground_entry = hero_entry ~= nil,
        entindex = unit:entindex(),
        encounter = meta.projection,
    })

    return {
        ok = true,
        encounter_id = encounter_id,
        entindex = unit:entindex(),
        encounter = meta.projection,
        camera_target = hero_entry and {
            x = hero_entry:GetAbsOrigin().x,
            y = hero_entry:GetAbsOrigin().y,
            z = hero_entry:GetAbsOrigin().z,
        } or nil,
    }
end

local function query_encounter(payload)
    local encounter_id = tostring(payload.encounter_id or "")
    if challenge_sessions.handles(encounter_id) then
        return challenge_sessions.query(encounter_id, payload.player_id)
    end
    local encounter = encounters.by_id[encounter_id]
    if not encounter then
        return { ok = false, error = "encounter_not_found" }
    end
    local meta = active_meta(encounter_id)
    local player_id = tonumber(payload.player_id)
    return {
        ok = true,
        active = meta ~= nil and tonumber(meta.player_id) == player_id,
        encounter = project_encounter(encounter),
    }
end

local function reenter_encounter(payload)
    local encounter_id = tostring(payload.encounter_id or "")
    local encounter = encounters.by_id[encounter_id]
    if not encounter or encounter.encounter_type ~= "rebirth_boss" then
        return { ok = false, error = "rebirth_encounter_not_found" }
    end
    local player_id = tonumber(payload.player_id)
    if not valid_player_id(player_id) then
        return { ok = false, error = "player_id_invalid" }
    end
    local meta = active_meta(encounter_id)
    if not meta then
        return { ok = false, error = "encounter_not_active" }
    end
    if tonumber(meta.player_id) ~= player_id then
        return { ok = false, error = "encounter_not_owned" }
    end
    local entry, entry_name = rebirth_entry(encounter_id)
    if not entry then
        return {
            ok = false,
            error = "hammer_marker_not_found:" .. tostring(entry_name),
        }
    end
    local hero = hero_for(player_id)
    if not hero then return { ok = false, error = "hero_not_ready" } end
    local origin = entry:GetAbsOrigin()
    hero:SetAbsOrigin(origin)
    FindClearSpaceForUnit(hero, origin, true)
    hero:Stop()
    return {
        ok = true,
        resumed = true,
        encounter_id = encounter_id,
        entindex = meta.unit:entindex(),
        boss_health = meta.unit:GetHealth(),
        camera_target = { x = origin.x, y = origin.y, z = origin.z },
    }
end

local function on_entity_killed(payload)
    local victim = payload.victim
    if not valid_entity(victim) then
        return
    end

    local entindex = victim:entindex()
    local meta = active_by_entindex[entindex]
    if not meta then
        return
    end

    active_by_entindex[entindex] = nil
    active_by_encounter[meta.encounter_id] = nil

    event_bus.emit(events.MONSTER_KILLED, {
        victim = victim,
        attacker = payload.attacker,
        encounter_id = meta.encounter_id,
        player_id = meta.player_id,
        team = meta.team,
        reward_profile_id = meta.reward_profile_id,
        encounter = meta.projection,
    })
    event_bus.emit(events.MONSTER_ENCOUNTER_COMPLETED, {
        victim = victim,
        attacker = payload.attacker,
        encounter_id = meta.encounter_id,
        player_id = meta.player_id,
        team = meta.team,
        reward_profile_id = meta.reward_profile_id,
        encounter = meta.projection,
    })
    event_bus.emit(events.MONSTER_ENCOUNTER_CHANGED, {
        player_id = meta.player_id,
        status = "completed",
        entindex = entindex,
        encounter = meta.projection,
    })
end

local function validate_all_markers()
    marker_cache = {}
    for _, spawn_point in ipairs(spawn_points.rows or {}) do
        if spawn_point.enabled ~= false then
            validate_marker(spawn_point)
        end
    end
end

function M.init()
    active_by_entindex = {}
    active_by_encounter = {}
    marker_cache = {}

    event_bus.handle_request(
        events.MONSTER_ENCOUNTER_START_REQUEST,
        start_encounter
    )
    event_bus.handle_request(
        events.MONSTER_ENCOUNTER_QUERY_REQUEST,
        query_encounter
    )
    event_bus.handle_request(
        events.MONSTER_ENCOUNTER_REENTER_REQUEST,
        reenter_encounter
    )
    event_bus.subscribe(events.ENGINE_ENTITY_KILLED, on_entity_killed)
    event_bus.subscribe(events.GAME_STARTED, validate_all_markers)
end

return M
