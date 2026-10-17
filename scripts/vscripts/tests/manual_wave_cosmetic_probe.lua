-- Inert, default-OFF Tools visual candidate. New formal NORMAL wave spawns by
-- default. apply_existing() is a separate explicit, audited native scan.
-- Ambient-only retires owned cosmetic handles via the existing visual module;
-- it never changes body/parts, gameplay, or attack/projectile/impact particles.
-- stop() removes our hook; fresh map is required to restore changed NPCs.
-- Low-model selection is an independent option, blocked pending native proof.
local M = {}
local KEY = 'SURVIVAL_WAVE_COSMETIC_PROBE'
local SAMPLE_LIMIT = 32
local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}; for key, child in pairs(value) do result[key] = copy(child) end
    return result
end
local function tools()
    assert(IsServer and IsServer() and IsInToolsMode and IsInToolsMode(), 'Tools server only')
    assert(GetMapName and GetMapName() == 'template_map', 'template_map only')
end
local function current(s)
    local setup = require('systems/match_setup_service')
    return _G[KEY] == s and s.mode == GameRules:GetGameModeEntity()
        and s.guard == _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION and s.guard.mode == s.mode
        and s.fixture == _G.SURVIVAL_FOUR_PLAYER_LIVE_PERF and s.fixture.mode == s.mode
        and s.fixture.guard == s.guard and s.fixture.status == 'ready'
        and s.bus == require('core/event_bus') and s.bus_generation == s.bus.get_generation()
        and setup.get_mode() == s.match_mode and setup.get_session_id() == s.session
end
local function stop_state(s, reason)
    if s.subscription then s.bus.unsubscribe(s.subscription); s.subscription = nil end
    s.enabled = false; s.stop_reason = reason or 'explicit_stop'
end
local function count_reason(s, kind, why)
    s[kind] = s[kind] + 1
    local reasons = s[kind .. '_reasons']; reasons[why] = (reasons[why] or 0) + 1
end
local function eligible(s, unit, payload)
    if not unit or unit:IsNull() or not unit:IsAlive() then return false, 'invalid_or_dead_unit' end
    if payload.monster_source ~= 'wave' or unit.survival_is_wave_monster ~= true then return false, 'not_formal_wave' end
    if payload.member_role ~= 'normal' or unit.survival_monster_role ~= 'normal'
        or payload.is_boss == true or unit.survival_is_boss == true then return false, 'not_ordinary_wave' end
    if unit:GetTeamNumber() ~= DOTA_TEAM_BADGUYS then return false, 'not_enemy_team' end
    if unit:GetClassname() ~= 'npc_dota_creature' or unit:IsRealHero()
        or (unit.IsHero and unit:IsHero()) or (unit.IsIllusion and unit:IsIllusion())
        or (unit.IsClone and unit:IsClone()) then return false, 'hero_clone_or_noncreature' end
    if unit.survival_hero_id ~= nil or unit.survival_training_id ~= nil
        or unit.survival_is_challenge_monster == true or unit.survival_visual_only == true
        or unit.survival_is_summon == true or unit.survival_permanent_summon == true
        or unit.survival_exclusive_summon == true or unit.survival_summon_skill_id ~= nil
        or unit.survival_monkey_king_clone == true or unit.survival_blademaster_clone == true
        or unit.survival_drow_companion == true then return false, 'excluded_gameplay_role' end
    local id = payload.player_id
    if type(id) ~= 'number' or id ~= math.floor(id) or id < 0 or id > 3
        or unit.survival_player_id ~= id then return false, 'formal_owner_mismatch' end
    local listed = false; for _, owner in ipairs(s.fixture.ids or {}) do if owner == id then listed = true end end
    local context = require('systems/player_context_service')
    if not listed or context.owner_player_id(unit, true) ~= id or context.is_defeated(id) then
        return false, 'context_owner_or_defeat_mismatch'
    end
    local native = unit:GetPlayerOwnerID()
    if native ~= -1 and native ~= id then return false, 'native_owner_mismatch' end
    local ai = unit:FindModifierByName('modifier_enemy_wall_ai')
    if not ai or ai:IsNull() or ai:GetParent() ~= unit or ai.wall_target_player_id ~= id then
        return false, 'authoritative_ai_owner_mismatch'
    end
    return true
