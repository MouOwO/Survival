-- Default-off Tools candidate, never called by production. First preview the
-- exact self-contained model, then explicitly attest that preview before use.
-- Only appearance changes; failed combat invariants abort the candidate.
local M = {}
local KEY = 'SURVIVAL_WAVE_LOW_MODEL_PROBE'
local MODEL_ID = 'vis_ogre_frostmage'
local SCALE = 0.88
local function copy(t)
    if type(t) ~= 'table' then return t end
    local r = {}; for k, v in pairs(t) do r[k] = copy(v) end; return r
end
local function tools()
    assert(IsServer and IsServer() and IsInToolsMode and IsInToolsMode(), 'Tools server only')
    assert(GetMapName() == 'template_map', 'template_map only')
end
local function valid(u) return u and not u:IsNull() end
local function current(s)
    local setup = require('systems/match_setup_service')
    return _G[KEY] == s and not s.stopped and s.mode == GameRules:GetGameModeEntity()
        and s.guard == _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION and s.guard.mode == s.mode
        and s.fixture == _G.SURVIVAL_FOUR_PLAYER_LIVE_PERF and s.fixture.guard == s.guard
        and s.fixture.mode == s.mode and s.fixture.status == 'ready'
        and s.bus == require('core/event_bus') and s.generation == s.bus.get_generation()
        and setup.get_mode() == s.match_mode and setup.get_session_id() == s.session
end
local function scope_current(s)
    local ok, matches = pcall(current, s); return ok and matches == true
end
local function resource_ready(s)
    return require('systems/asset_preload_service').resource_status('model', s.visual.model_path) == 'ready'
end
local function state_required()
    tools(); local s = assert(_G[KEY], 'Request preview first')
    assert(scope_current(s), 'Current isolated four-owner world required'); return s
end
local function remove_demo(s)
    local u = s.demo
    if not u then return false end
    if valid(u) and u.survival_wave_low_model_demo_token == s.demo_token
        and u.survival_visual_only == true and u:entindex() == s.demo_entindex then
        require('visual/endless_monster_visual_service').clear(u)
        UTIL_Remove(u); s.demo_removed = true; s.demo = nil; return true
    end
    s.demo_removal_refused = true; return false
end
local function disable(s, reason)
    if s.subscription then s.bus.unsubscribe(s.subscription); s.subscription = nil end
    s.enabled = false; s.stop_reason = reason or 'explicit_stop'
end
local REQUIRED = {health = 'GetHealth', max_health = 'GetMaxHealth',
    move_speed = 'GetBaseMoveSpeed', hull_radius = 'GetHullRadius', attack_capability = 'GetAttackCapability'}
local CADENCE = {BAT = 'GetBaseAttackTime', native_attack_speed = 'GetAttackSpeed',
    seconds_per_attack = 'GetSecondsPerAttack', attacks_per_second = 'GetAttacksPerSecond',
    attack_animation_point = 'GetAttackAnimationPoint', acquisition_range = 'GetAcquisitionRange'}
local function read_false_argument(u, getter)
    if type(u[getter]) ~= 'function' then return nil, 'required_combat_getter_missing:' .. getter end
    -- This engine build requires a bool for BAT/AS/SPA/APS. Only the precise
    -- old one-receiver arity failure allows no-argument compatibility.
    local ok, value = pcall(u[getter], u, false)
    local signature = 'explicit_false'
    if not ok and type(value) == 'string'
        and value:find(getter .. ' called with 2 arguments - expected 1', 1, true) then
        ok, value = pcall(u[getter], u); signature = 'legacy_noarg_after_arity'
    end
    if not ok or type(value) ~= 'number' or value ~= value or math.abs(value) == math.huge then
        return nil, 'required_combat_getter_failed:' .. getter
    end
    return value, nil, signature
