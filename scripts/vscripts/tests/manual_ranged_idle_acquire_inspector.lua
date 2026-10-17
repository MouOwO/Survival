-- Inert, explicit Tools-only API/proof inspection. No setter, attack order,
-- timer, subscription, modifier mutation or v3 observation is performed here.
-- A boolean ShouldIdleAcquire result is NOT proof of a stored-flag contract.
local M = {}
local function method(object, name)
    if not object then return nil end
    local ok, value = pcall(function() return object[name] end)
    return ok and type(value) == "function" and value or nil
end
local function read(object, name, ...)
    local fn = method(object, name)
    if not fn then return nil, "unavailable" end
    local ok, value = pcall(fn, object, ...)
    if not ok then return nil, "read_failed" end
    return value
end
local function valid(unit) return read(unit, "IsNull") == false end
local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge and value or nil
end
local function same_position(saved, unit)
    local p = read(unit, "GetAbsOrigin")
    local ok, same = pcall(function()
        return saved and p and finite(p.x) and finite(p.y) and finite(p.z)
            and saved.x == p.x and saved.y == p.y and saved.z == p.z or false
    end)
    return ok and same == true
end
local function authorized()
    if not IsServer or not IsServer() or not IsInToolsMode or not IsInToolsMode()
        or not GetMapName or GetMapName() ~= "template_map" then return false end
    local world = read(GameRules, "GetGameModeEntity")
    local guard = _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION
    return world ~= nil and guard and guard.mode == world or false
end
function M.inspect(owner, parent, wall)
    local result = { schema = "ranged_idle_acquire_readonly_inspector_v1",
        authorized = authorized(), native_state_mutations = false,
        attack_orders_issued = 0, timers_or_event_hooks_installed = false,
        stored_original_value_contract_verified = false,
        mutation_admission_granted = false, proof = {}, api = {} }
    if not result.authorized then result.reason = "tools_world_guard_required"; return result end
    if not valid(parent) or parent.survival_is_wave_monster ~= true
        or parent.survival_wave_movement_type ~= "ground"
        or read(parent, "GetClassname") ~= "npc_dota_creature"
        or read(parent, "GetTeamNumber") ~= DOTA_TEAM_BADGUYS
        or read(parent, "GetAttackCapability") ~= DOTA_UNIT_CAP_RANGED_ATTACK
        or not owner or read(owner, "GetParent") ~= parent then
        result.reason = "not_formal_owned_ground_ranged"; return result
    end
    result.unit_index = read(parent, "entindex")
    result.api.should_idle_acquire_function = method(parent, "ShouldIdleAcquire") ~= nil
    result.api.get_idle_acquire_function = method(parent, "GetIdleAcquire") ~= nil
    result.api.set_idle_acquire_function = method(parent, "SetIdleAcquire") ~= nil
    local idle, idle_error = read(parent, "ShouldIdleAcquire")
    result.api.should_idle_acquire_boolean_readable = type(idle) == "boolean"
    if type(idle) == "boolean" then result.api.observed_idle_boolean = idle
    else result.api.read_failure = idle_error or "non_boolean_result" end
    -- No false/nil coercion and no invented default restoration value.
    result.api.getter_semantics = "boolean_observation_only_stored_flag_vs_effective_policy_unverified"
    local hold = owner.ranged_stationary_hold
    local evidence = owner.ranged_stationary_evidence
    local sample = hold and hold.sample
    result.proof.v3_own_hold = hold ~= nil and owner.contact_mode == 6
    result.proof.native_fired_landed_record = sample ~= nil
        and sample.pair_source == "native_fired_record" and sample.proof_has_record == true
        and evidence ~= nil and evidence.has_record == true
    result.proof.wall_identity = valid(wall) and read(wall, "IsAlive") == true
        and read(wall, "entindex") == owner.wall_entindex
        and owner.goal_wall == wall and evidence ~= nil and evidence.wall == wall
    local native_target, native_target_error = read(parent, "GetAttackTarget")
    result.proof.native_attack_target_is_wall = valid(wall) and native_target == wall
    result.proof.native_attack_target_nil = native_target == nil and native_target_error == nil
    result.proof.native_attack_target_read_error = native_target_error
    result.proof.native_force_target_is_wall = valid(wall) and read(parent, "GetForceAttackTarget") == wall
    result.proof.chase_state = owner.ai_state == "chase"
    result.proof.geometry_matches = hold ~= nil and evidence ~= nil
        and same_position(hold.position, parent) and same_position(hold.wall_position, wall)
        and same_position(evidence.position, parent) and same_position(evidence.wall_position, wall)
        and hold.range == finite(read(parent, "Script_GetAttackRange"))
        and hold.parent_hull == finite(read(parent, "GetHullRadius"))
        and hold.wall_hull == finite(read(wall, "GetHullRadius")) or false
    result.proof.external_control_verification = "not_rechecked; mutation phase must reuse current v3 legal/release checks"
    result.proof.attack_cadence_verification = "not_measured; mutation phase requires native held Fired/Landed continuity"
    result.readonly_reversibility_test_prerequisites = result.api.should_idle_acquire_boolean_readable
        and result.api.set_idle_acquire_function and result.proof.v3_own_hold
        and result.proof.native_fired_landed_record and result.proof.wall_identity
        and result.proof.native_attack_target_is_wall and result.proof.native_force_target_is_wall
        and result.proof.chase_state and result.proof.geometry_matches or false
    result.reason = result.readonly_reversibility_test_prerequisites
        and "ready_for_separately_authorized_native_boolean_contract_check"
        or "api_or_stationary_native_proof_incomplete"
    return result
end
return M