end
local function particle_count(unit)
    local state = unit.survival_monster_cosmetic_details
    if type(state) ~= 'table' or type(state.asset) ~= 'table' or type(state.particles) ~= 'table' then
        return nil, 'no_readable_owned_cosmetic_state'
    end
    local count = 0
    for index, particle in pairs(state.particles) do
        if type(index) ~= 'number' or index < 1 or index ~= math.floor(index)
            or type(particle) ~= 'number' or particle ~= particle or math.abs(particle) == math.huge
            or particle < 0 or particle ~= math.floor(particle) then
            return nil, 'owned_particle_list_invalid'
        end
        count = count + 1
    end
    if count ~= #state.particles then return nil, 'owned_particle_list_not_dense' end
    return count, nil, state
end
-- Shared read-only eligibility policy for independent Tools visual candidates.
-- Requires the current isolated fixture but never enables/scans/retires ambient.
function M.check_ordinary_wave_unit(unit, payload)
    tools()
    local mode = GameRules:GetGameModeEntity()
    local guard, fixture = _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION, _G.SURVIVAL_FOUR_PLAYER_LIVE_PERF
    if not guard or guard.mode ~= mode or not fixture or fixture.mode ~= mode
        or fixture.guard ~= guard or fixture.status ~= 'ready' then return false, 'current_isolated_fixture_required' end
    local ok, allowed, reason = pcall(eligible, {fixture = fixture}, unit, payload or {})
    if not ok then return false, 'eligibility_read_failed' end
    return allowed, reason
end
local function on_spawn(s, payload, origin)
    if not s.enabled then return end
    local read_ok, matches = pcall(current, s)
    if not read_ok or not matches then stop_state(s, 'world_guard_fixture_or_bus_changed'); return end
    if origin == 'existing_scan' then s.existing_notifications = s.existing_notifications + 1
    else s.events = s.events + 1 end
    payload = payload or {}
    local unit = payload.unit
    local ok, allowed, why = pcall(eligible, s, unit, payload)
    if not ok then count_reason(s, 'failed', 'eligibility_read_failed'); return end
    if not allowed then count_reason(s, 'skipped', why); return end
    if s.seen[unit] then count_reason(s, 'skipped', 'duplicate_spawn_notification'); return end
    s.seen[unit] = true
    local before, reason, state = particle_count(unit)
    if before == nil then count_reason(s, 'skipped', reason); return end
    local sample = {entindex = unit:entindex(), player_id = payload.player_id, unit_name = unit:GetUnitName(),
        game_time = GameRules:GetGameTime(), observation_source = origin or 'new_spawn',
        owned_ambient_handles_before = before, stop_particles_calls = 0}
    if before == 0 then
        sample.owned_ambient_handles_after = 0; sample.owned_handles_retired = 0; sample.success = true
        s.processed = s.processed + 1; s.zero_particle_units = s.zero_particle_units + 1
    else
        s.stop_particles_calls = s.stop_particles_calls + 1; sample.stop_particles_calls = 1
        local stopped = pcall(s.details.stop_particles, unit)
        local after = particle_count(unit)
        sample.owned_ambient_handles_after = after
        sample.success = stopped and after == 0 and unit.survival_monster_cosmetic_details == state
        -- Production helper protects individual native calls. Empty owned lists
        -- prove retirement bookkeeping, not a GPU/native destroy-success result.
        if sample.success then
            sample.owned_handles_retired = before
            s.processed = s.processed + 1; s.modified_units = s.modified_units + 1
            s.owned_handles_retired = s.owned_handles_retired + before
            s.owners[payload.player_id + 1].modified_units = s.owners[payload.player_id + 1].modified_units + 1
            s.owners[payload.player_id + 1].owned_handles_retired = s.owners[payload.player_id + 1].owned_handles_retired + before
        else
            sample.failure = stopped and 'cosmetic_retirement_not_confirmed' or 'cosmetic_stop_failed'
            count_reason(s, 'failed', sample.failure)
        end
    end
    if #s.samples < SAMPLE_LIMIT then s.samples[#s.samples + 1] = sample end