end
local function combat_snapshot(u)
    local r = {handle = u, entindex = u:entindex(), unit_name = u:GetUnitName(),
        ai = u:FindModifierByName('modifier_enemy_wall_ai'), native_attack_cap = u.survival_wave_native_attack_cap,
        attack_speed = u.survival_attack_speed, player_id = u.survival_player_id}
    for key, getter in pairs(REQUIRED) do
        if type(u[getter]) ~= 'function' then return nil, 'required_combat_getter_missing:' .. getter end
        local ok, value = pcall(u[getter], u)
        if not ok or type(value) ~= 'number' or value ~= value or math.abs(value) == math.huge then
            return nil, 'required_combat_getter_failed:' .. getter
        end
        r[key] = value
    end
    for key, getter in pairs(CADENCE) do
        local value, error, signature = read_false_argument(u, getter)
        if value == nil then return nil, error end
        if (key == 'attack_animation_point' or key == 'acquisition_range') and value < 0
            or (key ~= 'attack_animation_point' and key ~= 'acquisition_range' and value <= 0) then
            return nil, 'required_combat_getter_failed:' .. getter
        end
        r[key] = value; r[key .. '_signature'] = signature
    end
    if math.abs(r.seconds_per_attack * r.attacks_per_second - 1) > 0.0001 then
        return nil, 'native_cadence_reciprocity_failed'
    end
    r.native_base_BAT_read = true -- Numeric actual getter; never inferred/config fallback.
    if type(u.GetAttackTarget) == 'function' then
        local ok, target = pcall(u.GetAttackTarget, u)
        if not ok then return nil, 'attack_target_getter_failed' end
        r.target_known = true; r.target = target
    end
    if u.FindModifierByName then r.attack_cap_modifier = u:FindModifierByName('modifier_debug_attack_cap') end
    if not r.ai then return nil, 'wall_ai_missing' end
    r.ai_state = r.ai.ai_state; r.wall_entindex = r.ai.wall_entindex
    r.wall_target_player_id = r.ai.wall_target_player_id
    return r
end
local function same_combat(a, b)
    for key, value in pairs(a) do if b[key] ~= value then return false, key end end
    for key, value in pairs(b) do if a[key] ~= value then return false, key end end
    return true
end
local function change(s, u, payload, origin)
    if not s.enabled then return false, 'candidate_disabled' end
    if not scope_current(s) then disable(s, 'world_or_guard_changed'); return false, s.stop_reason end
    local shared = require('tests/manual_wave_cosmetic_probe')
    if type(shared.check_ordinary_wave_unit) ~= 'function' then
        s.failed = s.failed + 1; disable(s, 'reload_shared_readonly_eligibility_required'); return false, s.stop_reason
    end
    local allowed, why = shared.check_ordinary_wave_unit(u, payload)
    if not allowed then s.skipped = s.skipped + 1; return false, why end
    if s.seen[u] then s.duplicates = s.duplicates + 1; return false, 'duplicate_unit' end
    if not resource_ready(s) then disable(s, 'resource_no_longer_ready'); return false, s.stop_reason end
    local before, read_error = combat_snapshot(u)
    if not before then s.failed = s.failed + 1; disable(s, read_error); return false, read_error end
    s.seen[u] = true -- Pre-read refusal must not poison a future validated retry.
    local previous_model = u:GetModelName()
    local previous_parts = require('visual/model_appearance_service')._count_for_test(u)
    local ok, applied, reason = pcall(require('visual/endless_monster_visual_service').apply, u, s.visual)
    local after, after_error = combat_snapshot(u)
    local unchanged, field = false, after_error
    if after then unchanged, field = same_combat(before, after) end
    local verified_model = u:GetModelName() == s.visual.model_path
    local parts_after = require('visual/model_appearance_service')._count_for_test(u)
    local success = ok and applied == true and unchanged and verified_model and parts_after == 0
    local sample = {entindex = before.entindex, player_id = before.player_id, origin = origin,
        previous_model = previous_model, model_after = u:GetModelName(), previous_owned_parts = previous_parts,
        owned_parts_after = parts_after, invariant_checked = unchanged, changed_combat_field = field,
        success = success, native_triangle_or_lod_measurement = false, native_base_BAT_read = before.native_base_BAT_read,
        BAT_before = before.BAT, BAT_after = after and after.BAT,
        seconds_per_attack_before = before.seconds_per_attack, seconds_per_attack_after = after and after.seconds_per_attack,
        attacks_per_second_before = before.attacks_per_second, attacks_per_second_after = after and after.attacks_per_second,
        native_attack_speed_before = before.native_attack_speed, native_attack_speed_after = after and after.native_attack_speed,
        attack_animation_point_before = before.attack_animation_point, attack_animation_point_after = after and after.attack_animation_point,
        acquisition_range_before = before.acquisition_range, acquisition_range_after = after and after.acquisition_range}
    s.visual_write_attempts = s.visual_write_attempts + 1
    if success then
        s.modified = s.modified + 1; s.retired_parts = s.retired_parts + previous_parts
    else
        s.failed = s.failed + 1; sample.failure = not ok and 'visual_apply_exception'
            or (applied ~= true and 'visual_apply_failed' or 'visual_or_combat_invariant_failed')
        -- No fake SetHealth/BAT/hull rollback or destructive source-unit removal.
        disable(s, sample.failure)
    end
    if #s.samples < 32 then s.samples[#s.samples + 1] = sample end
    if success then return true end
    return false, sample.failure or reason
