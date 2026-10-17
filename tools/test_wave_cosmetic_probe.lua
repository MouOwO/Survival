-- Real event bus + real cosmetic retirement helper; native particle APIs mocked.
package.path = 'scripts/vscripts/?.lua;' .. package.path
local probe = require('tests/manual_wave_cosmetic_probe')
assert(_G.SURVIVAL_WAVE_COSMETIC_PROBE == nil, 'Require must be inert/default off')
assert(probe.enable().request_disabled and _G.SURVIVAL_WAVE_COSMETIC_PROBE == nil)
local mode, session, in_tools = {}, 'cosmetic_probe_test', true
IsServer = function() return true end
IsInToolsMode = function() return in_tools end
GetMapName = function() return 'template_map' end
DOTA_TEAM_BADGUYS = 3
GameRules = {GetGameModeEntity = function() return mode end, GetGameTime = function() return 33 end}
package.loaded['systems/match_setup_service'] = {get_mode = function() return 'standard' end,
    get_session_id = function() return session end}
package.loaded['systems/player_context_service'] = {owner_player_id = function(u, authoritative)
    assert(authoritative == true); return u.context_owner end,
    is_defeated = function(id) return id == 3 and _G.test_owner3_defeated == true end}
local bus, events = require('core/event_bus'), require('core/events')
local subscriptions, original_subscribe = {}, bus.subscribe
bus.subscribe = function(event, callback)
    subscriptions[#subscriptions + 1] = callback
    return original_subscribe(event, callback)
end
local guard = {mode = mode}; _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION = guard
local fixture = {mode = mode, guard = guard, status = 'ready', ids = {0, 1, 2, 3}}
_G.SURVIVAL_FOUR_PLAYER_LIVE_PERF = fixture
local serial, particles, destroyed, released = 0, 100, {}, {}
ParticleManager = {
    CreateParticle = function() particles = particles + 1; return particles end,
    DestroyParticle = function(_, id, immediately)
        assert(immediately == true); destroyed[id] = (destroyed[id] or 0) + 1
        if _G.test_native_particle_fail then error('simulated native destroy exception') end
    end,
    ReleaseParticleIndex = function(_, id) released[id] = (released[id] or 0) + 1 end,
}
local details = require('visual/monster_cosmetic_details')
local original_stop, stop_calls = details.stop_particles, 0
details.stop_particles = function(u) stop_calls = stop_calls + 1; return original_stop(u) end
local asset = {asset_id = 'owned_wave_outfit', effects = {
    {enabled = true, effect_group_id = 'wave_cosmetic_ambient', particle_path = 'weapon_ambient', owner_component_id = 'weapon'},
    {enabled = true, effect_group_id = 'wave_cosmetic_ambient', particle_path = 'back_ambient', owner_component_id = 'back'},
    {enabled = true, effect_group_id = 'combat_impact', particle_path = 'not_owned_cosmetic'},
}}
local function unit(id)
    serial = serial + 1; id = id or 0
    local u = {index = serial, player = id, context_owner = id, native_owner = -1, alive = true, team = 3,
        survival_is_wave_monster = true, survival_monster_role = 'normal', survival_player_id = id,
        survival_is_boss = false, body = 'original_body', parts = {weapon = {}, back = {}},
        attack = {damage = 12, BAT = 0.714, range = 600, projectile = 'native_attack', impact = 'native_hit'},
        original_flags = 'unchanged'}
    function u:IsNull() return self.removed == true end
    function u:IsAlive() return self.alive end
    function u:entindex() return self.index end
    function u:GetUnitName() return 'npc_survival_wave_named_dwarf_white_rifle' end
    function u:GetTeamNumber() return self.team end
    function u:GetClassname() return self.class or 'npc_dota_creature' end
    function u:IsRealHero() return self.hero == true end
    function u:IsHero() return self.hero == true end
    function u:IsIllusion() return self.illusion == true end
    function u:IsClone() return self.clone == true end
    function u:GetPlayerOwnerID() return self.native_owner end
    function u:FindModifierByName(name)
        assert(name == 'modifier_enemy_wall_ai')
        if self.no_ai then return nil end
        return {IsNull = function() return false end, GetParent = function() return self.ai_parent or self end,
            wall_target_player_id = self.ai_owner or self.player}
    end
    function u:SetModel() error('Probe must not modify the body') end
    function u:SetBaseAttackTime() error('Probe must not modify attack speed') end
    function u:SetHealth() error('Probe must not modify health') end
    function u:Stop() error('Probe must not issue native orders') end
    details.apply(u, asset, u.parts)
    u.original_handles = {u.survival_monster_cosmetic_details.particles[1], u.survival_monster_cosmetic_details.particles[2]}
    return u
end
local function spawn(u, patch)
    local p = {unit = u, monster_source = 'wave', member_role = 'normal', player_id = u.player, is_boss = false}
    for key, value in pairs(patch or {}) do p[key] = value end
    bus.emit(events.MONSTER_SPAWNED, p)
end
Entities = {FindAllByClassname = function() error('Must not scan existing units') end}
local old = unit()
local native_calls_before = stop_calls
in_tools = false
assert(not pcall(probe.enable, {enabled = true, ambient_only = true}), 'Non-Tools enabling is rejected')
in_tools = true
local rejected = probe.enable({enabled = true, low_model = true})
assert(rejected.ok == false and rejected.error == 'low_model_native_validation_required'
    and #rejected.low_model_plan.candidates >= 2 and _G.SURVIVAL_WAVE_COSMETIC_PROBE == nil,
    'Low-model option must not silently substitute an unverified rig or enable ambient mode')
assert(probe.enable({enabled = true}).request_disabled)
local enabled = probe.enable({enabled = true, ambient_only = true})
assert(enabled.enabled and enabled.ambient_only and not enabled.low_model)
assert(stop_calls == native_calls_before and #old.survival_monster_cosmetic_details.particles == 2,
    'Enable cannot scan or mutate existing units')
local unrelated_events = 0
local unrelated_token = bus.subscribe(events.MONSTER_SPAWNED, function() unrelated_events = unrelated_events + 1 end)
local u = unit(2); local parts, attack, state = u.parts, u.attack, u.survival_monster_cosmetic_details
spawn(u)
assert(u.parts == parts and u.attack == attack and u.body == 'original_body' and u.original_flags == 'unchanged')
assert(u.survival_monster_cosmetic_details == state and state.components == parts and #state.particles == 0)
for _, id in ipairs(u.original_handles) do assert(destroyed[id] == 1 and released[id] == 1) end
local snapshot = probe.snapshot({quiet = true})
assert(snapshot.processed == 1 and snapshot.modified_units == 1 and snapshot.owned_handles_retired == 2
    and snapshot.owners[3].modified_units == 1 and snapshot.owners[3].owned_handles_retired == 2)
assert(snapshot.requires_map_reload_to_restore_modified_units and not snapshot.native_particle_removal_success_asserted)
spawn(u)
assert(stop_calls == native_calls_before + 1 and probe.snapshot({quiet = true}).skipped_reasons.duplicate_spawn_notification == 1)
local count_before_low_request = #subscriptions
rejected = probe.enable({enabled = true, ambient_only = true, low_model = true})
assert(not rejected.ok and rejected.existing_probe_enabled and #subscriptions == count_before_low_request)
local excluded = {
    function(v) v.hero = true end, function(v) v.illusion = true end, function(v) v.clone = true end,
    function(v) v.survival_monster_role = 'wave_leader' end, function(v) v.survival_is_boss = true end,
    function(v) v.survival_is_challenge_monster = true end, function(v) v.survival_training_id = 'worker' end,
    function(v) v.survival_hero_id = 'hero_doom' end, function(v) v.survival_exclusive_summon = true end,
    function(v) v.survival_monkey_king_clone = true end, function(v) v.survival_blademaster_clone = true end,
    function(v) v.survival_drow_companion = true end, function(v) v.survival_visual_only = true end,
    function(v) v.team = 2 end, function(v) v.class = 'npc_dota_hero_hoodwink' end,
    function(v) v.survival_is_wave_monster = false end, function(v) v.no_ai = true end,
    function(v) v.native_owner = 1 end, function(v) v.context_owner = 1 end,
    function(v) v.survival_player_id = 1 end, function(v) v.ai_owner = 1 end,
    function(v) v.ai_parent = {} end, function(v) v.alive = false end,
    function(v) v.removed = true end,
}
for _, change in ipairs(excluded) do
    local v = unit(); change(v); spawn(v)
    assert(#v.survival_monster_cosmetic_details.particles == 2, 'Excluded/ambiguous role retains all owned cosmetics')
end
for _, patch in ipairs({{monster_source = 'building_challenge'}, {member_role = 'wave_leader'}, {is_boss = true}, {player_id = 1}}) do
    local v = unit(); spawn(v, patch); assert(#v.survival_monster_cosmetic_details.particles == 2)
end
_G.test_owner3_defeated = true
local defeated = unit(3); spawn(defeated); assert(#defeated.survival_monster_cosmetic_details.particles == 2)
_G.test_owner3_defeated = nil
local valid_native = unit(1); valid_native.native_owner = 1; spawn(valid_native)
assert(#valid_native.survival_monster_cosmetic_details.particles == 0, 'Matching native positive owner is valid; -1 is also valid')
local unknown = unit(); unknown.survival_monster_cosmetic_details = nil; spawn(unknown)
local broken = unit(); broken.GetPlayerOwnerID = function() error('native handle invalidated') end; spawn(broken)
assert(#broken.survival_monster_cosmetic_details.particles == 2)
local sparse = unit(); sparse.survival_monster_cosmetic_details.particles = {[2] = 19999}; spawn(sparse)
assert(sparse.survival_monster_cosmetic_details.particles[2] == 19999)
local nonfinite = unit(); nonfinite.survival_monster_cosmetic_details.particles = {math.huge}; spawn(nonfinite)
assert(nonfinite.survival_monster_cosmetic_details.particles[1] == math.huge)
local empty = unit(); details.stop_particles(empty); local calls_before_empty = stop_calls; spawn(empty)
assert(stop_calls == calls_before_empty and probe.snapshot({quiet = true}).zero_particle_units == 1)
_G.test_native_particle_fail = true
local partial = unit(); spawn(partial); _G.test_native_particle_fail = nil
snapshot = probe.snapshot({quiet = true})
assert(#partial.survival_monster_cosmetic_details.particles == 0 and not snapshot.native_particle_removal_success_asserted,
    'Helper bookkeeping must not be falsely labelled native render success when protected native calls fail')
for index = 1, 65 do spawn(unit(index % 4)) end
snapshot = probe.snapshot({quiet = true})
assert(#snapshot.samples == 32 and snapshot.modified_units == 68 and snapshot.owned_handles_retired == 136,
    'Complete counters and exact owner totals stay valid beyond the bounded trace')
local summed = 0; for _, row in ipairs(snapshot.owners) do summed = summed + row.owned_handles_retired end
assert(summed == snapshot.owned_handles_retired)
local captured = subscriptions[1]
assert(probe.stop('sample_done'))
local stopped_unit = unit(); spawn(stopped_unit)
assert(#stopped_unit.survival_monster_cosmetic_details.particles == 2 and #u.survival_monster_cosmetic_details.particles == 0)
assert(probe.snapshot({quiet = true}).stop_reason == 'sample_done' and unrelated_events > 0,
    'Stop cancels only our own token and never fabricates restoration')
probe.enable({enabled = true, ambient_only = true})
local new_state = _G.SURVIVAL_WAVE_COSMETIC_PROBE
captured({unit = unit(), monster_source = 'wave', member_role = 'normal', player_id = 0})
assert(new_state.enabled, 'Late old callback must not cancel a newer candidate')
session = 'new_session'; local stale = unit(); spawn(stale)
assert(#stale.survival_monster_cosmetic_details.particles == 2 and not probe.snapshot({quiet = true}).enabled)
session = 'cosmetic_probe_test'; probe.enable({enabled = true, ambient_only = true})
mode = {}; local new_world = unit(); spawn(new_world)
assert(#new_world.survival_monster_cosmetic_details.particles == 2 and not probe.snapshot({quiet = true}).enabled)
guard = {mode = mode}; _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION = guard
fixture = {mode = mode, guard = guard, status = 'ready', ids = {0, 1, 2, 3}}
_G.SURVIVAL_FOUR_PLAYER_LIVE_PERF = fixture
probe.enable({enabled = true, ambient_only = true})
local foreign_guard = unit(); _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION = {mode = mode}; spawn(foreign_guard)
assert(#foreign_guard.survival_monster_cosmetic_details.particles == 2 and not probe.snapshot({quiet = true}).enabled)
_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION = guard
probe.enable({enabled = true, ambient_only = true})
local before_reset = _G.SURVIVAL_WAVE_COSMETIC_PROBE
local late_callback = subscriptions[#subscriptions]
bus.reset()
assert(not probe.snapshot({quiet = true}).current_fixture_and_guard, 'Bus generation replacement invalidates the old scope')
-- Fresh module/world bootstrap may clear our global while an old immutable
-- event snapshot still owns its callback. Only that old state may be stopped.
_G.SURVIVAL_WAVE_COSMETIC_PROBE = nil
probe.enable({enabled = true, ambient_only = true})
local after_reset = _G.SURVIVAL_WAVE_COSMETIC_PROBE
late_callback({unit = unit(), monster_source = 'wave', member_role = 'normal', player_id = 0})
assert(not before_reset.enabled and after_reset.enabled and after_reset.processed == 0,
    'A still-enabled stale callback retires only its own state/token')
local post_reset = unit(1); spawn(post_reset)
assert(after_reset.processed == 1 and #post_reset.survival_monster_cosmetic_details.particles == 0)
probe.stop('final_cleanup')
-- Existing units are an explicit opt-in operation after the same native batch
-- has been sampled. They share the exact eligibility/duplicate retirement path.
local existing0, existing2, already = unit(0), unit(2), unit(1)
local leader, challenge, dead, worker = unit(1), unit(3), unit(0), unit(0)
leader.survival_monster_role = 'wave_leader'; challenge.survival_is_challenge_monster = true
dead.alive = false; worker.survival_is_wave_monster = false; worker.survival_training_id = 'worker'
local collection = {existing0, existing2, already, leader, challenge, dead, worker}
local scan_calls = 0
Entities.FindAllByClassname = function(_, class)
    assert(class == 'npc_dota_creature'); scan_calls = scan_calls + 1; return collection
end
assert(not probe.apply_existing({quiet = true}).ok and scan_calls == 0, 'Stopped candidate must not scan')
probe.enable({enabled = true, ambient_only = true})
assert(scan_calls == 0 and #existing0.survival_monster_cosmetic_details.particles == 2)
spawn(already)
local existing_report = probe.apply_existing({quiet = true})
assert(existing_report.ok and existing_report.scan_complete and existing_report.processing_complete
    and existing_report.collected == 7 and existing_report.examined == 7)
assert(existing_report.eligible_before == 3 and existing_report.eligible_after == 3
    and existing_report.unseen_eligible_before == 2 and existing_report.duplicate_eligible_before == 1)
assert(existing_report.owned_handles_before == 4 and existing_report.owned_handles_after == 0
    and existing_report.owned_handles_before_complete and existing_report.owned_handles_after_complete
    and existing_report.modified_units_delta == 2 and existing_report.owned_handles_retired_delta == 4)
for _, v in ipairs({leader, challenge, dead, worker}) do assert(#v.survival_monster_cosmetic_details.particles == 2) end
snapshot = probe.snapshot({quiet = true})
assert(snapshot.events == 1 and snapshot.existing_notifications == 7 and snapshot.seen_unit_keys_are_weak
    and getmetatable(_G.SURVIVAL_WAVE_COSMETIC_PROBE.seen).__mode == 'k')
assert(snapshot.samples[2].observation_source == 'existing_scan'
    and snapshot.last_existing_scan.eligible_after == 3, 'Reports contain values only, without retaining NPC handles')
local calls_before_rescan = stop_calls
local duplicate_report = probe.apply_existing({quiet = true})
assert(duplicate_report.ok and duplicate_report.duplicate_eligible_before == 3
    and duplicate_report.modified_units_delta == 0 and duplicate_report.owned_handles_retired_delta == 0
    and stop_calls == calls_before_rescan, 'Explicit repeat scan must not retire the same handles twice')
local untouched = unit()
collection = {[2] = untouched}
local sparse_report = probe.apply_existing({quiet = true})
assert(not sparse_report.ok and not sparse_report.scan_complete
    and #untouched.survival_monster_cosmetic_details.particles == 2, 'Incomplete collection fails before mutation')
Entities.FindAllByClassname = function() error('native collection failure') end
local failed_report = probe.apply_existing({quiet = true})
assert(not failed_report.ok and failed_report.error == 'native_class_collection_failed'
    and not failed_report.scan_complete and #untouched.survival_monster_cosmetic_details.particles == 2)
local prior_scan_calls = scan_calls
_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION = {mode = mode}
local stale_report = probe.apply_existing({quiet = true})
assert(not stale_report.ok and not stale_report.scan_attempted and scan_calls == prior_scan_calls
    and #untouched.survival_monster_cosmetic_details.particles == 2, 'Old guard rejects before scan and native mutation')
_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION = guard
probe.stop('existing_finished')
bus.unsubscribe(unrelated_token)
print('WAVE_COSMETIC_PROBE_PASS: default off; real bus/helper; ordinary-owner waves only; unchanged body/parts/combat/impact; exact handles/owner counters; default no scan; explicit existing complete/before/after/duplicate/dead/foreign/stale guards; weak keys; bounded trace; low-model blocked; no fake native success/restoration')