end
function M.low_model_plan()
    local visuals = require('config/monster_visual_config')
    local result = {implemented = false, native_resource_animation_verified = false,
        error = 'low_model_native_validation_required', candidates = {},
        exclusions = 'leader/boss/player_hero/clone/summon/challenge',
        gameplay_mutation_allowed = false, blind_model_swap_allowed = false}
    for _, id in ipairs({'vis_ogre_frostmage', 'vis_kobold_pack', 'vis_centaur_courser'}) do
        local asset = visuals.asset(id)
        if asset and asset.assembly_mode == 'direct_model' then
            result.candidates[#result.candidates + 1] = {visual_asset_id = id, model_path = asset.model_path,
                async_unit_name = asset.async_unit_name, configured_self_contained = true,
                configured_source_evidence = asset.verified_source, native_spawn_attack_run_death_verified = false}
        end
    end
    result.required_checks = {'exact resource ready before fresh spawn', 'attack/run/idle/death native animations',
        'projectile/hit attachment compatibility', 'same stats/range/BAT/hull/AI/owner',
        'part/corpse cleanup with no player hero effects', 'mesh/LOD and matched native frametime benefit'}
    return result
end
function M.enable(options)
    options = options or {}
    for _, key in ipairs({'enabled', 'ambient_only', 'low_model'}) do
        assert(options[key] == nil or type(options[key]) == 'boolean', key .. ' must be boolean')
    end
    if options.enabled ~= true or (options.ambient_only ~= true and options.low_model ~= true) then
        return {ok = true, request_disabled = true, default_enabled = false, request_had_no_side_effects = true,
            existing_probe_enabled = _G[KEY] and _G[KEY].enabled == true or false}
    end
    tools()
    if options.low_model == true then
        return {ok = false, error = 'low_model_native_validation_required', request_had_no_side_effects = true,
            existing_probe_enabled = _G[KEY] and _G[KEY].enabled == true or false, low_model_plan = M.low_model_plan()}
    end
    local previous = _G[KEY]
    if previous and previous.enabled then
        assert(current(previous), 'Stop the old candidate before enabling another world')
        return M.snapshot({quiet = true})
    end
    local mode = GameRules:GetGameModeEntity(); local guard = _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION
    local fixture = _G.SURVIVAL_FOUR_PLAYER_LIVE_PERF; local bus = require('core/event_bus')
    assert(guard and guard.mode == mode and fixture and fixture.mode == mode and fixture.guard == guard
        and fixture.status == 'ready', 'Current ready four-owner fixture and write isolation required')
    assert(type(fixture.ids) == 'table' and #fixture.ids == 4, 'Four fixture owner IDs required')
    local owner_set = {}; for _, id in ipairs(fixture.ids) do owner_set[id] = true end
    for id = 0, 3 do assert(owner_set[id], 'Fixture owner set must equal 0..3') end
    local setup = require('systems/match_setup_service')
    local s = {enabled = true, mode = mode, guard = guard, fixture = fixture, bus = bus,
        bus_generation = bus.get_generation(), match_mode = setup.get_mode(), session = setup.get_session_id(),
        ambient_only = true, low_model = false, details = require('visual/monster_cosmetic_details'),
        events = 0, existing_notifications = 0, existing_scan_calls = 0,
        processed = 0, modified_units = 0, owned_handles_retired = 0, stop_particles_calls = 0,
        zero_particle_units = 0, skipped = 0, failed = 0, skipped_reasons = {}, failed_reasons = {},
        samples = {}, seen = setmetatable({}, {__mode = 'k'}), owners = {}}
    for id = 0, 3 do s.owners[id + 1] = {player_id = id, modified_units = 0, owned_handles_retired = 0} end
    _G[KEY] = s
    s.subscription = bus.subscribe(require('core/events').MONSTER_SPAWNED, function(payload) on_spawn(s, payload) end)
    return M.snapshot({quiet = true})
end
function M.apply_existing(options)
    tools(); options = options or {}; local s = _G[KEY]
    if not s or not s.enabled then return {ok = false, error = 'probe_not_enabled', scan_attempted = false} end
    local scope_ok, matches = pcall(current, s)
    if not scope_ok or not matches then
        stop_state(s, 'existing_scan_scope_changed')
        return {ok = false, error = 'world_guard_fixture_or_bus_changed', scan_attempted = false}
    end
    -- No default scan and no GetAllEntities fallback: the exact class API must
    -- return a dense complete collection before any owned particle is retired.
    if not Entities or type(Entities.FindAllByClassname) ~= 'function' then
        return {ok = false, error = 'native_class_collection_unavailable', scan_attempted = false}
    end
    s.existing_scan_calls = s.existing_scan_calls + 1
    local found_ok, units = pcall(Entities.FindAllByClassname, Entities, 'npc_dota_creature')
    local report = {ok = false, scan_attempted = true, scan_number = s.existing_scan_calls,
        collection_api = 'Entities.FindAllByClassname(npc_dota_creature)', scan_complete = false,
        processing_complete = false, eligibility_reads_complete = false,
        collected = 0, examined = 0, eligible_before = 0, eligible_after = 0,
        unseen_eligible_before = 0, duplicate_eligible_before = 0, eligibility_read_errors = 0,
        owned_handles_before = 0, owned_handles_after = 0,
        owned_handles_before_complete = true, owned_handles_after_complete = true,
        only_ordinary_formal_waves = true, spawned_units = 0, other_gameplay_mutations = false}
    if not found_ok or type(units) ~= 'table' then
        report.error = 'native_class_collection_failed'; s.last_existing_scan = copy(report); return report
    end
    for index in pairs(units) do
        if type(index) ~= 'number' or index < 1 or index ~= math.floor(index) then
            report.error = 'native_class_collection_not_dense'; s.last_existing_scan = copy(report); return report
        end
        report.collected = report.collected + 1
    end
    if report.collected ~= #units then
        report.error = 'native_class_collection_not_dense'; s.last_existing_scan = copy(report); return report
    end
    report.scan_complete = true
    local initial = {processed = s.processed, modified = s.modified_units, retired = s.owned_handles_retired,
        skipped = s.skipped, failed = s.failed, calls = s.stop_particles_calls}
    for _, unit in ipairs(units) do
        local world_ok, still_current = pcall(current, s)
        if not world_ok or not still_current or not s.enabled then
            report.error = 'existing_scan_scope_changed'; stop_state(s, report.error); break
        end
        report.examined = report.examined + 1
        local payload_ok, payload = pcall(function()
            return {unit = unit, monster_source = unit.survival_is_wave_monster == true and 'wave' or 'non_wave',
                member_role = unit.survival_monster_role, player_id = unit.survival_player_id,
                is_boss = unit.survival_is_boss == true}
        end)
        if not payload_ok then
            report.eligibility_read_errors = report.eligibility_read_errors + 1
        else
            local read_ok, allowed = pcall(eligible, s, unit, payload)
            if not read_ok then report.eligibility_read_errors = report.eligibility_read_errors + 1 end
            if read_ok and allowed then
                report.eligible_before = report.eligible_before + 1
                if s.seen[unit] then report.duplicate_eligible_before = report.duplicate_eligible_before + 1
                else report.unseen_eligible_before = report.unseen_eligible_before + 1 end
                local before = particle_count(unit)
                if before == nil then report.owned_handles_before_complete = false
                else report.owned_handles_before = report.owned_handles_before + before end
            end
            -- Same guarded eligibility/seen/retirement path as actual spawn;
            -- do not broadcast a fake MONSTER_SPAWNED event to production.
            on_spawn(s, payload, 'existing_scan')
            local after_ok, after_allowed = pcall(eligible, s, unit, payload)
            if not after_ok then report.eligibility_read_errors = report.eligibility_read_errors + 1 end
            if after_ok and after_allowed then
                report.eligible_after = report.eligible_after + 1
                local after = particle_count(unit)
                if after == nil then report.owned_handles_after_complete = false
                else report.owned_handles_after = report.owned_handles_after + after end
            end
        end
    end
    report.processing_complete = report.examined == report.collected and report.error == nil
    report.eligibility_reads_complete = report.eligibility_read_errors == 0
    report.processed_delta = s.processed - initial.processed
    report.modified_units_delta = s.modified_units - initial.modified
    report.owned_handles_retired_delta = s.owned_handles_retired - initial.retired
    report.stop_particles_calls_delta = s.stop_particles_calls - initial.calls
    report.skipped_delta = s.skipped - initial.skipped; report.failed_delta = s.failed - initial.failed
    report.native_particle_removal_success_asserted = false
    report.ok = report.scan_complete and report.processing_complete and report.eligibility_reads_complete
        and report.failed_delta == 0
    s.last_existing_scan = copy(report) -- Numbers/strings only; no NPC retention.
    if options.quiet ~= true then
        print(string.format('[WAVE_COSMETIC_EXISTING] complete=%s collected=%d examined=%d eligible=%d/%d modified=%d retired_handles=%d duplicates=%d native_render_proof=0',
            tostring(report.ok), report.collected, report.examined, report.eligible_before, report.eligible_after,
            report.modified_units_delta, report.owned_handles_retired_delta, report.duplicate_eligible_before))
    end
    return report
end
function M.stop(reason)
    tools(); local s = _G[KEY]; if not s then return false end
    stop_state(s, reason); return true
end
function M.snapshot(options)
    tools(); options = options or {}; local s = _G[KEY]
    if not s then return {ok = true, enabled = false, default_enabled = false, ambient_only = false,
        low_model = false, experimental_not_production = true, modified_units = 0, owned_handles_retired = 0} end
    local ok, matches = pcall(current, s)
    local result = {ok = true, enabled = s.enabled and ok and matches or false,
        current_fixture_and_guard = ok and matches or false, default_enabled = false,
        experimental_not_production = true, ambient_only = s.ambient_only, low_model = s.low_model,
        events = s.events, existing_notifications = s.existing_notifications, existing_scan_calls = s.existing_scan_calls,
        last_existing_scan = copy(s.last_existing_scan), processed = s.processed, modified_units = s.modified_units,
        owned_handles_retired = s.owned_handles_retired, stop_particles_calls = s.stop_particles_calls,
        zero_particle_units = s.zero_particle_units, skipped = s.skipped, failed = s.failed,
        skipped_reasons = copy(s.skipped_reasons), failed_reasons = copy(s.failed_reasons),
        owners = copy(s.owners), samples = copy(s.samples), sample_limit = SAMPLE_LIMIT,
        sample_policy = 'first_32_eligible_new_or_explicit_existing_retirement_observations', stop_reason = s.stop_reason,
        default_only_new_spawn_notifications_no_scan = true, explicit_existing_scan_available = true,
        seen_unit_keys_are_weak = true, stop_restores_particles_or_models = false,
        requires_map_reload_to_restore_modified_units = s.stop_particles_calls > 0,
        native_particle_removal_success_asserted = false, retired_handles_are_native_attempts_not_render_proof = true,
        body_parts_animation_gameplay_attack_and_impact_changed = false,
        scope = 'formal_ordinary_wave_owned_cosmetic_ambient_only'}
    if options.quiet ~= true then
        print(string.format('[WAVE_COSMETIC_PROBE] enabled=%s ambient_only=%s low_model=%s events=%d processed=%d modified=%d retired_handles=%d skipped=%d failed=%d reload_required=%s native_render_proof=0',
            tostring(result.enabled), tostring(result.ambient_only), tostring(result.low_model), result.events,
            result.processed, result.modified_units, result.owned_handles_retired, result.skipped, result.failed,
            tostring(result.requires_map_reload_to_restore_modified_units)))
    end
    return result
end
return M