end
local function create_demo(s)
    if not scope_current(s) or s.preview_status ~= 'loading' or not resource_ready(s) then return end
    s.preview_status = 'creating'
    local ok, u = pcall(CreateUnitByName, 'npc_survival_wave_named_dwarf_white_rifle',
        Vector(s.position.x, s.position.y, s.position.z), false, nil, nil, DOTA_TEAM_NEUTRALS)
    if not ok or not valid(u) then s.preview_status = 'failed'; s.error = 'demo_create_failed'; return end
    s.demo = u; s.demo_entindex = u:entindex(); s.demo_token = {}
    u.survival_wave_low_model_demo_token = s.demo_token; u.survival_visual_only = true
    u.survival_is_visual_carrier = true
    local applied_ok, applied = pcall(function()
        u:RemoveModifierByName('modifier_single_health_bar')
        u:AddNewModifier(u, nil, 'modifier_invulnerable', {})
        u:SetBaseDamageMin(0); u:SetBaseDamageMax(0)
        u:SetBaseMoveSpeed(270); u:SetIdleAcquire(false); u:SetAcquisitionRange(0)
        return require('visual/endless_monster_visual_service').apply(u, s.visual)
    end)
    if not applied_ok or applied ~= true or u:GetModelName() ~= s.visual.model_path then
        s.preview_status = 'failed'; s.error = 'demo_visual_readback_failed'; remove_demo(s); return
    end
    s.preview_status = 'ready'; s.model_readback_confirmed = true
