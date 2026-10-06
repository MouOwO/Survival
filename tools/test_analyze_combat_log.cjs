const assert = require('node:assert/strict');
const { analyze } = require('./analyze_combat_log.cjs');
const log = [
  '\uFEFF10/06 16:00:00 [Entity System] SERVER: dota_base_game_mode([552]) thinking for 12.00 ms!',
  '10/06 16:01:00 [SURVIVAL_MEMORY][LUA] phase=wave_started wave=15 game_time=100.0 lua_kib=32614.7 alive=0 pending=61 enemies=0 scheduler=87 visuals=0',
  '10/06 16:01:01 [Entity System] SERVER: dota_base_game_mode([552]) thinking for 52.57 ms!',
  '10/06 16:01:02 [Entity System] SERVER: npc_dota_creature(npc_dota_creature[12], model: models/test.vmdl) thinking for 12.00 ms!',
  '10/06 16:01:03 [Entity System] SERVER: npc_dota_creature(npc_dota_creature[13], model: models/test.vmdl) thinking for 14.00 ms!',
  '10/06 16:01:04 [BuildingUpgradeParticle] event=release ok=true error=',
  '10/06 16:01:05 [ResourceSystem] Failed loading resource "particles/missing.vpcf_c" (ERROR_FILEOPEN: File not found)',
  '10/06 16:01:06 account_id SECRET_ACCOUNT_TOKEN',
  '10/06 16:01:07 [CombatDamage] transaction_id=one',
  '10/06 16:02:00 [SURVIVAL_MEMORY][LUA] phase=wave_started wave=16 game_time=190.0 lua_kib=34796.9 alive=15 pending=60 enemies=15 scheduler=97 visuals=0',
  '10/06 16:02:01 [Entity System] SERVER: dota_base_game_mode([552]) thinking for 33.33 ms!',
  '10/06 16:02:02 Script Runtime Error: sample',
  '10/06 16:03:00 ShutdownSource2Logging',
  '10/06 17:00:00 [SURVIVAL_MEMORY][LUA] phase=wave_started wave=1 game_time=10.0 lua_kib=1.0 alive=0 pending=1 enemies=0 scheduler=2 visuals=0',
  '10/06 17:00:01 [Entity System] SERVER: dota_base_game_mode([888]) thinking for 20.00 ms!',
].join('\n');
const report = analyze(log);
assert.equal(report.sessions.length, 2);
const first = report.sessions[0];
assert.equal(first.waves[0].wave, 0);
const w15 = first.waves[1], w16 = first.waves[2];
assert.equal(w15.warnings, 3);
assert.equal(w15.game_mode_warnings, 1);
assert.equal(w15.npc_warnings, 2);
assert.equal(w15.game_mode_max_ms, 52.57);
assert.equal(w15.over_33_33_ms, 1);
assert.equal(w16.over_33_33_ms, 0);
assert.equal(w16.alive_at_start, 15);
assert.deepEqual(first.entity_warnings['npc_dota_creature(npc_dota_creature[], model: models/test.vmdl)'], { count: 2, max_ms: 14 });
assert.equal(first.resource_errors.length, 1);
assert.equal(first.lua_errors, 1);
assert.equal(first.damage_log_lines, 1);
assert(!JSON.stringify(report).includes('SECRET_ACCOUNT_TOKEN'));
assert.equal(report.client_fps_measured, false);
assert.equal(report.gpu_time_measured, false);
assert.equal(analyze(log + '\n10/06 17:01:00 [SURVIVAL_MEMORY][LUA] phase=wave_started wave=1 game_time=1.0 lua_kib=1.0 alive=0 pending=1 enemies=0 scheduler=2 visuals=0').sessions.length, 3);
console.log('COMBAT_LOG_ANALYSIS_PASS: wave boundaries, per-entity warnings, threshold, resource failures, privacy, multiple runs');
