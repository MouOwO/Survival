// node tools/analyze_combat_log.cjs console.log [summary.json]
// Emits selected performance fields only; never copies account/chat payloads.
const fs = require('node:fs');
const crypto = require('node:crypto');

function analyze(text) {
  const sessions = [];
  let session, wave = 0;
  function current() {
    if (!session) {
      session = { session: sessions.length + 1, waves: [], entity_warnings: Object.create(null),
        resource_errors: [], lua_errors: 0, damage_log_lines: 0 };
      sessions.push(session);
      wave = 0;
    }
    return session;
  }
  function waveRow() {
    const s = current();
    let row = s.waves.find(x => x.wave === wave);
    if (!row) {
      row = { wave, warnings: 0, game_mode_warnings: 0, npc_warnings: 0,
        max_think_ms: 0, game_mode_max_ms: 0, over_33_33_ms: 0,
        game_mode_over_33_33_ms: 0 };
      s.waves.push(row);
    }
    return row;
  }
  const lines = text.replace(/^\uFEFF/, '').split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    // A reused console.log can contain multiple map runs.
    if (/CGameRules::CGameRules constructed|ShutdownSource2Logging/.test(line)) {
      session = undefined;
      wave = 0;
      continue;
    }
    const memory = line.match(/\[SURVIVAL_MEMORY\]\[LUA\] phase=wave_started wave=(\d+) game_time=([\d.]+) lua_kib=([-\d.]+) alive=(\d+) pending=(\d+) enemies=(\d+) scheduler=(\d+) visuals=(-?\d+)/);
    if (memory) {
      if (session && Number(memory[1]) <= wave) session = undefined;
      current();
      wave = Number(memory[1]);
      Object.assign(waveRow(), { started: line.match(/^\S+\s+\S+/)?.[0],
        memory_line: i + 1, game_time: Number(memory[2]), lua_kib: Number(memory[3]),
        alive_at_start: Number(memory[4]), pending_at_start: Number(memory[5]),
        enemies_at_start: Number(memory[6]), scheduler_at_start: Number(memory[7]),
        tracked_monster_visuals_at_start: Number(memory[8]) });
    }
    const warning = line.match(/SERVER: (.+?) thinking for ([\d.]+) ms!/);
    if (warning) {
      const row = waveRow(), ms = Number(warning[2]);
      const gameMode = warning[1].startsWith('dota_base_game_mode(');
      row.warnings++;
      row[gameMode ? 'game_mode_warnings' : 'npc_warnings']++;
      row.max_think_ms = Math.max(row.max_think_ms, ms);
      if (gameMode) row.game_mode_max_ms = Math.max(row.game_mode_max_ms, ms);
      if (ms > 1000 / 30) {
        row.over_33_33_ms++;
        if (gameMode) row.game_mode_over_33_33_ms++;
      }
      // Keep a class/model grouping, without client or player identifiers.
      const entity = warning[1].replace(/\[\d+\]/g, '[]');
      const totals = current().entity_warnings[entity] ??= { count: 0, max_ms: 0 };
      totals.count++;
      totals.max_ms = Math.max(totals.max_ms, ms);
    }
    if (/Script Runtime Error|stack traceback|Runtime error/.test(line)) current().lua_errors++;
    if (/\[CombatDamage\]/.test(line)) current().damage_log_lines++;
    const resource = line.match(/Failed loading resource "([^"]+)" \(([^)]+)\)/);
    if (resource && /particle|\.vpcf/i.test(resource[1])) {
      const errors = current().resource_errors;
      if (errors.length < 32) errors.push({ line: i + 1, path: resource[1], reason: resource[2] });
    }
  }
  return { metric_scope: 'Logged server entity Think warnings, grouped by the last wave-start marker; not full tick times or FPS.',
    threshold_note: '33.33 ms is a comparison threshold, not a measured server tick interval.',
    client_fps_measured: false, gpu_time_measured: false,
    particle_alive_count_measured: false, line_count: lines.filter(Boolean).length,
    source_sha256: crypto.createHash('sha256').update(text).digest('hex'), sessions };
}

if (require.main === module) {
  const [source, destination] = process.argv.slice(2);
  if (!source) throw new Error('Usage: node tools/analyze_combat_log.cjs console.log [summary.json]');
  const result = JSON.stringify(analyze(fs.readFileSync(source, 'utf8')), null, 2) + '\n';
  if (destination) {
    // Do not overwrite the input log if the caller accidentally repeats its path.
    const path = require('node:path');
    if (path.resolve(source) === path.resolve(destination)) throw new Error('Output must differ from input');
    fs.writeFileSync(destination, result);
  } else process.stdout.write(result);
}
module.exports = { analyze };