end
function M.preview(options)
    options = options or {}; if options.enabled ~= true then return {enabled = false, default_off = true} end
    tools()
    assert(not _G[KEY] or not _G[KEY].enabled, 'Stop prior candidate first')
    assert(not _G[KEY] or not valid(_G[KEY].demo), 'Remove prior owned demo first')
    local position = assert(options.position, 'Explicit preview position required')
    for _, key in ipairs({'x', 'y', 'z'}) do
        assert(type(position[key]) == 'number' and position[key] == position[key]
            and math.abs(position[key]) < 20000, 'Finite bounded preview coordinate required')
    end
    local mode, guard, fixture = GameRules:GetGameModeEntity(), _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION, _G.SURVIVAL_FOUR_PLAYER_LIVE_PERF
    assert(guard and guard.mode == mode and fixture and fixture.mode == mode and fixture.guard == guard
        and fixture.status == 'ready', 'Current isolated ready fixture required')
    local a = assert(require('config/monster_visual_config').asset(MODEL_ID), 'Configured visual asset missing')
    assert(a.assembly_mode == 'direct_model' and a.async_unit_name and a.model_path, 'Self-contained proxy declaration required')
    local setup, bus = require('systems/match_setup_service'), require('core/event_bus')
    local s = {mode = mode, guard = guard, fixture = fixture, bus = bus, generation = bus.get_generation(),
        match_mode = setup.get_mode(), session = setup.get_session_id(), preview_status = 'loading',
        enabled = false, validated = false, position = copy(position), modified = 0, failed = 0, skipped = 0,
        duplicates = 0, retired_parts = 0, visual_write_attempts = 0, samples = {},
        seen = setmetatable({}, {__mode = 'k'}), request_started = GameRules:GetGameTime(),
        visual = {visual_id = 'tools_wave_self_contained_frostmage', model_path = a.model_path, model_scale = SCALE,
            components = {}, effects = {}, ornaments = {}, activity_modifiers = {}, model_skin = 0}, proxy = a.async_unit_name}
    _G[KEY] = s
    local preload = require('systems/asset_preload_service')
    local queued = preload.queue_resources({{resource_type = 'model', path = a.model_path, async_unit_name = a.async_unit_name}}, {urgent = true})
    if not queued then s.preview_status = 'failed'; s.error = 'exact_proxy_preload_failed'; return M.snapshot() end
    local scheduler = require('core/scheduler'); s.task_id = 'wave_low_model_preview_ready'
    local function check()
        if not scope_current(s) or s.preview_status ~= 'loading' then return end
        if resource_ready(s) then create_demo(s); return end
        if GameRules:GetGameTime() - s.request_started > 30 then s.preview_status = 'failed'; s.error = 'proxy_ready_timeout'; return end
        scheduler.after(0.1, check, s.task_id)
    end
    check(); return M.snapshot()
end
function M.demo_walk(position)
    local s = state_required(); assert(s.preview_status == 'ready' and valid(s.demo), 'Ready demo required')
    for _, key in ipairs({'x', 'y', 'z'}) do assert(type(position[key]) == 'number' and math.abs(position[key]) < 20000, 'Finite coordinate required') end
    ExecuteOrderFromTable({UnitIndex = s.demo_entindex, OrderType = DOTA_UNIT_ORDER_MOVE_TO_POSITION,
        Position = Vector(position.x, position.y, position.z), Queue = false})
    return {command_issued = true, native_completion_asserted = false, demo_entindex = s.demo_entindex}
end
function M.demo_attack_gesture()
    local s = state_required(); assert(s.preview_status == 'ready' and valid(s.demo), 'Ready demo required')
    s.demo:StartGestureWithPlaybackRate(ACT_DOTA_ATTACK, 1)
    return {gesture_issued = true, native_hit_or_damage_asserted = false, demo_entindex = s.demo_entindex}
end
function M.validate_preview(options)
    local s = state_required(); options = options or {}
    assert(options.approved == true and options.demo_entindex == s.demo_entindex and s.preview_status == 'ready'
        and valid(s.demo) and s.demo.survival_wave_low_model_demo_token == s.demo_token
        and s.demo:GetModelName() == s.visual.model_path and resource_ready(s), 'Explicit approval of this exact ready preview required')
    assert(options.walk_seen == true and options.attack_gesture_seen == true, 'Native walk and attack animation observation required')
    s.validated = true; s.validation_is_caller_native_observation_attestation = true; return M.snapshot()
end
function M.enable(options)
    options = options or {}; if options.enabled ~= true then return {enabled = false, default_off = true} end
    local s = state_required()
    assert(options.validated_preview == true and s.validated and resource_ready(s), 'Explicit validated preview required before candidate')
    if not s.enabled then
        s.enabled = true
        s.subscription = s.bus.subscribe(require('core/events').MONSTER_SPAWNED, function(payload)
            if s.enabled then change(s, payload.unit, payload, 'new_spawn') end
        end)
    end
    return M.snapshot()
end
function M.retry_read_only_failure(options)
    local s = state_required(); options = options or {}
    assert(not s.enabled and s.visual_write_attempts == 0 and s.modified == 0,
        'Retry requires zero source visual attempts/modifications and an already disabled candidate')
    local why = tostring(s.stop_reason or '')
    assert(why:match('^required_combat_getter_') or why == 'native_cadence_reciprocity_failed',
        'Only a pre-read getter refusal may reuse the validated demo')
    assert(options.approved_existing_demo == true and options.demo_entindex == s.demo_entindex
        and s.validated and s.preview_status == 'ready' and valid(s.demo)
        and s.demo.survival_wave_low_model_demo_token == s.demo_token
        and s.demo:GetModelName() == s.visual.model_path and resource_ready(s),
        'Explicit current exact validated demo acknowledgement required')
    s.pre_read_retry_count = (s.pre_read_retry_count or 0) + 1
    s.last_retried_pre_read_reason = why
    s.seen = setmetatable({}, {__mode = 'k'})
    s.stop_reason = nil -- Historical failed count/reason remain reported.
    return M.snapshot()
end
function M.apply_existing(options)
    local s = state_required(); assert(s.enabled and s.validated, 'Enabled validated candidate required')
    local units = Entities:FindAllByClassname('npc_dota_creature')
    assert(type(units) == 'table', 'Native class collection required')
    local count = 0; for index in pairs(units) do assert(type(index) == 'number' and index >= 1 and index == math.floor(index), 'Dense collection required'); count = count + 1 end
    assert(count == #units, 'Complete dense collection required')
    local report = {collected = count, examined = 0, modified_before = s.modified, failed_before = s.failed, complete = false}
    for _, u in ipairs(units) do
        if not s.enabled or not scope_current(s) then break end
        report.examined = report.examined + 1
        local read_ok, p = pcall(function() return {unit = u, monster_source = u.survival_is_wave_monster == true and 'wave' or 'non_wave',
            member_role = u.survival_monster_role, player_id = u.survival_player_id, is_boss = u.survival_is_boss == true} end)
        if read_ok then change(s, u, p, 'existing_scan') else s.skipped = s.skipped + 1 end
    end
    report.complete = report.examined == count and s.enabled and scope_current(s)
    report.modified_delta = s.modified - report.modified_before; report.failed = s.failed
    report.failed_delta = s.failed - report.failed_before
    s.last_existing = report; return copy(report)
end
function M.stop(reason)
    tools(); local s = _G[KEY]; if not s then return false end
    disable(s, reason); s.stopped = true; s.preview_status = 'stopped'
    if s.task_id then require('core/scheduler').cancel(s.task_id) end
    remove_demo(s); return M.snapshot()
end
function M.snapshot()
    tools(); local s = _G[KEY]; if not s then return {enabled = false, default_off = true} end
    return {enabled = s.enabled and scope_current(s), current_scope = scope_current(s), preview_status = s.preview_status, validated = s.validated,
        model_path = s.visual.model_path, scale = SCALE, async_proxy = s.proxy, demo_entindex = s.demo_entindex,
        demo_removed = s.demo_removed, demo_removal_refused = s.demo_removal_refused,
        model_readback_confirmed = s.model_readback_confirmed, error = s.error, stop_reason = s.stop_reason,
        modified = s.modified, skipped = s.skipped, failed = s.failed, duplicates = s.duplicates,
        retired_parts = s.retired_parts, samples = copy(s.samples), last_existing = copy(s.last_existing),
        pre_read_retry_count = s.pre_read_retry_count, last_retried_pre_read_reason = s.last_retried_pre_read_reason,
        default_off = true, native_triangle_or_lod_measurement = false, no_native_fps_claim = true,
        gameplay_invariants_read_and_compared = true, stop_restores_source_models = false,
        requires_fresh_map_to_restore_source_units = s.visual_write_attempts > 0,
        validation_is_caller_native_observation_attestation = s.validation_is_caller_native_observation_attestation}
end
return M
